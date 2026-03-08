// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#include "DeviceBackend.h"
#include "XlsxWriter.h"

#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QSerialPortInfo>
#include <QTextStream>
#include <QUrl>
#include <limits>
#include <cmath>

static double nowSecs()
{
    return QDateTime::currentMSecsSinceEpoch() / 1000.0;
}

static QString urlToPath(const QString& p)
{
    if(p.startsWith("file:///"))
    {
        return p.mid(7);
    }
    if(p.startsWith("file://"))
    {
        return p.mid(7);
    }
    return p;
}

static QString formatDuration(qint64 secs)
{
    return QString("%1:%2:%3")
           .arg(secs / 3600, 2, 10, QChar('0'))
           .arg((secs % 3600) / 60, 2, 10, QChar('0'))
           .arg(secs % 60, 2, 10, QChar('0'));
}

// ── Constructor / destructor ──────────────────────────────────────────────
DeviceBackend::DeviceBackend(QObject* parent) : QObject(parent)
{
    m_durationTimer = new QTimer(this);
    m_durationTimer->setInterval(1000);
    connect(m_durationTimer, &QTimer::timeout, this, &DeviceBackend::onDurationTick);
}

DeviceBackend::~DeviceBackend()
{
    cleanupTransport();
}

// ── Available ports ───────────────────────────────────────────────────────
QStringList DeviceBackend::availablePorts() const
{
    QStringList result;
    for(const auto& info : QSerialPortInfo::availablePorts())
    {
        result << info.portName();
    }
    return result;
}

// ── Connection management ─────────────────────────────────────────────────
void DeviceBackend::connectDevice(const QString& portName)
{
    if(m_connected)
    {
        return;
    }

    cleanupTransport();
    m_readings.clear();
    m_energyWh   = 0.0;
    m_energyBase = 0.0;
    m_startTime  = nowSecs();
    m_lastT      = -1.0;
    m_lastPower  = 0.0;
    m_portName   = portName;

    m_transport = new SerialTransport(portName, this);

    connect(m_transport, &SerialTransport::deviceInfoReady,
            this, &DeviceBackend::onDeviceInfoReady, Qt::QueuedConnection);
    connect(m_transport, &SerialTransport::statusUpdated,
            this, &DeviceBackend::onStatusUpdated, Qt::QueuedConnection);
    connect(m_transport, &SerialTransport::limitsUpdated,
            this, &DeviceBackend::onLimitsUpdated, Qt::QueuedConnection);
    connect(m_transport, &SerialTransport::setValuesUpdated,
            this, &DeviceBackend::onSetValuesUpdated, Qt::QueuedConnection);
    connect(m_transport, &SerialTransport::error,
            this, &DeviceBackend::onTransportError, Qt::QueuedConnection);
    connect(m_transport, &SerialTransport::statusMessage,
            this, &DeviceBackend::onTransportMessage, Qt::QueuedConnection);

    m_transport->start();
    m_connected = true;
    m_durationTimer->start();

    emit connectedChanged(true);
    emit portNameChanged(portName);
    emit statusMessage(QString("Connecting to %1…").arg(portName));
}

void DeviceBackend::disconnectDevice()
{
    if(!m_connected)
    {
        return;
    }

    // Switch back to manual mode before disconnect
    sendCommand(PS2000::buildControl(0, PS2000::CTRL_REMOTE_MASK, PS2000::CTRL_REMOTE_OFF));
    QThread::msleep(100);

    m_connected = false;
    m_durationTimer->stop();
    cleanupTransport();

    emit connectedChanged(false);
    emit statusMessage(QString("Disconnected — %1 samples, %2 Wh")
                       .arg(m_readings.size())
                       .arg(m_energyWh, 0, 'f', 3));
}

void DeviceBackend::cleanupTransport()
{
    if(!m_transport)
    {
        return;
    }
    m_transport->requestStop();
    m_transport->quit();
    if(!m_transport->wait(3000))
    {
        m_transport->terminate();
    }
    delete m_transport;
    m_transport = nullptr;
}

// ── Control commands ──────────────────────────────────────────────────────
void DeviceBackend::sendCommand(const QByteArray& telegram)
{
    if(m_transport)
    {
        m_transport->enqueueCommand(telegram);
    }
}

