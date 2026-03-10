// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// RemoteBackend.cpp — DeviceBackend-compatible REST client for remote instances.
#include "RemoteBackend.h"

#include <QNetworkReply>
#include <QNetworkRequest>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDateTime>
#include <QUrl>
#include <QUrlQuery>

RemoteBackend::RemoteBackend(const QString& url, QObject* parent)
    : QObject(parent)
    , m_url(url)
    , m_portName(url)
{
    m_nam       = new QNetworkAccessManager(this);
    m_pollTimer = new QTimer(this);
    m_pollTimer->setInterval(500);
    connect(m_pollTimer, &QTimer::timeout, this, &RemoteBackend::poll);

    // Auto-connect: fetch device info then start polling immediately.
    // The user doesn't need to click "Connect" in remote mode.
    fetchInfo();
    m_pollTimer->start();
    m_connected = true;
    // Defer signal until event loop is running
    QTimer::singleShot(0, this, [this]() { emit connectedChanged(true); });
}

RemoteBackend::~RemoteBackend() = default;

// ── Helpers ───────────────────────────────────────────────────────────────

void RemoteBackend::putJson(const QString& path, const QByteArray& body)
{
    QNetworkRequest req(QUrl(m_url + path));
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    auto* reply = m_nam->put(req, body);
    connect(reply, &QNetworkReply::finished, reply, &QNetworkReply::deleteLater);
}

// ── Polling ───────────────────────────────────────────────────────────────

void RemoteBackend::poll()
{
    QNetworkRequest req(QUrl(m_url + "/api/v1/status"));
    auto* reply = m_nam->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            if (m_connected) {
                m_connected = false;
                emit connectedChanged(false);
            }
            return;
        }

        const auto doc = QJsonDocument::fromJson(reply->readAll());
        if (doc.isNull() || !doc.isObject()) return;
        const auto obj = doc.object();

        if (!m_connected) {
            m_connected = true;
            emit connectedChanged(true);
        }

        const double v   = obj["voltage"].toDouble();
        const double i   = obj["current"].toDouble();
        const double p   = obj["power"].toDouble();
        bool measChanged = (v != m_voltage || i != m_current || p != m_power);
        m_voltage = v;
        m_current = i;
        m_power   = p;

        const double sv = obj["setVoltage"].toDouble();
        const double si = obj["setCurrent"].toDouble();
        bool spChanged  = (sv != m_setVoltage || si != m_setCurrent);
        m_setVoltage = sv;
        m_setCurrent = si;

        const double ovp = obj["ovpVoltage"].toDouble();
        const double ocp = obj["ocpCurrent"].toDouble();
        bool limChanged  = (ovp != m_ovpVoltage || ocp != m_ocpCurrent);
        m_ovpVoltage = ovp;
        m_ocpCurrent = ocp;

        const bool remMode  = obj["remoteMode"].toBool();
        const bool outOn    = obj["outputOn"].toBool();
        const bool cc       = obj["ccMode"].toBool();
        const bool ovpA     = obj["ovpActive"].toBool();
        const bool ocpA     = obj["ocpActive"].toBool();
        const bool oppA     = obj["oppActive"].toBool();
        const bool otpA     = obj["otpActive"].toBool();
        bool flagsChanged   = (remMode != m_remoteMode || outOn != m_outputOn
                                || cc != m_ccMode || ovpA != m_ovpActive
                                || ocpA != m_ocpActive || oppA != m_oppActive
                                || otpA != m_otpActive);
        m_remoteMode = remMode;
        m_outputOn   = outOn;
        m_ccMode     = cc;
        m_ovpActive  = ovpA;
        m_ocpActive  = ocpA;
        m_oppActive  = oppA;
        m_otpActive  = otpA;

        const double wh = obj["energyWh"].toDouble();
        m_energyWh = wh;

        if (measChanged) emit measurementChanged();
        if (spChanged)   emit setpointsChanged();
        if (limChanged)  emit limitsChanged();
        if (flagsChanged) emit statusFlagsChanged();
        emit energyChanged(m_energyWh);

        // Use session-relative time (seconds since first sample) so the chart
        // X-axis shows small elapsed values identical to local-backend behaviour.
        const double epoch = QDateTime::currentMSecsSinceEpoch() / 1000.0;
        if (m_startTime < 0) m_startTime = epoch;
        const double t = epoch - m_startTime;

        DataRecord rec;
        rec.timestamp = t;
        rec.voltage   = v;
        rec.current   = i;
        rec.power     = p;
        rec.energyCum = wh;
        m_readings.append(rec);
        m_lastT = t;
        emit newSample(t, v, i, p);
        emit sampleCountChanged(m_readings.size());
    });
}

