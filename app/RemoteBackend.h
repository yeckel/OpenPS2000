// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// RemoteBackend.h — DeviceBackend-compatible REST client for remote instances.
#pragma once

#include "DataRecord.h"
#include "PS2000Protocol.h"

#include <QObject>
#include <QString>
#include <QTimer>
#include <QVector>
#include <QVariantMap>
#include <QNetworkAccessManager>

class RemoteBackend : public QObject
{
    Q_OBJECT

    // ── Connection state ──────────────────────────────────────────────────
    Q_PROPERTY(bool    connected  READ connected  NOTIFY connectedChanged)
    Q_PROPERTY(QString portName   READ portName   NOTIFY portNameChanged)

    // ── Device info ───────────────────────────────────────────────────────
    Q_PROPERTY(QString deviceType   READ deviceType   NOTIFY deviceInfoChanged)
    Q_PROPERTY(QString serialNo     READ serialNo     NOTIFY deviceInfoChanged)
    Q_PROPERTY(QString articleNo    READ articleNo    NOTIFY deviceInfoChanged)
    Q_PROPERTY(QString manufacturer READ manufacturer NOTIFY deviceInfoChanged)
    Q_PROPERTY(QString swVersion    READ swVersion    NOTIFY deviceInfoChanged)
    Q_PROPERTY(double  nomVoltage   READ nomVoltage   NOTIFY deviceInfoChanged)
    Q_PROPERTY(double  nomCurrent   READ nomCurrent   NOTIFY deviceInfoChanged)
    Q_PROPERTY(double  nomPower     READ nomPower     NOTIFY deviceInfoChanged)

    // ── Live measurements ─────────────────────────────────────────────────
    Q_PROPERTY(double voltage  READ voltage  NOTIFY measurementChanged)
    Q_PROPERTY(double current  READ current  NOTIFY measurementChanged)
    Q_PROPERTY(double power    READ power    NOTIFY measurementChanged)

    // ── Setpoints ─────────────────────────────────────────────────────────
    Q_PROPERTY(double setVoltage READ setVoltage NOTIFY setpointsChanged)
    Q_PROPERTY(double setCurrent READ setCurrent NOTIFY setpointsChanged)

    // ── Limits ────────────────────────────────────────────────────────────
    Q_PROPERTY(double ovpVoltage READ ovpVoltage NOTIFY limitsChanged)
    Q_PROPERTY(double ocpCurrent READ ocpCurrent NOTIFY limitsChanged)

    // ── Status flags ──────────────────────────────────────────────────────
    Q_PROPERTY(bool remoteMode READ remoteMode NOTIFY statusFlagsChanged)
    Q_PROPERTY(bool outputOn   READ outputOn   NOTIFY statusFlagsChanged)
    Q_PROPERTY(bool ccMode     READ ccMode     NOTIFY statusFlagsChanged)
    Q_PROPERTY(bool ovpActive  READ ovpActive  NOTIFY statusFlagsChanged)
    Q_PROPERTY(bool ocpActive  READ ocpActive  NOTIFY statusFlagsChanged)
    Q_PROPERTY(bool oppActive  READ oppActive  NOTIFY statusFlagsChanged)
    Q_PROPERTY(bool otpActive  READ otpActive  NOTIFY statusFlagsChanged)
    Q_PROPERTY(bool anyAlarm   READ anyAlarm   NOTIFY statusFlagsChanged)

    // ── Session stats ─────────────────────────────────────────────────────
    Q_PROPERTY(double  energyWh    READ energyWh    NOTIFY energyChanged)
    Q_PROPERTY(QString duration    READ duration    NOTIFY durationChanged)
    Q_PROPERTY(int     sampleCount READ sampleCount NOTIFY sampleCountChanged)

    // ── Remote URL ────────────────────────────────────────────────────────
    Q_PROPERTY(QString remoteUrl READ remoteUrl NOTIFY remoteUrlChanged)

public:
    explicit RemoteBackend(const QString& url, QObject* parent = nullptr);
    ~RemoteBackend() override;

