// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#include "SerialTransport.h"

#include <QSerialPort>
#include <QThread>
#include <QMutexLocker>
#include <QDebug>

// ── Constructor ───────────────────────────────────────────────────────────
SerialTransport::SerialTransport(const QString& portName, QObject* parent)
    : QThread(parent), m_portName(portName)
{}

void SerialTransport::requestStop()
{
    m_stopFlag.storeRelease(1);
}

void SerialTransport::enqueueCommand(const QByteArray& telegram)
{
    if (telegram.size() < 3) return;
    // Key = (device_node << 8) | object — coalesce commands for the same object.
    quint16 key = (quint8(telegram[1]) << 8) | quint8(telegram[2]);
    QMutexLocker lock(&m_cmdMutex);
    if (!m_cmdMap.contains(key))
        m_cmdOrder.enqueue(key);   // preserve insertion order for new objects
    m_cmdMap[key] = telegram;      // overwrite any older command for this object
}

void SerialTransport::enqueueUrgent(const QByteArray& telegram)
{
    QMutexLocker lock(&m_cmdMutex);
    // Clear any pending normal commands — urgent takes over immediately.
    m_cmdMap.clear();
    m_cmdOrder.clear();
    m_urgentCmd = telegram;
}

// ── Thread entry point ────────────────────────────────────────────────────
void SerialTransport::run()
{
    QSerialPort port;
    port.setPortName(m_portName);
    port.setBaudRate(115200);
    port.setParity(QSerialPort::OddParity);
    port.setDataBits(QSerialPort::Data8);
    port.setStopBits(QSerialPort::OneStop);
    port.setFlowControl(QSerialPort::NoFlowControl);

    if(!port.open(QIODevice::ReadWrite))
    {
        emit error(QString("Cannot open %1: %2").arg(m_portName, port.errorString()));
        return;
    }
    port.clear();

    emit statusMessage(QString("Connected to %1").arg(m_portName));

    // Read device identity and nominal values.
    readDeviceInfo(static_cast<void*>(&port));

    if(m_stopFlag.loadAcquire())
    {
        port.close();
        return;
    }

    // Emit device info to backend.
    emit deviceInfoReady(m_deviceInfo);
    emit statusMessage(QString("Device: %1 — %2 V / %3 A / %4 W")
                       .arg(m_deviceInfo.deviceType)
                       .arg(m_deviceInfo.nomVoltage, 0, 'f', 1)
                       .arg(m_deviceInfo.nomCurrent, 0, 'f', 2)
                       .arg(m_deviceInfo.nomPower,   0, 'f', 0));

    // Read initial setpoints and protection limits.
    {
        QByteArray d72 = queryObject(static_cast<void*>(&port), PS2000::OBJ_STATUS_SET, 6);
        if(d72.size() == 6)
        {
            emit setValuesUpdated(
                PS2000::fromRaw(PS2000::parseUint16BE(d72, 2), m_deviceInfo.nomVoltage),
                PS2000::fromRaw(PS2000::parseUint16BE(d72, 4), m_deviceInfo.nomCurrent));
        }
        QByteArray dOvp = queryObject(static_cast<void*>(&port), PS2000::OBJ_OVP, 2);
        QByteArray dOcp = queryObject(static_cast<void*>(&port), PS2000::OBJ_OCP, 2);
        if(dOvp.size() == 2 && dOcp.size() == 2)
        {
            emit limitsUpdated(
                PS2000::fromLimitRaw(PS2000::parseUint16BE(dOvp), m_deviceInfo.nomVoltage),
                PS2000::fromLimitRaw(PS2000::parseUint16BE(dOcp), m_deviceInfo.nomCurrent));
        }
    }

    // ── Main loop ─────────────────────────────────────────────────────────
    int loopCnt = 0;
    while(!m_stopFlag.loadAcquire())
    {

        // Dequeue next command: urgent slot first, then coalesced map.
        QByteArray cmd;
        {
            QMutexLocker lock(&m_cmdMutex);
            if (!m_urgentCmd.isEmpty()) {
                cmd = m_urgentCmd;
                m_urgentCmd.clear();
            } else if (!m_cmdOrder.isEmpty()) {
                quint16 key = m_cmdOrder.dequeue();
                cmd = m_cmdMap.take(key);
            }
        }

        if(!cmd.isEmpty())
        {
            bool ok = sendAndAck(static_cast<void*>(&port), cmd);
            if(!ok)
            {
                emit statusMessage("Command error or timeout");
            }

            // After any setpoint command, re-read set values from obj 72.
            QByteArray d72 = queryObject(static_cast<void*>(&port), PS2000::OBJ_STATUS_SET, 6);
            if(d72.size() == 6)
            {
                uint16_t rawV = PS2000::parseUint16BE(d72, 2);
                uint16_t rawI = PS2000::parseUint16BE(d72, 4);
                emit setValuesUpdated(
                    PS2000::fromRaw(rawV, m_deviceInfo.nomVoltage),
                    PS2000::fromRaw(rawI, m_deviceInfo.nomCurrent));
            }
        }
        else
        {
            // Poll actual status (obj 71).
            QByteArray d71 = queryObject(static_cast<void*>(&port), PS2000::OBJ_STATUS_ACTUAL, 6);
            if(d71.size() == 6)
            {
                PS2000::DeviceStatus st = PS2000::parseStatus(
                                              d71, m_deviceInfo.nomVoltage, m_deviceInfo.nomCurrent);
                emit statusUpdated(st);
            }

            // Poll limits every 10 cycles (~2.5 s).
            if(loopCnt % 10 == 0)
            {
                QByteArray dOvp = queryObject(static_cast<void*>(&port), PS2000::OBJ_OVP, 2);
                QByteArray dOcp = queryObject(static_cast<void*>(&port), PS2000::OBJ_OCP, 2);
                if(dOvp.size() == 2 && dOcp.size() == 2)
                {
                    double ovpV = PS2000::fromLimitRaw(
                                      PS2000::parseUint16BE(dOvp), m_deviceInfo.nomVoltage);
                    double ocpA = PS2000::fromLimitRaw(
                                      PS2000::parseUint16BE(dOcp), m_deviceInfo.nomCurrent);
                    emit limitsUpdated(ovpV, ocpA);
                }
            }
        }

        ++loopCnt;
        QThread::msleep(250);  // 4 Hz
    }

    port.close();
    emit statusMessage("Disconnected");
}

