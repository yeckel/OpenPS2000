// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#include "BatteryProfile.h"
#include <QJsonArray>
#include <QJsonDocument>
#include <QStandardPaths>
#include <QFile>
#include <QDir>
#include <QVariantMap>

// ── Serialisation ────────────────────────────────────────────────────────────

QJsonObject BatteryProfile::toJson() const {
    return {
        {"name",             name},
        {"chemistry",        chemistry},
        {"cells",            cells},
        {"capacityMah",      capacityMah},
        {"chargeRateC",      chargeRateC},
        {"cutoffCurrentC",   cutoffCurrentC},
        {"cvVoltPerCell",    cvVoltPerCell},
        {"floatVoltPerCell", floatVoltPerCell},
        {"maxCellVoltage",   maxCellVoltage},
        {"deltavMvPerCell",  deltavMvPerCell},
        {"maxTimeMinutes",   maxTimeMinutes}
    };
}

BatteryProfile BatteryProfile::fromJson(const QJsonObject& o) {
    BatteryProfile p;
    p.name              = o["name"].toString("Profile");
    p.chemistry         = o["chemistry"].toString("LiPo");
    p.cells             = o["cells"].toInt(1);
    p.capacityMah       = o["capacityMah"].toDouble(1000);
    p.chargeRateC       = o["chargeRateC"].toDouble(1.0);
    p.cutoffCurrentC    = o["cutoffCurrentC"].toDouble(0.05);
    p.cvVoltPerCell     = o["cvVoltPerCell"].toDouble(4.20);
    p.floatVoltPerCell  = o["floatVoltPerCell"].toDouble(0.0);
    p.maxCellVoltage    = o["maxCellVoltage"].toDouble(4.25);
    p.deltavMvPerCell   = o["deltavMvPerCell"].toDouble(5.0);
    p.maxTimeMinutes    = o["maxTimeMinutes"].toInt(120);
    return p;
}

QVariantMap BatteryProfile::toVariantMap() const {
    return {
        {"name",             name},
        {"chemistry",        chemistry},
        {"cells",            cells},
        {"capacityMah",      capacityMah},
        {"chargeRateC",      chargeRateC},
        {"cutoffCurrentC",   cutoffCurrentC},
        {"cvVoltPerCell",    cvVoltPerCell},
        {"floatVoltPerCell", floatVoltPerCell},
        {"maxCellVoltage",   maxCellVoltage},
        {"deltavMvPerCell",  deltavMvPerCell},
        {"maxTimeMinutes",   maxTimeMinutes}
    };
}

// ── Chemistry factory ────────────────────────────────────────────────────────

BatteryProfile BatteryProfile::chemistryDefaults(const QString& chem) {
    BatteryProfile p;
    p.chemistry = chem;
    if (chem == "LiPo") {
        p.cvVoltPerCell = 4.20; p.maxCellVoltage = 4.25;
        p.chargeRateC = 1.0;   p.cutoffCurrentC = 0.05;
        p.floatVoltPerCell = 0.0; p.maxTimeMinutes = 180;
    } else if (chem == "LiFe") {
        p.cvVoltPerCell = 3.65; p.maxCellVoltage = 3.70;
        p.chargeRateC = 0.5;   p.cutoffCurrentC = 0.05;
        p.floatVoltPerCell = 0.0; p.maxTimeMinutes = 240;
    } else if (chem == "Pb") {
        p.cvVoltPerCell = 2.45; p.maxCellVoltage = 2.55;
        p.chargeRateC = 0.1;   p.cutoffCurrentC = 0.05;
        p.floatVoltPerCell = 2.30; p.maxTimeMinutes = 720;
    } else if (chem == "NiCd") {
        p.cvVoltPerCell = 1.55; p.maxCellVoltage = 1.60;
        p.chargeRateC = 0.1;   p.cutoffCurrentC = 0.0;
        p.deltavMvPerCell = 5.0; p.maxTimeMinutes = 180;
    } else if (chem == "NiMH") {
        p.cvVoltPerCell = 1.55; p.maxCellVoltage = 1.60;
        p.chargeRateC = 0.1;   p.cutoffCurrentC = 0.0;
        p.deltavMvPerCell = 3.0; p.maxTimeMinutes = 180;
    }
    return p;
}

// ── ProfileStore ─────────────────────────────────────────────────────────────

QString ProfileStore::profilesFilePath() {
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dir);
    return dir + "/charging_profiles.json";
}

QList<BatteryProfile> ProfileStore::defaultProfiles() {
    auto make = [](const QString& name, const QString& chem, int cells, double cap) {
        BatteryProfile p = BatteryProfile::chemistryDefaults(chem);
        p.name = name; p.cells = cells; p.capacityMah = cap;
        return p;
    };
    return {
        make("LiPo 1S 1000mAh", "LiPo", 1, 1000),
        make("LiPo 2S 2200mAh", "LiPo", 2, 2200),
        make("LiPo 3S 5000mAh", "LiPo", 3, 5000),
        make("LiPo 4S 5000mAh", "LiPo", 4, 5000),
        make("LiFe 4S 2000mAh", "LiFe", 4, 2000),
        make("Pb 12V 7Ah",      "Pb",   6, 7000),
        make("NiCd 6S 2000mAh", "NiCd", 6, 2000),
        make("NiMH 8S 2500mAh", "NiMH", 8, 2500),
    };
}

QList<BatteryProfile> ProfileStore::loadProfiles() {
    QFile f(profilesFilePath());
    if (!f.open(QIODevice::ReadOnly)) return defaultProfiles();
    QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isArray()) return defaultProfiles();
    QList<BatteryProfile> list;
    for (const QJsonValue& v : doc.array())
        list << BatteryProfile::fromJson(v.toObject());
    return list.isEmpty() ? defaultProfiles() : list;
}

void ProfileStore::saveProfiles(const QList<BatteryProfile>& profiles) {
    QJsonArray arr;
    for (const auto& p : profiles) arr << p.toJson();
    QFile f(profilesFilePath());
    if (f.open(QIODevice::WriteOnly))
        f.write(QJsonDocument(arr).toJson());
}
