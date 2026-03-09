// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// RemoteServer.cpp — QHttpServer-based REST API for remote control.
#include "RemoteServer.h"
#include "DeviceBackend.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDateTime>

#ifdef HAVE_QT_HTTPSERVER
#include <QHttpServer>
#include <QHttpServerRequest>
#include <QHttpServerResponse>
#include <QHostAddress>

static QHttpServerResponse jsonResponse(const QJsonObject& obj,
                                         QHttpServerResponse::StatusCode code
                                         = QHttpServerResponse::StatusCode::Ok)
{
    QHttpServerResponse resp(QJsonDocument(obj).toJson(QJsonDocument::Compact), code);
    resp.addHeader("Content-Type", "application/json");
    return resp;
}

static QHttpServerResponse authError()
{
    return jsonResponse({{"error", "Unauthorized"}},
                        QHttpServerResponse::StatusCode::Unauthorized);
}

bool RemoteServer::checkAuth(const QHttpServerRequest& req) const
{
    if (m_token.isEmpty())
        return true;
    const QByteArray auth = req.value("Authorization");
    const QByteArray expected = "Bearer " + m_token.toUtf8();
    return auth == expected;
}

void RemoteServer::registerRoutes()
{
    // GET /api/v1/info
    m_server->route("/api/v1/info", QHttpServerRequest::Method::Get,
        [this](const QHttpServerRequest& req) -> QHttpServerResponse {
            if (!checkAuth(req)) return authError();
            QJsonObject obj;
            obj["deviceType"]   = m_backend->deviceType();
            obj["serialNo"]     = m_backend->serialNo();
            obj["articleNo"]    = m_backend->articleNo();
            obj["manufacturer"] = m_backend->manufacturer();
            obj["swVersion"]    = m_backend->swVersion();
            obj["nomVoltage"]   = m_backend->nomVoltage();
            obj["nomCurrent"]   = m_backend->nomCurrent();
            obj["nomPower"]     = m_backend->nomPower();
            return jsonResponse(obj);
        });

    // GET /api/v1/status
    m_server->route("/api/v1/status", QHttpServerRequest::Method::Get,
        [this](const QHttpServerRequest& req) -> QHttpServerResponse {
            if (!checkAuth(req)) return authError();
            QJsonObject obj;
            obj["connected"]   = m_backend->connected();
            obj["outputOn"]    = m_backend->outputOn();
            obj["remoteMode"]  = m_backend->remoteMode();
            obj["ccMode"]      = m_backend->ccMode();
            obj["voltage"]     = m_backend->voltage();
            obj["current"]     = m_backend->current();
            obj["power"]       = m_backend->power();
            obj["setVoltage"]  = m_backend->setVoltage();
            obj["setCurrent"]  = m_backend->setCurrent();
            obj["ovpVoltage"]  = m_backend->ovpVoltage();
            obj["ocpCurrent"]  = m_backend->ocpCurrent();
            obj["energyWh"]    = m_backend->energyWh();
            obj["ovpActive"]   = m_backend->ovpActive();
            obj["ocpActive"]   = m_backend->ocpActive();
            obj["oppActive"]   = m_backend->oppActive();
            obj["otpActive"]   = m_backend->otpActive();
            return jsonResponse(obj);
        });

    // PUT /api/v1/setpoint
    m_server->route("/api/v1/setpoint", QHttpServerRequest::Method::Put,
        [this](const QHttpServerRequest& req) -> QHttpServerResponse {
            if (!checkAuth(req)) return authError();
            const auto doc = QJsonDocument::fromJson(req.body());
            if (doc.isNull() || !doc.isObject())
                return jsonResponse({{"error", "invalid JSON"}},
                                    QHttpServerResponse::StatusCode::BadRequest);
            const auto obj = doc.object();
            double v = obj.value("voltage").toDouble(m_backend->setVoltage());
            double i = obj.value("current").toDouble(m_backend->setCurrent());
            emit setpointReceived(v, i);
            return jsonResponse({{"ok", true}});
        });

    // PUT /api/v1/output
    m_server->route("/api/v1/output", QHttpServerRequest::Method::Put,
        [this](const QHttpServerRequest& req) -> QHttpServerResponse {
            if (!checkAuth(req)) return authError();
            const auto doc = QJsonDocument::fromJson(req.body());
            if (doc.isNull() || !doc.isObject())
                return jsonResponse({{"error", "invalid JSON"}},
                                    QHttpServerResponse::StatusCode::BadRequest);
            bool on = doc.object().value("enabled").toBool(false);
            emit outputReceived(on);
            return jsonResponse({{"ok", true}});
        });

    // PUT /api/v1/limits
    m_server->route("/api/v1/limits", QHttpServerRequest::Method::Put,
        [this](const QHttpServerRequest& req) -> QHttpServerResponse {
            if (!checkAuth(req)) return authError();
            const auto doc = QJsonDocument::fromJson(req.body());
            if (doc.isNull() || !doc.isObject())
                return jsonResponse({{"error", "invalid JSON"}},
                                    QHttpServerResponse::StatusCode::BadRequest);
            const auto obj = doc.object();
            double ovp = obj.value("ovp").toDouble(m_backend->ovpVoltage());
            double ocp = obj.value("ocp").toDouble(m_backend->ocpCurrent());
            emit limitsReceived(ovp, ocp);
            return jsonResponse({{"ok", true}});
        });

    // GET /api/v1/history
    m_server->route("/api/v1/history", QHttpServerRequest::Method::Get,
        [this](const QHttpServerRequest& req) -> QHttpServerResponse {
            if (!checkAuth(req)) return authError();
            double minutes = 5.0;
            const auto params = req.query();
            if (params.hasQueryItem("minutes"))
                minutes = params.queryItemValue("minutes").toDouble();
            double tNow   = QDateTime::currentMSecsSinceEpoch() / 1000.0;
            double tStart = tNow - minutes * 60.0;
            QVariantMap stats = m_backend->measureRange(tStart, tNow);
            QJsonObject statsObj;
            for (auto it = stats.cbegin(); it != stats.cend(); ++it)
                statsObj[it.key()] = QJsonValue::fromVariant(it.value());
            QJsonObject result;
            result["samples"] = stats.value("sampleCount").toInt();
            result["stats"]   = statsObj;
            return jsonResponse(result);
        });

    // POST /api/v1/sequence/stop
    m_server->route("/api/v1/sequence/stop", QHttpServerRequest::Method::Post,
        [this](const QHttpServerRequest& req) -> QHttpServerResponse {
            if (!checkAuth(req)) return authError();
            emit sequenceStopRequested();
            return jsonResponse({{"ok", true}});
        });

    // POST /api/v1/pulse/stop
    m_server->route("/api/v1/pulse/stop", QHttpServerRequest::Method::Post,
        [this](const QHttpServerRequest& req) -> QHttpServerResponse {
            if (!checkAuth(req)) return authError();
            emit pulseStopRequested();
            return jsonResponse({{"ok", true}});
        });
}
#endif // HAVE_QT_HTTPSERVER

RemoteServer::RemoteServer(DeviceBackend* backend, QObject* parent)
    : QObject(parent)
    , m_backend(backend)
{}

RemoteServer::~RemoteServer()
{
    stop();
}

void RemoteServer::start(int port, const QString& token)
{
#ifdef HAVE_QT_HTTPSERVER
    stop();

    m_token  = token;
    m_server = new QHttpServer(this);
    registerRoutes();

    const auto boundPort = m_server->listen(QHostAddress::Any, static_cast<quint16>(port));
    if (boundPort == 0) {
        emit errorOccurred(tr("Failed to start REST server on port %1").arg(port));
        delete m_server;
        m_server = nullptr;
        return;
    }

    m_port    = static_cast<int>(boundPort);
    m_running = true;
    emit portChanged(m_port);
    emit runningChanged(true);
#else
    Q_UNUSED(port)
    Q_UNUSED(token)
    emit errorOccurred(tr("REST server not available (built without QtHttpServer)"));
#endif
}

void RemoteServer::stop()
{
#ifdef HAVE_QT_HTTPSERVER
    if (m_server) {
        delete m_server;
        m_server = nullptr;
    }
#endif
    if (m_running) {
        m_running = false;
        emit runningChanged(false);
    }
}
