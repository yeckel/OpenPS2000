// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QIcon>
#include "DeviceBackend.h"

int main(int argc, char* argv[])
{
    qputenv("QT_QUICK_CONTROLS_STYLE", "Material");

    QApplication app(argc, argv);
    app.setApplicationName("OpenPS2000");
    app.setOrganizationName("OpenPS2000");
    app.setApplicationVersion("1.0");

    DeviceBackend backend;

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("backend", &backend);

    engine.loadFromModule("openps2000app", "Main");

    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
