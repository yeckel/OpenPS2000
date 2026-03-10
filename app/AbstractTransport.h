// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// AbstractTransport — common base class for SerialTransport (desktop) and
// AndroidSerialTransport (Android USB Host JNI).
// DeviceBackend holds an AbstractTransport* so it never needs to know which
// concrete transport is in use.
//
#pragma once
#include <QThread>
#include "PS2000Protocol.h"

class AbstractTransport : public QThread
{
    Q_OBJECT

public:
    explicit AbstractTransport(const QString& portName, QObject* parent = nullptr)
        : QThread(parent), m_portName(portName)
    {}

    // ── Thread-safe command queue ──────────────────────────────────────────
    // Normal queue: coalesces newer command for the same OBJ (replaces older).
    virtual void enqueueCommand(const QByteArray& telegram) = 0;

    // Urgent queue: bypasses coalescing (used for emergency output-OFF).
    virtual void enqueueUrgent(const QByteArray& telegram) = 0;

    // Request graceful thread stop.
    virtual void requestStop() = 0;

    // Read-only access to device identity (valid after deviceInfoReady signal).
    const PS2000::DeviceInfo& deviceInfo() const { return m_deviceInfo; }

signals:
    // Emitted once after successful device-info query on connection.
    void deviceInfoReady(const PS2000::DeviceInfo& info);

    // Emitted at each polling cycle (~4 Hz).
    void statusUpdated(const PS2000::DeviceStatus& status);

    // Current OVP / OCP limits (polled less frequently, ~every 10 cycles).
    void limitsUpdated(double ovpV, double ocpA);

    // Set-point values read back from device after issuing a command.
    void setValuesUpdated(double setV, double setI);

    void error(const QString& msg);
    void statusMessage(const QString& msg);

protected:
    QString            m_portName;
    PS2000::DeviceInfo m_deviceInfo;
};
