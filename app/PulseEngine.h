// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#pragma once
#include <QObject>
#include <QTimer>
#include <QElapsedTimer>
#include <qqmlregistration.h>

// ── PulseEngine ──────────────────────────────────────────────────────────────
// Software-timed square-wave / pulse generator for EA PS 2000 B.
// Min ON/OFF time is 50 ms (device protocol limit). Output alternates between
// an "on" setpoint and an "off" setpoint (or output disabled).
class PulseEngine : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("")

    Q_PROPERTY(int     state         READ state         NOTIFY stateChanged)
    Q_PROPERTY(int     cyclesDone    READ cyclesDone    NOTIFY cyclesDone_changed)
    Q_PROPERTY(double  elapsedSecs   READ elapsedSecs   NOTIFY tick)
    Q_PROPERTY(double  actualVoltage READ actualVoltage NOTIFY tick)
    Q_PROPERTY(double  actualCurrent READ actualCurrent NOTIFY tick)
    Q_PROPERTY(bool    inOnPhase     READ inOnPhase     NOTIFY stateChanged)

public:
    enum State { Idle = 0, OnPhase = 1, OffPhase = 2, Done = 3 };
    Q_ENUM(State)

    explicit PulseEngine(QObject *parent = nullptr);

    int    state()         const { return m_state; }
    int    cyclesDone()    const { return m_cyclesDone; }
    double elapsedSecs()   const;
    double actualVoltage() const { return m_lastV; }
    double actualCurrent() const { return m_lastI; }
    bool   inOnPhase()     const { return m_state == OnPhase; }

public slots:
    // Called from QML to start
    void start(double onVoltage, double onCurrent,
               double offVoltage, double offCurrent,
               bool   outputOffDuringOff,
               int    onTimeMs, int offTimeMs,
               int    totalCycles);   // 0 = infinite
    void stop();

    // Called by DeviceBackend::newSample to update live readback
    void onSample(double t, double v, double i, double p);

signals:
    void stateChanged();
    void cyclesDone_changed();
    void tick();                        // 4 Hz display refresh
    void finished(int cycles);
    void faulted(const QString &msg);

    // Routed to DeviceBackend slots
    void setVoltageRequested(double v);
    void setCurrentRequested(double a);
    void setOutputRequested(bool on);

    // Emitted for the live chart: (elapsed_s, voltage, current)
    void newPoint(double t, double v, double i);

private slots:
    void onPhaseTimer();
    void onTickTimer();

private:
    void applyOn();
    void applyOff();
    void advanceCycle();

    QTimer        m_phaseTimer;
    QTimer        m_tickTimer;
    QElapsedTimer m_elapsed;

    State  m_state       = Idle;
    int    m_cyclesDone  = 0;
    int    m_totalCycles = 0;   // 0 = infinite

    double m_onVoltage  = 5.0;
    double m_onCurrent  = 1.0;
    double m_offVoltage = 0.0;
    double m_offCurrent = 0.1;
    bool   m_offDisable = false;
    int    m_onTimeMs   = 500;
    int    m_offTimeMs  = 500;

    double m_lastV = 0.0;
    double m_lastI = 0.0;
    double m_startT = 0.0;      // elapsed seconds at run start
};
