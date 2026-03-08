// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
// Adapted from OpenFNB58 (same author)
#pragma once
#include <QString>
#include <QByteArray>
#include <QList>

class ZipWriter
{
public:
    ZipWriter() = default;
    void addFile(const QString& name, const QByteArray& data);
    bool save(const QString& path);
private:
    struct Entry {
        QString    name;
        QByteArray data;
        quint32    crc32  = 0;
        quint32    offset = 0;
    };
    QList<Entry> m_entries;
    static quint32 computeCrc32(const QByteArray& data);
    static void writeLE16(QByteArray& buf, quint16 v);
    static void writeLE32(QByteArray& buf, quint32 v);
};
