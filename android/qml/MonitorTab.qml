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

    // Alarm acknowledgment state
    property bool alarmAcknowledged: false
    // When true: turn output back on as soon as the PSU clears the alarm
    property bool resumeOutputAfterAck: false

    // Send/cancel system notification and handle resume-after-ack.
    Connections {
        target: backend
        function onAnyAlarmChanged() {
            if (backend.anyAlarm) {
                alarmAcknowledged = false
                var kind = backend.ovpActive ? qsTr("Over Voltage (OVP)") :
                           backend.ocpActive ? qsTr("Over Current (OCP)") :
                           backend.oppActive ? qsTr("Over Power (OPP)")   :
                           backend.otpActive ? qsTr("Over Temperature (OTP)") :
                                              qsTr("Protection Alarm")
                alarmNotifier.showAlarm(
                    "⚠ " + qsTr("PSU Protection Alarm"),
                    kind + (backend.deviceType.length > 0 ? " — " + backend.deviceType : ""))
            } else {
                alarmNotifier.cancelAlarm()
                alarmAcknowledged = false
                // Alarm cleared — restore output if user chose "Ack & Resume"
                if (resumeOutputAfterAck) {
                    resumeOutputAfterAck = false
                    backend.setOutputOn(true)
                }
            }
        }
    }
    // Reset state when backend switches (new connection).
    Connections {
        target: backendFactory
        function onModeChanged() {
            alarmAcknowledged = false
            resumeOutputAfterAck = false
        }
    }

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

            // Small alarm badge — always visible while alarm is active
            Rectangle {
                height: 28; width: alarmBadge.implicitWidth + 16; radius: 4
                visible: backend.connected && backend.anyAlarm
                color: "#3a0d0d"; border.color: "#f44336"; border.width: 1
                MouseArea {
                    anchors.fill: parent
                    onClicked: alarmAcknowledged = false
                }
                Label {
                    id: alarmBadge
                    anchors.centerIn: parent
                    text: backend.ovpActive ? "⚠ OVP" :
                          backend.ocpActive ? "⚠ OCP" :
                          backend.oppActive ? "⚠ OPP" :
                          backend.otpActive ? "⚠ OTP" : "⚠ ALARM"
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

        // ── Full alarm banner (shown until user dismisses) ────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: bannerCol.implicitHeight + 16
            radius: 8
            visible: backend.connected && backend.anyAlarm && !alarmAcknowledged
            color: "#3a0d0d"; border.color: "#f44336"; border.width: 2

            ColumnLayout {
                id: bannerCol
                anchors { fill: parent; margins: 10 }
                spacing: 6

                // Alarm title row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Label { text: "🔴"; font.pixelSize: 20 }
                    Label {
                        text: qsTr("PROTECTION ALARM: ") + (
                              backend.ovpActive ? qsTr("Over Voltage (OVP)") :
                              backend.ocpActive ? qsTr("Over Current (OCP)") :
                              backend.oppActive ? qsTr("Over Power (OPP)")   :
                              backend.otpActive ? qsTr("Over Temperature (OTP)") : qsTr("Triggered"))
                        font.pixelSize: 13; font.bold: true; color: "#ff6b6b"
                        Layout.fillWidth: true; wrapMode: Text.WordWrap
                    }
                }

                // Action buttons in a row
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    // Acknowledges on PSU + restores output once alarm clears
                    Button {
                        text: qsTr("Ack & Resume")
                        Layout.fillWidth: true
                        Material.theme: Material.Dark
                        Material.accent: "#4caf50"
                        onClicked: {
                            resumeOutputAfterAck = true
                            backend.acknowledgeAlarms()
                            alarmAcknowledged = true
                            alarmNotifier.cancelAlarm()
                        }
                    }

                    // Acknowledges on PSU, output stays OFF
                    Button {
                        text: qsTr("Acknowledge")
                        Layout.fillWidth: true
                        Material.theme: Material.Dark
                        Material.accent: "#f44336"
                        onClicked: {
                            resumeOutputAfterAck = false
                            backend.acknowledgeAlarms()
                            alarmAcknowledged = true
                            alarmNotifier.cancelAlarm()
                        }
                    }

                    // UI dismiss only — no PSU command
                    Button {
                        text: qsTr("Dismiss")
                        flat: true
                        Material.theme: Material.Dark
                        Material.foreground: "#ef9a9a"
                        onClicked: alarmAcknowledged = true
                    }
                }
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
                leftUnit:  "V"
                rightUnit: "A"
                seriesList: [
                    { name: "Voltage", color: "#4dc8ff", yAxis: "left",  data: [], fillArea: false },
                    { name: "Current", color: "#ff9940", yAxis: "right", data: [], fillArea: false }
                ]
            }

            // Wire new samples
            Connections {
                target: backend
                function onNewSample(t, v, i, p) {
                    liveChart.appendTo(0, t, v)
                    liveChart.appendTo(1, t, i)
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
