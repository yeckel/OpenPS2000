// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#include "PulseEngine.h"
#include <QDebug>

PulseEngine::PulseEngine(QObject *parent) : QObject(parent)
{
    m_phaseTimer.setSingleShot(true);
    connect(&m_phaseTimer, &QTimer::timeout, this, &PulseEngine::onPhaseTimer);

    m_tickTimer.setInterval(250); // 4 Hz display refresh
    connect(&m_tickTimer, &QTimer::timeout, this, &PulseEngine::onTickTimer);
}

void PulseEngine::start(double onVoltage, double onCurrent,
                        double offVoltage, double offCurrent,
                        bool   outputOffDuringOff,
                        int    onTimeMs,  int offTimeMs,
                        int    totalCycles)
{
    if (m_state != Idle)
        stop();

    m_onVoltage   = onVoltage;
    m_onCurrent   = onCurrent;
    m_offVoltage  = offVoltage;
    m_offCurrent  = offCurrent;
    m_offDisable  = outputOffDuringOff;
    m_onTimeMs    = qMax(50, onTimeMs);
    m_offTimeMs   = qMax(50, offTimeMs);
    m_totalCycles = totalCycles;
    m_cyclesDone  = 0;

    m_elapsed.restart();
    m_tickTimer.start();

    applyOn();
}

void PulseEngine::stop()
{
    if (m_state == Idle) return;

    m_phaseTimer.stop();
    m_tickTimer.stop();

    emit setOutputRequested(false);

    m_state = Idle;
    emit stateChanged();
    emit tick();
}

void PulseEngine::onSample(double /*t*/, double v, double i, double /*p*/)
{
    m_lastV = v;
    m_lastI = i;
}

// ── private ──────────────────────────────────────────────────────────────────

void PulseEngine::applyOn()
{
    emit setVoltageRequested(m_onVoltage);
    emit setCurrentRequested(m_onCurrent);
    emit setOutputRequested(true);

    m_state = OnPhase;
    emit stateChanged();

    double t = elapsedSecs();
    emit newPoint(t, m_onVoltage, m_onCurrent);

    m_phaseTimer.start(m_onTimeMs);
}

void PulseEngine::applyOff()
{
    if (m_offDisable) {
        emit setOutputRequested(false);
    } else {
        emit setVoltageRequested(m_offVoltage);
        emit setCurrentRequested(m_offCurrent);
        emit setOutputRequested(true);
    }

    m_state = OffPhase;
    emit stateChanged();

    double t = elapsedSecs();
    emit newPoint(t, m_offVoltage, m_offDisable ? 0.0 : m_offCurrent);

    m_phaseTimer.start(m_offTimeMs);
}

void PulseEngine::advanceCycle()
{
    ++m_cyclesDone;
    emit cyclesDone_changed();

    if (m_totalCycles > 0 && m_cyclesDone >= m_totalCycles) {
        // All cycles done
        m_phaseTimer.stop();
        m_tickTimer.stop();
        emit setOutputRequested(false);
        m_state = Done;
        emit stateChanged();
        emit tick();
        emit finished(m_cyclesDone);
        return;
    }

    applyOn();
}

void PulseEngine::onPhaseTimer()
{
    if (m_state == OnPhase) {
        // ON phase ended — go to OFF
        double t = elapsedSecs();
        emit newPoint(t, m_offDisable ? 0.0 : m_offVoltage,
                         m_offDisable ? 0.0 : m_offCurrent);
        applyOff();
    } else if (m_state == OffPhase) {
        // OFF phase ended — complete cycle, start next ON
        double t = elapsedSecs();
        emit newPoint(t, m_onVoltage, m_onCurrent);
        advanceCycle();
    }
}

void PulseEngine::onTickTimer()
{
    emit tick();
}

double PulseEngine::elapsedSecs() const
{
    if (m_state == Idle || m_state == Done)
        return m_elapsed.elapsed() / 1000.0;
    return m_elapsed.elapsed() / 1000.0;
}
