// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#pragma once
#include "SequenceProfile.h"
#include <QObject>
#include <QTimer>
#include <QElapsedTimer>
#include <qqmlregistration.h>

class SequenceEngine : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("")

    Q_PROPERTY(int    state        READ state        NOTIFY stateChanged)
    Q_PROPERTY(int    currentStep  READ currentStep  NOTIFY stepChanged)
    Q_PROPERTY(double stepProgress READ stepProgress NOTIFY tick)   // 0–1 within current step
    Q_PROPERTY(double totalProgress READ totalProgress NOTIFY tick) // 0–1 overall
    Q_PROPERTY(double elapsedSecs  READ elapsedSecs  NOTIFY tick)
    Q_PROPERTY(int    totalSteps   READ totalSteps   NOTIFY stateChanged)
    Q_PROPERTY(QString phaseName   READ phaseName    NOTIFY stateChanged)

public:
    enum State { Idle = 0, Ramping = 1, Holding = 2, Done = 3, Fault = 4 };
    Q_ENUM(State)

    explicit SequenceEngine(QObject* parent = nullptr);

    int    state()         const { return m_state; }
    int    currentStep()   const { return m_stepIdx; }
    double stepProgress()  const;
    double totalProgress() const;
    double elapsedSecs()   const { return m_elapsed.isValid() ? m_elapsed.elapsed() / 1000.0 : 0; }
    int    totalSteps()    const { return m_steps.size(); }
    QString phaseName()    const;

public slots:
    void start(const QVariantList& steps);  // list of QVariantMap steps
    void stop();
    void onSample(double t, double v, double i, double p);

signals:
    void stateChanged();
    void stepChanged(int step);
    void tick();
    void finished();
    void faulted(const QString& msg);

    // Actual chart point
    void newPoint(double t, double v, double i);
    // Planned (target) chart point — emitted when plan is computed and during ramp
    void plannedPoint(double t, double v, double i);

    void setVoltageRequested(double v);
    void setCurrentRequested(double a);
    void setOutputRequested(bool on);

private slots:
    void onPhaseTimer();
    void onRampTimer();
    void onTickTimer();

private:
    void applyStep(int idx);
    void startRamp(int idx);
    void startHold(int idx);
    void advance();
    void emitPlannedCurve();
    double lerp(double a, double b, double t) { return a + (b - a) * t; }

    QTimer        m_phaseTimer;   // single-shot: triggers phase end
    QTimer        m_rampTimer;    // 250 ms periodic: sends interpolated setpoints
    QTimer        m_tickTimer;    // 250 ms periodic: updates display
    QElapsedTimer m_elapsed;      // total elapsed
    QElapsedTimer m_phaseElapsed; // elapsed within current phase

    State m_state   = Idle;
    int   m_stepIdx = 0;

    QList<SequenceStep> m_steps;

    // For ramp interpolation
    double m_rampStartV  = 0;
    double m_rampStartI  = 0;
    double m_rampTargetV = 0;
    double m_rampTargetI = 0;

    // Last known actual values (from onSample)
    double m_lastV = 0, m_lastI = 0;
    // Accumulated total ms before current step (for progress calculation)
    QList<int> m_stepStartMs; // cumulative ms at start of each step
    int        m_totalMs = 0;
};