// ── Helpers ───────────────────────────────────────────────────────────────
QByteArray SerialTransport::readBytes(void* vport, int expected, int timeoutMs) const
{
    auto* port = static_cast<QSerialPort*>(vport);
    QByteArray buf;
    buf.reserve(expected);

    int elapsed = 0;
    const int step = 20;
    while(buf.size() < expected && elapsed < timeoutMs)
    {
        if(port->bytesAvailable() > 0 || port->waitForReadyRead(step))
        {
            buf += port->readAll();
        }
        elapsed += step;
    }
    return buf;
}

bool SerialTransport::sendAndAck(void* vport, const QByteArray& telegram) const
{
    auto* port = static_cast<QSerialPort*>(vport);
    port->clear();
    port->write(telegram);
    if(!port->waitForBytesWritten(200))
    {
        return false;
    }

    // ACK telegram: SD(0x80) DN OBJ ERROR_BYTE CS_HI CS_LO = 6 bytes
    QByteArray ack = readBytes(vport, 6, 300);
    if(ack.size() < 6)
    {
        return false;
    }

    uint8_t obj;
    QByteArray data;
    if(!PS2000::parseResponse(ack, obj, data))
    {
        return false;
    }
    // Error byte 0 = success
    return data.size() >= 1 && static_cast<uint8_t>(data[0]) == 0;
}

QByteArray SerialTransport::queryObject(void* vport, uint8_t obj, int dataLen) const
{
    auto* port = static_cast<QSerialPort*>(vport);
    port->clear();
    port->write(PS2000::buildQuery(obj, 0, dataLen));
    if(!port->waitForBytesWritten(200)) return {};

    int totalLen = 3 + dataLen + 2;  // SD + DN + OBJ + DATA + CS[2]
    QByteArray raw = readBytes(vport, totalLen, 300);
    if(raw.size() < totalLen) return {};

    uint8_t respObj;
    QByteArray respData;
    if(!PS2000::parseResponse(raw, respObj, respData)) return {};
    if(respObj != obj) return {};
    return respData;
}

void SerialTransport::readDeviceInfo(void* vport)
{
    // Helper to query a null-terminated string object.
    auto readString = [&](uint8_t obj) -> QString
    {
        QByteArray d = queryObject(vport, obj, 16);
        if(d.isEmpty()) return {};
        int nul = d.indexOf('\0');
        return QString::fromLatin1(nul >= 0 ? d.left(nul) : d);
    };

    m_deviceInfo.deviceType  = readString(PS2000::OBJ_DEVICE_TYPE);
    m_deviceInfo.serialNo    = readString(PS2000::OBJ_SERIAL_NO);
    m_deviceInfo.articleNo   = readString(PS2000::OBJ_ARTICLE_NO);
    m_deviceInfo.manufacturer = readString(PS2000::OBJ_MANUFACTURER);
    m_deviceInfo.swVersion   = readString(PS2000::OBJ_SW_VERSION);

    // Nominal values (IEEE754 float, 4 bytes)
    auto readFloat = [&](uint8_t obj) -> float
    {
        QByteArray d = queryObject(vport, obj, 4);
        return PS2000::parseFloat32BE(d);
    };
    m_deviceInfo.nomVoltage = readFloat(PS2000::OBJ_NOM_VOLTAGE);
    m_deviceInfo.nomCurrent = readFloat(PS2000::OBJ_NOM_CURRENT);
    m_deviceInfo.nomPower   = readFloat(PS2000::OBJ_NOM_POWER);

    // Device class
    QByteArray dc = queryObject(vport, PS2000::OBJ_DEVICE_CLASS, 2);
    if(dc.size() == 2)
    {
        m_deviceInfo.deviceClass = PS2000::parseUint16BE(dc);
        m_deviceInfo.isTriple    = (m_deviceInfo.deviceClass == 0x0018);
    }
}
