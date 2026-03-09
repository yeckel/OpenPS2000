// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// MqttClient.h — Qt MQTT client for publishing measurements and receiving commands.
#pragma once

#include <QObject>
#include <QString>

#ifdef HAVE_QT_MQTT
class QMqttClient;
#endif

class MqttClient : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool    connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(QString status    READ status    NOTIFY statusChanged)

public:
    explicit MqttClient(QObject* parent = nullptr);
    ~MqttClient() override;

    bool    connected() const { return m_connected; }
    QString status()    const { return m_status; }

public slots:
    void configure(const QString& host, int port, const QString& prefix,
                   const QString& user, const QString& pass, bool tls);
    void connectToBroker();
    void disconnectFromBroker();
    void publishMeasurement(double v, double i, double p, double wh);
    void publishStatus(bool outputOn, double setV, double setI);

signals:
    void connectedChanged(bool connected);
    void statusChanged(QString status);

    void cmdSetpoint(double v, double i);
    void cmdOutput(bool on);
    void cmdLimits(double ovp, double ocp);

private:
#ifdef HAVE_QT_MQTT
    void onStateChanged(int state);
    void onMessageReceived(const QByteArray& msg, const class QMqttTopicName& topic);
    void subscribeToCommands();

    QMqttClient* m_client = nullptr;
#endif

    QString m_host   = "localhost";
    int     m_port   = 1883;
    QString m_prefix = "openps2000";
    QString m_user;
    QString m_pass;
    bool    m_tls       = false;
    bool    m_connected = false;
    QString m_status    = "Disconnected";
};
