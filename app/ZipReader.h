// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#pragma once
#include <QString>
#include <QByteArray>
#include <QMap>

// Reads ZIP archives (method 0 = stored, method 8 = deflate via zlib).
// Loads the entire archive into memory on open() — suitable for the small
// spreadsheet files (XLSX / ODS) handled by OpenPS2000.
class ZipReader
{
public:
    bool open(const QString& path);
    bool hasFile(const QString& name) const { return m_files.contains(name); }
    QByteArray fileData(const QString& name) const { return m_files.value(name); }
    QStringList fileNames() const { return QStringList(m_files.keys()); }
    QString lastError() const { return m_error; }

private:
    QMap<QString, QByteArray> m_files;
    QString m_error;
};