void RemoteBackend::fetchInfo()
{
    QNetworkRequest req(QUrl(m_url + "/api/v1/info"));
    auto* reply = m_nam->get(req);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) return;
        const auto doc = QJsonDocument::fromJson(reply->readAll());
        if (doc.isNull() || !doc.isObject()) return;
        const auto obj = doc.object();
        m_deviceInfo.deviceType   = obj["deviceType"].toString();
        m_deviceInfo.serialNo     = obj["serialNo"].toString();
        m_deviceInfo.articleNo    = obj["articleNo"].toString();
        m_deviceInfo.manufacturer = obj["manufacturer"].toString();
        m_deviceInfo.swVersion    = obj["swVersion"].toString();
        m_deviceInfo.nomVoltage   = obj["nomVoltage"].toDouble();
        m_deviceInfo.nomCurrent   = obj["nomCurrent"].toDouble();
        m_deviceInfo.nomPower     = obj["nomPower"].toDouble();
        emit deviceInfoChanged();
    });
}

// ── Control slots ─────────────────────────────────────────────────────────

void RemoteBackend::connectDevice(const QString& /*portName*/)
{
    m_pollTimer->start();
    if (!m_connected) {
        m_connected = true;
        emit connectedChanged(true);
    }
}

void RemoteBackend::disconnectDevice()
{
    m_pollTimer->stop();
    m_startTime = -1.0;
    m_lastT     = -1.0;
    m_readings.clear();
    if (m_connected) {
        m_connected = false;
        emit connectedChanged(false);
    }
}

void RemoteBackend::setRemoteMode(bool /*remote*/) {}

void RemoteBackend::setOutputOn(bool on)
{
    QJsonObject obj;
    obj["enabled"] = on;
    putJson("/api/v1/output", QJsonDocument(obj).toJson(QJsonDocument::Compact));
}

void RemoteBackend::setOutputOnQueued(bool on)
{
    setOutputOn(on);
}

void RemoteBackend::sendSetVoltage(double voltage)
{
    m_setVoltage = voltage;
    QJsonObject obj;
    obj["voltage"] = m_setVoltage;
    obj["current"] = m_setCurrent;
    putJson("/api/v1/setpoint", QJsonDocument(obj).toJson(QJsonDocument::Compact));
}

void RemoteBackend::sendSetCurrent(double current)
{
    m_setCurrent = current;
    QJsonObject obj;
    obj["voltage"] = m_setVoltage;
    obj["current"] = m_setCurrent;
    putJson("/api/v1/setpoint", QJsonDocument(obj).toJson(QJsonDocument::Compact));
}

void RemoteBackend::sendOvpVoltage(double voltage)
{
    m_ovpVoltage = voltage;
    QJsonObject obj;
    obj["ovp"] = m_ovpVoltage;
    obj["ocp"] = m_ocpCurrent;
    putJson("/api/v1/limits", QJsonDocument(obj).toJson(QJsonDocument::Compact));
}

void RemoteBackend::sendOcpCurrent(double current)
{
    m_ocpCurrent = current;
    QJsonObject obj;
    obj["ovp"] = m_ovpVoltage;
    obj["ocp"] = m_ocpCurrent;
    putJson("/api/v1/limits", QJsonDocument(obj).toJson(QJsonDocument::Compact));
}

void RemoteBackend::acknowledgeAlarms()
{
    QNetworkRequest req(QUrl(m_url + "/api/v1/alarm/acknowledge"));
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    m_nam->post(req, QByteArray("{}"));
}

void RemoteBackend::resetEnergy()
{
    m_energyWh = 0.0;
    emit energyChanged(0.0);
}

void RemoteBackend::exportCsv(const QString& /*path*/) {}
void RemoteBackend::exportExcel(const QString& /*path*/) {}

// ── Queries ───────────────────────────────────────────────────────────────

QStringList RemoteBackend::availablePorts() const
{
    return {m_url};
}

QVariantMap RemoteBackend::measureRange(double tStart, double tEnd) const
{
    QVariantMap r;
    if (tStart > tEnd) std::swap(tStart, tEnd);

    double sumV = 0, sumI = 0, sumP = 0;
    double peakV = 0, peakI = 0, peakP = 0;
    double minV = std::numeric_limits<double>::infinity();
    double minI = std::numeric_limits<double>::infinity();
    double minP = std::numeric_limits<double>::infinity();
    double energyStart = -1, energyEnd = -1;
    int count = 0;

    for (const auto& rec : m_readings) {
        if (rec.timestamp < tStart || rec.timestamp > tEnd) continue;
        sumV  += rec.voltage;
        sumI  += rec.current;
        sumP  += rec.power;
        peakV  = std::max(peakV, rec.voltage);
        peakI  = std::max(peakI, rec.current);
        peakP  = std::max(peakP, rec.power);
        minV   = std::min(minV, rec.voltage);
        minI   = std::min(minI, rec.current);
        minP   = std::min(minP, rec.power);
        if (energyStart < 0) energyStart = rec.energyCum;
        energyEnd = rec.energyCum;
        ++count;
    }

    r["sampleCount"] = count;
    r["duration"]    = tEnd - tStart;
    if (count > 0) {
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
