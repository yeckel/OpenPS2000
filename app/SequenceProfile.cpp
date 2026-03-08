// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#include "SequenceProfile.h"
#include <QFile>
#include <QDir>
#include <QStandardPaths>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>

// ── SequenceProfile ──────────────────────────────────────────────────────────
int SequenceProfile::totalMs() const {
    int t = 0;
    for (auto& s : steps) { if (s.ramp) t += s.rampMs; t += s.holdMs; }
    return t;
}

QVariantMap SequenceProfile::toVariant() const {
    QVariantList sl;
    for (auto& s : steps) {
        sl << QVariantMap{{"voltage", s.voltage}, {"current", s.current},
                          {"holdMs",  s.holdMs},  {"ramp",    s.ramp},
                          {"rampMs",  s.rampMs}};
    }
    return {{"name", name}, {"steps", sl}};
}

SequenceProfile SequenceProfile::fromVariant(const QVariantMap& m) {
    SequenceProfile p;
    p.name = m["name"].toString();
    for (auto& sv : m["steps"].toList()) {
        QVariantMap sm = sv.toMap();
        SequenceStep s;
        s.voltage = sm["voltage"].toDouble();
        s.current = sm["current"].toDouble();
        s.holdMs  = sm["holdMs"].toInt();
        s.ramp    = sm["ramp"].toBool();
        s.rampMs  = sm["rampMs"].toInt();
        p.steps << s;
    }
    return p;
}

// ── SequenceStore ─────────────────────────────────────────────────────────────
SequenceStore::SequenceStore(QObject* parent) : QObject(parent) {
    load();
    if (m_profiles.isEmpty()) addDefaults();
}

QStringList SequenceStore::names() const {
    QStringList n;
    for (auto& p : m_profiles) n << p.name;
    return n;
}

QVariantMap SequenceStore::getProfile(int index) const {
    if (index < 0 || index >= m_profiles.size()) return {};
    return m_profiles[index].toVariant();
}

void SequenceStore::saveProfile(const QVariantMap& data, int index) {
    SequenceProfile p = SequenceProfile::fromVariant(data);
    if (index < 0 || index >= m_profiles.size())
        m_profiles << p;
    else
        m_profiles[index] = p;
    save();
    emit profilesChanged();
}

void SequenceStore::deleteProfile(int index) {
    if (index < 0 || index >= m_profiles.size()) return;
    m_profiles.removeAt(index);
    save();
    emit profilesChanged();
}

void SequenceStore::moveStep(int profileIndex, int from, int to) {
    if (profileIndex < 0 || profileIndex >= m_profiles.size()) return;
    auto& steps = m_profiles[profileIndex].steps;
    if (from < 0 || from >= steps.size() || to < 0 || to >= steps.size()) return;
    steps.move(from, to);
    save();
    emit profilesChanged();
}

QVariantMap SequenceStore::defaultStep() const {
    return {{"voltage", 5.0}, {"current", 1.0}, {"holdMs", 5000},
            {"ramp", false}, {"rampMs", 2000}};
}

void SequenceStore::load() {
    QFile f(filePath());
    if (!f.open(QIODevice::ReadOnly)) return;
    QJsonArray arr = QJsonDocument::fromJson(f.readAll()).array();
    for (auto v : arr)
        m_profiles << SequenceProfile::fromVariant(v.toObject().toVariantMap());
}

void SequenceStore::save() const {
    QJsonArray arr;
    for (auto& p : m_profiles)
        arr << QJsonObject::fromVariantMap(p.toVariant());
    QFile f(filePath());
    QDir().mkpath(QFileInfo(f).absolutePath());
    if (f.open(QIODevice::WriteOnly))
        f.write(QJsonDocument(arr).toJson());
}

QString SequenceStore::filePath() const {
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
           + "/sequences.json";
}

void SequenceStore::addDefaults() {
    // Simple 3-step voltage sweep
    {
        SequenceProfile p; p.name = "Voltage Sweep 0→10V";
        p.steps << SequenceStep{0.0,  1.0, 1000, false, 0}
                << SequenceStep{5.0,  1.0, 5000, true,  3000}
                << SequenceStep{10.0, 1.0, 5000, true,  3000}
                << SequenceStep{0.0,  1.0, 2000, true,  3000};
        m_profiles << p;
    }
    // CC-CV style manual
    {
        SequenceProfile p; p.name = "CC then CV";
        p.steps << SequenceStep{12.0, 2.0, 30000, false, 0}   // CC phase 30s
                << SequenceStep{13.8, 0.5,  20000, true, 2000}; // CV phase 20s
        m_profiles << p;
    }
    // Pulse stress test
    {
        SequenceProfile p; p.name = "Stress: 3V / 12V steps";
        p.steps << SequenceStep{3.0,  1.0, 2000, false, 0}
                << SequenceStep{12.0, 1.0, 2000, false, 0}
                << SequenceStep{3.0,  1.0, 2000, false, 0}
                << SequenceStep{12.0, 1.0, 2000, false, 0};
        m_profiles << p;
    }
    save();
    emit profilesChanged();
}
