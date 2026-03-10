// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// RemoteServer.cpp — Lightweight QTcpServer-based REST API (no QtHttpServer needed).

#include "RemoteServer.h"
#include "DeviceBackend.h"

#include <QTcpServer>
#include <QTcpSocket>
#include <QHostAddress>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDateTime>
#include <QVariantMap>

// ── Limits ────────────────────────────────────────────────────────────────────
static constexpr int MAX_HEADER_BYTES = 16 * 1024;   // 16 KB — protects against infinite header DoS
static constexpr int MAX_BODY_BYTES   = 4  * 1024;   // 4 KB — all our request bodies are tiny JSON

// ── HTTP helpers ─────────────────────────────────────────────────────────────

QByteArray RemoteServer::httpResponse(int code, const QByteArray& body,
                                      const QByteArray& contentType)
{
    static const QHash<int,QByteArray> reasons = {
        {200,"OK"},{201,"Created"},{204,"No Content"},
        {400,"Bad Request"},{401,"Unauthorized"},{404,"Not Found"},
        {405,"Method Not Allowed"},{500,"Internal Server Error"},
    };
    QByteArray resp;
    resp  = "HTTP/1.1 " + QByteArray::number(code) + " "
          + reasons.value(code, "Unknown") + "\r\n";
    resp += "Content-Type: "   + contentType          + "\r\n";
    resp += "Content-Length: " + QByteArray::number(body.size()) + "\r\n";
    resp += "Access-Control-Allow-Origin: *\r\n";
    resp += "Connection: keep-alive\r\n";
    resp += "\r\n";
    resp += body;
    return resp;
}

static QByteArray jsonOk(const QJsonObject& obj = {{"ok", true}})
{
    return QJsonDocument(obj).toJson(QJsonDocument::Compact);
}

static QByteArray jsonErr(const QString& msg, int& code)
{
    QJsonObject o; o["error"] = msg;
    return QJsonDocument(o).toJson(QJsonDocument::Compact);
}

bool RemoteServer::checkAuth(const QHash<QString,QString>& headers) const
{
    if (m_token.isEmpty()) return true;
    return headers.value("authorization") == "Bearer " + m_token;
}

// ── Request routing ──────────────────────────────────────────────────────────

