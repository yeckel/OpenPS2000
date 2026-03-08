// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#pragma once
#include "ZipWriter.h"
#include <QString>
#include <QStringList>
#include <QList>
#include <QXmlStreamWriter>

// Writes an OpenDocument Spreadsheet (.ods) file.
// Same API as XlsxWriter — swap the class name to switch format.
class OdsWriter
{
public:
    OdsWriter() = default;
    void setTitle(const QString& title)     { m_title = title; }
    void addSheet(const QString& name);
    void setHeaders(const QStringList& headers);
    void addRow(const QList<double>& values);
    void addSummaryRow(const QString& key, double value);
    bool save(const QString& path);
    QString lastError() const { return m_error; }

private:
    struct Sheet {
        QString name;
        QStringList headers;
        QList<QList<double>> rows;
        QList<QPair<QString,double>> summaryRows;
    };
    QString      m_title;
    QList<Sheet> m_sheets;
    QString      m_error;

    static QByteArray buildMimeType();
    static QByteArray buildManifest(const QList<Sheet>& sheets);
    static QByteArray buildMeta(const QString& title);
    static QByteArray buildStyles();
    QByteArray buildContent() const;
    static void writeCell(QXmlStreamWriter& x, const QString& text);
    static void writeCell(QXmlStreamWriter& x, double value);
};
