// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// RemoteServer.h — Lightweight REST API using QTcpServer (no optional modules needed).
#pragma once

#include <QObject>
#include <QString>
#include <QHash>
#include <QByteArray>

class DeviceBackend;
class QTcpServer;
class QTcpSocket;

// Per-connection state for incremental HTTP parsing
struct HttpConn {
    QByteArray buf;
    bool       headersComplete = false;
    QString    method;
    QString    path;
    QHash<QString, QString> headers;
    int        contentLength = 0;
};

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

private slots:
    void onNewConnection();
    void onReadyRead(QTcpSocket* sock);
    void onDisconnected(QTcpSocket* sock);

private:
    QByteArray handleRequest(const QString& method, const QString& path,
                              const QByteArray& body);
    bool checkAuth(const QHash<QString,QString>& headers) const;
    static QByteArray httpResponse(int code, const QByteArray& body,
                                   const QByteArray& contentType = "application/json");

    QTcpServer*  m_server  = nullptr;
    DeviceBackend* m_backend;
    QHash<QTcpSocket*, HttpConn> m_conns;
    int     m_port    = 8484;
    QString m_token;
    bool    m_running = false;
};
