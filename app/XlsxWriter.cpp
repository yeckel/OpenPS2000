// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP — adapted from OpenFNB58
#include "XlsxWriter.h"
#include <QXmlStreamWriter>
#include <cmath>

void XlsxWriter::addSheet(const QString& name) {
    Sheet s; s.name = name; s.isSummary = !m_sheets.isEmpty();
    m_sheets.append(s);
}
void XlsxWriter::setHeaders(const QStringList& headers) {
    if (!m_sheets.isEmpty()) m_sheets.last().headers = headers;
}
void XlsxWriter::addRow(const QList<double>& values) {
    if (!m_sheets.isEmpty()) m_sheets.last().rows.append(values);
}
void XlsxWriter::addSummaryRow(const QString& key, double value) {
    if (!m_sheets.isEmpty()) m_sheets.last().summaryRows.append({key, value});
}
QString XlsxWriter::cellRef(int col, int row) {
    QString c; int cc = col;
    while (cc > 0) { c.prepend(QChar('A'+(cc-1)%26)); cc=(cc-1)/26; }
    return c + QString::number(row);
}
QByteArray XlsxWriter::buildContentTypes(const QList<Sheet>& sheets) {
    QByteArray buf; QXmlStreamWriter x(&buf); x.setAutoFormatting(true);
    x.writeStartDocument();
    x.writeStartElement("Types");
    x.writeDefaultNamespace("http://schemas.openxmlformats.org/package/2006/content-types");
    x.writeEmptyElement("Default"); x.writeAttribute("Extension","rels");
    x.writeAttribute("ContentType","application/vnd.openxmlformats-package.relationships+xml");
    x.writeEmptyElement("Default"); x.writeAttribute("Extension","xml");
    x.writeAttribute("ContentType","application/xml");
    x.writeEmptyElement("Override"); x.writeAttribute("PartName","/xl/workbook.xml");
    x.writeAttribute("ContentType","application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml");
    x.writeEmptyElement("Override"); x.writeAttribute("PartName","/xl/styles.xml");
    x.writeAttribute("ContentType","application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml");
    for (int i=0;i<sheets.size();++i) {
        x.writeEmptyElement("Override");
        x.writeAttribute("PartName",QString("/xl/worksheets/sheet%1.xml").arg(i+1));
        x.writeAttribute("ContentType","application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml");
    }
    x.writeEndElement(); x.writeEndDocument(); return buf;
}
QByteArray XlsxWriter::buildRels() {
    QByteArray buf; QXmlStreamWriter x(&buf); x.setAutoFormatting(true);
    x.writeStartDocument();
    x.writeStartElement("Relationships");
    x.writeDefaultNamespace("http://schemas.openxmlformats.org/package/2006/relationships");
    x.writeEmptyElement("Relationship"); x.writeAttribute("Id","rId1");
    x.writeAttribute("Type","http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument");
    x.writeAttribute("Target","xl/workbook.xml");
    x.writeEndElement(); x.writeEndDocument(); return buf;
}
QByteArray XlsxWriter::buildWorkbook(const QList<Sheet>& sheets) {
    QByteArray buf; QXmlStreamWriter x(&buf); x.setAutoFormatting(true);
    x.writeStartDocument();
    x.writeStartElement("workbook");
    x.writeDefaultNamespace("http://schemas.openxmlformats.org/spreadsheetml/2006/main");
    x.writeNamespace("http://schemas.openxmlformats.org/officeDocument/2006/relationships","r");
    x.writeStartElement("sheets");
    for (int i=0;i<sheets.size();++i) {
        x.writeEmptyElement("sheet"); x.writeAttribute("name",sheets[i].name);
        x.writeAttribute("sheetId",QString::number(i+1));
        x.writeAttribute("r:id",QString("rId%1").arg(i+1));
    }
    x.writeEndElement(); x.writeEndElement(); x.writeEndDocument(); return buf;
}
QByteArray XlsxWriter::buildWorkbookRels(const QList<Sheet>& sheets) {
    QByteArray buf; QXmlStreamWriter x(&buf); x.setAutoFormatting(true);
    x.writeStartDocument();
    x.writeStartElement("Relationships");
    x.writeDefaultNamespace("http://schemas.openxmlformats.org/package/2006/relationships");
    for (int i=0;i<sheets.size();++i) {
        x.writeEmptyElement("Relationship"); x.writeAttribute("Id",QString("rId%1").arg(i+1));
        x.writeAttribute("Type","http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet");
        x.writeAttribute("Target",QString("worksheets/sheet%1.xml").arg(i+1));
    }
    x.writeEmptyElement("Relationship"); x.writeAttribute("Id","rIdStyles");
    x.writeAttribute("Type","http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles");
    x.writeAttribute("Target","styles.xml");
    x.writeEndElement(); x.writeEndDocument(); return buf;
}
QByteArray XlsxWriter::buildStyles() {
    return QByteArray(R"(<?xml version="1.0" encoding="UTF-8"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><name val="Calibri"/><color rgb="FFFFFFFF"/></font></fonts>
  <fills count="3"><fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="gray125"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FF1F4E79"/></patternFill></fill></fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="3">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
    <xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
  </cellXfs></styleSheet>)");
}
QByteArray XlsxWriter::buildDataSheet(const Sheet& s) {
    QByteArray buf; QXmlStreamWriter x(&buf); x.setAutoFormatting(false);
    x.writeStartDocument();
    x.writeStartElement("worksheet");
    x.writeDefaultNamespace("http://schemas.openxmlformats.org/spreadsheetml/2006/main");
    x.writeStartElement("sheetViews"); x.writeStartElement("sheetView");
    x.writeAttribute("tabSelected","1"); x.writeAttribute("workbookViewId","0");
    x.writeEmptyElement("pane"); x.writeAttribute("ySplit","1");
    x.writeAttribute("topLeftCell","A2"); x.writeAttribute("activePane","bottomLeft");
    x.writeAttribute("state","frozen");
    x.writeEndElement(); x.writeEndElement();
    x.writeStartElement("sheetData");
    if (!s.headers.isEmpty()) {
        x.writeStartElement("row"); x.writeAttribute("r","1");
        for (int c=0;c<s.headers.size();++c) {
            x.writeStartElement("c"); x.writeAttribute("r",cellRef(c+1,1));
            x.writeAttribute("t","inlineStr"); x.writeAttribute("s","1");
            x.writeStartElement("is"); x.writeTextElement("t",s.headers[c]);
            x.writeEndElement(); x.writeEndElement();
        }
        x.writeEndElement();
    }
    for (int ri=0;ri<s.rows.size();++ri) {
        const auto& row=s.rows[ri];
        x.writeStartElement("row"); x.writeAttribute("r",QString::number(ri+2));
        for (int ci=0;ci<row.size();++ci) {
            double v=row[ci]; if (!std::isfinite(v)) continue;
            x.writeStartElement("c"); x.writeAttribute("r",cellRef(ci+1,ri+2));
            x.writeAttribute("s","2");
            x.writeTextElement("v",QString::number(v,'f',6));
            x.writeEndElement();
        }
        x.writeEndElement();
    }
    x.writeEndElement(); x.writeEndElement(); x.writeEndDocument(); return buf;
}
QByteArray XlsxWriter::buildSummarySheet(const Sheet& s) {
    QByteArray buf; QXmlStreamWriter x(&buf); x.setAutoFormatting(false);
    x.writeStartDocument();
    x.writeStartElement("worksheet");
    x.writeDefaultNamespace("http://schemas.openxmlformats.org/spreadsheetml/2006/main");
    x.writeStartElement("sheetData");
    int row=1;
    for (const auto& [key,val]:s.summaryRows) {
        x.writeStartElement("row"); x.writeAttribute("r",QString::number(row));
        x.writeStartElement("c"); x.writeAttribute("r",cellRef(1,row)); x.writeAttribute("t","inlineStr");
        x.writeStartElement("is"); x.writeTextElement("t",key); x.writeEndElement(); x.writeEndElement();
        x.writeStartElement("c"); x.writeAttribute("r",cellRef(2,row)); x.writeAttribute("s","2");
        x.writeTextElement("v",QString::number(val,'g',8)); x.writeEndElement();
        x.writeEndElement(); ++row;
    }
    x.writeEndElement(); x.writeEndElement(); x.writeEndDocument(); return buf;
}
bool XlsxWriter::save(const QString& path) {
    if (m_sheets.isEmpty()) { m_error="No sheets"; return false; }
    ZipWriter zip;
    zip.addFile("[Content_Types].xml", buildContentTypes(m_sheets));
    zip.addFile("_rels/.rels", buildRels());
    zip.addFile("xl/workbook.xml", buildWorkbook(m_sheets));
    zip.addFile("xl/_rels/workbook.xml.rels", buildWorkbookRels(m_sheets));
    zip.addFile("xl/styles.xml", buildStyles());
    for (int i=0;i<m_sheets.size();++i) {
        QByteArray sheet = m_sheets[i].isSummary ? buildSummarySheet(m_sheets[i]) : buildDataSheet(m_sheets[i]);
        zip.addFile(QString("xl/worksheets/sheet%1.xml").arg(i+1), sheet);
    }
    if (!zip.save(path)) { m_error="Cannot write: "+path; return false; }
    return true;
}