QByteArray RemoteServer::handleRequest(const QString& method, const QString& path,
                                       const QByteArray& body)
{
    // Strip query string for routing
    const QString route = path.section('?', 0, 0);

    // GET /api/v1/info
    if (method == "GET" && route == "/api/v1/info") {
        QJsonObject o;
        o["deviceType"]   = m_backend->deviceType();
        o["serialNo"]     = m_backend->serialNo();
        o["articleNo"]    = m_backend->articleNo();
        o["manufacturer"] = m_backend->manufacturer();
        o["swVersion"]    = m_backend->swVersion();
        o["nomVoltage"]   = m_backend->nomVoltage();
        o["nomCurrent"]   = m_backend->nomCurrent();
        o["nomPower"]     = m_backend->nomPower();
        return httpResponse(200, jsonOk(o));
    }

    // GET /api/v1/status
    if (method == "GET" && route == "/api/v1/status") {
        QJsonObject o;
        o["connected"]  = m_backend->connected();
        o["outputOn"]   = m_backend->outputOn();
        o["remoteMode"] = m_backend->remoteMode();
        o["ccMode"]     = m_backend->ccMode();
        o["voltage"]    = m_backend->voltage();
        o["current"]    = m_backend->current();
        o["power"]      = m_backend->power();
        o["setVoltage"] = m_backend->setVoltage();
        o["setCurrent"] = m_backend->setCurrent();
        o["ovpVoltage"] = m_backend->ovpVoltage();
        o["ocpCurrent"] = m_backend->ocpCurrent();
        o["energyWh"]   = m_backend->energyWh();
        o["ovpActive"]  = m_backend->ovpActive();
        o["ocpActive"]  = m_backend->ocpActive();
        o["oppActive"]  = m_backend->oppActive();
        o["otpActive"]  = m_backend->otpActive();
        return httpResponse(200, jsonOk(o));
    }

    // PUT /api/v1/setpoint
    if (method == "PUT" && route == "/api/v1/setpoint") {
        const auto doc = QJsonDocument::fromJson(body);
        if (doc.isNull()) { int c=400; return httpResponse(c, jsonErr("invalid JSON",c)); }
        double v = doc.object().value("voltage").toDouble(m_backend->setVoltage());
        double i = doc.object().value("current").toDouble(m_backend->setCurrent());
        // Clamp to hardware nominals — never send out-of-range values to the PSU
        v = qBound(0.0, v, m_backend->nomVoltage());
        i = qBound(0.0, i, m_backend->nomCurrent());
        emit setpointReceived(v, i);
        return httpResponse(200, jsonOk());
    }

    // PUT /api/v1/output
    if (method == "PUT" && route == "/api/v1/output") {
        const auto doc = QJsonDocument::fromJson(body);
        if (doc.isNull()) { int c=400; return httpResponse(c, jsonErr("invalid JSON",c)); }
        emit outputReceived(doc.object().value("enabled").toBool(false));
        return httpResponse(200, jsonOk());
    }

    // GET /api/v1/limits
    if (method == "GET" && route == "/api/v1/limits") {
        QJsonObject o;
        o["ovp"] = m_backend->ovpVoltage();
        o["ocp"] = m_backend->ocpCurrent();
        return httpResponse(200, jsonOk(o));
    }

    // PUT /api/v1/limits
    if (method == "PUT" && route == "/api/v1/limits") {
        const auto doc = QJsonDocument::fromJson(body);
        if (doc.isNull()) { int c=400; return httpResponse(c, jsonErr("invalid JSON",c)); }
        double ovp = doc.object().value("ovp").toDouble(m_backend->ovpVoltage());
        double ocp = doc.object().value("ocp").toDouble(m_backend->ocpCurrent());
        // Clamp to hardware nominals
        ovp = qBound(0.0, ovp, m_backend->nomVoltage());
        ocp = qBound(0.0, ocp, m_backend->nomCurrent());
        emit limitsReceived(ovp, ocp);
        return httpResponse(200, jsonOk());
    }

    // GET /api/v1/history  ?minutes=5
    if (method == "GET" && route == "/api/v1/history") {
        double minutes = 5.0;
        const QString qs = path.section('?', 1);
        for (const QString& kv : qs.split('&')) {
            if (kv.startsWith("minutes=")) {
                bool ok = false;
                double m = kv.mid(8).toDouble(&ok);
                if (ok) minutes = m;
            }
        }
        // Clamp: minimum 1 second, maximum 24 hours — prevents underflow and huge range scans
        minutes = qBound(1.0 / 60.0, minutes, 1440.0);
        double tNow   = QDateTime::currentMSecsSinceEpoch() / 1000.0;
        QVariantMap stats = m_backend->measureRange(tNow - minutes * 60.0, tNow);
        QJsonObject statsObj;
        for (auto it = stats.cbegin(); it != stats.cend(); ++it)
            statsObj[it.key()] = QJsonValue::fromVariant(it.value());
        QJsonObject result;
        result["samples"] = stats.value("sampleCount").toInt();
        result["stats"]   = statsObj;
        return httpResponse(200, jsonOk(result));
    }

    // POST /api/v1/alarm/acknowledge
    if (method == "POST" && route == "/api/v1/alarm/acknowledge") {
        emit alarmAcknowledgeRequested();
        return httpResponse(200, jsonOk());
    }

    // POST /api/v1/sequence/stop
    if (method == "POST" && route == "/api/v1/sequence/stop") {
        emit sequenceStopRequested();
        return httpResponse(200, jsonOk());
    }

    // POST /api/v1/pulse/stop
    if (method == "POST" && route == "/api/v1/pulse/stop") {
        emit pulseStopRequested();
        return httpResponse(200, jsonOk());
    }

    // OPTIONS (CORS preflight)
    if (method == "OPTIONS") {
        QByteArray resp =
            "HTTP/1.1 204 No Content\r\n"
            "Access-Control-Allow-Origin: *\r\n"
            "Access-Control-Allow-Methods: GET, PUT, POST, OPTIONS\r\n"
            "Access-Control-Allow-Headers: Authorization, Content-Type\r\n"
            "Content-Length: 0\r\n\r\n";
        return resp;
    }

    int c = 404; return httpResponse(c, jsonErr("Not found", c));
}

// ── TCP plumbing ─────────────────────────────────────────────────────────────

