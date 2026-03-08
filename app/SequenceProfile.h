// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#pragma once
#include <QObject>
#include <QList>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <qqmlregistration.h>

// ── SequenceStep ─────────────────────────────────────────────────────────────
struct SequenceStep {
    double voltage = 5.0;
    double current = 1.0;
    int    holdMs  = 5000;   // hold time after reaching target
    bool   ramp    = false;  // if true, linearly interpolate from previous value
    int    rampMs  = 1000;   // ramp duration (ignored when ramp==false)
};

// ── SequenceProfile ──────────────────────────────────────────────────────────
struct SequenceProfile {
    QString            name;
    QList<SequenceStep> steps;

    int totalMs() const;
    QVariantMap toVariant() const;
    static SequenceProfile fromVariant(const QVariantMap& m);
};

// ── SequenceStore ─────────────────────────────────────────────────────────────
class SequenceStore : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("")

    Q_PROPERTY(QStringList names READ names NOTIFY profilesChanged)
    Q_PROPERTY(int count READ count NOTIFY profilesChanged)

public:
    explicit SequenceStore(QObject* parent = nullptr);

    QStringList names() const;
    int count() const { return m_profiles.size(); }

    Q_INVOKABLE QVariantMap getProfile(int index) const;
    Q_INVOKABLE void saveProfile(const QVariantMap& data, int index); // -1 = new
    Q_INVOKABLE void deleteProfile(int index);
    Q_INVOKABLE void moveStep(int profileIndex, int from, int to);
    Q_INVOKABLE QVariantMap defaultStep() const;

    // CSV / XLSX / ODS import & export
    Q_INVOKABLE QString toCsv(int index) const;
    Q_INVOKABLE bool saveToFile(int index, const QString& filePath) const;   // .csv
    Q_INVOKABLE bool saveToXlsx(int index, const QString& filePath) const;   // .xlsx
    Q_INVOKABLE bool saveToOds(int index, const QString& filePath) const;    // .ods
    Q_INVOKABLE bool loadFromFile(const QString& filePath);                  // .csv
    Q_INVOKABLE bool loadFromXlsx(const QString& filePath);                  // .xlsx
    Q_INVOKABLE bool loadFromOds(const QString& filePath);                   // .ods

    // Last error from any loadFrom* call — check after a false return
    Q_INVOKABLE QString lastImportError() const { return m_importError; }

    const SequenceProfile& profile(int index) const { return m_profiles.at(index); }

signals:
    void profilesChanged();

private:
    void load();
    void save() const;
    QString filePath() const;
    void addDefaults();

    QList<SequenceProfile> m_profiles;
    mutable QString m_importError;
};
