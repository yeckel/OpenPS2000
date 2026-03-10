// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// SerialTransport.h — QThread worker for EA PS 2000 B over USB VCP.
// Communicates at 115200 baud, odd parity, 8 data bits, 1 stop bit.
#pragma once

#include "AbstractTransport.h"
#include <QMutex>
#include <QQueue>
#include <QMap>
#include <QAtomicInt>
#include <QByteArray>
#include <QString>

class SerialTransport : public AbstractTransport
{
    Q_OBJECT

public:
    explicit SerialTransport(const QString& portName, QObject* parent = nullptr);

    void enqueueCommand(const QByteArray& telegram) override;
    void enqueueUrgent(const QByteArray& telegram) override;
    void requestStop() override;

protected:
    void run() override;

private:
    QByteArray readBytes(void* port, int expected, int timeoutMs = 300) const;
    bool sendAndAck(void* port, const QByteArray& telegram) const;
    QByteArray queryObject(void* port, uint8_t obj, int dataLen) const;
    void readDeviceInfo(void* port);

    QAtomicInt         m_stopFlag{0};
    mutable QMutex     m_cmdMutex;

    // Coalescing queue: object-key → telegram, insertion-ordered via m_cmdOrder.
    QMap<quint16, QByteArray> m_cmdMap;
    QQueue<quint16>           m_cmdOrder;

    // Urgent slot — always dequeued before m_cmdMap entries.
    QByteArray m_urgentCmd;
};
