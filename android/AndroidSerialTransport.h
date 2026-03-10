// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// AndroidSerialTransport — full drop-in replacement for SerialTransport on
// Android.  Runs the same 4 Hz PS2000 polling loop as the desktop transport
// but uses Android USB Host API (via JNI → UsbSerial.java) instead of
// QSerialPort, since the latter is not available on Android.
//
#pragma once

#include "../app/AbstractTransport.h"
#include <QAtomicInt>
#include <QMutex>
#include <QMap>
#include <QQueue>
#include <QByteArray>
#include <QStringList>

class AndroidSerialTransport : public AbstractTransport
{
    Q_OBJECT

public:
    explicit AndroidSerialTransport(const QString& portName = QString(),
                                    QObject* parent = nullptr);

    // ── AbstractTransport interface ───────────────────────────────────────
    void enqueueCommand(const QByteArray& telegram) override;
    void enqueueUrgent(const QByteArray& telegram) override;
    void requestStop() override;

    // ── Android-specific ─────────────────────────────────────────────────
    // Returns list of EA USB device names detected via UsbManager.
    static QStringList listDevices();

protected:
    void run() override;

private:
    // Low-level JNI I/O (called only from the worker thread).
    bool      jniOpen(const QString& deviceName);
    void      jniClose();
    int       jniWrite(const QByteArray& data);
    QByteArray jniRead(int maxLen, int timeoutMs = 300);

    // Protocol helpers — mirror SerialTransport private methods.
    QByteArray readBytes(int expected, int timeoutMs = 300);
    bool       sendAndAck(const QByteArray& telegram);
    QByteArray queryObject(uint8_t obj, int dataLen);
    void       readDeviceInfo();

    QAtomicInt         m_stopFlag{0};
    mutable QMutex     m_cmdMutex;

    // Coalescing command queue (same as desktop).
    QMap<quint16, QByteArray> m_cmdMap;
    QQueue<quint16>           m_cmdOrder;
    QByteArray                m_urgentCmd;
};

