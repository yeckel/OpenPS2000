// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// TrayManager.h — System tray icon manager.
#pragma once

#include <QObject>
#include <QString>

class QSystemTrayIcon;
class QWindow;

class TrayManager : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool minimizeToTray READ minimizeToTray WRITE setMinimizeToTray NOTIFY minimizeToTrayChanged)

public:
    explicit TrayManager(QObject* parent = nullptr);
    ~TrayManager() override;

    bool minimizeToTray() const { return m_minimizeToTray; }
    void setMinimizeToTray(bool value);
    void setWindow(QWindow* window);

public slots:
    void setup(const QString& iconPath);
    void showTray();
    void hideTray();
    Q_INVOKABLE void hideToTray();
    Q_INVOKABLE void showWindow();

signals:
    void showRequested();
    void minimizeToTrayChanged(bool minimizeToTray);

private:
    QSystemTrayIcon* m_tray   = nullptr;
    QWindow*         m_window = nullptr;
    bool             m_minimizeToTray = false;
};
