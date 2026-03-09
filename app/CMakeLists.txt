cmake_minimum_required(VERSION 3.28)
project(openps2000app VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

# ── Qt location: prefer /opt/Qt local install if present ──────────────────
foreach(_qt_ver 6.9.2 6.9.1 6.9.0 6.8.3 6.8.2 6.8.1 6.8.0 6.7.3 6.7.2 6.7.0)
    foreach(_suffix gcc_64 macos)
        if(EXISTS "/opt/Qt/${_qt_ver}/${_suffix}" AND NOT DEFINED CMAKE_PREFIX_PATH)
            list(APPEND CMAKE_PREFIX_PATH "/opt/Qt/${_qt_ver}/${_suffix}")
        endif()
    endforeach()
endforeach()

find_package(Qt6 6.7 REQUIRED COMPONENTS
    Core Gui Quick QuickControls2 Qml QuickDialogs2 Widgets SerialPort LabsPlatform Network)

# Optional modules: Mqtt — installed via CI; gracefully absent locally
# (REST server uses QTcpServer which is always available via Qt6::Network)
find_package(Qt6 OPTIONAL_COMPONENTS Mqtt)

# Prefer system zlib; fall back to Qt's bundled copy (always present on all platforms)
find_package(ZLIB QUIET)
if(ZLIB_FOUND)
    set(_zlib_target ZLIB::ZLIB)
else()
    find_package(Qt6 REQUIRED COMPONENTS ZlibPrivate)
    set(_zlib_target Qt6::ZlibPrivate)
    message(STATUS "System zlib not found – using Qt's bundled zlib")
endif()

qt_standard_project_setup(REQUIRES 6.7)

set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")

# ── Sources ────────────────────────────────────────────────────────────────
qt_add_executable(openps2000app
    main.cpp
    PS2000Protocol.h    PS2000Protocol.cpp
    SerialTransport.h   SerialTransport.cpp
    DeviceBackend.h     DeviceBackend.cpp
    DataRecord.h
    ZipWriter.h         ZipWriter.cpp
    ZipReader.h         ZipReader.cpp
    XlsxWriter.h        XlsxWriter.cpp
    OdsWriter.h         OdsWriter.cpp
    BatteryProfile.h    BatteryProfile.cpp
    ChargerEngine.h     ChargerEngine.cpp
    PulseEngine.h       PulseEngine.cpp
    SequenceProfile.h   SequenceProfile.cpp
    SequenceEngine.h    SequenceEngine.cpp
    TrayManager.h       TrayManager.cpp
    RemoteServer.h      RemoteServer.cpp
    MqttClient.h        MqttClient.cpp
    RemoteBackend.h     RemoteBackend.cpp
)

qt_add_qml_module(openps2000app
    URI "openps2000app"
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/LiveChart.qml
        qml/ChargingChart.qml
        qml/ChargerTab.qml
        qml/PulseTab.qml
        qml/PulseChart.qml
        qml/SequenceTab.qml
        qml/SequenceChart.qml
        qml/SequenceEditorDialog.qml
        qml/RemoteSettingsPanel.qml
)

target_link_libraries(openps2000app PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Qml
    Qt6::QuickDialogs2
    Qt6::Widgets
    Qt6::SerialPort
    Qt6::LabsPlatform
    Qt6::Network
    ${_zlib_target}
)

# Optional remote control modules
if(Qt6Mqtt_FOUND)
    target_link_libraries(openps2000app PRIVATE Qt6::Mqtt)
    target_compile_definitions(openps2000app PRIVATE HAVE_QT_MQTT)
endif()

# ── DBus on Linux (Qt serial port may need it transitively) ───────────────
if(UNIX AND NOT APPLE)
    find_package(Qt6 OPTIONAL_COMPONENTS DBus)
    if(Qt6DBus_FOUND)
        target_link_libraries(openps2000app PRIVATE Qt6::DBus)
    endif()
endif()

# ── macOS bundle ──────────────────────────────────────────────────────────
if(APPLE)
    set_target_properties(openps2000app PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_BUNDLE_NAME          "OpenPS2000"
        MACOSX_BUNDLE_BUNDLE_VERSION       "1.0"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0"
        MACOSX_BUNDLE_GUI_IDENTIFIER       "cz.yeckel.openps2000"
    )
endif()

# ── Windows: embed manifest for long paths ────────────────────────────────
if(WIN32)
    set_target_properties(openps2000app PROPERTIES
        WIN32_EXECUTABLE TRUE
    )
endif()

# ── RPATH (local dev) ─────────────────────────────────────────────────────
if(DEFINED CMAKE_PREFIX_PATH)
    list(GET CMAKE_PREFIX_PATH 0 _qt_prefix)
    if(EXISTS "${_qt_prefix}/lib")
        set_target_properties(openps2000app PROPERTIES
            BUILD_RPATH   "${_qt_prefix}/lib"
            INSTALL_RPATH "${_qt_prefix}/lib"
        )
    endif()
endif()

# ── Translations ───────────────────────────────────────────────────────────
find_package(Qt6 REQUIRED COMPONENTS LinguistTools)

qt_add_translations(openps2000app
    TS_FILES
        i18n/openps2000_de.ts
        i18n/openps2000_es.ts
        i18n/openps2000_cs.ts
        i18n/openps2000_pl.ts
        i18n/openps2000_zh_CN.ts
    SOURCES
        qml/Main.qml
        qml/LiveChart.qml
        qml/ChargingChart.qml
        qml/ChargerTab.qml
        qml/PulseTab.qml
        qml/PulseChart.qml
        qml/SequenceTab.qml
        qml/SequenceChart.qml
        qml/SequenceEditorDialog.qml
    LUPDATE_OPTIONS
        -no-obsolete
)
