// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#include "AlarmNotifier.h"

#include <QCoreApplication>
#include <QJniObject>
#include <QJniEnvironment>
#include <QPermission>

static constexpr int  NOTIF_ID    = 1001;
static constexpr char CHANNEL_ID[] = "openps2000_alarms";

AlarmNotifier::AlarmNotifier(QObject* parent) : QObject(parent) {}

void AlarmNotifier::requestPermission()
{
    // POST_NOTIFICATIONS was added in Android 13 (API 33).
    // On older releases the permission is implicitly granted.
    QNotificationPermission perm;
    qApp->requestPermission(perm, [](const QPermission &) {});
}

void AlarmNotifier::ensureChannel()
{
    if (m_channelReady) return;

    QJniObject context = QNativeInterface::QAndroidApplication::context();
    if (!context.isValid()) return;

    QJniObject channelId   = QJniObject::fromString(QLatin1String(CHANNEL_ID));
    QJniObject channelName = QJniObject::fromString(QStringLiteral("PSU Protection Alarms"));

    // NotificationManager.IMPORTANCE_HIGH = 4
    QJniObject channel(
        "android/app/NotificationChannel",
        "(Ljava/lang/String;Ljava/lang/CharSequence;I)V",
        channelId.object<jstring>(),
        channelName.object<jstring>(),
        jint(4));

    if (!channel.isValid()) return;

    QJniObject nm = context.callObjectMethod(
        "getSystemService",
        "(Ljava/lang/String;)Ljava/lang/Object;",
        QJniObject::fromString(QStringLiteral("notification")).object<jstring>());

    if (nm.isValid()) {
        nm.callMethod<void>(
            "createNotificationChannel",
            "(Landroid/app/NotificationChannel;)V",
            channel.object());
        m_channelReady = true;
    }
}

void AlarmNotifier::showAlarm(const QString &title, const QString &text)
{
    ensureChannel();

    QJniObject context = QNativeInterface::QAndroidApplication::context();
    if (!context.isValid()) return;

    // Resolve android.R.drawable.ic_dialog_alert at runtime for reliability
    jint iconId = 0x0108008f; // fallback value
    {
        QJniEnvironment env;
        jclass cls = env.findClass("android/R$drawable");
        if (cls) {
            jfieldID fid = env->GetStaticFieldID(cls, "ic_dialog_alert", "I");
            if (fid) iconId = env->GetStaticIntField(cls, fid);
        }
    }

    QJniObject builder(
        "android/app/Notification$Builder",
        "(Landroid/content/Context;Ljava/lang/String;)V",
        context.object(),
        QJniObject::fromString(QLatin1String(CHANNEL_ID)).object<jstring>());

    if (!builder.isValid()) return;

    builder.callObjectMethod("setSmallIcon",
        "(I)Landroid/app/Notification$Builder;", iconId);
    builder.callObjectMethod("setContentTitle",
        "(Ljava/lang/CharSequence;)Landroid/app/Notification$Builder;",
        QJniObject::fromString(title).object<jstring>());
    builder.callObjectMethod("setContentText",
        "(Ljava/lang/CharSequence;)Landroid/app/Notification$Builder;",
        QJniObject::fromString(text).object<jstring>());
    // Ongoing = stays in notification bar until alarm clears
    builder.callObjectMethod("setOngoing",
        "(Z)Landroid/app/Notification$Builder;", static_cast<jboolean>(true));
    builder.callObjectMethod("setAutoCancel",
        "(Z)Landroid/app/Notification$Builder;", static_cast<jboolean>(false));
    // PRIORITY_HIGH = 1
    builder.callObjectMethod("setPriority",
        "(I)Landroid/app/Notification$Builder;", jint(1));

    QJniObject notification = builder.callObjectMethod(
        "build", "()Landroid/app/Notification;");

    QJniObject nm = context.callObjectMethod(
        "getSystemService",
        "(Ljava/lang/String;)Ljava/lang/Object;",
        QJniObject::fromString(QStringLiteral("notification")).object<jstring>());

    if (nm.isValid() && notification.isValid()) {
        nm.callMethod<void>("notify",
            "(ILandroid/app/Notification;)V",
            jint(NOTIF_ID),
            notification.object());
    }
}

void AlarmNotifier::cancelAlarm()
{
    QJniObject context = QNativeInterface::QAndroidApplication::context();
    if (!context.isValid()) return;

    QJniObject nm = context.callObjectMethod(
        "getSystemService",
        "(Ljava/lang/String;)Ljava/lang/Object;",
        QJniObject::fromString(QStringLiteral("notification")).object<jstring>());

    if (nm.isValid())
        nm.callMethod<void>("cancel", "(I)V", jint(NOTIF_ID));
}
