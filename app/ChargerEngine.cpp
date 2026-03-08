// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#include "ChargerEngine.h"
#include <QCoreApplication>
#include <algorithm>

ChargerEngine::ChargerEngine(QObject* parent)
    : QObject(parent)
    , m_profiles(ProfileStore::loadProfiles())
{}

// ── Helpers ──────────────────────────────────────────────────────────────────

QString ChargerEngine::stateString() const {
    switch (m_state) {
    case ChargingState::Idle:        return tr("Idle");
    case ChargingState::CCPhase:     return tr("CC Phase");
    case ChargingState::CVPhase:     return tr("CV Phase");
    case ChargingState::FloatPhase:  return tr("Float");
    case ChargingState::Done:        return tr("Done ✓");
    case ChargingState::Fault:       return tr("Fault ✗");
    }
    return {};
}

double ChargerEngine::elapsedSecs() const {
    if (m_state == ChargingState::Idle) return 0;
    return m_lastT - m_startT;
}

QVariantList ChargerEngine::profileVariants() const {
    QVariantList list;
    for (const auto& p : m_profiles) list << p.toVariantMap();
    return list;
}

// ── Profile management ────────────────────────────────────────────────────────

QStringList ChargerEngine::profileNames() const {
    QStringList names;
    for (const auto& p : m_profiles) names << p.name;
    return names;
}

QVariantMap ChargerEngine::getProfile(int index) const {
    if (index < 0 || index >= m_profiles.size()) return {};
    return m_profiles[index].toVariantMap();
}

QVariantMap ChargerEngine::defaultsForChemistry(const QString& chem) const {
    return BatteryProfile::chemistryDefaults(chem).toVariantMap();
}

void ChargerEngine::saveProfile(const QVariantMap& map, int replaceIndex) {
    BatteryProfile p;
    p.name             = map["name"].toString();
    p.chemistry        = map["chemistry"].toString();
    p.cells            = map["cells"].toInt();
    p.capacityMah      = map["capacityMah"].toDouble();
    p.chargeRateC      = map["chargeRateC"].toDouble();
    p.cutoffCurrentC   = map["cutoffCurrentC"].toDouble();
    p.cvVoltPerCell    = map["cvVoltPerCell"].toDouble();
    p.floatVoltPerCell = map["floatVoltPerCell"].toDouble();
    p.maxCellVoltage   = map["maxCellVoltage"].toDouble();
    p.deltavMvPerCell  = map["deltavMvPerCell"].toDouble();
    p.maxTimeMinutes   = map["maxTimeMinutes"].toInt();

    if (replaceIndex >= 0 && replaceIndex < m_profiles.size())
        m_profiles[replaceIndex] = p;
    else
        m_profiles.append(p);

    ProfileStore::saveProfiles(m_profiles);
    emit profilesChanged();
}

void ChargerEngine::deleteProfile(int index) {
    if (index < 0 || index >= m_profiles.size()) return;
    m_profiles.removeAt(index);
    ProfileStore::saveProfiles(m_profiles);
    emit profilesChanged();
}

// ── State machine helpers ─────────────────────────────────────────────────────

void ChargerEngine::setState(ChargingState s, const QString& fault) {
    m_state = s;
    m_faultReason = fault;
    emit stateChanged();
}

void ChargerEngine::applySetpoints() {
    emit setVoltageRequested(m_profile.chargeVoltage());
    emit setCurrentRequested(m_profile.chargeCurrent());
    emit setOvpRequested(m_profile.ovpVoltage());
    // OCP = charge current × 1.15 headroom (PSU will protect)
    emit setOcpRequested(m_profile.chargeCurrent() * 1.15);
}

void ChargerEngine::applyFloatSetpoints() {
    emit setVoltageRequested(m_profile.floatVoltage());
    emit setCurrentRequested(m_profile.chargeCurrent() * 0.1); // trickle
    emit setOvpRequested(m_profile.floatVoltage() * 1.05);
}

// ── Public control ─────────────────────────────────────────────────────────────

void ChargerEngine::startCharging(int profileIndex) {
    if (profileIndex < 0 || profileIndex >= m_profiles.size()) return;
    if (m_state != ChargingState::Idle) stopCharging();

    m_profile      = m_profiles[profileIndex];
    m_mAh          = 0;
    m_wh           = 0;
    m_peakV        = 0;
    m_peakI        = 0;
    m_minV         = 1e9;
    m_peakVForDV   = 0;
    m_warmupCount  = 0;
    m_startT       = 0;   // will be set on first sample
    m_lastT        = 0;

    applySetpoints();
    emit setOutputRequested(true);
    setState(ChargingState::CCPhase);
    emit statusMessage(tr("Charging started: %1").arg(m_profile.name));
}

void ChargerEngine::stopCharging() {
    if (m_state == ChargingState::Idle) return;
    emit setOutputRequested(false);
    setState(ChargingState::Idle);
    emit statusMessage(tr("Charging stopped."));
}

