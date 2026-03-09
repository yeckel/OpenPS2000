// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// TrayManager.cpp — System tray icon manager.
#include "TrayManager.h"

#include <QSystemTrayIcon>
#include <QMenu>
#include <QAction>
#include <QWindow>
#include <QSettings>
#include <QApplication>
#include <QIcon>

TrayManager::TrayManager(QObject* parent)
    : QObject(parent)
{
    QSettings s;
    m_minimizeToTray = s.value("ui/minimizeToTray", false).toBool();
}

TrayManager::~TrayManager()
{
    hideTray();
}

void TrayManager::setMinimizeToTray(bool value)
{
    if (m_minimizeToTray == value) return;
    m_minimizeToTray = value;
    QSettings s;
    s.setValue("ui/minimizeToTray", value);
    emit minimizeToTrayChanged(value);
}

void TrayManager::setWindow(QWindow* window)
{
    m_window = window;
}

void TrayManager::setup(const QString& iconPath)
{
    if (m_tray) return;

    m_tray = new QSystemTrayIcon(QIcon(iconPath), this);

    auto* menu   = new QMenu();
    auto* show   = menu->addAction(tr("Show OpenPS2000"));
    auto* quit   = menu->addAction(tr("Quit"));

    connect(show, &QAction::triggered, this, &TrayManager::showRequested);
    connect(quit, &QAction::triggered, qApp, &QApplication::quit);
    connect(m_tray, &QSystemTrayIcon::activated, this,
            [this](QSystemTrayIcon::ActivationReason reason) {
                if (reason == QSystemTrayIcon::DoubleClick)
                    emit showRequested();
            });

    m_tray->setContextMenu(menu);
}

void TrayManager::showTray()
{
    if (m_tray) m_tray->show();
}

void TrayManager::hideTray()
{
    if (m_tray) m_tray->hide();
}

void TrayManager::hideToTray()
{
    if (m_window) m_window->hide();
    showTray();
}

void TrayManager::showWindow()
{
    if (m_window) {
        m_window->show();
        m_window->raise();
        m_window->requestActivate();
    }
    hideTray();
}
