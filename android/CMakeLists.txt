# OpenPS2000 Android
# Qt for Android build — reuses shared C++ sources from ../app/
cmake_minimum_required(VERSION 3.28)
project(openps2000android VERSION 1.0 LANGUAGES CXX Java)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# ── Shared source root ────────────────────────────────────────────────────
set(APP_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../app")

find_package(Qt6 6.7 REQUIRED COMPONENTS
    Core Gui Quick QuickControls2 Qml Network)

qt_standard_project_setup(REQUIRES 6.7)

# ── Sources ───────────────────────────────────────────────────────────────
qt_add_executable(openps2000android
    main.cpp
    AndroidSerialTransport.h
    AndroidSerialTransport.cpp

    # ── Shared protocol / backend layers ──────────────────────────────────
    ${APP_SRC}/AbstractTransport.h
    ${APP_SRC}/PS2000Protocol.h     ${APP_SRC}/PS2000Protocol.cpp
    ${APP_SRC}/DeviceBackend.h      ${APP_SRC}/DeviceBackend.cpp
    ${APP_SRC}/RemoteBackend.h      ${APP_SRC}/RemoteBackend.cpp
    ${APP_SRC}/DataRecord.h

    # ── Shared data model (for measurement history / export) ──────────────
    ${APP_SRC}/ZipWriter.h          ${APP_SRC}/ZipWriter.cpp
    ${APP_SRC}/ZipReader.h          ${APP_SRC}/ZipReader.cpp
    ${APP_SRC}/XlsxWriter.h         ${APP_SRC}/XlsxWriter.cpp
    ${APP_SRC}/OdsWriter.h          ${APP_SRC}/OdsWriter.cpp
)

# DeviceBackend includes SerialTransport — on Android we substitute it via
# the ANDROID_SERIAL_TRANSPORT compile definition so DeviceBackend.cpp uses
# AndroidSerialTransport instead of the desktop QSerialPort version.
target_compile_definitions(openps2000android PRIVATE
    ANDROID_BUILD
)
target_include_directories(openps2000android PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${APP_SRC}
)

qt_add_qml_module(openps2000android
    URI "openps2000android"
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/MonitorTab.qml
        qml/ControlTab.qml
        qml/SettingsTab.qml
        qml/LiveChart.qml
)

# ── Zlib (for XLSX/ODS) ───────────────────────────────────────────────────
find_package(ZLIB QUIET)
if(ZLIB_FOUND)
    target_link_libraries(openps2000android PRIVATE ZLIB::ZLIB)
else()
    find_package(Qt6 REQUIRED COMPONENTS ZlibPrivate)
    target_link_libraries(openps2000android PRIVATE Qt6::ZlibPrivate)
endif()

target_link_libraries(openps2000android PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Qml
    Qt6::Network
)

# ── Android packaging ─────────────────────────────────────────────────────
if(ANDROID)
    set_target_properties(openps2000android PROPERTIES
        QT_ANDROID_PACKAGE_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/android_package"
        QT_ANDROID_TARGET_SDK_VERSION 34
        QT_ANDROID_MIN_SDK_VERSION    26
        QT_ANDROID_VERSION_CODE       1
        QT_ANDROID_VERSION_NAME       "1.0"
    )

    # Java sources must live inside android_package/src/ for androiddeployqt.
    # We copy them at configure time.
    file(COPY "${CMAKE_CURRENT_SOURCE_DIR}/java/"
         DESTINATION "${CMAKE_CURRENT_SOURCE_DIR}/android_package/src")
endif()
