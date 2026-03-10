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
#include <QCoreApplication>
#include <QQuickWindow>

#include "../app/DeviceBackend.h"
#include "../app/RemoteBackend.h"
#include "AndroidSerialTransport.h"
#include "AlarmNotifier.h"

// ── NullBackend ───────────────────────────────────────────────────────────
// Safe placeholder exposed to QML before the user selects a connection.
// All properties return harmless defaults; all invokable methods are no-ops.
class NullBackend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool    connected    READ connected    CONSTANT)
    Q_PROPERTY(QString portName     READ portName     CONSTANT)
    Q_PROPERTY(QString deviceType   READ deviceType   CONSTANT)
    Q_PROPERTY(QString serialNo     READ serialNo     CONSTANT)
    Q_PROPERTY(QString articleNo    READ articleNo    CONSTANT)
    Q_PROPERTY(QString manufacturer READ manufacturer CONSTANT)
    Q_PROPERTY(QString swVersion    READ swVersion    CONSTANT)
    Q_PROPERTY(double  nomVoltage   READ nomVoltage   CONSTANT)
    Q_PROPERTY(double  nomCurrent   READ nomCurrent   CONSTANT)
    Q_PROPERTY(double  nomPower     READ nomPower     CONSTANT)
    Q_PROPERTY(double  voltage      READ voltage      CONSTANT)
    Q_PROPERTY(double  current      READ current      CONSTANT)
    Q_PROPERTY(double  power        READ power        CONSTANT)
    Q_PROPERTY(double  setVoltage   READ setVoltage   CONSTANT)
    Q_PROPERTY(double  setCurrent   READ setCurrent   CONSTANT)
    Q_PROPERTY(double  ovpVoltage   READ ovpVoltage   CONSTANT)
    Q_PROPERTY(double  ocpCurrent   READ ocpCurrent   CONSTANT)
    Q_PROPERTY(bool    remoteMode   READ remoteMode   CONSTANT)
    Q_PROPERTY(bool    outputOn     READ outputOn     CONSTANT)
    Q_PROPERTY(bool    ccMode       READ ccMode       CONSTANT)
    Q_PROPERTY(bool    ovpActive    READ ovpActive    CONSTANT)
    Q_PROPERTY(bool    ocpActive    READ ocpActive    CONSTANT)
    Q_PROPERTY(bool    oppActive    READ oppActive    CONSTANT)
    Q_PROPERTY(bool    otpActive    READ otpActive    CONSTANT)
    Q_PROPERTY(bool    anyAlarm     READ anyAlarm     CONSTANT)
    Q_PROPERTY(double  energyWh     READ energyWh     CONSTANT)
    Q_PROPERTY(QString duration     READ duration     CONSTANT)
    Q_PROPERTY(int     sampleCount  READ sampleCount  CONSTANT)
    Q_PROPERTY(QString remoteUrl    READ remoteUrl    CONSTANT)
public:
    explicit NullBackend(QObject* parent = nullptr) : QObject(parent) {}
    bool    connected()    const { return false; }
    QString portName()     const { return {}; }
    QString deviceType()   const { return {}; }
    QString serialNo()     const { return {}; }
    QString articleNo()    const { return {}; }
    QString manufacturer() const { return {}; }
    QString swVersion()    const { return {}; }
    double  nomVoltage()   const { return 0.0; }
    double  nomCurrent()   const { return 0.0; }
    double  nomPower()     const { return 0.0; }
    double  voltage()      const { return 0.0; }
    double  current()      const { return 0.0; }
    double  power()        const { return 0.0; }
    double  setVoltage()   const { return 0.0; }
    double  setCurrent()   const { return 0.0; }
    double  ovpVoltage()   const { return 0.0; }
    double  ocpCurrent()   const { return 0.0; }
    bool    remoteMode()   const { return false; }
    bool    outputOn()     const { return false; }
    bool    ccMode()       const { return false; }
    bool    ovpActive()    const { return false; }
    bool    ocpActive()    const { return false; }
    bool    oppActive()    const { return false; }
    bool    otpActive()    const { return false; }
    bool    anyAlarm()     const { return false; }
    double  energyWh()     const { return 0.0; }
    QString duration()     const { return QStringLiteral("0s"); }
    int     sampleCount()  const { return 0; }
    QString remoteUrl()    const { return {}; }
    Q_INVOKABLE void sendSetVoltage(double)  {}
    Q_INVOKABLE void sendSetCurrent(double)  {}
    Q_INVOKABLE void sendOvpVoltage(double)  {}
    Q_INVOKABLE void sendOcpCurrent(double)  {}
    Q_INVOKABLE void setOutputOn(bool)       {}
    Q_INVOKABLE void setRemoteMode(bool)     {}
    Q_INVOKABLE void acknowledgeAlarms()     {}
};

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
        return AndroidSerialTransport::listDevices();
    }

    /** True if the first found EA USB device already has permission. */
    Q_INVOKABLE bool hasUsbPermission()
    {
        QJniObject ctx = QNativeInterface::QAndroidApplication::context();
        if (!ctx.isValid()) return false;
        return QJniObject::callStaticMethod<jboolean>(
            "org/openps2000/UsbSerial", "hasPermission",
            "(Landroid/content/Context;)Z", ctx.object<jobject>());
    }

    /** Show the Android system USB permission dialog for the EA device. */
    Q_INVOKABLE void requestUsbPermission()
    {
        QJniObject ctx = QNativeInterface::QAndroidApplication::context();
        if (!ctx.isValid()) return;
        QJniObject::callStaticMethod<void>(
            "org/openps2000/UsbSerial", "requestPermissionAsync",
            "(Landroid/content/Context;)V", ctx.object<jobject>());
    }

    /**
     * Poll the Java-side flag set by the BroadcastReceiver.
     * Returns true once the user has granted permission.
     */
    Q_INVOKABLE bool isUsbPermissionGranted()
    {
        return QJniObject::callStaticMethod<jboolean>(
            "org/openps2000/UsbSerial", "isPermissionGranted", "()Z");
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
    // Force OpenGL ES rendering backend to avoid SIGABRT in hwuiTask0.
    // Qt 6.9 defaults to Vulkan on Android, which conflicts with Android HWUI's
    // Vulkan renderer on Samsung devices (Android 16 / Xclipse 540 GPU).
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGLRhi);

    QGuiApplication app(argc, argv);
    app.setApplicationName("OpenPS2000");
    app.setOrganizationDomain("yeckel.cz");
    app.setOrganizationName("OpenPS2000");

    QQmlApplicationEngine engine;

    // Null backend with all required properties — prevents QML TypeErrors before
    // the user selects a connection in the Settings tab.
    NullBackend* nullBackend = new NullBackend(&app);
    engine.rootContext()->setContextProperty("backend", nullBackend);

    BackendFactory factory(&engine, &app);
    engine.rootContext()->setContextProperty("backendFactory", &factory);

    AlarmNotifier alarmNotifier(&app);
    engine.rootContext()->setContextProperty("alarmNotifier", &alarmNotifier);
    // Request notification permission on first run (Android 13+)
    alarmNotifier.requestPermission();

    const QUrl url(QStringLiteral("qrc:/qt/qml/openps2000android/qml/Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, []() { QCoreApplication::exit(-1); },
                     Qt::QueuedConnection);
    engine.load(url);

    return app.exec();
}

#include "main.moc"

