// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls
import QtQuick.Layouts

// ── Root window ──────────────────────────────────────────────────────────
// Portrait phone layout: status bar at top, tab content, bottom navigation.
ApplicationWindow {
    id: root
    visible: true
    width:  390
    height: 844
    title:  "OpenPS2000"

    Material.theme:  Material.Dark
    Material.accent: Material.LightBlue

    // ── Status bar ────────────────────────────────────────────────────────
    header: ToolBar {
        height: 52
        Material.background: backend.connected ? "#0d2a3a" : "#1a1a1a"

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 8

            // Connection indicator dot
            Rectangle {
                width: 10; height: 10; radius: 5
                color: backend.connected ? "#4caf50" : "#616161"
            }

            Label {
                text: backend.connected
                      ? (backend.deviceType !== "" ? backend.deviceType
                                                   : (backendFactory.isRemote ? "REST" : "USB"))
                      : qsTr("Not connected")
                font.pixelSize: 14; font.bold: backend.connected
                color: backend.connected ? "#e0f0ff" : "#757575"
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            // Live readings — only shown when connected
            Label {
                visible: backend.connected
                text: backend.voltage.toFixed(1) + "V"
                font.pixelSize: 13; font.bold: true; color: "#64b5f6"
            }
            Label {
                visible: backend.connected
                text: (backend.current * 1000).toFixed(0) + "mA"
                font.pixelSize: 13; font.bold: true; color: "#ffb74d"
            }

            // Output badge
            Rectangle {
                visible: backend.connected
                width:   outputBadgeLabel.implicitWidth + 12
                height:  22; radius: 4
                color: backend.outputOn ? "#1b5e20" : "#37474f"
                border.color: backend.outputOn ? "#4caf50" : "#546e7a"; border.width: 1
                Label {
                    id: outputBadgeLabel
                    anchors.centerIn: parent
                    text: backend.outputOn ? qsTr("ON") : qsTr("OFF")
                    font.pixelSize: 11; font.bold: true
                    color: backend.outputOn ? "#a5d6a7" : "#90a4ae"
                }
            }
        }
    }

    // ── Page content ──────────────────────────────────────────────────────
    StackLayout {
        id: pageStack
        anchors { top: parent.top; left: parent.left; right: parent.right; bottom: navBar.top }
        currentIndex: navBar.currentIndex

        MonitorTab  { }
        ControlTab  { }
        SettingsTab { }
    }

    // ── Bottom navigation bar ─────────────────────────────────────────────
    TabBar {
        id: navBar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 60
        Material.background: "#111820"

        TabButton {
            text: qsTr("Monitor")
            icon.source: "qrc:/icons/monitor.svg"
            font.pixelSize: 11
        }
        TabButton {
            text: qsTr("Control")
            icon.source: "qrc:/icons/control.svg"
            font.pixelSize: 11
        }
        TabButton {
            text: qsTr("Settings")
            icon.source: "qrc:/icons/settings.svg"
            font.pixelSize: 11
        }
    }
}
