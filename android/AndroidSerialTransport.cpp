// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#include "AndroidSerialTransport.h"

#include <QJniObject>
#include <QJniEnvironment>
#include <QCoreApplication>
#include <QMutexLocker>
#include <QThread>
#include <QDebug>

#include "../app/PS2000Protocol.h"

static constexpr const char* JAVA_CLASS = "org/openps2000/UsbSerial";

// ── Constructor / Destructor ──────────────────────────────────────────────

AndroidSerialTransport::AndroidSerialTransport(const QString& portName,
                                               QObject* parent)
    : AbstractTransport(portName, parent)
{}

// ── AbstractTransport interface ───────────────────────────────────────────

void AndroidSerialTransport::requestStop()
{
    m_stopFlag.storeRelease(1);
}

void AndroidSerialTransport::enqueueCommand(const QByteArray& telegram)
{
    if (telegram.size() < 3) return;
    quint16 key = (quint8(telegram[1]) << 8) | quint8(telegram[2]);
    QMutexLocker lock(&m_cmdMutex);
    if (!m_cmdMap.contains(key))
        m_cmdOrder.enqueue(key);
    m_cmdMap[key] = telegram;
}

void AndroidSerialTransport::enqueueUrgent(const QByteArray& telegram)
{
    QMutexLocker lock(&m_cmdMutex);
    m_cmdMap.clear();
    m_cmdOrder.clear();
    m_urgentCmd = telegram;
}

// ── Static helper: list EA USB devices ───────────────────────────────────

QStringList AndroidSerialTransport::listDevices()
{
    QJniObject ctx = QNativeInterface::QAndroidApplication::context();
    if (!ctx.isValid()) return {};

    QJniEnvironment env;
    auto arr = static_cast<jobjectArray>(
        QJniObject::callStaticMethod<jobject>(
            JAVA_CLASS, "listDevices",
            "(Landroid/content/Context;)[Ljava/lang/String;",
            ctx.object<jobject>()));

    QStringList result;
    if (!arr) return result;
    const int len = env->GetArrayLength(arr);
    for (int i = 0; i < len; ++i) {
        auto s = static_cast<jstring>(env->GetObjectArrayElement(arr, i));
        result << QJniObject(s).toString();
        env->DeleteLocalRef(s);
    }
    env->DeleteLocalRef(arr);
    return result;
}

// ── QThread run() — mirrors SerialTransport::run() but uses JNI I/O ──────

