// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
// Adapted from OpenFNB58 (same author)
#pragma once
#include "ZipWriter.h"
#include "DataRecord.h"
#include <QString>
#include <QStringList>
#include <QList>

class XlsxWriter
{
public:
    XlsxWriter() = default;
    void setTitle(const QString& title)    { m_title = title; }
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
        bool isSummary = false;
    };
    QString        m_title;
    QList<Sheet>   m_sheets;
    QString        m_error;
    static QByteArray buildContentTypes(const QList<Sheet>& sheets);
    static QByteArray buildRels();
    static QByteArray buildWorkbook(const QList<Sheet>& sheets);
    static QByteArray buildWorkbookRels(const QList<Sheet>& sheets);
    static QByteArray buildStyles();
    static QByteArray buildDataSheet(const Sheet& s);
    static QByteArray buildSummarySheet(const Sheet& s);
    static QString cellRef(int col, int row);
};
