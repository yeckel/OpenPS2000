// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#pragma once
#include <QObject>
#include <QVariantMap>
#include <QVariantList>
#include "BatteryProfile.h"

// Charging state values are exposed as int to QML
// 0=Idle 1=CC 2=CV 3=Float 4=Done 5=Fault
enum class ChargingState { Idle, CCPhase, CVPhase, FloatPhase, Done, Fault };

class ChargerEngine : public QObject {
    Q_OBJECT
    Q_PROPERTY(int     state        READ stateInt       NOTIFY stateChanged)
    Q_PROPERTY(QString stateString  READ stateString    NOTIFY stateChanged)
    Q_PROPERTY(QString faultReason  READ faultReason    NOTIFY stateChanged)
    Q_PROPERTY(double  elapsedSecs  READ elapsedSecs    NOTIFY statsUpdated)
    Q_PROPERTY(double  mAhCharged   READ mAhCharged     NOTIFY statsUpdated)
    Q_PROPERTY(double  whCharged    READ whCharged      NOTIFY statsUpdated)
    Q_PROPERTY(double  peakVoltage  READ peakVoltage    NOTIFY statsUpdated)
    Q_PROPERTY(double  peakCurrent  READ peakCurrent    NOTIFY statsUpdated)
    Q_PROPERTY(double  minVoltage   READ minVoltage     NOTIFY statsUpdated)
    Q_PROPERTY(QVariantList profiles READ profileVariants NOTIFY profilesChanged)

public:
    explicit ChargerEngine(QObject* parent = nullptr);

    int          stateInt()      const { return static_cast<int>(m_state); }
    QString      stateString()   const;
    QString      faultReason()   const { return m_faultReason; }
    double       elapsedSecs()   const;
    double       mAhCharged()    const { return m_mAh; }
    double       whCharged()     const { return m_wh; }
    double       peakVoltage()   const { return m_peakV; }
    double       peakCurrent()   const { return m_peakI; }
    double       minVoltage()    const { return m_minV; }
    QVariantList profileVariants() const;

    Q_INVOKABLE void startCharging(int profileIndex);
    Q_INVOKABLE void stopCharging();
    Q_INVOKABLE QStringList profileNames() const;
    Q_INVOKABLE QVariantMap getProfile(int index) const;
    Q_INVOKABLE QVariantMap defaultsForChemistry(const QString& chem) const;
    Q_INVOKABLE void saveProfile(const QVariantMap& map, int replaceIndex = -1);
    Q_INVOKABLE void deleteProfile(int index);

public slots:
    void onSample(double t, double v, double i, double p);

signals:
    void stateChanged();
    void statsUpdated();
    void profilesChanged();
    void newChargingPoint(double t, double v, double i);    // t seconds from charger start
    void phaseMarker(double t, int stateInt, QString label); // for chart annotation
    void chargingComplete(double mAh, double wh, double secs);
    void chargingFault(const QString& reason);
    void statusMessage(const QString& msg);

    // ── Device control ── connect to DeviceBackend slots in main.cpp ────────
    void setVoltageRequested(double v);
    void setCurrentRequested(double i);
    void setOvpRequested(double v);
    void setOcpRequested(double i);
    void setOutputRequested(bool on);

private:
    void setState(ChargingState s, const QString& fault = {});
    void applySetpoints();
    void applyFloatSetpoints();
    void checkCCCV(double v, double i, double relT);
    void checkNixx(double v, double relT);

    ChargingState m_state = ChargingState::Idle;
    QString       m_faultReason;

    QList<BatteryProfile> m_profiles;
    BatteryProfile        m_profile;        // active profile copy

    double m_startT      = 0;
    double m_lastT       = 0;
    double m_mAh         = 0;
    double m_wh          = 0;
    double m_peakV       = 0;
    double m_peakI       = 0;
    double m_minV        = 1e9;
    double m_peakVForDV  = 0;   // for -ΔV detection
    int    m_warmupCount = 0;   // ignore -ΔV for first N samples
};