void DeviceBackend::setRemoteMode(bool remote)
{
    sendCommand(PS2000::buildControl(
                    0,
                    PS2000::CTRL_REMOTE_MASK,
                    remote ? PS2000::CTRL_REMOTE_ON : PS2000::CTRL_REMOTE_OFF));
}

void DeviceBackend::setOutputOn(bool on)
{
    QByteArray telegram = PS2000::buildControl(
                    0,
                    PS2000::CTRL_OUTPUT_MASK,
                    on ? PS2000::CTRL_OUTPUT_ON : PS2000::CTRL_OUTPUT_OFF);
    if (!on && m_transport) {
        // Output OFF is safety-critical — bypass and flush the command queue.
        m_transport->enqueueUrgent(telegram);
    } else {
        sendCommand(telegram);
    }
}

void DeviceBackend::setOutputOnQueued(bool on)
{
    // Always use the normal coalescing queue — safe for pulse-cycle transitions
    // where we must not flush pending setpoint commands.
    sendCommand(PS2000::buildControl(
                    0,
                    PS2000::CTRL_OUTPUT_MASK,
                    on ? PS2000::CTRL_OUTPUT_ON : PS2000::CTRL_OUTPUT_OFF));
}

void DeviceBackend::sendSetVoltage(double voltage)
{
    if(m_deviceInfo.nomVoltage <= 0)
    {
        return;
    }
    uint16_t raw = PS2000::toRaw(voltage, m_deviceInfo.nomVoltage);
    sendCommand(PS2000::buildSetInt(PS2000::OBJ_SET_VOLTAGE, 0, raw));
}

void DeviceBackend::sendSetCurrent(double current)
{
    if(m_deviceInfo.nomCurrent <= 0)
    {
        return;
    }
    uint16_t raw = PS2000::toRaw(current, m_deviceInfo.nomCurrent);
    sendCommand(PS2000::buildSetInt(PS2000::OBJ_SET_CURRENT, 0, raw));
}

void DeviceBackend::sendOvpVoltage(double voltage)
{
    if(m_deviceInfo.nomVoltage <= 0)
    {
        return;
    }
    uint16_t raw = PS2000::toLimitRaw(voltage, m_deviceInfo.nomVoltage);
    sendCommand(PS2000::buildSetInt(PS2000::OBJ_OVP, 0, raw));
}

void DeviceBackend::sendOcpCurrent(double current)
{
    if(m_deviceInfo.nomCurrent <= 0)
    {
        return;
    }
    uint16_t raw = PS2000::toLimitRaw(current, m_deviceInfo.nomCurrent);
    sendCommand(PS2000::buildSetInt(PS2000::OBJ_OCP, 0, raw));
}

void DeviceBackend::acknowledgeAlarms()
{
    sendCommand(PS2000::buildControl(0, PS2000::CTRL_ACK_MASK, PS2000::CTRL_ACK_ALARMS));
}

void DeviceBackend::resetEnergy()
{
    m_energyBase = m_energyWh;
    emit energyChanged(0.0);
    emit statusMessage("Energy counter reset");
}

// ── Transport slots ───────────────────────────────────────────────────────
void DeviceBackend::onDeviceInfoReady(const PS2000::DeviceInfo& info)
{
    m_deviceInfo = info;
    emit deviceInfoChanged();
}