    // ── Property readers ─────────────────────────────────────────────────
    bool    connected()    const { return m_connected; }
    QString portName()     const { return m_portName; }
    QString deviceType()   const { return m_deviceInfo.deviceType; }
    QString serialNo()     const { return m_deviceInfo.serialNo; }
    QString articleNo()    const { return m_deviceInfo.articleNo; }
    QString manufacturer() const { return m_deviceInfo.manufacturer; }
    QString swVersion()    const { return m_deviceInfo.swVersion; }
    double  nomVoltage()   const { return m_deviceInfo.nomVoltage; }
    double  nomCurrent()   const { return m_deviceInfo.nomCurrent; }
    double  nomPower()     const { return m_deviceInfo.nomPower; }
    double  voltage()      const { return m_voltage; }
    double  current()      const { return m_current; }
    double  power()        const { return m_power; }
    double  setVoltage()   const { return m_setVoltage; }
    double  setCurrent()   const { return m_setCurrent; }
    double  ovpVoltage()   const { return m_ovpVoltage; }
    double  ocpCurrent()   const { return m_ocpCurrent; }
    bool    remoteMode()   const { return m_remoteMode; }
    bool    outputOn()     const { return m_outputOn; }
    bool    ccMode()       const { return m_ccMode; }
    bool    ovpActive()    const { return m_ovpActive; }
    bool    ocpActive()    const { return m_ocpActive; }
    bool    oppActive()    const { return m_oppActive; }
    bool    otpActive()    const { return m_otpActive; }
    bool    anyAlarm()     const { return m_ovpActive || m_ocpActive || m_oppActive || m_otpActive; }
    double  energyWh()     const { return m_energyWh; }
    QString duration()     const { return m_duration; }
    int     sampleCount()  const { return m_readings.size(); }
    QString remoteUrl()    const { return m_url; }

    Q_INVOKABLE QStringList availablePorts() const;
    Q_INVOKABLE QVariantMap measureRange(double tStart, double tEnd) const;

public slots:
    void connectDevice(const QString& portName);
    void disconnectDevice();
    void setRemoteMode(bool remote);
    void setOutputOn(bool on);
    void setOutputOnQueued(bool on);
    void sendSetVoltage(double voltage);
    void sendSetCurrent(double current);
    void sendOvpVoltage(double voltage);
    void sendOcpCurrent(double current);
    void acknowledgeAlarms();
    void resetEnergy();
    void exportCsv(const QString& path);
    void exportExcel(const QString& path);

signals:
    void connectedChanged(bool connected);
    void portNameChanged(const QString& port);
    void deviceInfoChanged();
    void measurementChanged();
    void setpointsChanged();
    void limitsChanged();
    void statusFlagsChanged();
    void alarmTriggered(bool ovp, bool ocp, bool opp, bool otp);
    void energyChanged(double wh);
    void durationChanged(const QString& hms);
    void sampleCountChanged(int n);
    void newSample(double t, double v, double i, double p);
    void statusMessage(const QString& msg);
    void errorOccurred(const QString& msg);
    void remoteUrlChanged(const QString& url);

private slots:
    void poll();
    void fetchInfo();

private:
    void putJson(const QString& path, const QByteArray& body);

    QNetworkAccessManager* m_nam       = nullptr;
    QTimer*                m_pollTimer = nullptr;
    QString                m_url       = "http://localhost:8484";
    QString                m_portName;

    PS2000::DeviceInfo m_deviceInfo;

    bool    m_connected  = false;
    double  m_voltage    = 0.0;
    double  m_current    = 0.0;
    double  m_power      = 0.0;
    double  m_setVoltage = 0.0;
    double  m_setCurrent = 0.0;
    double  m_ovpVoltage = 0.0;
    double  m_ocpCurrent = 0.0;

    bool m_remoteMode = false;
    bool m_outputOn   = false;
    bool m_ccMode     = false;
    bool m_ovpActive  = false;
    bool m_ocpActive  = false;
    bool m_oppActive  = false;
    bool m_otpActive  = false;

    QVector<DataRecord> m_readings;
    double  m_energyWh = 0.0;
    double  m_lastT    = -1.0;
    QString m_duration = "00:00:00";
};
