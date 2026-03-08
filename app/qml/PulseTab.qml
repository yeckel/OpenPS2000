// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls
import QtQuick.Layouts

// ── Pulse / Cycle generator tab ──────────────────────────────────────────────
// Produces a software-timed square wave by alternating between two setpoints.
// Minimum ON/OFF time is 50 ms (EA PS 2000 B protocol limit).
Rectangle {
    id: root
    color: "#0d1117"

    // ── Helpers ─────────────────────────────────────────────────────────────
    function fmtTime(s) {
        var sec = Math.floor(s)
        var h = Math.floor(sec / 3600)
        var m = Math.floor((sec % 3600) / 60)
        var r = sec % 60
        if (h > 0) return h + "h " + m + "m " + r + "s"
        if (m > 0) return m + "m " + r + "s"
        return r + "s"
    }

    // ── Connections ──────────────────────────────────────────────────────────
    Connections {
        target: pulser
        function onNewPoint(t, v, i) { pulseChart.addPoint(t, v, i) }
        function onFinished(cycles) {
            statusLabel.text = qsTr("Done — %1 cycles completed").arg(cycles)
        }
    }

    // ── Layout ───────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Left: settings panel ─────────────────────────────────────────────
        Rectangle {
            Layout.preferredWidth: 340
            Layout.fillHeight: true
            color: "#111820"
            radius: 0

            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#1e2d3d" }

            // START/STOP anchored at bottom
            Rectangle {
                id: startStopBar
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 64; color: "#0d1117"

                Button {
                    anchors { fill: parent; margins: 10 }
                    text: pulser.state === 0 || pulser.state === 3
                          ? qsTr("▶ START") : qsTr("■ STOP")
                    font.pixelSize: 15; font.bold: true
                    highlighted: true
                    Material.theme: Material.Dark
                    Material.accent: pulser.state === 0 || pulser.state === 3
                                     ? "#4caf50" : "#f44336"
                    enabled: backend.connected
                    onClicked: {
                        if (pulser.state === 0 || pulser.state === 3) {
                            pulseChart.clearAll()
                            pulser.start(
                                backend.setVoltage,
                                backend.setCurrent,
                                offDisableCheck.checked ? 0.0 : offVoltSpin.value / 1000.0,
                                offDisableCheck.checked ? 0.0 : offCurrSpin.value / 1000.0,
                                offDisableCheck.checked,
                                onTimeSpin.value,
                                offTimeSpin.value,
                                cyclesSpin.value
                            )
                        } else {
                            pulser.stop()
                        }
                    }
                }
            }

            ScrollView {
                anchors { fill: parent; bottomMargin: startStopBar.height }
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: 0

                    // ── Header ──────────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true; height: 48; color: "#0d1117"
                        Label {
                            anchors.centerIn: parent
                            text: "⚡ " + qsTr("Pulse / Cycle Generator")
                            font.pixelSize: 14; font.bold: true; color: "#e0e8f0"
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#1e2d3d" }

                    // ── ON setpoint ─────────────────────────────────────────
                    Item { Layout.fillWidth: true; height: 8 }
                    Label {
                        Layout.leftMargin: 12
                        text: qsTr("ON setpoint")
                        font.pixelSize: 11; font.bold: true; color: "#4caf50"
                    }
                    Item { Layout.fillWidth: true; height: 4 }

                    // ON state uses the main panel setpoints — no duplicate input needed
                    Rectangle {
                        Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12
                        height: 44; radius: 6; color: "#0d1f0d"
                        border.color: "#2e7d32"; border.width: 1
                        RowLayout {
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            Label {
                                text: qsTr("Uses main setpoint:")
                                font.pixelSize: 11; color: "#8899aa"
                            }
                            Item { Layout.fillWidth: true }
                            Label {
                                font.pixelSize: 12; font.bold: true; color: "#81c784"
                                text: backend.setVoltage.toFixed(2) + " V  /  " +
                                      backend.setCurrent.toFixed(3) + " A"
                            }
                        }
                    }

                    Item { Layout.fillWidth: true; height: 10 }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#1e2d3d" }

                    // ── OFF setpoint ────────────────────────────────────────
                    Item { Layout.fillWidth: true; height: 8 }
                    Label {
                        Layout.leftMargin: 12
                        text: qsTr("OFF setpoint")
                        font.pixelSize: 11; font.bold: true; color: "#e57373"
                    }
                    Item { Layout.fillWidth: true; height: 4 }

                    RowLayout {
                        Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12
                        spacing: 8
                        CheckBox {
                            id: offDisableCheck
                            text: qsTr("Disable output during OFF")
                            font.pixelSize: 11; Material.theme: Material.Dark
                            checked: false
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12
                        spacing: 8
                        enabled: !offDisableCheck.checked
                        opacity: offDisableCheck.checked ? 0.35 : 1.0
                        ColumnLayout {
                            spacing: 2; Layout.fillWidth: true
                            Label { text: qsTr("Voltage (V)"); color: "#8899aa"; font.pixelSize: 11 }
                            SpinBox {
                                id: offVoltSpin
                                Layout.fillWidth: true; Layout.minimumWidth: 120
                                // stored in mV (integer)
                                from: 0; to: Math.round(backend.nominalVoltage * 1000)
                                stepSize: 100; value: 0
                                Material.theme: Material.Dark; wheelEnabled: true
                                textFromValue: function(v) { return (v / 1000).toFixed(2) }
                                valueFromText: function(t) { return Math.round(parseFloat(t) * 1000) }
                                validator: RegularExpressionValidator { regularExpression: /[0-9]*\.?[0-9]*/ }
                            }
                        }
                        ColumnLayout {
                            spacing: 2; Layout.fillWidth: true
                            Label { text: qsTr("Current (A)"); color: "#8899aa"; font.pixelSize: 11 }
                            SpinBox {
                                id: offCurrSpin
                                Layout.fillWidth: true; Layout.minimumWidth: 120
                                // stored in mA (integer)
                                from: 0; to: Math.round(backend.nominalCurrent * 1000)
                                stepSize: 10; value: 0
                                Material.theme: Material.Dark; wheelEnabled: true
                                textFromValue: function(v) { return (v / 1000).toFixed(3) }
                                valueFromText: function(t) { return Math.round(parseFloat(t) * 1000) }
                                validator: RegularExpressionValidator { regularExpression: /[0-9]*\.?[0-9]*/ }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true; height: 10 }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#1e2d3d" }

                    // ── Timing ──────────────────────────────────────────────
                    Item { Layout.fillWidth: true; height: 8 }
                    Label {
                        Layout.leftMargin: 12
                        text: qsTr("Timing")
                        font.pixelSize: 11; font.bold: true; color: "#64b5f6"
                    }

                    // Derived frequency / duty cycle display
                    Label {
                        Layout.leftMargin: 12
                        font.pixelSize: 11; color: "#8899aa"
                        text: {
                            var period = onTimeSpin.value + offTimeSpin.value
                            var freq   = period > 0 ? (1000.0 / period).toFixed(3) : "—"
                            var duty   = period > 0
                                ? ((onTimeSpin.value / period) * 100).toFixed(1) : "—"
                            return qsTr("Period: %1 ms  |  Freq: %2 Hz  |  Duty: %3 %")
                                   .arg(period).arg(freq).arg(duty)
                        }
                    }
                    Item { Layout.fillWidth: true; height: 4 }

                    RowLayout {
                        Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12
                        spacing: 8
                        ColumnLayout {
                            spacing: 2; Layout.fillWidth: true
                            Label { text: qsTr("ON time (ms)"); color: "#8899aa"; font.pixelSize: 11 }
                            SpinBox {
                                id: onTimeSpin
                                Layout.fillWidth: true; Layout.minimumWidth: 140
                                from: 500; to: 3600000; stepSize: 100; value: 500
                                Material.theme: Material.Dark; wheelEnabled: true
                                onValueModified: {}
                            }
                        }
                        ColumnLayout {
                            spacing: 2; Layout.fillWidth: true
                            Label { text: qsTr("OFF time (ms)"); color: "#8899aa"; font.pixelSize: 11 }
                            SpinBox {
                                id: offTimeSpin
                                Layout.fillWidth: true; Layout.minimumWidth: 140
                                from: 500; to: 3600000; stepSize: 100; value: 500
                                Material.theme: Material.Dark; wheelEnabled: true
                                onValueModified: {}
                            }
                        }
                    }

                    Item { Layout.fillWidth: true; height: 10 }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#1e2d3d" }

                    // ── Cycles ──────────────────────────────────────────────
                    Item { Layout.fillWidth: true; height: 8 }
                    Label {
                        Layout.leftMargin: 12
                        text: qsTr("Cycles (0 = infinite)")
                        font.pixelSize: 11; font.bold: true; color: "#ce93d8"
                    }
                    Item { Layout.fillWidth: true; height: 4 }
                    SpinBox {
                        id: cyclesSpin
                        Layout.fillWidth: true
                        Layout.leftMargin: 12; Layout.rightMargin: 12
                        from: 0; to: 999999; stepSize: 1; value: 0
                        Material.theme: Material.Dark; wheelEnabled: true
                        textFromValue: function(v) { return v === 0 ? qsTr("∞") : v.toString() }
                        valueFromText: function(t) { return t === "∞" ? 0 : parseInt(t) || 0 }
                        onValueModified: {}
                    }

                    Item { Layout.fillWidth: true; height: 10 }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#1e2d3d" }

                    // ── Live stats ──────────────────────────────────────────
                    Item { Layout.fillWidth: true; height: 8 }
                    Label {
                        Layout.leftMargin: 12
                        text: qsTr("Status")
                        font.pixelSize: 11; font.bold: true; color: "#ffb74d"
                    }
                    Item { Layout.fillWidth: true; height: 4 }

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 12; Layout.rightMargin: 12
                        columns: 2; rowSpacing: 4; columnSpacing: 8

                        Label { text: qsTr("State:"); color: "#8899aa"; font.pixelSize: 11 }
                        Label {
                            font.pixelSize: 11; font.bold: true
                            color: pulser.state === 1 ? "#4caf50"
                                 : pulser.state === 2 ? "#e57373"
                                 : pulser.state === 3 ? "#64b5f6" : "#8899aa"
                            text: pulser.state === 0 ? qsTr("Idle")
                                : pulser.state === 1 ? qsTr("ON")
                                : pulser.state === 2 ? qsTr("OFF")
                                : qsTr("Done")
                        }

                        Label { text: qsTr("Elapsed:"); color: "#8899aa"; font.pixelSize: 11 }
                        Label {
                            font.pixelSize: 11; color: "#e0e8f0"
                            text: fmtTime(pulser.elapsedSecs)
                            // tick property drives re-evaluation
                            property var _t: pulser.tick
                        }

                        Label { text: qsTr("Cycles done:"); color: "#8899aa"; font.pixelSize: 11 }
                        Label {
                            font.pixelSize: 11; color: "#e0e8f0"
                            text: {
                                var c = pulser.cyclesDone
                                var tot = cyclesSpin.value
                                return tot === 0 ? c.toString()
                                                 : c + " / " + tot
                            }
                        }

                        Label { text: qsTr("Actual V:"); color: "#8899aa"; font.pixelSize: 11 }
                        Label {
                            font.pixelSize: 11; color: "#80deea"
                            text: pulser.actualVoltage.toFixed(3) + " V"
                            property var _t: pulser.tick
                        }

                        Label { text: qsTr("Actual I:"); color: "#8899aa"; font.pixelSize: 11 }
                        Label {
                            font.pixelSize: 11; color: "#ffcc80"
                            text: (pulser.actualCurrent * 1000).toFixed(1) + " mA"
                            property var _t: pulser.tick
                        }
                    }

                    Label {
                        id: statusLabel
                        Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12
                        Layout.topMargin: 6
                        wrapMode: Text.WordWrap; font.pixelSize: 11; color: "#64b5f6"
                        text: ""
                    }

                    // warning if not connected
                    Label {
                        Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12
                        Layout.topMargin: 4
                        wrapMode: Text.WordWrap; font.pixelSize: 11; color: "#ef9a9a"
                        visible: !backend.connected
                        text: qsTr("⚠ Device not connected")
                    }

                    Item { Layout.fillWidth: true; height: 16 }
                }
            }
        }

        // ── Right: chart ─────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#0d1117"

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // title bar
                Rectangle {
                    Layout.fillWidth: true; height: 36; color: "#111820"
                    Label {
                        anchors.centerIn: parent
                        text: qsTr("Pulse Waveform")
                        font.pixelSize: 13; font.bold: true; color: "#b0bec5"
                    }
                }

                // The chart
                PulseChart {
                    id: pulseChart
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }
            }
        }
    }
}
