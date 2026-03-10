// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#pragma once
#include <QObject>
#include <QString>

// Posts and cancels Android system notifications for PSU protection alarms.
// Exposed to QML as the "alarmNotifier" context property.
class AlarmNotifier : public QObject
{
    Q_OBJECT
public:
    explicit AlarmNotifier(QObject* parent = nullptr);

    // Request POST_NOTIFICATIONS permission (Android 13+ / API 33+).
    // Call once on first run.
    Q_INVOKABLE void requestPermission();

    // Post an ongoing system notification visible in the status bar.
    Q_INVOKABLE void showAlarm(const QString &title, const QString &text);

    // Cancel the notification (call when alarm clears or user dismisses).
    Q_INVOKABLE void cancelAlarm();

private:
    void ensureChannel();
    bool m_channelReady = false;
};
