// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include <QObject>
#include <QTranslator>
#include <QLocale>
#include <QSettings>
#include <QSystemTrayIcon>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QEventLoop>
#include <QTimer>
#include <QCommandLineParser>
#include <QWindow>
#include "DeviceBackend.h"
#include "ChargerEngine.h"
#include "PulseEngine.h"
#include "SequenceEngine.h"
#include "SequenceProfile.h"
#include "RemoteServer.h"
#include "MqttClient.h"
#include "RemoteBackend.h"
#include "TrayManager.h"

class LanguageChanger : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString currentLanguage READ currentLanguage NOTIFY languageChanged)
public:
    explicit LanguageChanger(QObject* parent = nullptr) : QObject(parent) {}

    // engine must be set before the first runtime call from QML
    void setEngine(QQmlApplicationEngine* engine)
    {
        m_engine = engine;
    }

    Q_INVOKABLE bool setLanguage(const QString& locale, bool save = true)
    {
        QTranslator* t = new QTranslator(this);
        bool loaded = t->load(":/i18n/openps2000_" + locale);
        if(!loaded && locale != "en")
        {
            delete t;
            return false;
        }
        if(m_current)
        {
            QCoreApplication::removeTranslator(m_current);
            delete m_current;
        }
        m_current = loaded ? t : nullptr;
        if(loaded)
        {
            QCoreApplication::installTranslator(m_current);
        }
        m_locale = locale;
        // Retranslate all live QML bindings immediately
        if(m_engine)
        {
            m_engine->retranslate();
        }
        if(save)
        {
            QSettings settings;
            settings.setValue("ui/language", locale);
        }
        emit languageChanged();
        return true;
    }

    Q_INVOKABLE QString currentLanguage() const
    {
        return m_locale;
    }
    Q_INVOKABLE QStringList availableLanguages() const
    {
        return {"en", "de", "es", "cs", "pl", "zh_CN"};
    }
    Q_INVOKABLE QStringList languageDisplayNames() const
    {
        return {"English", "Deutsch", "Español", "Čeština", "Polski", "中文"};
    }

signals:
    void languageChanged();

private:
    QTranslator* m_current = nullptr;
    QString m_locale = "en";
    QQmlApplicationEngine* m_engine = nullptr;
};