RemoteServer::RemoteServer(DeviceBackend* backend, QObject* parent)
    : QObject(parent), m_backend(backend)
{}

RemoteServer::~RemoteServer()
{
    stop();
}

void RemoteServer::start(int port, const QString& token)
{
    stop();
    m_token  = token;
    m_server = new QTcpServer(this);
    connect(m_server, &QTcpServer::newConnection, this, &RemoteServer::onNewConnection);

    if (!m_server->listen(QHostAddress::Any, static_cast<quint16>(port))) {
        emit errorOccurred(tr("Failed to start REST server on port %1: %2")
                           .arg(port).arg(m_server->errorString()));
        delete m_server;
        m_server = nullptr;
        return;
    }
    m_port    = m_server->serverPort();
    m_running = true;
    emit portChanged(m_port);
    emit runningChanged(true);
}

void RemoteServer::stop()
{
    if (m_server) {
        for (auto* s : m_conns.keys()) s->disconnectFromHost();
        m_conns.clear();
        m_server->close();
        delete m_server;
        m_server = nullptr;
    }
    if (m_running) {
        m_running = false;
        emit runningChanged(false);
    }
}

void RemoteServer::onNewConnection()
{
    while (m_server->hasPendingConnections()) {
        QTcpSocket* sock = m_server->nextPendingConnection();
        m_conns[sock] = {};
        connect(sock, &QTcpSocket::readyRead,    this, [this, sock]() { onReadyRead(sock); });
        connect(sock, &QTcpSocket::disconnected, this, [this, sock]() { onDisconnected(sock); });
    }
}

void RemoteServer::onReadyRead(QTcpSocket* sock)
{
    HttpConn& conn = m_conns[sock];
    conn.buf.append(sock->readAll());

    while (true) {
        // ── Parse headers ────────────────────────────────────────────────
        if (!conn.headersComplete) {
            // Guard: disconnect if headers are unreasonably large
            if (conn.buf.size() > MAX_HEADER_BYTES) {
                sock->disconnectFromHost();
                return;
            }
            int sep = conn.buf.indexOf("\r\n\r\n");
            if (sep < 0) return; // Need more data

            QByteArray head = conn.buf.left(sep);
            conn.buf.remove(0, sep + 4);

            QList<QByteArray> lines = head.split('\n');
            // Request line
            QList<QByteArray> rl = lines[0].trimmed().split(' ');
            if (rl.size() < 2) { sock->disconnectFromHost(); return; }
            conn.method = QString::fromUtf8(rl[0]).toUpper();
            conn.path   = QString::fromUtf8(rl[1]);
            // Header fields
            conn.headers.clear();
            for (int i = 1; i < lines.size(); ++i) {
                QByteArray line = lines[i].trimmed();
                int colon = line.indexOf(':');
                if (colon < 0) continue;
                conn.headers[QString::fromUtf8(line.left(colon)).trimmed().toLower()] =
                    QString::fromUtf8(line.mid(colon + 1)).trimmed();
            }
            // Validate content-length: must be a non-negative integer within our body size limit
            bool clOk = false;
            int cl = conn.headers.value("content-length", "0").toInt(&clOk);
            if (!clOk || cl < 0 || cl > MAX_BODY_BYTES) {
                sock->disconnectFromHost();
                return;
            }
            conn.contentLength   = cl;
            conn.headersComplete = true;
        }

        // ── Wait for body ────────────────────────────────────────────────
        if (conn.buf.size() < conn.contentLength) return;

        QByteArray body = conn.buf.left(conn.contentLength);
        conn.buf.remove(0, conn.contentLength);

        // ── Auth check ────────────────────────────────────────────────────
        QByteArray respData;
        if (!checkAuth(conn.headers)) {
            QJsonObject e; e["error"] = "Unauthorized";
            respData = httpResponse(401, QJsonDocument(e).toJson(QJsonDocument::Compact));
        } else {
            respData = handleRequest(conn.method, conn.path, body);
        }
        sock->write(respData);

        // Prepare for next request on the same connection (keep-alive)
        conn.headersComplete = false;
        conn.contentLength   = 0;
        conn.headers.clear();
        if (conn.buf.isEmpty()) return;
    }
}

void RemoteServer::onDisconnected(QTcpSocket* sock)
{
    m_conns.remove(sock);
    sock->deleteLater();
}
