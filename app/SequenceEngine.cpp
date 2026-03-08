// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#include "SequenceEngine.h"
#include <QDebug>

SequenceEngine::SequenceEngine(QObject* parent) : QObject(parent)
{
    m_phaseTimer.setSingleShot(true);
    connect(&m_phaseTimer, &QTimer::timeout, this, &SequenceEngine::onPhaseTimer);

    m_rampTimer.setInterval(250);
    connect(&m_rampTimer, &QTimer::timeout, this, &SequenceEngine::onRampTimer);

    m_tickTimer.setInterval(250);
    connect(&m_tickTimer, &QTimer::timeout, this, &SequenceEngine::onTickTimer);
}

// ── Public slots ──────────────────────────────────────────────────────────────
void SequenceEngine::start(const QVariantList& steps)
{
    if (m_state != Idle && m_state != Done && m_state != Fault) stop();

    m_steps.clear();
    m_stepStartMs.clear();
    m_totalMs = 0;

    for (auto& sv : steps) {
        QVariantMap sm = sv.toMap();
        SequenceStep s;
        s.voltage = sm["voltage"].toDouble();
        s.current = sm["current"].toDouble();
        s.holdMs  = qMax(500, sm["holdMs"].toInt());
        s.ramp    = sm["ramp"].toBool();
        s.rampMs  = qMax(500, sm["rampMs"].toInt());
        m_steps << s;
        m_stepStartMs << m_totalMs;
        m_totalMs += (s.ramp ? s.rampMs : 0) + s.holdMs;
    }

    if (m_steps.isEmpty()) return;

    m_stepIdx = 0;
    m_lastV   = 0;
    m_lastI   = 0;
    m_elapsed.start();
    m_tickTimer.start();

    emit setOutputRequested(true);
    emitPlannedCurve();
    applyStep(0);
}

void SequenceEngine::stop()
{
    if (m_state == Idle) return;
    m_phaseTimer.stop();
    m_rampTimer.stop();
    m_tickTimer.stop();
    emit setOutputRequested(false);
    m_state = Idle;
    emit stateChanged();
    emit tick();
}

void SequenceEngine::onSample(double /*t*/, double v, double i, double /*p*/)
{
    m_lastV = v;
    m_lastI = i;
}

// ── Private ───────────────────────────────────────────────────────────────────
void SequenceEngine::applyStep(int idx)
{
    if (idx >= m_steps.size()) { advance(); return; }
    const SequenceStep& s = m_steps[idx];
    if (s.ramp && idx > 0)
        startRamp(idx);
    else {
        emit setVoltageRequested(s.voltage);
        emit setCurrentRequested(s.current);
        startHold(idx);
    }
    emit stepChanged(idx);
}

void SequenceEngine::startRamp(int idx)
{
    const SequenceStep& s = m_steps[idx];
    // Ramp from previous target (or current actual if first step)
    m_rampStartV  = (idx > 0) ? m_steps[idx - 1].voltage : m_lastV;
    m_rampStartI  = (idx > 0) ? m_steps[idx - 1].current : m_lastI;
    m_rampTargetV = s.voltage;
    m_rampTargetI = s.current;

    m_state = Ramping;
    emit stateChanged();

    m_phaseElapsed.start();
    m_rampTimer.start();
    m_phaseTimer.start(s.rampMs);
}

void SequenceEngine::startHold(int idx)
{
    const SequenceStep& s = m_steps[idx];
    m_rampTimer.stop();

    emit setVoltageRequested(s.voltage);
    emit setCurrentRequested(s.current);

    m_state = Holding;
    emit stateChanged();

    m_phaseElapsed.start();
    m_phaseTimer.start(s.holdMs);
}

void SequenceEngine::advance()
{
    ++m_stepIdx;
    if (m_stepIdx >= m_steps.size()) {
        m_rampTimer.stop();
        m_tickTimer.stop();
        emit setOutputRequested(false);
        m_state = Done;
        emit stateChanged();
        emit tick();
        emit finished();
        return;
    }
    applyStep(m_stepIdx);
}

void SequenceEngine::onPhaseTimer()
{
    if (m_state == Ramping) {
        // Ramp finished — snap to target and start hold
        emit setVoltageRequested(m_rampTargetV);
        emit setCurrentRequested(m_rampTargetI);
        startHold(m_stepIdx);
    } else if (m_state == Holding) {
        advance();
    }
}

void SequenceEngine::onRampTimer()
{
    if (m_state != Ramping) { m_rampTimer.stop(); return; }
    const SequenceStep& s = m_steps[m_stepIdx];
    double t = qMin(1.0, m_phaseElapsed.elapsed() / double(s.rampMs));
    double v = lerp(m_rampStartV, m_rampTargetV, t);
    double i = lerp(m_rampStartI, m_rampTargetI, t);
    emit setVoltageRequested(v);
    emit setCurrentRequested(i);
}

void SequenceEngine::onTickTimer()
{
    double t = elapsedSecs();
    emit newPoint(t, m_lastV, m_lastI);
    emit tick();
}

void SequenceEngine::emitPlannedCurve()
{
    // Emit planned step-function / ramp curve so chart can draw it immediately
    double t = 0;
    double prevV = 0, prevI = 0;
    for (int i = 0; i < m_steps.size(); ++i) {
        const SequenceStep& s = m_steps[i];
        if (s.ramp && i > 0) {
            emit plannedPoint(t,                       prevV,     prevI);
            emit plannedPoint(t + s.rampMs / 1000.0,  s.voltage, s.current);
            t += s.rampMs / 1000.0;
        } else {
            emit plannedPoint(t, s.voltage, s.current);
        }
        emit plannedPoint(t + s.holdMs / 1000.0, s.voltage, s.current);
        t += s.holdMs / 1000.0;
        prevV = s.voltage;
        prevI = s.current;
    }
}

double SequenceEngine::stepProgress() const
{
    if (m_state == Idle || m_state == Done || m_steps.isEmpty()) return 0;
    const SequenceStep& s = m_steps[m_stepIdx];
    int phaseDur = (m_state == Ramping) ? s.rampMs : s.holdMs;
    if (phaseDur <= 0) return 1;
    return qMin(1.0, m_phaseElapsed.elapsed() / double(phaseDur));
}

double SequenceEngine::totalProgress() const
{
    if (m_totalMs <= 0 || m_state == Idle) return 0;
    if (m_state == Done) return 1;
    return qMin(1.0, m_elapsed.elapsed() / double(m_totalMs));
}

QString SequenceEngine::phaseName() const
{
    switch (m_state) {
    case Idle:    return "Idle";
    case Ramping: return "Ramp";
    case Holding: return "Hold";
    case Done:    return "Done";
    case Fault:   return "Fault";
    }
    return "";
}
