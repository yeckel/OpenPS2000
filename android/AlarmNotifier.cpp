// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#include "AlarmNotifier.h"

#include <QCoreApplication>
#include <QJniObject>
#include <QJniEnvironment>

static constexpr int  NOTIF_ID    = 1001;
static constexpr char CHANNEL_ID[] = "openps2000_alarms";

AlarmNotifier::AlarmNotifier(QObject* parent) : QObject(parent) {}

void AlarmNotifier::requestPermission()
{
    // POST_NOTIFICATIONS requires explicit runtime grant on Android 13+ (API 33+).
    // We request it via the Activity obtained from Qt's native bridge.
    const jint sdk = QJniObject::getStaticField<jint>("android/os/Build$VERSION", "SDK_INT");
    if (sdk < 33) return;  // auto-granted on Android ≤ 12

    const QString permName = QStringLiteral("android.permission.POST_NOTIFICATIONS");

    // Retrieve the current Activity via Qt's JNI bridge
    QJniObject activity = QJniObject::callStaticObjectMethod(
        "org/qtproject/qt/android/QtNative",
        "activity",
        "()Landroid/app/Activity;");
    if (!activity.isValid()) return;

    // Check if already granted (PackageManager.PERMISSION_GRANTED == 0)
    QJniObject permStr = QJniObject::fromString(permName);
    jint status = activity.callMethod<jint>(
        "checkSelfPermission", "(Ljava/lang/String;)I",
        permStr.object<jstring>());
    if (status == 0) return;

    // Build a String[] and call Activity.requestPermissions()
    QJniEnvironment env;
    jclass stringClass = env.findClass("java/lang/String");
    jobjectArray arr = env->NewObjectArray(1, stringClass, nullptr);
    env->SetObjectArrayElement(arr, 0, permStr.object<jstring>());
    activity.callMethod<void>("requestPermissions", "([Ljava/lang/String;I)V",
                              arr, jint(1001));
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

    // Tap on the notification → bring the app to the foreground
    {
        QJniObject packageName = context.callObjectMethod(
            "getPackageName", "()Ljava/lang/String;");
        QJniObject pm = context.callObjectMethod(
            "getPackageManager", "()Landroid/content/pm/PackageManager;");
        QJniObject launchIntent = pm.callObjectMethod(
            "getLaunchIntentForPackage",
            "(Ljava/lang/String;)Landroid/content/Intent;",
            packageName.object<jstring>());
        if (launchIntent.isValid()) {
            // FLAG_ACTIVITY_SINGLE_TOP: reuse existing task instead of spawning new
            launchIntent.callObjectMethod("addFlags", "(I)Landroid/content/Intent;",
                                          jint(0x20000000));
            // FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE
            QJniObject pi = QJniObject::callStaticObjectMethod(
                "android/app/PendingIntent",
                "getActivity",
                "(Landroid/content/Context;ILandroid/content/Intent;I)Landroid/app/PendingIntent;",
                context.object(), jint(0), launchIntent.object(),
                jint(0x08000000 | 0x04000000));
            if (pi.isValid())
                builder.callObjectMethod("setContentIntent",
                    "(Landroid/app/PendingIntent;)Landroid/app/Notification$Builder;",
                    pi.object());
        }
    }

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
