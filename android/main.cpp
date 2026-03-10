// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// Android entry point — creates DeviceBackend (USB) or RemoteBackend (REST)
// depending on user selection, registers context properties, and loads QML.
//
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QSettings>
#include <QTimer>
#include <QJniObject>
#include <QJniEnvironment>
#include <QtCore/private/qandroidextras_p.h>

#include "../app/DeviceBackend.h"
#include "../app/RemoteBackend.h"
#include "AndroidSerialTransport.h"

// ── BackendFactory ────────────────────────────────────────────────────────
// Exposed to QML as context property "backendFactory".
// QML calls switchToUsb() or switchToRest(url) when the user taps Connect.
//
class BackendFactory : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isRemote READ isRemote NOTIFY modeChanged)
    Q_PROPERTY(QObject* backend READ backendObject NOTIFY modeChanged)

public:
    explicit BackendFactory(QQmlApplicationEngine* engine, QObject* parent = nullptr)
        : QObject(parent), m_engine(engine)
    {}

    bool     isRemote()     const { return m_remote; }
    QObject* backendObject()const { return m_backend; }

    /** Returns list of detected EA USB devices for the Settings UI. */
    Q_INVOKABLE QStringList listUsbDevices()
    {
        AndroidSerialTransport tmp;
        return tmp.availablePorts();
    }

    Q_INVOKABLE void switchToUsb(const QString& deviceName = QString())
    {
        clearBackend();
        auto* b = new DeviceBackend(this);
        m_backend = b;
        m_remote  = false;
        wireBackend();
        emit modeChanged();

        // connectDevice drives AndroidSerialTransport (via #ifdef in DeviceBackend)
        QTimer::singleShot(100, this, [b, deviceName](){
            b->connectDevice(deviceName);
        });
    }

    Q_INVOKABLE void switchToRest(const QString& url)
    {
        clearBackend();
        auto* b = new RemoteBackend(normalizeUrl(url), this);
        m_backend = b;
        m_remote  = true;
        wireBackend();
        emit modeChanged();
    }

    Q_INVOKABLE void disconnect()
    {
        if (auto* lb = qobject_cast<DeviceBackend*>(m_backend))
            lb->disconnectDevice();
        else if (auto* rb = qobject_cast<RemoteBackend*>(m_backend))
            rb->disconnectDevice();
    }

signals:
    void modeChanged();

private:
    void wireBackend()
    {
        m_engine->rootContext()->setContextProperty("backend", m_backend);
    }

    void clearBackend()
    {
        if (m_backend) {
            disconnect();
            m_backend->deleteLater();
            m_backend = nullptr;
        }
    }

    static QString normalizeUrl(const QString& raw)
    {
        QString url = raw.trimmed();
        if (!url.startsWith("http://") && !url.startsWith("https://"))
            url.prepend("http://");
        QUrl qurl(url);
        if (qurl.port() == -1) {
            qurl.setPort(8484);
            url = qurl.toString();
        }
        return url;
    }

    QQmlApplicationEngine* m_engine  = nullptr;
    QObject*               m_backend = nullptr;
    bool                   m_remote  = false;
};

// ── main ──────────────────────────────────────────────────────────────────

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName("OpenPS2000");
    app.setOrganizationDomain("yeckel.cz");
    app.setOrganizationName("OpenPS2000");

    QQmlApplicationEngine engine;

    // Null backend placeholder — QML guards on backend.connected
    QObject* nullBackend = new QObject(&app);
    engine.rootContext()->setContextProperty("backend", nullBackend);

    BackendFactory factory(&engine, &app);
    engine.rootContext()->setContextProperty("backendFactory", &factory);

    const QUrl url(QStringLiteral("qrc:/qt/qml/openps2000android/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, []() { QCoreApplication::exit(-1); },
                     Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}

#include "main.moc"


// ── BackendFactory ────────────────────────────────────────────────────────
// Exposed to QML as context property "backendFactory".
// QML calls switchToUsb() or switchToRest(url) when the user taps Connect.
//
class BackendFactory : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isRemote READ isRemote NOTIFY modeChanged)
    Q_PROPERTY(QObject* backend READ backendObject NOTIFY modeChanged)

public:
    explicit BackendFactory(QQmlApplicationEngine* engine, QObject* parent = nullptr)
        : QObject(parent), m_engine(engine)
    {}

    bool     isRemote()     const { return m_remote; }
    QObject* backendObject()const { return m_backend; }

    Q_INVOKABLE void switchToUsb(const QString& deviceName = QString())
    {
        clearBackend();
        auto* b = new DeviceBackend(this);
        m_backend = b;
        m_remote  = false;
        wireBackend();
        emit modeChanged();

        // Open the USB device; DeviceBackend's connectDevice() drives SerialTransport
        QTimer::singleShot(100, this, [b, deviceName](){
            b->connectDevice(deviceName);
        });
    }

    Q_INVOKABLE void switchToRest(const QString& url)
    {
        clearBackend();
        auto* b = new RemoteBackend(normalizeUrl(url), this);
        m_backend = b;
        m_remote  = true;
        wireBackend();
        emit modeChanged();
    }

    Q_INVOKABLE void disconnect()
    {
        if (auto* lb = qobject_cast<DeviceBackend*>(m_backend))
            lb->disconnectDevice();
        else if (auto* rb = qobject_cast<RemoteBackend*>(m_backend))
            rb->disconnectDevice();
    }

signals:
    void modeChanged();

private:
    void wireBackend()
    {
        // Expose as "backend" context property (same name QML uses)
        m_engine->rootContext()->setContextProperty("backend", m_backend);
    }

    void clearBackend()
    {
        if (m_backend) {
            disconnect(); // stop polling / serial
            m_backend->deleteLater();
            m_backend = nullptr;
        }
    }

    static QString normalizeUrl(const QString& raw)
    {
        QString url = raw.trimmed();
        if (!url.startsWith("http://") && !url.startsWith("https://"))
            url.prepend("http://");
        // Append default port if none given
        QUrl qurl(url);
        if (qurl.port() == -1) {
            qurl.setPort(8484);
            url = qurl.toString();
        }
        return url;
    }

    QQmlApplicationEngine* m_engine  = nullptr;
    QObject*               m_backend = nullptr;
    bool                   m_remote  = false;
};

// ── main ──────────────────────────────────────────────────────────────────

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName("OpenPS2000");
    app.setOrganizationDomain("yeckel.cz");
    app.setOrganizationName("OpenPS2000");

    QQmlApplicationEngine engine;

    // Null backend until user connects — QML guards on backend.connected
    QObject* nullBackend = new QObject(&app);
    engine.rootContext()->setContextProperty("backend", nullBackend);

    BackendFactory factory(&engine, &app);
    engine.rootContext()->setContextProperty("backendFactory", &factory);

    const QUrl url(QStringLiteral("qrc:/qt/qml/openps2000android/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, []() { QCoreApplication::exit(-1); },
                     Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}

#include "main.moc"
