// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// RemoteServer.h — QHttpServer-based REST API for remote control.
#pragma once

#include <QObject>
#include <QString>

class DeviceBackend;

#ifdef HAVE_QT_HTTPSERVER
class QHttpServer;
#endif

class RemoteServer : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(int  port    READ port    NOTIFY portChanged)

public:
    explicit RemoteServer(DeviceBackend* backend, QObject* parent = nullptr);
    ~RemoteServer() override;

    bool running() const { return m_running; }
    int  port()    const { return m_port; }

public slots:
    void start(int port = 8484, const QString& token = {});
    void stop();

signals:
    void runningChanged(bool running);
    void portChanged(int port);
    void errorOccurred(QString msg);

    void setpointReceived(double v, double i);
    void outputReceived(bool on);
    void limitsReceived(double ovp, double ocp);
    void sequenceStopRequested();
    void pulseStopRequested();

private:
#ifdef HAVE_QT_HTTPSERVER
    bool checkAuth(const class QHttpServerRequest& req) const;
    void registerRoutes();

    QHttpServer* m_server = nullptr;
#endif

    DeviceBackend* m_backend;
    int     m_port    = 8484;
    QString m_token;
    bool    m_running = false;
};
