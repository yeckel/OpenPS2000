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

    // ── Chart view state ──────────────────────────────────────────────────
    property real chartWindowSecs: 60
    property real chartViewLeft:   0
    property bool chartFollow:     true

    // Discrete zoom steps in seconds: 15s, 30s, 1m, 2m, 5m, 10m, 30m, 1h
    readonly property var windowSteps: [15, 30, 60, 120, 300, 600, 1800, 3600]

    function windowStepIdx(ws) {
        var best = 0
        var bestDist = Math.abs(windowSteps[0] - ws)
        for (var i = 1; i < windowSteps.length; i++) {
            var d = Math.abs(windowSteps[i] - ws)
            if (d < bestDist) { bestDist = d; best = i }
        }
        return best
    }
    function formatWindow(ws) {
        if (ws < 60)   return ws.toFixed(0) + "s"
        if (ws < 3600) return (ws / 60).toFixed(0) + "m"
        return (ws / 3600).toFixed(0) + "h"
    }

    // ── Selection statistics ──────────────────────────────────────────────
    property bool   hasStats:    false
    property string statDt:      ""
    property string statV:       ""
    property string statI:       ""
    property string statP:       ""
    property string statEnergy:  ""

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
                followMode: chartFollow
                effectiveWindowSecs: chartWindowSecs
                viewLeft: chartViewLeft
                seriesList: [
                    { name: "Voltage", color: "#4dc8ff", yAxis: "left",  data: [], fillArea: false },
                    { name: "Current", color: "#ff9940", yAxis: "right", data: [], fillArea: false }
                ]
                onViewChanged: (vl, ws) => {
                    chartViewLeft   = vl
                    chartWindowSecs = ws
                    chartFollow     = false
                }
                onRangeSelected: (t0, t1) => {
                    var r = backend.measureRange(t0, t1)
                    if (!r || (r.sampleCount || 0) <= 0) {
                        hasStats = false
                        return
                    }
                    hasStats   = true
                    statDt     = qsTr("Δt %1 s  n=%2").arg((r.duration || 0).toFixed(1)).arg(r.sampleCount)
                    statV      = qsTr("V  %1 / %2 / %3 V")
                                    .arg((r.minVoltage  || 0).toFixed(2))
                                    .arg((r.meanVoltage || 0).toFixed(2))
                                    .arg((r.peakVoltage || 0).toFixed(2))
                    statI      = qsTr("I  %1 / %2 / %3 mA")
                                    .arg(((r.minCurrent  || 0)*1000).toFixed(0))
                                    .arg(((r.meanCurrent || 0)*1000).toFixed(0))
                                    .arg(((r.peakCurrent || 0)*1000).toFixed(0))
                    statP      = qsTr("P  %1 / %2 / %3 W")
                                    .arg((r.minPower  || 0).toFixed(2))
                                    .arg((r.meanPower || 0).toFixed(2))
                                    .arg((r.peakPower || 0).toFixed(2))
                    statEnergy = qsTr("%1 mWh  /  %2 mAh")
                                    .arg(((r.energyWh  || 0)*1000).toFixed(2))
                                    .arg(((r.energyMAh || 0)*1000).toFixed(1))
                }
                onSelectionCleared: { hasStats = false }
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

        // ── Chart zoom / pan controls ─────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            visible: backend.connected

            // Zoom out
            RoundButton {
                text: "−"; font.pixelSize: 16
                Layout.preferredWidth: 40; Layout.preferredHeight: 40
                flat: true; Material.foreground: "#90caf9"
                onClicked: {
                    var idx = windowStepIdx(chartWindowSecs)
                    if (idx > 0) {
                        var curLeft = liveChart.currentViewLeft()
                        chartWindowSecs = windowSteps[idx - 1]
                        chartViewLeft   = curLeft
                        chartFollow     = false
                    }
                }
            }

            // Current window size label — tap to reset to 1 min live
            Label {
                text: formatWindow(chartWindowSecs)
                font.pixelSize: 12; color: "#90caf9"
                Layout.minimumWidth: 32
                horizontalAlignment: Text.AlignHCenter
                MouseArea { anchors.fill: parent; onClicked: { chartFollow = true; chartWindowSecs = 60 } }
            }

            // Zoom in
            RoundButton {
                text: "+"; font.pixelSize: 16
                Layout.preferredWidth: 40; Layout.preferredHeight: 40
                flat: true; Material.foreground: "#90caf9"
                onClicked: {
                    var idx = windowStepIdx(chartWindowSecs)
                    if (idx < windowSteps.length - 1) {
                        var curLeft = liveChart.currentViewLeft()
                        chartWindowSecs = windowSteps[idx + 1]
                        chartViewLeft   = curLeft
                        chartFollow     = false
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Pan ← (half-window step)
            RoundButton {
                text: "◀"; font.pixelSize: 13
                Layout.preferredWidth: 40; Layout.preferredHeight: 40
                flat: true; Material.foreground: "#607d8b"
                onClicked: {
                    var curLeft = liveChart.currentViewLeft()
                    chartViewLeft = Math.max(0, curLeft - chartWindowSecs * 0.5)
                    chartFollow   = false
                }
            }

            // Pan → (half-window step)
            RoundButton {
                text: "▶"; font.pixelSize: 13
                Layout.preferredWidth: 40; Layout.preferredHeight: 40
                flat: true; Material.foreground: "#607d8b"
                onClicked: {
                    var curLeft  = liveChart.currentViewLeft()
                    var newLeft  = curLeft + chartWindowSecs * 0.5
                    // If we've panned past the live edge, re-engage follow mode
                    if (newLeft + chartWindowSecs >= liveChart.xHead) {
                        chartFollow = true
                    } else {
                        chartViewLeft = newLeft
                        chartFollow   = false
                    }
                }
            }

            // Live / Follow button
            Button {
                text: chartFollow ? "● Live" : "▶ Live"
                font.pixelSize: 11
                flat: chartFollow
                highlighted: !chartFollow
                Material.accent: chartFollow ? "#4caf50" : "#2196f3"
                onClicked: { chartFollow = true; chartWindowSecs = 60 }
            }
        }

        // ── Selection statistics panel ────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: statsCol.implicitHeight + 12
            visible: hasStats
            radius: 6; color: "#0d1a2a"
            border.color: "#1e3a5a"; border.width: 1

            ColumnLayout {
                id: statsCol
                anchors { fill: parent; margins: 6 }
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: statDt
                        font.pixelSize: 10; color: "#6699bb"
                        Layout.fillWidth: true
                    }
                    // Tap × to dismiss
                    Label {
                        text: "✕"
                        font.pixelSize: 12; color: "#446688"
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                hasStats = false
                                liveChart.selectionStart = -1
                                liveChart.selectionEnd   = -1
                                liveChart.repaint()
                            }
                        }
                    }
                }
                Label { text: statV;      font.pixelSize: 10; color: "#4dc8ff"; font.family: "monospace" }
                Label { text: statI;      font.pixelSize: 10; color: "#ff9940"; font.family: "monospace" }
                Label { text: statP;      font.pixelSize: 10; color: "#81c784"; font.family: "monospace" }
                Label { text: statEnergy; font.pixelSize: 10; color: "#ce93d8"; font.family: "monospace" }
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
