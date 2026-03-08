// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// SerialTransport.h — QThread worker for EA PS 2000 B over USB VCP.
// Communicates at 115200 baud, odd parity, 8 data bits, 1 stop bit.
#pragma once

#include "PS2000Protocol.h"
#include <QThread>
#include <QMutex>
#include <QQueue>
#include <QAtomicInt>
#include <QByteArray>
#include <QString>

class SerialTransport : public QThread
{
    Q_OBJECT

public:
    explicit SerialTransport(const QString& portName, QObject* parent = nullptr);

    // Thread-safe; may be called from any thread to enqueue a command telegram.
    void enqueueCommand(const QByteArray& telegram);

    // Request graceful stop (thread-safe).
    void requestStop();

    const PS2000::DeviceInfo& deviceInfo() const { return m_deviceInfo; }

signals:
    // Emitted after successful device info read on connection.
    void deviceInfoReady(const PS2000::DeviceInfo& info);

    // Emitted at each polling cycle (~4 Hz).
    void statusUpdated(const PS2000::DeviceStatus& status);

    // Current OVP/OCP limits (polled less frequently).
    void limitsUpdated(double ovpV, double ocpA);

    // Set values from device (polled after sending commands).
    void setValuesUpdated(double setV, double setI);

    void error(const QString& msg);
    void statusMessage(const QString& msg);

protected:
    void run() override;

private:
    // Read exactly `expected` bytes from serial port with timeout.
    // Returns the bytes read; may be fewer on timeout.
    QByteArray readBytes(void* port, int expected, int timeoutMs = 300) const;

    // Send telegram and read ACK (error response, 6 bytes).
    // Returns true if acknowledged without error.
    bool sendAndAck(void* port, const QByteArray& telegram) const;

    // Query an object and return the data bytes.
    QByteArray queryObject(void* port, uint8_t obj, int dataLen) const;

    // Read all device info strings and nominal values.
    void readDeviceInfo(void* port);

    QString            m_portName;
    QAtomicInt         m_stopFlag{0};
    mutable QMutex     m_cmdMutex;
    QQueue<QByteArray> m_cmdQueue;
    PS2000::DeviceInfo m_deviceInfo;
};