void AndroidSerialTransport::run()
{
    // Open the USB device.  Empty portName → auto-select first EA device.
    QString devName = m_portName;
    if (devName.isEmpty()) {
        QStringList devs = listDevices();
        if (devs.isEmpty()) {
            emit error("No EA USB device found");
            return;
        }
        devName = devs.first();
    }

    if (!jniOpen(devName)) {
        emit error(QString("Cannot open USB device: %1").arg(devName));
        return;
    }

    emit statusMessage(QString("Connected to %1").arg(devName));

    // Read device identity and nominal values.
    readDeviceInfo();

    if (m_stopFlag.loadAcquire()) {
        jniClose();
        return;
    }

    emit deviceInfoReady(m_deviceInfo);
    emit statusMessage(QString("Device: %1 — %2 V / %3 A / %4 W")
                       .arg(m_deviceInfo.deviceType)
                       .arg(m_deviceInfo.nomVoltage, 0, 'f', 1)
                       .arg(m_deviceInfo.nomCurrent, 0, 'f', 2)
                       .arg(m_deviceInfo.nomPower,   0, 'f', 0));

    // Read initial setpoints and limits.
    {
        QByteArray d72 = queryObject(PS2000::OBJ_STATUS_SET, 6);
        if (d72.size() == 6)
            emit setValuesUpdated(
                PS2000::fromRaw(PS2000::parseUint16BE(d72, 2), m_deviceInfo.nomVoltage),
                PS2000::fromRaw(PS2000::parseUint16BE(d72, 4), m_deviceInfo.nomCurrent));

        QByteArray dOvp = queryObject(PS2000::OBJ_OVP, 2);
        QByteArray dOcp = queryObject(PS2000::OBJ_OCP, 2);
        if (dOvp.size() == 2 && dOcp.size() == 2)
            emit limitsUpdated(
                PS2000::fromLimitRaw(PS2000::parseUint16BE(dOvp), m_deviceInfo.nomVoltage),
                PS2000::fromLimitRaw(PS2000::parseUint16BE(dOcp), m_deviceInfo.nomCurrent));
    }

    // ── Main loop ─────────────────────────────────────────────────────────
    int loopCnt   = 0;
    int failStreak = 0;
    static constexpr int MAX_FAILS = 4;

    while (!m_stopFlag.loadAcquire()) {
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

        if (!cmd.isEmpty()) {
            bool ok = sendAndAck(cmd);
            if (!ok) {
                emit statusMessage("Command error or timeout");
                ++failStreak;
            } else {
                failStreak = 0;
                QByteArray d72 = queryObject(PS2000::OBJ_STATUS_SET, 6);
                if (d72.size() == 6)
                    emit setValuesUpdated(
                        PS2000::fromRaw(PS2000::parseUint16BE(d72, 2), m_deviceInfo.nomVoltage),
                        PS2000::fromRaw(PS2000::parseUint16BE(d72, 4), m_deviceInfo.nomCurrent));
            }
        } else {
            QByteArray d71 = queryObject(PS2000::OBJ_STATUS_ACTUAL, 6);
            if (d71.size() == 6) {
                failStreak = 0;
                emit statusUpdated(PS2000::parseStatus(
                    d71, m_deviceInfo.nomVoltage, m_deviceInfo.nomCurrent));
            } else {
                ++failStreak;
            }

            if (loopCnt % 10 == 0) {
                QByteArray dOvp = queryObject(PS2000::OBJ_OVP, 2);
                QByteArray dOcp = queryObject(PS2000::OBJ_OCP, 2);
                if (dOvp.size() == 2 && dOcp.size() == 2)
                    emit limitsUpdated(
                        PS2000::fromLimitRaw(PS2000::parseUint16BE(dOvp), m_deviceInfo.nomVoltage),
                        PS2000::fromLimitRaw(PS2000::parseUint16BE(dOcp), m_deviceInfo.nomCurrent));
            }
        }

        if (failStreak >= MAX_FAILS) {
            emit error("Device not responding — cable disconnected?");
            break;
        }

        ++loopCnt;
        QThread::msleep(250);  // 4 Hz
    }

    jniClose();
    emit statusMessage("Disconnected");
}

// ── JNI I/O helpers ───────────────────────────────────────────────────────

bool AndroidSerialTransport::jniOpen(const QString& deviceName)
{
    QJniObject ctx = QNativeInterface::QAndroidApplication::context();
    if (!ctx.isValid()) return false;

    QJniObject jName = QJniObject::fromString(deviceName);
    return QJniObject::callStaticMethod<jboolean>(
        JAVA_CLASS, "open",
        "(Landroid/content/Context;Ljava/lang/String;)Z",
        ctx.object<jobject>(),
        jName.object<jstring>());
}

void AndroidSerialTransport::jniClose()
{
    QJniObject::callStaticMethod<void>(JAVA_CLASS, "close", "()V");
}

int AndroidSerialTransport::jniWrite(const QByteArray& data)
{
    QJniEnvironment env;
    jbyteArray jData = env->NewByteArray(data.size());
    env->SetByteArrayRegion(jData, 0, data.size(),
                            reinterpret_cast<const jbyte*>(data.constData()));
    int written = QJniObject::callStaticMethod<jint>(
        JAVA_CLASS, "write", "([B)I", jData);
    env->DeleteLocalRef(jData);
    return written;
}

