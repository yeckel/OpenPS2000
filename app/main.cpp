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
#include "DeviceBackend.h"
#include "ChargerEngine.h"
#include "PulseEngine.h"
#include "SequenceEngine.h"
#include "SequenceProfile.h"

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
        // Load without saving (we're just restoring state)
        langChanger.setLanguage(chosen, /*save=*/false);
    }

    DeviceBackend  backend;
    ChargerEngine  charger;
    PulseEngine    pulser;
    SequenceEngine sequencer;
    SequenceStore  seqStore;

    // Wire charger control signals → device backend slots
    QObject::connect(&charger, &ChargerEngine::setVoltageRequested, &backend, &DeviceBackend::sendSetVoltage);
    QObject::connect(&charger, &ChargerEngine::setCurrentRequested, &backend, &DeviceBackend::sendSetCurrent);
    QObject::connect(&charger, &ChargerEngine::setOvpRequested,     &backend, &DeviceBackend::sendOvpVoltage);
    QObject::connect(&charger, &ChargerEngine::setOcpRequested,     &backend, &DeviceBackend::sendOcpCurrent);
    QObject::connect(&charger, &ChargerEngine::setOutputRequested,  &backend, &DeviceBackend::setOutputOn);
    // Feed live measurements into charger state machine
    QObject::connect(&backend, &DeviceBackend::newSample,
                     &charger, &ChargerEngine::onSample);
    // Forward charger status messages to main status bar
    QObject::connect(&charger, &ChargerEngine::statusMessage,
                     &backend, &DeviceBackend::statusMessage);
    // Stop charger if device disconnects mid-charge
    QObject::connect(&backend, &DeviceBackend::connectedChanged, &charger, [&]()
    {
        if(!backend.connected())
            charger.stopCharging();
    });

    // Wire pulse engine control signals → device backend slots
    QObject::connect(&pulser, &PulseEngine::setVoltageRequested, &backend, &DeviceBackend::sendSetVoltage);
    QObject::connect(&pulser, &PulseEngine::setCurrentRequested, &backend, &DeviceBackend::sendSetCurrent);
    QObject::connect(&pulser, &PulseEngine::setOutputRequested,  &backend, &DeviceBackend::setOutputOn);
    // Feed live measurements into pulse engine
    QObject::connect(&backend, &DeviceBackend::newSample,
                     &pulser, &PulseEngine::onSample);
    // Stop pulser if device disconnects
    QObject::connect(&backend, &DeviceBackend::connectedChanged, &pulser, [&]()
    {
        if(!backend.connected())
            pulser.stop();
    });

    // Wire sequence engine control signals → device backend slots
    QObject::connect(&sequencer, &SequenceEngine::setVoltageRequested, &backend, &DeviceBackend::sendSetVoltage);
    QObject::connect(&sequencer, &SequenceEngine::setCurrentRequested, &backend, &DeviceBackend::sendSetCurrent);
    QObject::connect(&sequencer, &SequenceEngine::setOutputRequested,  &backend, &DeviceBackend::setOutputOn);
    // Feed live measurements into sequence engine
    QObject::connect(&backend, &DeviceBackend::newSample, &sequencer, &SequenceEngine::onSample);
    // Stop sequencer if device disconnects
    QObject::connect(&backend, &DeviceBackend::connectedChanged, &sequencer, [&]()
    {
        if(!backend.connected())
            sequencer.stop();
    });

    QQmlApplicationEngine engine;
    // Wire engine so setLanguage() can call retranslate() immediately
    langChanger.setEngine(&engine);

    engine.rootContext()->setContextProperty("backend", &backend);
    engine.rootContext()->setContextProperty("langChanger", &langChanger);
    engine.rootContext()->setContextProperty("charger", &charger);
    engine.rootContext()->setContextProperty("pulser", &pulser);
    engine.rootContext()->setContextProperty("sequencer", &sequencer);
    engine.rootContext()->setContextProperty("seqStore", &seqStore);

    engine.loadFromModule("openps2000app", "Main");

    if(engine.rootObjects().isEmpty())
    {
        return -1;
    }

    return app.exec();
}

#include "main.moc"
