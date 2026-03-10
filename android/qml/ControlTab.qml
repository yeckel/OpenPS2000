// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls
import QtQuick.Layouts

// ── Control Tab ──────────────────────────────────────────────────────────
// Voltage / current setpoints + Output ON/OFF + Emergency stop.
// All controls are touch-friendly (large tap targets).
Rectangle {
    color: "#0d1117"

    // Confirm dialog for switching output on
    Dialog {
        id: confirmOnDialog
        anchors.centerIn: parent
        title: qsTr("Enable Output")
        modal: true
        Material.theme: Material.Dark
        standardButtons: Dialog.Yes | Dialog.Cancel
        Label {
            text: qsTr("Apply %1 V / %2 A to the load?")
                  .arg(backend.setVoltage.toFixed(2))
                  .arg(backend.setCurrent.toFixed(3))
            wrapMode: Text.WordWrap
            font.pixelSize: 14; color: "#e0e8f0"
        }
        onAccepted: backend.setOutputOn(true)
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: parent.width
            spacing: 0

            Item { Layout.fillWidth: true; height: 12 }

            // ── Emergency stop ────────────────────────────────────────────
            Button {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                height: 64
                text: "⚡  " + qsTr("EMERGENCY STOP")
                font.pixelSize: 16; font.bold: true
                highlighted: true
                Material.theme:  Material.Dark
                Material.accent: "#f44336"
                enabled: backend.connected && backend.outputOn
                onClicked: backend.setOutputOn(false)
            }

            Item { Layout.fillWidth: true; height: 16 }
            Rectangle { Layout.fillWidth: true; height: 1; color: "#1e2d3d" }
            Item { Layout.fillWidth: true; height: 12 }

            // ── Output ON/OFF toggle ──────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                spacing: 12

                Label {
                    text: qsTr("Output")
                    font.pixelSize: 16; font.bold: true; color: "#e0e8f0"
                    Layout.fillWidth: true
                }

                Switch {
                    id: outputSwitch
                    checked: backend.connected && backend.outputOn
                    enabled: backend.connected
                    Material.theme:  Material.Dark
                    Material.accent: "#4caf50"
                    // Intercept turn-on to show confirmation
                    onToggled: {
                        if (checked) {
                            confirmOnDialog.open()
                            // Revert switch — dialog result drives actual state
                            checked = Qt.binding(function() {
                                return backend.connected && backend.outputOn
                            })
                        } else {
                            backend.setOutputOn(false)
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true; height: 16 }
            Rectangle { Layout.fillWidth: true; height: 1; color: "#1e2d3d" }
            Item { Layout.fillWidth: true; height: 12 }

            // ── Voltage setpoint ──────────────────────────────────────────
            Label {
                Layout.leftMargin: 16
                text: qsTr("Voltage Setpoint")
                font.pixelSize: 13; font.bold: true; color: "#64b5f6"
            }
            Item { Layout.fillWidth: true; height: 6 }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                spacing: 12

                Slider {
                    id: voltSlider
                    Layout.fillWidth: true
                    from: 0
                    to:   backend.connected ? backend.nomVoltage : 84
                    value: backend.setVoltage
                    stepSize: 0.1
                    enabled: backend.connected && backend.remoteMode
                    Material.theme:  Material.Dark
                    Material.accent: "#64b5f6"

                    onMoved: {
                        voltField.text = value.toFixed(2)
                        backend.sendSetVoltage(value)
                    }
                }

                Rectangle {
                    width: 80; height: 44; radius: 6
                    color: "#0d2233"; border.color: "#1e4060"; border.width: 1

                    TextInput {
                        id: voltField
                        anchors { fill: parent; margins: 8 }
                        text:             backend.setVoltage.toFixed(2)
                        font.pixelSize:   16; font.bold: true
                        color:            "#64b5f6"
                        inputMethodHints: Qt.ImhFormattedNumbersOnly
                        verticalAlignment: Text.AlignVCenter
                        enabled:          backend.connected && backend.remoteMode

                        onEditingFinished: {
                            var v = parseFloat(text)
                            if (!isNaN(v)) {
                                var clamped = Math.max(0, Math.min(v, backend.nomVoltage))
                                backend.sendSetVoltage(clamped)
                                voltSlider.value = clamped
                            }
                        }
                    }
                }

                Label {
                    text: "V"; font.pixelSize: 14; color: "#4a7a9b"
                }
            }

            Item { Layout.fillWidth: true; height: 16 }
            Rectangle { Layout.fillWidth: true; height: 1; color: "#1e2d3d" }
            Item { Layout.fillWidth: true; height: 12 }

            // ── Current setpoint ──────────────────────────────────────────
            Label {
                Layout.leftMargin: 16
                text: qsTr("Current Setpoint")
                font.pixelSize: 13; font.bold: true; color: "#ffb74d"
            }
            Item { Layout.fillWidth: true; height: 6 }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                spacing: 12

                Slider {
                    id: currSlider
                    Layout.fillWidth: true
                    from: 0
                    to:   backend.connected ? backend.nomCurrent : 5
                    value: backend.setCurrent
                    stepSize: 0.001
                    enabled: backend.connected && backend.remoteMode
                    Material.theme:  Material.Dark
                    Material.accent: "#ffb74d"

                    onMoved: {
                        currField.text = (value * 1000).toFixed(0)
                        backend.sendSetCurrent(value)
                    }
                }

                Rectangle {
                    width: 80; height: 44; radius: 6
                    color: "#1a1400"; border.color: "#3a3000"; border.width: 1

                    TextInput {
                        id: currField
                        anchors { fill: parent; margins: 8 }
                        text:             (backend.setCurrent * 1000).toFixed(0)
                        font.pixelSize:   16; font.bold: true
                        color:            "#ffb74d"
                        inputMethodHints: Qt.ImhDigitsOnly
                        verticalAlignment: Text.AlignVCenter
                        enabled:          backend.connected && backend.remoteMode

                        onEditingFinished: {
                            var i = parseFloat(text) / 1000.0
                            if (!isNaN(i)) {
                                var clamped = Math.max(0, Math.min(i, backend.nomCurrent))
                                backend.sendSetCurrent(clamped)
                                currSlider.value = clamped
                            }
                        }
                    }
                }

                Label {
                    text: "mA"; font.pixelSize: 14; color: "#9a7a30"
                }
            }

            Item { Layout.fillWidth: true; height: 16 }
            Rectangle { Layout.fillWidth: true; height: 1; color: "#1e2d3d" }
            Item { Layout.fillWidth: true; height: 12 }

            // ── Protection limits ─────────────────────────────────────────
            Label {
                Layout.leftMargin: 16
                text: qsTr("Protection Limits")
                font.pixelSize: 13; font.bold: true; color: "#ef9a9a"
            }
            Item { Layout.fillWidth: true; height: 6 }

            GridLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                columns: 4; columnSpacing: 8; rowSpacing: 8

                Label { text: qsTr("OVP"); font.pixelSize: 12; color: "#8899aa" }
                TextField {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    text: backend.ovpVoltage.toFixed(1)
                    font.pixelSize: 14; color: "#ef9a9a"
                    leftPadding: 8; rightPadding: 8
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    enabled: backend.connected && backend.remoteMode
                    background: Rectangle {
                        color: "#1a0d0d"; border.color: "#4a1a1a"; border.width: 1; radius: 6
                    }
                    onEditingFinished: {
                        var v = parseFloat(text)
                        if (!isNaN(v)) backend.sendOvpVoltage(v)
                    }
                }
                Label { text: "V"; font.pixelSize: 12; color: "#8899aa" }
                Item  { width: 1 }

                Label { text: qsTr("OCP"); font.pixelSize: 12; color: "#8899aa" }
                TextField {
                    Layout.fillWidth: true
                    implicitHeight: 40
                    text: backend.ocpCurrent.toFixed(3)
                    font.pixelSize: 14; color: "#ef9a9a"
                    leftPadding: 8; rightPadding: 8
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    enabled: backend.connected && backend.remoteMode
                    background: Rectangle {
                        color: "#1a0d0d"; border.color: "#4a1a1a"; border.width: 1; radius: 6
                    }
                    onEditingFinished: {
                        var i = parseFloat(text)
                        if (!isNaN(i)) backend.sendOcpCurrent(i)
                    }
                }
                Label { text: "A"; font.pixelSize: 12; color: "#8899aa" }
                Item  { width: 1 }
            }

            // Remote mode warning
            Label {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                Layout.topMargin: 8
                visible: backend.connected && !backend.remoteMode
                text: qsTr("⚠ Enable Remote mode on the PSU to change setpoints")
                wrapMode: Text.WordWrap
                font.pixelSize: 12; color: "#ef9a9a"
            }

            // Remote mode button
            Button {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                Layout.topMargin: 4
                text: backend.remoteMode ? qsTr("Switch to Manual mode")
                                         : qsTr("Enable Remote mode")
                enabled: backend.connected
                Material.theme: Material.Dark
                Material.accent: "#64b5f6"
                onClicked: backend.setRemoteMode(!backend.remoteMode)
            }

            Item { Layout.fillWidth: true; height: 24 }
        }
    }
}
