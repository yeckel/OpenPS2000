// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// DeviceBackend.h — QML-exposed controller for the EA PS 2000 B power supply.
#pragma once

#include "DataRecord.h"
#include "PS2000Protocol.h"
#include "SerialTransport.h"

#include <QObject>
#include <QString>
#include <QTimer>
#include <QVector>
#include <QVariantMap>

class DeviceBackend : public QObject
{
    Q_OBJECT

    // ── Connection state ──────────────────────────────────────────────────
    Q_PROPERTY(bool   connected    READ connected    NOTIFY connectedChanged)
    Q_PROPERTY(QString portName    READ portName     NOTIFY portNameChanged)

    // ── Device info ───────────────────────────────────────────────────────
    Q_PROPERTY(QString deviceType   READ deviceType   NOTIFY deviceInfoChanged)
    Q_PROPERTY(QString serialNo     READ serialNo     NOTIFY deviceInfoChanged)
    Q_PROPERTY(QString articleNo    READ articleNo    NOTIFY deviceInfoChanged)
    Q_PROPERTY(QString manufacturer READ manufacturer NOTIFY deviceInfoChanged)
    Q_PROPERTY(QString swVersion    READ swVersion    NOTIFY deviceInfoChanged)
    Q_PROPERTY(double  nomVoltage   READ nomVoltage   NOTIFY deviceInfoChanged)
    Q_PROPERTY(double  nomCurrent   READ nomCurrent   NOTIFY deviceInfoChanged)
    Q_PROPERTY(double  nomPower     READ nomPower     NOTIFY deviceInfoChanged)

    // ── Live measurements ────────────────────────────────────────────────
    Q_PROPERTY(double  voltage     READ voltage     NOTIFY measurementChanged)
    Q_PROPERTY(double  current     READ current     NOTIFY measurementChanged)
    Q_PROPERTY(double  power       READ power       NOTIFY measurementChanged)

    // ── Setpoints ────────────────────────────────────────────────────────
    Q_PROPERTY(double setVoltage  READ setVoltage  NOTIFY setpointsChanged)
    Q_PROPERTY(double setCurrent  READ setCurrent  NOTIFY setpointsChanged)

    // ── Limits ───────────────────────────────────────────────────────────
    Q_PROPERTY(double  ovpVoltage  READ ovpVoltage  NOTIFY limitsChanged)
    Q_PROPERTY(double  ocpCurrent  READ ocpCurrent  NOTIFY limitsChanged)

    // ── Status flags ─────────────────────────────────────────────────────
    Q_PROPERTY(bool    remoteMode  READ remoteMode  NOTIFY statusFlagsChanged)
    Q_PROPERTY(bool    outputOn    READ outputOn    NOTIFY statusFlagsChanged)
    Q_PROPERTY(bool    ccMode      READ ccMode      NOTIFY statusFlagsChanged)  // CC vs CV
    Q_PROPERTY(bool    ovpActive   READ ovpActive   NOTIFY statusFlagsChanged)
    Q_PROPERTY(bool    ocpActive   READ ocpActive   NOTIFY statusFlagsChanged)
    Q_PROPERTY(bool    oppActive   READ oppActive   NOTIFY statusFlagsChanged)
    Q_PROPERTY(bool    otpActive   READ otpActive   NOTIFY statusFlagsChanged)
    Q_PROPERTY(bool    anyAlarm    READ anyAlarm    NOTIFY statusFlagsChanged)

    // ── Session stats ────────────────────────────────────────────────────
    Q_PROPERTY(double  energyWh    READ energyWh    NOTIFY energyChanged)
    Q_PROPERTY(QString duration    READ duration    NOTIFY durationChanged)
    Q_PROPERTY(int     sampleCount READ sampleCount NOTIFY sampleCountChanged)

public:
    explicit DeviceBackend(QObject* parent = nullptr);
    ~DeviceBackend() override;

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
    double  energyWh()     const { return m_energyWh - m_energyBase; }
    QString duration()     const { return m_duration; }
    int     sampleCount()  const { return m_readings.size(); }

    // ── Available serial ports (for UI port picker) ───────────────────────
    Q_INVOKABLE QStringList availablePorts() const;

    // ── Range measurement ────────────────────────────────────────────────
    Q_INVOKABLE QVariantMap measureRange(double tStart, double tEnd) const;

public slots:
    // Connection
    void connectDevice(const QString& portName);
    void disconnectDevice();

    // Control (requires remote mode)
    void setRemoteMode(bool remote);
    void setOutputOn(bool on);
    void sendSetVoltage(double voltage);
    void sendSetCurrent(double current);
    void sendOvpVoltage(double voltage);
    void sendOcpCurrent(double current);
    void acknowledgeAlarms();
    void resetEnergy();

    // Export
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
    // Emitted once when any protection alarm transitions from off → active
    void alarmTriggered(bool ovp, bool ocp, bool opp, bool otp);
    void energyChanged(double wh);
    void durationChanged(const QString& hms);
    void sampleCountChanged(int n);

    // Forwarded to QML for chart updates
    void newSample(double t, double v, double i, double p);

    void statusMessage(const QString& msg);
    void errorOccurred(const QString& msg);

private slots:
    void onDeviceInfoReady(const PS2000::DeviceInfo& info);
    void onStatusUpdated(const PS2000::DeviceStatus& st);
    void onLimitsUpdated(double ovpV, double ocpA);
    void onSetValuesUpdated(double setV, double setI);
    void onTransportError(const QString& msg);
    void onTransportMessage(const QString& msg);
    void onDurationTick();

private:
    void cleanupTransport();
    void sendCommand(const QByteArray& telegram);

    SerialTransport* m_transport = nullptr;
    QTimer*          m_durationTimer = nullptr;
    bool             m_connected  = false;
    QString          m_portName;
    PS2000::DeviceInfo m_deviceInfo;

    // Live readings
    double m_voltage   = 0.0;
    double m_current   = 0.0;
    double m_power     = 0.0;
    double m_setVoltage= 0.0;
    double m_setCurrent= 0.0;
    double m_ovpVoltage= 0.0;
    double m_ocpCurrent= 0.0;

    // Status flags
    bool m_remoteMode = false;
    bool m_outputOn   = false;
    bool m_ccMode     = false;
    bool m_ovpActive  = false;
    bool m_ocpActive  = false;
    bool m_oppActive  = false;
    bool m_otpActive  = false;

    // Session data
    QVector<DataRecord> m_readings;
    double m_energyWh   = 0.0;
    double m_energyBase = 0.0;
    double m_startTime  = 0.0;
    double m_lastT      = -1.0;
    double m_lastPower  = 0.0;
    QString m_duration  = "00:00:00";
};
