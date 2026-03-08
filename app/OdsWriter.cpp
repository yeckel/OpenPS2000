// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#include "OdsWriter.h"
#include <QXmlStreamWriter>
#include <QDateTime>

// ── Sheet helpers ─────────────────────────────────────────────────────────────
void OdsWriter::addSheet(const QString& name)
{
    Sheet s; s.name = name;
    m_sheets.append(s);
}
void OdsWriter::setHeaders(const QStringList& h)
{
    if (!m_sheets.isEmpty()) m_sheets.last().headers = h;
}
void OdsWriter::addRow(const QList<double>& row)
{
    if (!m_sheets.isEmpty()) m_sheets.last().rows.append(row);
}
void OdsWriter::addSummaryRow(const QString& key, double value)
{
    if (!m_sheets.isEmpty()) m_sheets.last().summaryRows.append({key, value});
}

// ── Cell writers ──────────────────────────────────────────────────────────────
void OdsWriter::writeCell(QXmlStreamWriter& x, const QString& text)
{
    x.writeStartElement("table:table-cell");
    x.writeAttribute("office:value-type", "string");
    x.writeStartElement("text:p");
    x.writeCharacters(text);
    x.writeEndElement(); // text:p
    x.writeEndElement(); // table:table-cell
}
void OdsWriter::writeCell(QXmlStreamWriter& x, double value)
{
    x.writeStartElement("table:table-cell");
    x.writeAttribute("office:value-type", "float");
    x.writeAttribute("office:value", QString::number(value, 'g', 10));
    x.writeStartElement("text:p");
    x.writeCharacters(QString::number(value, 'g', 10));
    x.writeEndElement(); // text:p
    x.writeEndElement(); // table:table-cell
}

// ── content.xml ───────────────────────────────────────────────────────────────
QByteArray OdsWriter::buildContent() const
{
    QByteArray buf;
    QXmlStreamWriter x(&buf);
    x.setAutoFormatting(true);
    x.writeStartDocument();

    x.writeStartElement("office:document-content");
    x.writeDefaultNamespace("urn:oasis:names:tc:opendocument:xmlns:office:1.0");
    x.writeNamespace("urn:oasis:names:tc:opendocument:xmlns:table:1.0",   "table");
    x.writeNamespace("urn:oasis:names:tc:opendocument:xmlns:text:1.0",    "text");
    x.writeNamespace("urn:oasis:names:tc:opendocument:xmlns:style:1.0",   "style");
    x.writeNamespace("urn:oasis:names:tc:opendocument:xmlns:number:1.0",  "number");
    x.writeAttribute("office:version", "1.3");

    x.writeStartElement("office:body");
    x.writeStartElement("office:spreadsheet");

    for (const auto& sheet : m_sheets) {
        x.writeStartElement("table:table");
        x.writeAttribute("table:name", sheet.name);

        // Header row
        if (!sheet.headers.isEmpty()) {
            x.writeStartElement("table:table-row");
            for (const auto& h : sheet.headers)
                writeCell(x, h);
            x.writeEndElement(); // table:table-row
        }

        // Data rows
        for (const auto& row : sheet.rows) {
            x.writeStartElement("table:table-row");
            for (double v : row)
                writeCell(x, v);
            x.writeEndElement(); // table:table-row
        }

        // Summary rows (key / value pairs)
        if (!sheet.summaryRows.isEmpty()) {
            // Blank separator
            x.writeEmptyElement("table:table-row");
            for (const auto& sr : sheet.summaryRows) {
                x.writeStartElement("table:table-row");
                writeCell(x, sr.first);
                writeCell(x, sr.second);
                x.writeEndElement(); // table:table-row
            }
        }

        x.writeEndElement(); // table:table
    }

    x.writeEndElement(); // office:spreadsheet
    x.writeEndElement(); // office:body
    x.writeEndElement(); // office:document-content
    x.writeEndDocument();
    return buf;
}

// ── Static XML fragments ──────────────────────────────────────────────────────
QByteArray OdsWriter::buildMimeType()
{
    return QByteArray("application/vnd.oasis.opendocument.spreadsheet");
}

QByteArray OdsWriter::buildManifest(const QList<Sheet>& /*sheets*/)
{
    QByteArray buf;
    QXmlStreamWriter x(&buf);
    x.setAutoFormatting(true);
    x.writeStartDocument();
    x.writeStartElement("manifest:manifest");
    x.writeDefaultNamespace("urn:oasis:names:tc:opendocument:xmlns:manifest:1.0");
    x.writeAttribute("manifest:version", "1.3");

    auto fe = [&](const QString& path, const QString& type) {
        x.writeEmptyElement("manifest:file-entry");
        x.writeAttribute("manifest:full-path",  path);
        x.writeAttribute("manifest:media-type", type);
    };
    fe("/",           "application/vnd.oasis.opendocument.spreadsheet");
    fe("content.xml", "text/xml");
    fe("styles.xml",  "text/xml");
    fe("meta.xml",    "text/xml");

    x.writeEndElement();
    x.writeEndDocument();
    return buf;
}

QByteArray OdsWriter::buildMeta(const QString& title)
{
    QByteArray buf;
    QXmlStreamWriter x(&buf);
    x.setAutoFormatting(true);
    x.writeStartDocument();
    x.writeStartElement("office:document-meta");
    x.writeDefaultNamespace("urn:oasis:names:tc:opendocument:xmlns:office:1.0");
    x.writeNamespace("urn:oasis:names:tc:opendocument:xmlns:meta:1.0", "meta");
    x.writeNamespace("http://purl.org/dc/elements/1.1/",               "dc");
    x.writeAttribute("office:version", "1.3");

    x.writeStartElement("office:meta");
    x.writeTextElement("dc:title",  title);
    x.writeTextElement("meta:creation-date",
                       QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    x.writeTextElement("meta:generator", "OpenPS2000");
    x.writeEndElement(); // office:meta
    x.writeEndElement(); // office:document-meta
    x.writeEndDocument();
    return buf;
}

QByteArray OdsWriter::buildStyles()
{
    QByteArray buf;
    QXmlStreamWriter x(&buf);
    x.setAutoFormatting(true);
    x.writeStartDocument();
    x.writeStartElement("office:document-styles");
    x.writeDefaultNamespace("urn:oasis:names:tc:opendocument:xmlns:office:1.0");
    x.writeAttribute("office:version", "1.3");
    x.writeEmptyElement("office:styles");
    x.writeEmptyElement("office:automatic-styles");
    x.writeEmptyElement("office:master-styles");
    x.writeEndElement(); // office:document-styles
    x.writeEndDocument();
    return buf;
}

// ── save ──────────────────────────────────────────────────────────────────────
bool OdsWriter::save(const QString& path)
{
    if (m_sheets.isEmpty()) { m_error = "No sheets"; return false; }

    ZipWriter zip;
    // mimetype MUST be first and uncompressed — ZipWriter uses method=0 (stored) for all
    zip.addFile("mimetype",          buildMimeType());
    zip.addFile("META-INF/manifest.xml", buildManifest(m_sheets));
    zip.addFile("meta.xml",          buildMeta(m_title));
    zip.addFile("styles.xml",        buildStyles());
    zip.addFile("content.xml",       buildContent());

    if (!zip.save(path)) { m_error = "Failed to write " + path; return false; }
    return true;
}
