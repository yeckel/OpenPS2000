// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#include "SequenceProfile.h"
#include "XlsxWriter.h"
#include "OdsWriter.h"
#include "ZipReader.h"
#include <QXmlStreamReader>
#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QUrl>
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

// Replace an existing profile with the same name, or append as new.
static void upsertProfile(QList<SequenceProfile>& list, const SequenceProfile& p)
{
    for (int i = 0; i < list.size(); ++i) {
        if (list[i].name == p.name) { list[i] = p; return; }
    }
    list << p;
}

void SequenceStore::load() {
    QFile f(filePath());
    if (!f.open(QIODevice::ReadOnly)) return;
    QJsonArray arr = QJsonDocument::fromJson(f.readAll()).array();
    for (auto v : arr)
        upsertProfile(m_profiles, SequenceProfile::fromVariant(v.toObject().toVariantMap()));
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

// ── CSV import / export ───────────────────────────────────────────────────────
QString SequenceStore::toCsv(int index) const {
    if (index < 0 || index >= m_profiles.size()) return {};
    QStringList lines;
    lines << "voltage,current,holdMs,ramp,rampMs";
    for (auto& s : m_profiles[index].steps)
        lines << QString("%1,%2,%3,%4,%5")
                 .arg(s.voltage, 0, 'f', 3)
                 .arg(s.current, 0, 'f', 3)
                 .arg(s.holdMs)
                 .arg(s.ramp ? 1 : 0)
                 .arg(s.rampMs);
    return lines.join("\n") + "\n";
}

bool SequenceStore::saveToFile(int index, const QString& filePath) const {
    QString csv = toCsv(index);
    if (csv.isEmpty()) return false;
    QString localPath = QUrl(filePath).isLocalFile() ? QUrl(filePath).toLocalFile() : filePath;
    QFile f(localPath);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Text)) return false;
    f.write(csv.toUtf8());
    return true;
}

bool SequenceStore::saveToXlsx(int index, const QString& filePath) const {
    if (index < 0 || index >= m_profiles.size()) return false;
    QString localPath = QUrl(filePath).isLocalFile() ? QUrl(filePath).toLocalFile() : filePath;
    const auto& p = m_profiles[index];

    XlsxWriter xlsx;
    xlsx.setTitle(p.name);
    xlsx.addSheet(p.name.left(31));   // Excel sheet name ≤ 31 chars
    xlsx.setHeaders({"Voltage (V)", "Current (A)", "Hold (ms)", "Ramp", "Ramp ms"});
    for (const auto& s : p.steps)
        xlsx.addRow({s.voltage, s.current, double(s.holdMs), s.ramp ? 1.0 : 0.0, double(s.rampMs)});

    return xlsx.save(localPath);
}

bool SequenceStore::saveToOds(int index, const QString& filePath) const {
    if (index < 0 || index >= m_profiles.size()) return false;
    QString localPath = QUrl(filePath).isLocalFile() ? QUrl(filePath).toLocalFile() : filePath;
    const auto& p = m_profiles[index];

    OdsWriter ods;
    ods.setTitle(p.name);
    ods.addSheet(p.name.left(31));
    ods.setHeaders({"Voltage (V)", "Current (A)", "Hold (ms)", "Ramp", "Ramp ms"});
    for (const auto& s : p.steps)
        ods.addRow({s.voltage, s.current, double(s.holdMs), s.ramp ? 1.0 : 0.0, double(s.rampMs)});

    return ods.save(localPath);
}

bool SequenceStore::loadFromFile(const QString& filePath) {
    m_importError.clear();
    QString localPath = QUrl(filePath).isLocalFile() ? QUrl(filePath).toLocalFile() : filePath;
    QFile f(localPath);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        m_importError = tr("Cannot open file: %1").arg(f.errorString()); return false;
    }
    QString name = QFileInfo(localPath).baseName();
    QStringList lines = QString::fromUtf8(f.readAll()).split('\n', Qt::SkipEmptyParts);
    if (lines.size() < 2) { m_importError = tr("File is empty or has no data rows."); return false; }

    SequenceProfile p;
    p.name = name;
    for (int i = 1; i < lines.size(); ++i) {
        QStringList c = lines[i].split(',');
        if (c.size() < 5) continue;
        SequenceStep s;
        s.voltage = c[0].trimmed().toDouble();
        s.current = c[1].trimmed().toDouble();
        s.holdMs  = c[2].trimmed().toInt();
        s.ramp    = c[3].trimmed().toInt() != 0;
        s.rampMs  = c[4].trimmed().toInt();
        p.steps << s;
    }
    if (p.steps.isEmpty()) { m_importError = tr("No valid rows found. Expected columns: Voltage,Current,Hold ms,Ramp,Ramp ms"); return false; }
    upsertProfile(m_profiles, p);
    save();
    emit profilesChanged();
    return true;
}

