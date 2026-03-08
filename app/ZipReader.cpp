// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#include "ZipReader.h"
#include <QFile>
#include <QHash>
#include <zlib.h>

static inline quint16 readLE16(const char* p)
{
    return static_cast<quint8>(p[0]) | (static_cast<quint8>(p[1]) << 8);
}
static inline quint32 readLE32(const char* p)
{
    return static_cast<quint8>(p[0]) | (static_cast<quint8>(p[1]) << 8)
         | (static_cast<quint8>(p[2]) << 16) | (static_cast<quint8>(p[3]) << 24);
}

// Decompress a raw deflate stream (ZIP method 8) using zlib.
// The function is named distinctly to avoid shadowing the zlib inflate() symbol.
static bool decompressDeflate(const QByteArray& compressed, QByteArray& out, quint32 uncompressedSize)
{
    out.resize(static_cast<int>(uncompressedSize));
    z_stream zs{};
    zs.next_in   = reinterpret_cast<Bytef*>(const_cast<char*>(compressed.data()));
    zs.avail_in  = static_cast<uInt>(compressed.size());
    zs.next_out  = reinterpret_cast<Bytef*>(out.data());
    zs.avail_out = static_cast<uInt>(out.size());

    // -MAX_WBITS → raw deflate (no zlib/gzip wrapper)
    if (inflateInit2(&zs, -MAX_WBITS) != Z_OK) return false;
    int ret = inflate(&zs, Z_FINISH);
    inflateEnd(&zs);
    return ret == Z_STREAM_END;
}

struct ZipCdEntry {
    quint16 method;
    quint32 compressedSz;
    quint32 uncompressedSz;
    quint32 localOffset;
};

// Locate the End-of-Central-Directory record (EOCD) and return its offset.
// Returns -1 if not found.
static int findEOCD(const char* base, int sz)
{
    // EOCD signature: PK\x05\x06 = 0x06054b50, minimum size 22 bytes.
    // Search backwards from end (comment may add up to 65535 bytes).
    for (int i = sz - 22; i >= 0; --i) {
        if (readLE32(base + i) == 0x06054b50u)
            return i;
    }
    return -1;
}

bool ZipReader::open(const QString& path)
{
    m_files.clear();
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) { m_error = f.errorString(); return false; }
    const QByteArray data = f.readAll();
    const char* base = data.constData();
    const int   sz   = data.size();

    // --- Step 1: Read the Central Directory for correct sizes ---
    // When the data descriptor flag (bit 3) is set in the local header,
    // compressed/uncompressed sizes in the local header are 0; the central
    // directory always has the correct values.

    QHash<QString, ZipCdEntry> cdMap;

    int eocdOff = findEOCD(base, sz);
    if (eocdOff >= 0 && eocdOff + 22 <= sz) {
        quint32 cdOffset = readLE32(base + eocdOff + 16);
        quint16 cdCount  = readLE16(base + eocdOff + 10);
        int cdPos = static_cast<int>(cdOffset);
        for (int i = 0; i < cdCount && cdPos + 46 <= sz; ++i) {
            if (readLE32(base + cdPos) != 0x02014b50u) break; // central dir sig
            quint16 method         = readLE16(base + cdPos + 10);
            quint32 compressedSz   = readLE32(base + cdPos + 20);
            quint32 uncompressedSz = readLE32(base + cdPos + 24);
            quint16 nameLen        = readLE16(base + cdPos + 28);
            quint16 extraLen       = readLE16(base + cdPos + 30);
            quint16 commentLen     = readLE16(base + cdPos + 32);
            quint32 localOffset    = readLE32(base + cdPos + 42);
            QString name = QString::fromUtf8(base + cdPos + 46, nameLen);
            cdMap.insert(name, ZipCdEntry{method, compressedSz, uncompressedSz, localOffset});
            cdPos += 46 + nameLen + extraLen + commentLen;
        }
    }

    // --- Step 2: For each entry, jump to local header and read data ---
    for (auto it = cdMap.cbegin(); it != cdMap.cend(); ++it) {
        const QString&    name = it.key();
        const ZipCdEntry& cd   = it.value();

        int lhPos = static_cast<int>(cd.localOffset);
        if (lhPos + 30 > sz) continue;
        if (readLE32(base + lhPos) != 0x04034b50u) continue;

        quint16 lhNameLen  = readLE16(base + lhPos + 26);
        quint16 lhExtraLen = readLE16(base + lhPos + 28);
        int dataStart = lhPos + 30 + lhNameLen + lhExtraLen;
        if (dataStart + static_cast<int>(cd.compressedSz) > sz) continue;

        QByteArray entry;
        if (cd.method == 0) {
            entry = QByteArray(base + dataStart, static_cast<int>(cd.compressedSz));
        } else if (cd.method == 8) {
            QByteArray comp(base + dataStart, static_cast<int>(cd.compressedSz));
            if (!decompressDeflate(comp, entry, cd.uncompressedSz)) {
                m_error = "Inflate failed for: " + name;
                continue;
            }
        } else {
            m_error = "Unsupported compression method " + QString::number(cd.method) + " in: " + name;
            continue;
        }
        m_files.insert(name, entry);
    }
    return !m_files.isEmpty();
}