void DeviceBackend::onStatusUpdated(const PS2000::DeviceStatus& st)
{
    const double t = nowSecs() - m_startTime;

    m_voltage  = st.voltage;
    m_current  = st.current;
    m_power    = st.power;

    bool flagsChanged =
        m_remoteMode != st.remoteMode ||
        m_outputOn   != st.outputOn   ||
        m_ccMode     != st.ccMode     ||
        m_ovpActive  != st.ovpActive  ||
        m_ocpActive  != st.ocpActive  ||
        m_oppActive  != st.oppActive  ||
        m_otpActive  != st.otpActive;

    // Detect new alarm activation (false → true transition)
    bool newAlarm = (!m_ovpActive && st.ovpActive) ||
                    (!m_ocpActive && st.ocpActive) ||
                    (!m_oppActive && st.oppActive) ||
                    (!m_otpActive && st.otpActive);

    m_remoteMode = st.remoteMode;
    m_outputOn   = st.outputOn;
    m_ccMode     = st.ccMode;
    m_ovpActive  = st.ovpActive;
    m_ocpActive  = st.ocpActive;
    m_oppActive  = st.oppActive;
    m_otpActive  = st.otpActive;

    if (newAlarm)
        emit alarmTriggered(m_ovpActive, m_ocpActive, m_oppActive, m_otpActive);

    // Energy integration (trapezoidal rule)
    if(m_lastT >= 0.0)
    {
        double dt = t - m_lastT;
        if(dt > 0 && dt < 10.0)
        {
            m_energyWh += 0.5 * (st.power + m_lastPower) * dt / 3600.0;
        }
    }
    m_lastT      = t;
    m_lastPower  = st.power;

    // Record sample
    DataRecord rec;
    rec.timestamp  = t;
    rec.voltage    = st.voltage;
    rec.current    = st.current;
    rec.power      = st.power;
    rec.setVoltage = m_setVoltage;
    rec.setCurrent = m_setCurrent;
    rec.outputOn   = st.outputOn;
    rec.ccMode     = st.ccMode;
    rec.remoteMode = st.remoteMode;
    rec.energyCum  = m_energyWh;
    m_readings.append(rec);

    emit measurementChanged();
    if(flagsChanged)
    {
        emit statusFlagsChanged();
    }
    emit energyChanged(m_energyWh - m_energyBase);
    emit sampleCountChanged(m_readings.size());
    emit newSample(t, st.voltage, st.current, st.power);
}

void DeviceBackend::onLimitsUpdated(double ovpV, double ocpA)
{
    m_ovpVoltage = ovpV;
    m_ocpCurrent = ocpA;
    emit limitsChanged();
}

void DeviceBackend::onSetValuesUpdated(double setV, double setI)
{
    m_setVoltage = setV;
    m_setCurrent = setI;
    emit setpointsChanged();
}

void DeviceBackend::onTransportError(const QString& msg)
{
    emit errorOccurred(msg);
    m_connected = false;
    m_durationTimer->stop();
    cleanupTransport();
    emit connectedChanged(false);
}

void DeviceBackend::onTransportMessage(const QString& msg)
{
    emit statusMessage(msg);
}

void DeviceBackend::onDurationTick()
{
    m_duration = formatDuration(static_cast<qint64>(nowSecs() - m_startTime));
    emit durationChanged(m_duration);
}

// ── Range measurement ─────────────────────────────────────────────────────
QVariantMap DeviceBackend::measureRange(double tStart, double tEnd) const
{
    QVariantMap r;
    if(tStart > tEnd)
    {
        std::swap(tStart, tEnd);
    }

    double sumV = 0, sumI = 0, sumP = 0;
    double peakV = 0, peakI = 0, peakP = 0;
    double minV = std::numeric_limits<double>::infinity();
    double minI = std::numeric_limits<double>::infinity();
    double minP = std::numeric_limits<double>::infinity();
    double energyStart = -1, energyEnd = -1;
    int count = 0;

    for(const auto& rec : m_readings)
    {
        if(rec.timestamp < tStart || rec.timestamp > tEnd)
        {
            continue;
        }
        sumV += rec.voltage;
        sumI += rec.current;
        sumP += rec.power;
        peakV = std::max(peakV, rec.voltage);
        peakI = std::max(peakI, rec.current);
        peakP = std::max(peakP, rec.power);
        minV  = std::min(minV, rec.voltage);
        minI  = std::min(minI, rec.current);
        minP  = std::min(minP, rec.power);
        if(energyStart < 0)
        {
            energyStart = rec.energyCum;
        }
        energyEnd = rec.energyCum;
        ++count;
    }

    r["sampleCount"] = count;
    r["duration"]    = tEnd - tStart;
    if(count > 0)
    {
        double meanV = sumV / count;
        double meanI = sumI / count;
        double dE    = energyEnd - energyStart;
        r["meanVoltage"]  = meanV;
        r["meanCurrent"]  = meanI;
        r["meanPower"]    = sumP / count;
        r["peakVoltage"]  = peakV;
        r["peakCurrent"]  = peakI;
        r["peakPower"]    = peakP;
        r["minVoltage"]   = minV;
        r["minCurrent"]   = minI;
        r["minPower"]     = minP;
        r["energyWh"]     = dE;
        r["energyMWh"]    = dE * 1000.0;
        r["energyMAh"]    = meanV > 0.01 ? (dE * 1000.0 / meanV) : 0.0;
    }
    return r;
}