// ── Sample processing ──────────────────────────────────────────────────────────

void ChargerEngine::onSample(double t, double v, double i, double p) {
    if (m_state == ChargingState::Idle || m_state == ChargingState::Done
        || m_state == ChargingState::Fault)
        return;

    // Initialise start time on first sample
    if (m_startT == 0 && m_lastT == 0) {
        m_startT = t;
        m_lastT  = t;
    }

    double dt    = t - m_lastT;
    double relT  = t - m_startT;
    m_lastT = t;

    // Integrate energy (trapezoidal, dt in seconds)
    if (dt > 0 && dt < 10) {  // guard against stale jumps
        m_mAh += i * dt / 3.6;
        m_wh  += p * dt / 3600.0;
    }

    // Track extremes
    if (v > m_peakV) m_peakV = v;
    if (i > m_peakI) m_peakI = i;
    if (v < m_minV && v > 0.1) m_minV = v;

    emit newChargingPoint(relT, v, i);
    emit statsUpdated();

    // ── Safety guards ────────────────────────────────────────────────────────
    // Absolute overvoltage (PSU OVP should catch this first, but belt & braces)
    if (v > m_profile.ovpVoltage() * 1.02) {
        emit setOutputRequested(false);
        setState(ChargingState::Fault, tr("Overvoltage: %1 V").arg(v, 0, 'f', 2));
        emit chargingFault(m_faultReason);
        return;
    }
    // Timeout
    if (relT > m_profile.maxTimeMinutes * 60.0) {
        emit setOutputRequested(false);
        setState(ChargingState::Fault, tr("Timeout after %1 min").arg(m_profile.maxTimeMinutes));
        emit chargingFault(m_faultReason);
        return;
    }

    // ── State-specific transitions ────────────────────────────────────────────
    if (m_profile.isCCCV()) {
        checkCCCV(v, i, relT);
    } else {
        checkNixx(v, relT);
    }
}

void ChargerEngine::checkCCCV(double v, double i, double relT) {
    Q_UNUSED(relT)
    const double targetV  = m_profile.chargeVoltage();
    const double cutoffI  = m_profile.cutoffCurrent();
    // Threshold: consider "voltage reached" when within 50 mV per cell
    const double cvThresh = targetV - 0.05 * m_profile.cells;

    switch (m_state) {
    case ChargingState::CCPhase:
        if (v >= cvThresh) {
            setState(ChargingState::CVPhase);
            emit phaseMarker(m_lastT - m_startT, static_cast<int>(ChargingState::CVPhase), tr("CV"));
            emit statusMessage(tr("CV phase started — voltage reached %1 V").arg(v, 0, 'f', 2));
        }
        break;

    case ChargingState::CVPhase:
        if (cutoffI > 0 && i <= cutoffI) {
            if (m_profile.hasFloat()) {
                applyFloatSetpoints();
                setState(ChargingState::FloatPhase);
                emit phaseMarker(m_lastT - m_startT, static_cast<int>(ChargingState::FloatPhase), tr("Float"));
                emit statusMessage(tr("Float stage — maintaining %1 V").arg(m_profile.floatVoltage(), 0, 'f', 2));
            } else {
                emit setOutputRequested(false);
                setState(ChargingState::Done);
                emit phaseMarker(m_lastT - m_startT, static_cast<int>(ChargingState::Done), tr("Done"));
                emit chargingComplete(m_mAh, m_wh, m_lastT - m_startT);
                emit statusMessage(tr("Charging complete: %1 mAh / %2 Wh").arg(m_mAh, 0, 'f', 0).arg(m_wh, 0, 'f', 3));
            }
        }
        break;

    case ChargingState::FloatPhase:
        // Float runs indefinitely until user stops
        break;

    default: break;
    }
}

void ChargerEngine::checkNixx(double v, double relT) {
    if (m_state != ChargingState::CCPhase) return;

    m_warmupCount++;
    // Skip -ΔV detection for first 60 seconds (voltage is still rising)
    if (relT < 60.0) {
        m_peakVForDV = v;
        return;
    }

    if (v > m_peakVForDV) {
        m_peakVForDV = v;
    } else {
        double drop = m_peakVForDV - v;
        double threshold = m_profile.deltavMvPerCell * m_profile.cells / 1000.0;
        if (threshold > 0 && drop >= threshold) {
            emit setOutputRequested(false);
            setState(ChargingState::Done);
            emit phaseMarker(m_lastT - m_startT, static_cast<int>(ChargingState::Done), tr("Done"));
            emit chargingComplete(m_mAh, m_wh, m_lastT - m_startT);
            emit statusMessage(tr("Charging complete (–ΔV): %1 mAh").arg(m_mAh, 0, 'f', 0));
        }
    }
}
