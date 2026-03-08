// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#pragma once
#include <QString>
#include <QList>
#include <QJsonObject>

struct BatteryProfile {
    QString name;
    QString chemistry;          // "LiPo","LiFe","Pb","NiCd","NiMH"
    int     cells           = 1;
    double  capacityMah     = 1000.0;   // battery capacity in mAh
    double  chargeRateC     = 1.0;      // charge current as multiple of 1C
    double  cutoffCurrentC  = 0.05;     // CC/CV: terminate when I < this × 1C
    double  cvVoltPerCell   = 4.20;     // target CV voltage per cell
    double  floatVoltPerCell= 0.0;      // >0 → enter float stage after CV (Pb)
    double  maxCellVoltage  = 4.25;     // absolute OVP limit per cell
    double  deltavMvPerCell = 5.0;      // -ΔV termination threshold per cell (NiCd/NiMH)
    int     maxTimeMinutes  = 120;      // safety timeout

    // ── Computed helpers ────────────────────────────────────────────────────
    double chargeVoltage()  const { return cells * cvVoltPerCell; }
    double chargeCurrent()  const { return capacityMah / 1000.0 * chargeRateC; }
    double cutoffCurrent()  const { return capacityMah / 1000.0 * cutoffCurrentC; }
    double ovpVoltage()     const { return cells * maxCellVoltage; }
    double floatVoltage()   const { return cells * floatVoltPerCell; }

    bool   isCCCV()         const { return chemistry == "LiPo" || chemistry == "LiFe" || chemistry == "Pb"; }
    bool   isNixx()         const { return chemistry == "NiCd" || chemistry == "NiMH"; }
    bool   hasFloat()       const { return chemistry == "Pb" && floatVoltPerCell > 0; }

    QJsonObject toJson() const;
    static BatteryProfile fromJson(const QJsonObject& obj);
    static BatteryProfile chemistryDefaults(const QString& chemistry);
    QVariantMap toVariantMap() const;
};

class ProfileStore {
public:
    static QList<BatteryProfile> loadProfiles();
    static void saveProfiles(const QList<BatteryProfile>& profiles);

private:
    static QString profilesFilePath();
    static QList<BatteryProfile> defaultProfiles();
};