QByteArray AndroidSerialTransport::jniRead(int maxLen, int /*timeoutMs*/)
{
    QJniEnvironment env;
    jbyteArray jBuf = env->NewByteArray(maxLen);
    jint got = QJniObject::callStaticMethod<jint>(
        JAVA_CLASS, "read", "([BI)I", jBuf, static_cast<jint>(maxLen));

    QByteArray result;
    if (got > 0) {
        result.resize(got);
        env->GetByteArrayRegion(jBuf, 0, got,
                                reinterpret_cast<jbyte*>(result.data()));
    }
    env->DeleteLocalRef(jBuf);
    return result;
}

// ── Protocol helpers — mirror SerialTransport private methods ─────────────

QByteArray AndroidSerialTransport::readBytes(int expected, int timeoutMs)
{
    QByteArray buf;
    buf.reserve(expected);
    const int stepMs = 20;
    int elapsed = 0;
    while (buf.size() < expected && elapsed < timeoutMs) {
        QByteArray chunk = jniRead(expected - buf.size(), stepMs);
        if (!chunk.isEmpty())
            buf += chunk;
        else
            QThread::msleep(stepMs);
        elapsed += stepMs;
    }
    return buf;
}

bool AndroidSerialTransport::sendAndAck(const QByteArray& telegram)
{
    if (jniWrite(telegram) < 0) return false;

    // ACK: SD DN OBJ ERROR_BYTE CS_HI CS_LO = 6 bytes
    QByteArray ack = readBytes(6, 300);
    if (ack.size() < 6) return false;

    uint8_t obj;
    QByteArray data;
    if (!PS2000::parseResponse(ack, obj, data)) return false;
    return data.size() >= 1 && static_cast<uint8_t>(data[0]) == 0;
}

QByteArray AndroidSerialTransport::queryObject(uint8_t obj, int dataLen)
{
    QByteArray query = PS2000::buildQuery(obj, 0, dataLen);
    if (jniWrite(query) < 0) return {};

    int totalLen = 3 + dataLen + 2;
    QByteArray raw = readBytes(totalLen, 300);
    if (raw.size() < totalLen) return {};

    uint8_t respObj;
    QByteArray respData;
    if (!PS2000::parseResponse(raw, respObj, respData)) return {};
    if (respObj != obj) return {};
    return respData;
}

void AndroidSerialTransport::readDeviceInfo()
{
    auto readString = [this](uint8_t obj) -> QString {
        QByteArray d = queryObject(obj, 16);
        if (d.isEmpty()) return {};
        int nul = d.indexOf('\0');
        return QString::fromLatin1(nul >= 0 ? d.left(nul) : d);
    };

    m_deviceInfo.deviceType   = readString(PS2000::OBJ_DEVICE_TYPE);
    m_deviceInfo.serialNo     = readString(PS2000::OBJ_SERIAL_NO);
    m_deviceInfo.articleNo    = readString(PS2000::OBJ_ARTICLE_NO);
    m_deviceInfo.manufacturer = readString(PS2000::OBJ_MANUFACTURER);
    m_deviceInfo.swVersion    = readString(PS2000::OBJ_SW_VERSION);

    auto readFloat = [this](uint8_t obj) -> float {
        QByteArray d = queryObject(obj, 4);
        return PS2000::parseFloat32BE(d);
    };
    m_deviceInfo.nomVoltage = readFloat(PS2000::OBJ_NOM_VOLTAGE);
    m_deviceInfo.nomCurrent = readFloat(PS2000::OBJ_NOM_CURRENT);
    m_deviceInfo.nomPower   = readFloat(PS2000::OBJ_NOM_POWER);

    QByteArray dc = queryObject(PS2000::OBJ_DEVICE_CLASS, 2);
    if (dc.size() == 2) {
        m_deviceInfo.deviceClass = PS2000::parseUint16BE(dc);
        m_deviceInfo.isTriple    = (m_deviceInfo.deviceClass == 0x0018);
    }
}