int main(int argc, char* argv[])
{
    qputenv("QT_QUICK_CONTROLS_STYLE", "Material");

    QApplication app(argc, argv);
    app.setApplicationName("OpenPS2000");
    app.setOrganizationName("OpenPS2000");
    app.setOrganizationDomain("openps2000.app");
    app.setApplicationVersion("1.0");

    // ── CLI parsing ────────────────────────────────────────────────────────
    QCommandLineParser cli;
    cli.addHelpOption();
    cli.addVersionOption();
    QCommandLineOption remoteOpt("remote", "Connect to a remote OpenPS2000 REST server", "url");
    cli.addOption(remoteOpt);
    cli.process(app);

    // ── Determine backend ──────────────────────────────────────────────────
    QString remoteUrl;
    bool    isRemote = false;

    auto normalizeUrl = [](QString url) -> QString {
        if (!url.startsWith("http://") && !url.startsWith("https://"))
            url = "http://" + url;
        QUrl u(url);
        if (u.port() == -1) { u.setPort(8484); url = u.toString(); }
        // strip trailing slash
        if (url.endsWith('/')) url.chop(1);
        return url;
    };

    if (cli.isSet(remoteOpt)) {
        remoteUrl = normalizeUrl(cli.value(remoteOpt));
        isRemote  = true;
    } else {
        // Auto-detect: probe 127.0.0.1 directly (avoids IPv6 localhost ambiguity)
        // Give a generous 800 ms – the reply will arrive much sooner on a connection refuse
        QNetworkAccessManager probeNam;
        QNetworkReply* reply = probeNam.get(
            QNetworkRequest(QUrl("http://127.0.0.1:8484/api/v1/info")));
        QEventLoop loop;
        QTimer::singleShot(800, &loop, &QEventLoop::quit);
        QObject::connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
        loop.exec();
        if (reply->error() == QNetworkReply::NoError) {
            remoteUrl = "http://127.0.0.1:8484";
            isRemote  = true;
        }
        reply->deleteLater();
    }

    DeviceBackend*  localBackend  = nullptr;
    RemoteBackend*  remoteBackend = nullptr;

    if (isRemote) {
        remoteBackend = new RemoteBackend(remoteUrl);
    } else {
        localBackend = new DeviceBackend();
    }

    LanguageChanger langChanger;

    // Determine startup language: saved preference > system locale > English
    {
        QSettings settings;
        QString saved = settings.value("ui/language", QString()).toString();
        QStringList available = langChanger.availableLanguages();

        QString chosen = "en";
        if(!saved.isEmpty() && available.contains(saved))
        {
            chosen = saved;
        }
        else
        {
            QString sysLang = QLocale::system().name();
            for(const QString& lang : available)
            {
                if(sysLang == lang || sysLang.startsWith(lang + "_"))
                {
                    chosen = lang;
                    break;
                }
            }
        }
        langChanger.setLanguage(chosen, /*save=*/false);
    }

    // ── Engines (always created; wiring only when using local backend) ─────────
    ChargerEngine   chargerObj;
    PulseEngine     pulserObj;
    SequenceEngine  sequencerObj;
    SequenceStore   seqStoreObj;

    ChargerEngine*  charger   = &chargerObj;
    PulseEngine*    pulser    = &pulserObj;
    SequenceEngine* sequencer = &sequencerObj;
    SequenceStore*  seqStore  = &seqStoreObj;

    if (localBackend) {

        // Wire charger
        QObject::connect(charger, &ChargerEngine::setVoltageRequested, localBackend, &DeviceBackend::sendSetVoltage);
        QObject::connect(charger, &ChargerEngine::setCurrentRequested, localBackend, &DeviceBackend::sendSetCurrent);
        QObject::connect(charger, &ChargerEngine::setOvpRequested,     localBackend, &DeviceBackend::sendOvpVoltage);
        QObject::connect(charger, &ChargerEngine::setOcpRequested,     localBackend, &DeviceBackend::sendOcpCurrent);
        QObject::connect(charger, &ChargerEngine::setOutputRequested,  localBackend, &DeviceBackend::setOutputOn);
        QObject::connect(localBackend, &DeviceBackend::newSample,      charger,      &ChargerEngine::onSample);
        QObject::connect(charger,      &ChargerEngine::statusMessage,  localBackend, &DeviceBackend::statusMessage);
        QObject::connect(localBackend, &DeviceBackend::connectedChanged, charger, [charger]() {
            if (!charger->parent()) return; // guard
            // property check done via lambda capture
        });
        QObject::connect(localBackend, &DeviceBackend::connectedChanged, charger, [localBackend, charger]() {
            if (!localBackend->connected()) charger->stopCharging();
        });

        // Wire pulser
        QObject::connect(pulser, &PulseEngine::setVoltageRequested,      localBackend, &DeviceBackend::sendSetVoltage);
        QObject::connect(pulser, &PulseEngine::setCurrentRequested,      localBackend, &DeviceBackend::sendSetCurrent);
        QObject::connect(pulser, &PulseEngine::setOutputRequested,       localBackend, &DeviceBackend::setOutputOn);
        QObject::connect(pulser, &PulseEngine::setOutputQueuedRequested, localBackend, &DeviceBackend::setOutputOnQueued);
        QObject::connect(localBackend, &DeviceBackend::newSample,         pulser,       &PulseEngine::onSample);
        QObject::connect(localBackend, &DeviceBackend::connectedChanged, pulser, [localBackend, pulser]() {
            if (!localBackend->connected()) pulser->stop();
        });

        // Wire sequencer
        QObject::connect(sequencer, &SequenceEngine::setVoltageRequested, localBackend, &DeviceBackend::sendSetVoltage);
        QObject::connect(sequencer, &SequenceEngine::setCurrentRequested, localBackend, &DeviceBackend::sendSetCurrent);
        QObject::connect(sequencer, &SequenceEngine::setOutputRequested,  localBackend, &DeviceBackend::setOutputOn);
        QObject::connect(localBackend, &DeviceBackend::newSample,          sequencer,    &SequenceEngine::onSample);
        QObject::connect(localBackend, &DeviceBackend::connectedChanged, sequencer, [localBackend, sequencer]() {
            if (!localBackend->connected()) sequencer->stop();
        });
    }

    // ── Remote server + MQTT (local backend only) ──────────────────────────
    RemoteServer* remoteServer = nullptr;
    MqttClient*   mqttClient   = nullptr;

    if (localBackend) {
        remoteServer = new RemoteServer(localBackend);
        mqttClient   = new MqttClient();

        // Wire RemoteServer → DeviceBackend
        QObject::connect(remoteServer, &RemoteServer::setpointReceived, localBackend, [localBackend](double v, double i) {
            localBackend->sendSetVoltage(v);
            localBackend->sendSetCurrent(i);
        });
        QObject::connect(remoteServer, &RemoteServer::outputReceived, localBackend, &DeviceBackend::setOutputOn);
        QObject::connect(remoteServer, &RemoteServer::limitsReceived, localBackend, [localBackend](double ovp, double ocp) {
            localBackend->sendOvpVoltage(ovp);
            localBackend->sendOcpCurrent(ocp);
        });

        // Wire MqttClient → DeviceBackend
        QObject::connect(mqttClient, &MqttClient::cmdSetpoint, localBackend, [localBackend](double v, double i) {
            localBackend->sendSetVoltage(v);
            localBackend->sendSetCurrent(i);
        });
        QObject::connect(mqttClient, &MqttClient::cmdOutput, localBackend, &DeviceBackend::setOutputOn);
        QObject::connect(mqttClient, &MqttClient::cmdLimits, localBackend, [localBackend](double ovp, double ocp) {
            localBackend->sendOvpVoltage(ovp);
            localBackend->sendOcpCurrent(ocp);
        });

        // Wire DeviceBackend → MqttClient
        QObject::connect(localBackend, &DeviceBackend::newSample, mqttClient, [localBackend, mqttClient](double, double v, double i, double p) {
            mqttClient->publishMeasurement(v, i, p, localBackend->energyWh());
        });
        QObject::connect(localBackend, &DeviceBackend::statusFlagsChanged, mqttClient, [localBackend, mqttClient]() {
            mqttClient->publishStatus(localBackend->outputOn(), localBackend->setVoltage(), localBackend->setCurrent());
        });

        // Restore saved remote settings
        QSettings s;
        if (s.value("remote/restEnabled", false).toBool())
            remoteServer->start(s.value("remote/restPort", 8484).toInt(),
                                s.value("remote/restToken").toString());
        if (s.value("remote/mqttEnabled", false).toBool()) {
            mqttClient->configure(
                s.value("remote/mqttHost",   "localhost").toString(),
                s.value("remote/mqttPort",   1883).toInt(),
                s.value("remote/mqttPrefix", "openps2000").toString(),
                s.value("remote/mqttUser",   "").toString(),
                s.value("remote/mqttPass",   "").toString(),
                s.value("remote/mqttTls",    false).toBool()
            );
            mqttClient->connectToBroker();
        }
    }

    // ── TrayManager ────────────────────────────────────────────────────────
    TrayManager trayMgr;

    QQmlApplicationEngine engine;
    langChanger.setEngine(&engine);

    // Register context properties
    QObject* backendObj = localBackend ? static_cast<QObject*>(localBackend)
                                       : static_cast<QObject*>(remoteBackend);

    engine.rootContext()->setContextProperty("backend",      backendObj);
    engine.rootContext()->setContextProperty("langChanger",  &langChanger);
    engine.rootContext()->setContextProperty("trayManager",  &trayMgr);
    engine.rootContext()->setContextProperty("isRemoteMode",  isRemote);
    // Engines always registered (in remote mode they're idle dummies — QML tabs stay functional)
    engine.rootContext()->setContextProperty("charger",    charger);
    engine.rootContext()->setContextProperty("pulser",     pulser);
    engine.rootContext()->setContextProperty("sequencer",  sequencer);
    engine.rootContext()->setContextProperty("seqStore",   seqStore);
    // REST / MQTT only available in primary mode
    engine.rootContext()->setContextProperty("remoteServer", remoteServer ? static_cast<QObject*>(remoteServer) : nullptr);
    engine.rootContext()->setContextProperty("mqttClient",   mqttClient   ? static_cast<QObject*>(mqttClient)   : nullptr);

    // Give the tray manager the root window once QML loads
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &trayMgr, [&trayMgr](QObject* obj, const QUrl&) {
        if (obj)
            trayMgr.setWindow(qobject_cast<QWindow*>(obj));
    });
    trayMgr.setup(":/qt/qml/openps2000app/openps2000.png");

    engine.loadFromModule("openps2000app", "Main");

    if(engine.rootObjects().isEmpty())
    {
        return -1;
    }

    return app.exec();
}

#include "main.moc"