// ── XLSX import ───────────────────────────────────────────────────────────────
// Reads the first worksheet from a .xlsx file. Both our own exports (method 0)
// and files from Excel/LibreOffice (method 8 deflate) are supported.
// Column order must match what we export: V, I, Hold, Ramp, RampMs.
bool SequenceStore::loadFromXlsx(const QString& filePath)
{
    m_importError.clear();
    QString localPath = QUrl(filePath).isLocalFile() ? QUrl(filePath).toLocalFile() : filePath;
    ZipReader zip;
    if (!zip.open(localPath)) {
        m_importError = tr("Cannot read XLSX: %1").arg(zip.lastError()); return false;
    }

    // Build shared strings table
    QStringList sharedStrings;
    if (zip.hasFile("xl/sharedStrings.xml")) {
        QXmlStreamReader x(zip.fileData("xl/sharedStrings.xml"));
        QString cur;
        while (!x.atEnd()) {
            x.readNext();
            if (x.isStartElement() && x.name() == QLatin1String("t"))
                cur += x.readElementText();
            else if (x.isStartElement() && x.name() == QLatin1String("si"))
                cur.clear();
            else if (x.isEndElement() && x.name() == QLatin1String("si"))
                sharedStrings << cur;
        }
    }

    // Find first sheet file
    QString sheetPath = "xl/worksheets/sheet1.xml";
    if (!zip.hasFile(sheetPath)) {
        for (const auto& n : zip.fileNames())
            if (n.startsWith("xl/worksheets/") && n.endsWith(".xml"))
                { sheetPath = n; break; }
    }
    if (!zip.hasFile(sheetPath)) {
        m_importError = tr("No worksheet found in XLSX file."); return false;
    }

    QXmlStreamReader x(zip.fileData(sheetPath));
    QString name = QFileInfo(localPath).baseName();
    SequenceProfile p; p.name = name;
    int rowNum = 0;
    QList<double> rowVals;
    QString cellType;

    while (!x.atEnd()) {
        x.readNext();
        if (x.isStartElement()) {
            if (x.name() == QLatin1String("row")) {
                rowNum = x.attributes().value("r").toInt();
                rowVals.clear();
            } else if (x.name() == QLatin1String("c")) {
                cellType = x.attributes().value("t").toString();
            } else if (x.name() == QLatin1String("v") && rowNum > 1) {
                QString val = x.readElementText();
                if (cellType == "s") {
                    int idx = val.toInt();
                    rowVals << (idx < sharedStrings.size() ? sharedStrings[idx].toDouble() : 0.0);
                } else {
                    rowVals << val.toDouble();
                }
                cellType.clear();
            }
        } else if (x.isEndElement() && x.name() == QLatin1String("row") && rowNum > 1) {
            if (rowVals.size() >= 5) {
                SequenceStep s;
                s.voltage = rowVals[0]; s.current = rowVals[1];
                s.holdMs  = static_cast<int>(rowVals[2]);
                s.ramp    = rowVals[3] != 0.0;
                s.rampMs  = static_cast<int>(rowVals[4]);
                p.steps << s;
            }
        }
    }
    if (p.steps.isEmpty()) {
        m_importError = tr("No data rows found in XLSX. Expected columns: Voltage (V), Current (A), Hold (ms), Ramp (0/1), Ramp ms");
        return false;
    }
    upsertProfile(m_profiles, p);
    save();
    emit profilesChanged();
    return true;
}

// ── ODS import ────────────────────────────────────────────────────────────────
// Reads the first table from a .ods file. Both stored (our exports) and
// deflate-compressed (LibreOffice) archives are supported.
bool SequenceStore::loadFromOds(const QString& filePath)
{
    m_importError.clear();
    QString localPath = QUrl(filePath).isLocalFile() ? QUrl(filePath).toLocalFile() : filePath;
    ZipReader zip;
    if (!zip.open(localPath)) {
        m_importError = tr("Cannot read ODS: %1").arg(zip.lastError()); return false;
    }
    if (!zip.hasFile("content.xml")) {
        m_importError = tr("Not a valid ODS file (missing content.xml)."); return false;
    }

    QXmlStreamReader x(zip.fileData("content.xml"));
    QString name = QFileInfo(localPath).baseName();
    SequenceProfile p; p.name = name;
    int rowNum = 0;
    QList<double> rowVals;
    bool inTable = false;

    while (!x.atEnd()) {
        x.readNext();
        if (x.isStartElement()) {
            const auto ln = x.name();
            if (ln == QLatin1String("table") && !inTable)
                inTable = true;
            else if (ln == QLatin1String("table-row") && inTable) {
                ++rowNum; rowVals.clear();
            } else if (ln == QLatin1String("table-cell") && rowNum > 1 && inTable) {
                QString vtype = x.attributes().value("value-type").toString();
                if (vtype == "float") {
                    rowVals << x.attributes().value("value").toDouble();
                } else if (vtype.isEmpty()) {
                    int repeat = x.attributes().value("number-columns-repeated").toInt();
                    if (repeat < 1) repeat = 1;
                    for (int i = 0; i < repeat && rowVals.size() < 5; ++i)
                        rowVals << 0.0;
                }
            }
        } else if (x.isEndElement()) {
            const auto ln = x.name();
            if (ln == QLatin1String("table-row") && rowNum > 1 && inTable) {
                if (rowVals.size() >= 5) {
                    SequenceStep s;
                    s.voltage = rowVals[0]; s.current = rowVals[1];
                    s.holdMs  = static_cast<int>(rowVals[2]);
                    s.ramp    = rowVals[3] != 0.0;
                    s.rampMs  = static_cast<int>(rowVals[4]);
                    p.steps << s;
                }
            } else if (ln == QLatin1String("table") && inTable) {
                break;
            }
        }
    }
    if (p.steps.isEmpty()) {
        m_importError = tr("No data rows found in ODS. Expected columns: Voltage (V), Current (A), Hold (ms), Ramp (0/1), Ramp ms");
        return false;
    }
    upsertProfile(m_profiles, p);
    save();
    emit profilesChanged();
    return true;
}
