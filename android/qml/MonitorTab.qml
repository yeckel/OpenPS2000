// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls
import QtQuick.Layouts

// ── Monitor Tab ──────────────────────────────────────────────────────────
// Large V/I/P readings + live scrolling chart + energy counter.
Rectangle {
    color: "#0d1117"

    ColumnLayout {
        anchors { fill: parent; margins: 12 }
        spacing: 10

        // ── Big readings ─────────────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 8
            rowSpacing: 8

            // Voltage
            Rectangle {
                Layout.fillWidth: true; height: 88; radius: 10
                color: "#0d2233"; border.color: "#1e4060"; border.width: 1
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 2
                    Label {
                        text: qsTr("Voltage")
                        font.pixelSize: 11; color: "#607d8b"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Label {
                        text: backend.voltage.toFixed(2)
                        font.pixelSize: 28; font.bold: true; color: "#64b5f6"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Label {
                        text: "V"
                        font.pixelSize: 12; color: "#4a7a9b"
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            // Current
            Rectangle {
                Layout.fillWidth: true; height: 88; radius: 10
                color: "#1a1400"; border.color: "#3a3000"; border.width: 1
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 2
                    Label {
                        text: qsTr("Current")
                        font.pixelSize: 11; color: "#78600a"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Label {
                        text: (backend.current * 1000).toFixed(0)
                        font.pixelSize: 28; font.bold: true; color: "#ffb74d"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Label {
                        text: "mA"
                        font.pixelSize: 12; color: "#9a7a30"
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            // Power
            Rectangle {
                Layout.fillWidth: true; height: 88; radius: 10
                color: "#0d1a0d"; border.color: "#1a3a1a"; border.width: 1
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 2
                    Label {
                        text: qsTr("Power")
                        font.pixelSize: 11; color: "#4a7a4a"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Label {
                        text: backend.power.toFixed(2)
                        font.pixelSize: 28; font.bold: true; color: "#81c784"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Label {
                        text: "W"
                        font.pixelSize: 12; color: "#4a7a4a"
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }

        // ── Secondary readings row ────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.fillWidth: true; height: 52; radius: 8
                color: "#111820"; border.color: "#1e2d3d"; border.width: 1
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 1
                    Label {
                        text: qsTr("Set V")
                        font.pixelSize: 10; color: "#607d8b"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Label {
                        text: backend.setVoltage.toFixed(2) + " V"
                        font.pixelSize: 14; font.bold: true; color: "#90caf9"
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true; height: 52; radius: 8
                color: "#111820"; border.color: "#1e2d3d"; border.width: 1
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 1
                    Label {
                        text: qsTr("Set I")
                        font.pixelSize: 10; color: "#607d8b"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Label {
                        text: (backend.setCurrent * 1000).toFixed(0) + " mA"
                        font.pixelSize: 14; font.bold: true; color: "#ffcc80"
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true; height: 52; radius: 8
                color: "#111820"; border.color: "#1e2d3d"; border.width: 1
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 1
                    Label {
                        text: qsTr("Energy")
                        font.pixelSize: 10; color: "#607d8b"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Label {
                        text: backend.energyWh.toFixed(3) + " Wh"
                        font.pixelSize: 14; font.bold: true; color: "#ce93d8"
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }
        }

        // ── Mode indicators ───────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                height: 28; width: ccLabel.implicitWidth + 16; radius: 4
                visible: backend.connected
                color: backend.ccMode ? "#1a3a1a" : "#0d2233"
                border.color: backend.ccMode ? "#4caf50" : "#1e4060"; border.width: 1
                Label {
                    id: ccLabel
                    anchors.centerIn: parent
                    text: backend.ccMode ? "CC" : "CV"
                    font.pixelSize: 11; font.bold: true
                    color: backend.ccMode ? "#a5d6a7" : "#90caf9"
                }
            }

            Rectangle {
                height: 28; width: alarmLabel.implicitWidth + 16; radius: 4
                visible: backend.connected && backend.anyAlarm
                color: "#3a0d0d"; border.color: "#f44336"; border.width: 1
                Label {
                    id: alarmLabel
                    anchors.centerIn: parent
                    text: backend.ovpActive ? "OVP" :
                          backend.ocpActive ? "OCP" :
                          backend.oppActive ? "OPP" : "ALARM"
                    font.pixelSize: 11; font.bold: true; color: "#ef9a9a"
                }
            }

            Item { Layout.fillWidth: true }

            Label {
                visible: backend.connected
                text: backend.duration
                font.pixelSize: 11; color: "#607d8b"
            }
        }

        // ── Live chart ────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 8; color: "#0a0f14"
            border.color: "#1e2d3d"; border.width: 1
            clip: true

            LiveChart {
                id: liveChart
                anchors { fill: parent; margins: 4 }
            }

            // Wire new samples
            Connections {
                target: backend
                function onNewSample(t, v, i, p) {
                    liveChart.addPoint(t, v, i)
                }
            }
        }

        // ── Not connected placeholder ─────────────────────────────────────
        Label {
            Layout.fillWidth: true
            visible: !backend.connected
            text: qsTr("⚡ Go to Settings to connect")
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 13; color: "#607d8b"
        }
    }
}
