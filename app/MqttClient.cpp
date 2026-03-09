// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// MqttClient.cpp — Qt MQTT client for publishing measurements and receiving commands.
#include "MqttClient.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QDateTime>

#ifdef HAVE_QT_MQTT
#include <QtMqtt/QMqttClient>
#include <QtMqtt/QMqttSubscription>
#include <QtMqtt/QMqttTopicName>

void MqttClient::onStateChanged(int state)
{
    switch (state) {
    case QMqttClient::Connected:
        m_connected = true;
        m_status    = tr("Connected to %1:%2").arg(m_host).arg(m_port);
        emit connectedChanged(true);
        emit statusChanged(m_status);
        subscribeToCommands();
        break;
    case QMqttClient::Disconnected:
        m_connected = false;
        m_status    = tr("Disconnected");
        emit connectedChanged(false);
        emit statusChanged(m_status);
        break;
    case QMqttClient::Connecting:
        m_status = tr("Connecting…");
        emit statusChanged(m_status);
        break;
    default:
        break;
    }
}

void MqttClient::subscribeToCommands()
{
    if (!m_client) return;
    auto sub = [this](const QString& suffix) {
        m_client->subscribe(QMqttTopicFilter(m_prefix + suffix), 0);
    };
    sub("/cmd/setpoint");
    sub("/cmd/output");
    sub("/cmd/limits");
}

void MqttClient::onMessageReceived(const QByteArray& msg, const QMqttTopicName& topic)
{
    const auto doc = QJsonDocument::fromJson(msg);
    if (doc.isNull() || !doc.isObject()) return;
    const auto obj = doc.object();

    const QString topicStr = topic.name();
    if (topicStr.endsWith("/cmd/setpoint")) {
        double v = obj.value("voltage").toDouble();
        double i = obj.value("current").toDouble();
        emit cmdSetpoint(v, i);
    } else if (topicStr.endsWith("/cmd/output")) {
        emit cmdOutput(obj.value("enabled").toBool());
    } else if (topicStr.endsWith("/cmd/limits")) {
        double ovp = obj.value("ovp").toDouble();
        double ocp = obj.value("ocp").toDouble();
        emit cmdLimits(ovp, ocp);
    }
}
#endif // HAVE_QT_MQTT

MqttClient::MqttClient(QObject* parent)
    : QObject(parent)
{}

MqttClient::~MqttClient()
{
    disconnectFromBroker();
}

void MqttClient::configure(const QString& host, int port, const QString& prefix,
                            const QString& user, const QString& pass, bool tls)
{
    m_host   = host;
    m_port   = port;
    m_prefix = prefix;
    m_user   = user;
    m_pass   = pass;
    m_tls    = tls;
}

void MqttClient::connectToBroker()
{
#ifdef HAVE_QT_MQTT
    if (m_client) {
        m_client->disconnectFromHost();
        m_client->deleteLater();
        m_client = nullptr;
    }

    m_client = new QMqttClient(this);
    m_client->setHostname(m_host);
    m_client->setPort(static_cast<quint16>(m_port));
    if (!m_user.isEmpty()) m_client->setUsername(m_user);
    if (!m_pass.isEmpty()) m_client->setPassword(m_pass);

    connect(m_client, &QMqttClient::stateChanged, this,
            [this](QMqttClient::ClientState state) { onStateChanged(static_cast<int>(state)); });
    connect(m_client, &QMqttClient::messageReceived, this,
            [this](const QByteArray& msg, const QMqttTopicName& topic) {
                onMessageReceived(msg, topic);
            });

    if (m_tls)
        m_client->connectToHostEncrypted();
    else
        m_client->connectToHost();

    m_status = tr("Connecting…");
    emit statusChanged(m_status);
#else
    m_status = tr("MQTT not available (built without QtMqtt)");
    emit statusChanged(m_status);
#endif
}

void MqttClient::disconnectFromBroker()
{
#ifdef HAVE_QT_MQTT
    if (m_client) {
        m_client->disconnectFromHost();
        m_client->deleteLater();
        m_client = nullptr;
    }
#endif
    if (m_connected) {
        m_connected = false;
        m_status    = tr("Disconnected");
        emit connectedChanged(false);
        emit statusChanged(m_status);
    }
}

void MqttClient::publishMeasurement(double v, double i, double p, double wh)
{
#ifdef HAVE_QT_MQTT
    if (!m_client || !m_connected) return;
    QJsonObject obj;
    obj["v"]  = v;
    obj["i"]  = i;
    obj["p"]  = p;
    obj["wh"] = wh;
    obj["ts"] = QDateTime::currentSecsSinceEpoch();
    const QByteArray payload = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    m_client->publish(QMqttTopicName(m_prefix + "/measurement"), payload, 0, false);
#else
    Q_UNUSED(v) Q_UNUSED(i) Q_UNUSED(p) Q_UNUSED(wh)
#endif
}

void MqttClient::publishStatus(bool outputOn, double setV, double setI)
{
#ifdef HAVE_QT_MQTT
    if (!m_client || !m_connected) return;
    QJsonObject obj;
    obj["outputOn"] = outputOn;
    obj["setV"]     = setV;
    obj["setI"]     = setI;
    obj["ts"]       = QDateTime::currentSecsSinceEpoch();
    const QByteArray payload = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    m_client->publish(QMqttTopicName(m_prefix + "/status"), payload, 0, true);
#else
    Q_UNUSED(outputOn) Q_UNUSED(setV) Q_UNUSED(setI)
#endif
}