// ── CSV export ────────────────────────────────────────────────────────────
void DeviceBackend::exportCsv(const QString& rawPath)
{
    const QString path = urlToPath(rawPath);
    if(m_readings.isEmpty())
    {
        emit statusMessage("No data to export.");
        return;
    }

    QFile f(path);
    if(!f.open(QIODevice::WriteOnly | QIODevice::Text))
    {
        emit statusMessage("Cannot open file: " + path);
        return;
    }
    QTextStream out(&f);
    out << "time_s,voltage_V,current_A,power_W,setVoltage_V,setCurrent_A,"
        "outputOn,ccMode,remoteMode,energy_Wh\n";
    for(const auto& rec : m_readings)
    {
        out << QString::number(rec.timestamp,  'f', 3) << ','
            << QString::number(rec.voltage,    'f', 4) << ','
            << QString::number(rec.current,    'f', 4) << ','
            << QString::number(rec.power,      'f', 4) << ','
            << QString::number(rec.setVoltage, 'f', 4) << ','
            << QString::number(rec.setCurrent, 'f', 4) << ','
            << (rec.outputOn   ? '1' : '0') << ','
            << (rec.ccMode     ? '1' : '0') << ','
            << (rec.remoteMode ? '1' : '0') << ','
            << QString::number(rec.energyCum,  'f', 8) << '\n';
    }
    emit statusMessage("CSV saved → " + QFileInfo(path).fileName());
}

// ── Excel export ──────────────────────────────────────────────────────────
void DeviceBackend::exportExcel(const QString& rawPath)
{
    const QString path = urlToPath(rawPath);
    if(m_readings.isEmpty())
    {
        emit statusMessage("No data to export.");
        return;
    }

    XlsxWriter writer;
    writer.setTitle(QString("OpenPS2000 — %1 Session").arg(m_deviceInfo.deviceType));

    writer.addSheet("Data");
    writer.setHeaders({"Time (s)", "Voltage (V)", "Current (A)", "Power (W)",
                       "Set Voltage (V)", "Set Current (A)", "Energy (Wh)"});
    for(const auto& rec : m_readings)
    {
        writer.addRow({rec.timestamp, rec.voltage, rec.current, rec.power,
                       rec.setVoltage, rec.setCurrent, rec.energyCum});
    }

    writer.addSheet("Summary");
    writer.addSummaryRow("Device",        0);   // placeholder
    writer.addSummaryRow("Samples",       static_cast<double>(m_readings.size()));
    writer.addSummaryRow("Duration (s)",  m_readings.isEmpty() ? 0 : m_readings.last().timestamp);
    writer.addSummaryRow("Total Energy (Wh)",  m_energyWh);
    writer.addSummaryRow("Total Energy (mWh)", m_energyWh * 1000.0);

    auto maxOf = [&](double DataRecord::*field)
    {
        double mx = 0;
        for(const auto& r : m_readings)
        {
            mx = std::max(mx, r.*field);
        }
        return mx;
    };
    writer.addSummaryRow("Peak Voltage (V)",  maxOf(&DataRecord::voltage));
    writer.addSummaryRow("Peak Current (A)",  maxOf(&DataRecord::current));
    writer.addSummaryRow("Peak Power (W)",    maxOf(&DataRecord::power));
    writer.addSummaryRow("Nom. Voltage (V)",  m_deviceInfo.nomVoltage);
    writer.addSummaryRow("Nom. Current (A)",  m_deviceInfo.nomCurrent);
    writer.addSummaryRow("Nom. Power (W)",    m_deviceInfo.nomPower);

    if(!writer.save(path))
    {
        emit statusMessage("Excel export failed: " + writer.lastError());
        return;
    }
    emit statusMessage("Excel saved → " + QFileInfo(path).fileName());
}
