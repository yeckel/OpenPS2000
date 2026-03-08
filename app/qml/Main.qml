// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
// Main.qml — OpenPS2000 main window
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Platform

ApplicationWindow {
    id: window
    visible:  true
    width:    1280
    height:   820
    minimumWidth:  900
    minimumHeight: 620
    title: "OpenPS2000"
    color: "#0d1117"

    Material.theme:   Material.Dark
    Material.accent:  Material.Cyan
    Material.primary: "#1a2030"

    // ── Shared chart state ─────────────────────────────────────────────────
    property real sharedWindowSecs: 60
    property real sharedViewLeft:   0
    property bool followMode:       true

    // ── Measurement panel state ────────────────────────────────────────────
    property var   measureData:   null
    property bool  showMeasure:   false

    // ── Status snackbar ────────────────────────────────────────────────────
    property string lastStatus: ""

    Connections {
        target: backend
        function onStatusMessage(msg)  { lastStatus = msg; statusTimer.restart() }
        function onErrorOccurred(msg)  { lastStatus = "⚠ " + msg; statusTimer.restart() }
        function onNewSample(t, v, i, p) {
            vcChart.appendTo(0, t, v)
            vcChart.appendTo(1, t, i)
            pwChart.appendTo(0, t, p)
        }
        function onConnectedChanged(connected) {
            if (!connected) {
                vcChart.clearAll()
                pwChart.clearAll()
                window.measureData = null
                window.showMeasure = false
            }
        }
    }

    Timer { id: statusTimer; interval: 5000; onTriggered: lastStatus = "" }

    // ── Fonts ──────────────────────────────────────────────────────────────
    FontMetrics { id: fm }

    // ── Layout ────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Toolbar ───────────────────────────────────────────────────────
        ToolBar {
            Layout.fillWidth: true
            height: 52
            Material.background: "#141c2b"

            RowLayout {
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                anchors.leftMargin: 12; anchors.rightMargin: 12
                spacing: 8

                // App name
                Label {
                    text: "⚡ OpenPS2000"
                    font.pixelSize: 18; font.bold: true
                    color: Material.accent
                }

                // Port selector
                ComboBox {
                    id: portCombo
                    implicitWidth: 160
                    model: backend.availablePorts()
                    enabled: !backend.connected
                    Material.background: "#1e2a3e"
                    onActivated: {}
                    Component.onCompleted: {
                        // Pre-select /dev/ttyACM0 or ttyUSB0 if present
                        for (var i = 0; i < model.length; i++) {
                            if (model[i].indexOf("ttyACM") >= 0 || model[i].indexOf("ttyUSB") >= 0) {
                                currentIndex = i; break
                            }
                        }
                    }
                }

                ToolButton {
                    text: "↻"
                    ToolTip.text: "Refresh port list"; ToolTip.visible: hovered
                    enabled: !backend.connected
                    onClicked: portCombo.model = backend.availablePorts()
                }

                // Connect / Disconnect
                Button {
                    text: backend.connected ? "⏹ Disconnect" : "▶ Connect"
                    highlighted: !backend.connected
                    Material.accent: backend.connected ? Material.Red : Material.Cyan
                    onClicked: {
                        if (backend.connected) backend.disconnectDevice()
                        else if (portCombo.currentText !== "") backend.connectDevice(portCombo.currentText)
                    }
                }

                Item { Layout.fillWidth: true }

                // Remote mode toggle
                RowLayout {
                    spacing: 4
                    enabled: backend.connected
                    Label { text: "Remote"; color: backend.remoteMode ? Material.accent : "#888"; font.pixelSize: 13 }
                    Switch {
                        id: remoteSwitch
                        checked: backend.remoteMode
                        onClicked: backend.setRemoteMode(checked)
                    }
                }

                // Output ON/OFF
                Button {
                    text: backend.outputOn ? "Output ON" : "Output OFF"
                    highlighted: backend.outputOn
                    Material.accent: backend.outputOn ? Material.Green : "#555"
                    enabled: backend.connected && backend.remoteMode
                    onClicked: backend.setOutputOn(!backend.outputOn)
                }

                // Alarm indicators
                Row {
                    spacing: 4
                    visible: backend.anyAlarm

                    Rectangle {
                        width: 36; height: 24; radius: 4
                        color: "#cc2200"
                        visible: backend.ovpActive
                        Label { anchors.centerIn: parent; text: "OVP"; font.pixelSize: 11; font.bold: true; color: "white" }
                    }
                    Rectangle {
                        width: 36; height: 24; radius: 4
                        color: "#cc5500"
                        visible: backend.ocpActive
                        Label { anchors.centerIn: parent; text: "OCP"; font.pixelSize: 11; font.bold: true; color: "white" }
                    }
                    Rectangle {
                        width: 36; height: 24; radius: 4
                        color: "#884400"
                        visible: backend.oppActive
                        Label { anchors.centerIn: parent; text: "OPP"; font.pixelSize: 11; font.bold: true; color: "white" }
                    }
                    Rectangle {
                        width: 36; height: 24; radius: 4
                        color: "#882200"
                        visible: backend.otpActive
                        Label { anchors.centerIn: parent; text: "OTP"; font.pixelSize: 11; font.bold: true; color: "white" }
                    }
                    ToolButton {
                        text: "✕ Ack"
                        ToolTip.text: "Acknowledge all alarms"
                        onClicked: backend.acknowledgeAlarms()
                    }
                }

                // CV/CC badge
                Rectangle {
                    width: 38; height: 24; radius: 4
                    color: backend.ccMode ? "#1a6622" : "#164a70"
                    visible: backend.connected
                    Label {
                        anchors.centerIn: parent
                        text: backend.ccMode ? "CC" : "CV"
                        font.pixelSize: 11; font.bold: true
                        color: backend.ccMode ? "#4eff7a" : Material.accent
                    }
                }

                // Export button
                ToolButton {
                    text: "⬇ Export"
                    ToolTip.text: "Export session data"
                    enabled: backend.sampleCount > 0
                    onClicked: exportMenu.open()
                    Menu {
                        id: exportMenu
                        MenuItem {
                            text: "Export CSV…"
                            onTriggered: csvDialog.open()
                        }
                        MenuItem {
                            text: "Export Excel (.xlsx)…"
                            onTriggered: xlsxDialog.open()
                        }
                    }
                }
            }
        }

        // ── Main area ─────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ── Left sidebar: device info + control ──────────────────────
            Rectangle {
                Layout.fillHeight: true
                width: 280
                color: "#10182a"

                ScrollView {
                    anchors.fill: parent
                    contentWidth: parent.width
                    clip: true

                    ColumnLayout {
                        width: 264
                        anchors { left: parent.left; right: parent.right; leftMargin: 8; rightMargin: 8 }
                        spacing: 6

                        // ── Live readout ──────────────────────────────────
                        Rectangle {
                            Layout.fillWidth: true
                            height: 110
                            radius: 6
                            color: "#0d1b2e"
                            border.color: "#1e3050"

                            ColumnLayout {
                                anchors { fill: parent; margins: 10 }
                                spacing: 2

                                // Voltage
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        text: backend.voltage.toFixed(3) + " V"
                                        font.pixelSize: 28; font.bold: true; font.family: "monospace"
                                        color: "#4dc8ff"
                                        Layout.fillWidth: true
                                    }
                                    Label {
                                        text: "(set: " + backend.setVoltage.toFixed(3) + ")"
                                        font.pixelSize: 11; color: "#5588aa"
                                    }
                                }

                                // Current
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        text: backend.current.toFixed(4) + " A"
                                        font.pixelSize: 22; font.bold: true; font.family: "monospace"
                                        color: "#ff9940"
                                        Layout.fillWidth: true
                                    }
                                    Label {
                                        text: "(set: " + backend.setCurrent.toFixed(4) + ")"
                                        font.pixelSize: 11; color: "#886633"
                                    }
                                }

                                // Power
                                Label {
                                    text: backend.power.toFixed(3) + " W"
                                    font.pixelSize: 18; font.bold: true; font.family: "monospace"
                                    color: "#b068ff"
                                }
                            }
                        }

                        // ── Energy & duration ─────────────────────────────
                        Rectangle {
                            Layout.fillWidth: true
                            height: 64
                            radius: 6; color: "#0d1b2e"; border.color: "#1e3050"

                            ColumnLayout {
                                anchors { fill: parent; margins: 10 }
                                spacing: 2
                                RowLayout {
                                    Label { text: "Energy:"; color: "#99aabb"; font.pixelSize: 12 }
                                    Label {
                                        text: backend.energyWh.toFixed(4) + " Wh"
                                        color: "#ddeecc"; font.pixelSize: 13; font.bold: true
                                    }
                                    ToolButton {
                                        text: "↺"
                                        ToolTip.text: "Reset energy counter"
                                        implicitWidth: 28; implicitHeight: 28
                                        font.pixelSize: 14
                                        onClicked: backend.resetEnergy()
                                    }
                                }
                                RowLayout {
                                    Label { text: "Duration:"; color: "#99aabb"; font.pixelSize: 12 }
                                    Label {
                                        text: backend.duration
                                        color: "#ccddee"; font.pixelSize: 12; font.family: "monospace"
                                    }
                                    Label { text: "  " + backend.sampleCount + " smpl"; color: "#667788"; font.pixelSize: 11 }
                                }
                            }
                        }

                        // ── Section: Set values ────────────────────────────
                        Label {
                            text: "SET VALUES"
                            font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.5
                            color: "#556677"
                            topPadding: 4
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 130
                            radius: 6; color: "#0d1b2e"; border.color: "#1e3050"

                            ColumnLayout {
                                anchors { fill: parent; margins: 10 }
                                spacing: 8

                                // Set Voltage
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: "Voltage"; color: "#99aabb"; font.pixelSize: 12; Layout.preferredWidth: 56 }
                                    SpinBox {
                                        id: setVSpin
                                        Layout.fillWidth: true
                                        from: 0; to: Math.round(backend.nomVoltage * 1000)
                                        stepSize: 100  // 0.1 V steps
                                        value: Math.round(backend.setVoltage * 1000)
                                        editable: true
                                        enabled: backend.connected && backend.remoteMode
                                        textFromValue: function(v) { return (v / 1000.0).toFixed(3) + " V" }
                                        valueFromText: function(t) { return Math.round(parseFloat(t) * 1000) }
                                        validator: DoubleValidator { bottom: 0; top: backend.nomVoltage; decimals: 3 }
                                        onValueModified: applyVTimer.restart()
                                        Timer {
                                            id: applyVTimer; interval: 500
                                            onTriggered: backend.sendSetVoltage(setVSpin.value / 1000.0)
                                        }
                                    }
                                }

                                // Set Current
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: "Current"; color: "#99aabb"; font.pixelSize: 12; Layout.preferredWidth: 56 }
                                    SpinBox {
                                        id: setISpin
                                        Layout.fillWidth: true
                                        from: 0; to: Math.round(backend.nomCurrent * 1000)
                                        stepSize: 10  // 0.01 A steps
                                        value: Math.round(backend.setCurrent * 1000)
                                        editable: true
                                        enabled: backend.connected && backend.remoteMode
                                        textFromValue: function(v) { return (v / 1000.0).toFixed(3) + " A" }
                                        valueFromText: function(t) { return Math.round(parseFloat(t) * 1000) }
                                        validator: DoubleValidator { bottom: 0; top: backend.nomCurrent; decimals: 3 }
                                        onValueModified: applyITimer.restart()
                                        Timer {
                                            id: applyITimer; interval: 500
                                            onTriggered: backend.sendSetCurrent(setISpin.value / 1000.0)
                                        }
                                    }
                                }
                            }
                        }

                        // ── Section: Protection limits ─────────────────────
                        Label {
                            text: "PROTECTION LIMITS"
                            font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.5
                            color: "#556677"
                            topPadding: 4
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: 130
                            radius: 6; color: "#0d1b2e"; border.color: "#1e3050"

                            ColumnLayout {
                                anchors { fill: parent; margins: 10 }
                                spacing: 8

                                // OVP
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: "OVP"; color: "#ff5555"; font.pixelSize: 12; Layout.preferredWidth: 40 }
                                    SpinBox {
                                        id: ovpSpin
                                        Layout.fillWidth: true
                                        from: 0; to: Math.round(backend.nomVoltage * 1.1 * 1000)
                                        stepSize: 100
                                        value: Math.round(backend.ovpVoltage * 1000)
                                        editable: true
                                        enabled: backend.connected && backend.remoteMode
                                        textFromValue: function(v) { return (v / 1000.0).toFixed(3) + " V" }
                                        valueFromText: function(t) { return Math.round(parseFloat(t) * 1000) }
                                        onValueModified: applyOvpTimer.restart()
                                        Timer {
                                            id: applyOvpTimer; interval: 600
                                            onTriggered: backend.sendOvpVoltage(ovpSpin.value / 1000.0)
                                        }
                                    }
                                }

                                // OCP
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label { text: "OCP"; color: "#ff8844"; font.pixelSize: 12; Layout.preferredWidth: 40 }
                                    SpinBox {
                                        id: ocpSpin
                                        Layout.fillWidth: true
                                        from: 0; to: Math.round(backend.nomCurrent * 1.1 * 1000)
                                        stepSize: 10
                                        value: Math.round(backend.ocpCurrent * 1000)
                                        editable: true
                                        enabled: backend.connected && backend.remoteMode
                                        textFromValue: function(v) { return (v / 1000.0).toFixed(3) + " A" }
                                        valueFromText: function(t) { return Math.round(parseFloat(t) * 1000) }
                                        onValueModified: applyOcpTimer.restart()
                                        Timer {
                                            id: applyOcpTimer; interval: 600
                                            onTriggered: backend.sendOcpCurrent(ocpSpin.value / 1000.0)
                                        }
                                    }
                                }
                            }
                        }

                        // ── Device info ────────────────────────────────────
                        Label {
                            text: "DEVICE INFO"
                            font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.5
                            color: "#556677"
                            topPadding: 4
                            visible: backend.deviceType !== ""
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            height: visible ? 130 : 0
                            radius: 6; color: "#0d1b2e"; border.color: "#1e3050"
                            visible: backend.deviceType !== ""

                            ColumnLayout {
                                anchors { fill: parent; margins: 10 }
                                spacing: 2

                                Repeater {
                                    model: [
                                        ["Model",  backend.deviceType],
                                        ["Serial", backend.serialNo],
                                        ["FW",     backend.swVersion],
                                        ["Unom",   backend.nomVoltage.toFixed(1) + " V"],
                                        ["Inom",   backend.nomCurrent.toFixed(2) + " A"],
                                        ["Pnom",   backend.nomPower.toFixed(0) + " W"],
                                    ]
                                    RowLayout {
                                        Label { text: modelData[0] + ":"; color: "#556677"; font.pixelSize: 11; Layout.preferredWidth: 46 }
                                        Label { text: modelData[1]; color: "#aabbcc"; font.pixelSize: 11; elide: Text.ElideRight; Layout.fillWidth: true }
                                    }
                                }
                            }
                        }

                        // ── Chart view options ────────────────────────────
                        Label {
                            text: "CHART"
                            font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.5
                            color: "#556677"
                            topPadding: 4
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Label { text: "Window:"; color: "#99aabb"; font.pixelSize: 12 }
                            ComboBox {
                                id: windowCombo
                                model: ["10 s", "30 s", "60 s", "5 min", "15 min", "1 h"]
                                currentIndex: 2
                                implicitWidth: 80
                                onCurrentIndexChanged: {
                                    var secs = [10, 30, 60, 300, 900, 3600]
                                    window.sharedWindowSecs = secs[currentIndex]
                                }
                            }
                            Item { Layout.fillWidth: true }
                            Label { text: "Follow"; color: "#99aabb"; font.pixelSize: 12 }
                            Switch {
                                checked: window.followMode
                                onCheckedChanged: window.followMode = checked
                                implicitWidth: 44
                            }
                        }

                        Item { height: 12 }  // bottom padding
                    }
                }
            }

            // ── Divider ───────────────────────────────────────────────────
            Rectangle { width: 1; Layout.fillHeight: true; color: "#1e2a3e" }

            // ── Right area: charts + measurement panel ────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // ── V/I chart ─────────────────────────────────────────────
                LiveChart {
                    id: vcChart
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 150

                    title:      "Voltage & Current"
                    leftUnit:   "Voltage (V)"
                    rightUnit:  "Current (A)"
                    followMode: window.followMode
                    effectiveWindowSecs: window.sharedWindowSecs
                    viewLeft: window.sharedViewLeft

                    seriesList: [
                        { name: "Voltage", color: "#4dc8ff", yAxis: "left",  data: [], fillArea: false },
                        { name: "Current", color: "#ff9940", yAxis: "right", data: [], fillArea: false }
                    ]

                    onRangeSelected: (t0, t1) => {
                        measureData = backend.measureRange(t0, t1)
                        showMeasure = measureData !== null && measureData.sampleCount > 0
                        pwChart.selectionStart = t0
                        pwChart.selectionEnd   = t1
                        pwChart.canvas.requestPaint()
                    }
                    onViewChanged: (vl, ws) => {
                        window.sharedViewLeft = vl
                        window.sharedWindowSecs = ws
                    }
                }

                // ── Divider ───────────────────────────────────────────────
                Rectangle { height: 4; Layout.fillWidth: true; color: "#0d1117" }

                // ── Power chart ───────────────────────────────────────────
                LiveChart {
                    id: pwChart
                    Layout.fillWidth: true
                    Layout.preferredHeight: parent.height * 0.35
                    Layout.minimumHeight: 100

                    title:    "Power"
                    leftUnit: "Power (W)"
                    followMode: window.followMode
                    effectiveWindowSecs: window.sharedWindowSecs
                    viewLeft: window.sharedViewLeft

                    seriesList: [
                        { name: "Power", color: "#b068ff", yAxis: "left", data: [], fillArea: true,
                          fillColor: Qt.rgba(0.5, 0.2, 0.8, 0.12) }
                    ]

                    onRangeSelected: (t0, t1) => {
                        measureData = backend.measureRange(t0, t1)
                        showMeasure = measureData !== null && measureData.sampleCount > 0
                        vcChart.selectionStart = t0
                        vcChart.selectionEnd   = t1
                        vcChart.canvas.requestPaint()
                    }
                    onViewChanged: (vl, ws) => {
                        window.sharedViewLeft = vl
                        window.sharedWindowSecs = ws
                    }
                }

                // ── Measurement panel (slides up when range selected) ──────
                Rectangle {
                    id: measurePanel
                    Layout.fillWidth: true
                    height: showMeasure ? 96 : 0
                    clip: true
                    color: "#0e1f38"
                    border.color: "#1e4070"

                    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    RowLayout {
                        anchors { fill: parent; margins: 12 }
                        spacing: 24

                        // Voltage stats
                        ColumnLayout {
                            spacing: 2
                            Label { text: "VOLTAGE"; color: "#4dc8ff"; font.pixelSize: 10; font.letterSpacing: 1 }
                            Label {
                                text: measureData ? (measureData.meanVoltage !== undefined ?
                                    "Mean: " + measureData.meanVoltage.toFixed(3) + " V" : "—") : "—"
                                color: "#aaccee"; font.pixelSize: 12
                            }
                            Label {
                                text: measureData ? (measureData.peakVoltage !== undefined ?
                                    "Peak: " + measureData.peakVoltage.toFixed(3) + " V" : "—") : "—"
                                color: "#7799bb"; font.pixelSize: 12
                            }
                        }

                        // Current stats
                        ColumnLayout {
                            spacing: 2
                            Label { text: "CURRENT"; color: "#ff9940"; font.pixelSize: 10; font.letterSpacing: 1 }
                            Label {
                                text: measureData ? (measureData.meanCurrent !== undefined ?
                                    "Mean: " + measureData.meanCurrent.toFixed(4) + " A" : "—") : "—"
                                color: "#ddaa77"; font.pixelSize: 12
                            }
                            Label {
                                text: measureData ? (measureData.peakCurrent !== undefined ?
                                    "Peak: " + measureData.peakCurrent.toFixed(4) + " A" : "—") : "—"
                                color: "#bb8855"; font.pixelSize: 12
                            }
                        }

                        // Power stats
                        ColumnLayout {
                            spacing: 2
                            Label { text: "POWER"; color: "#b068ff"; font.pixelSize: 10; font.letterSpacing: 1 }
                            Label {
                                text: measureData ? (measureData.meanPower !== undefined ?
                                    "Mean: " + measureData.meanPower.toFixed(3) + " W" : "—") : "—"
                                color: "#cc99ff"; font.pixelSize: 12
                            }
                            Label {
                                text: measureData ? (measureData.peakPower !== undefined ?
                                    "Peak: " + measureData.peakPower.toFixed(3) + " W" : "—") : "—"
                                color: "#9966cc"; font.pixelSize: 12
                            }
                        }

                        // Energy stats
                        ColumnLayout {
                            spacing: 2
                            Label { text: "ENERGY"; color: "#66ddaa"; font.pixelSize: 10; font.letterSpacing: 1 }
                            Label {
                                text: measureData ? (measureData.energyWh !== undefined ?
                                    "Energy: " + (measureData.energyWh * 1000.0).toFixed(3) + " mWh" : "—") : "—"
                                color: "#88ccaa"; font.pixelSize: 12
                            }
                            Label {
                                text: measureData ? (measureData.energyMAh !== undefined ?
                                    "Charge: " + measureData.energyMAh.toFixed(2) + " mAh" : "—") : "—"
                                color: "#66aa88"; font.pixelSize: 12
                            }
                        }

                        // Duration + close
                        ColumnLayout {
                            spacing: 2
                            Label { text: "SELECTION"; color: "#99aabb"; font.pixelSize: 10; font.letterSpacing: 1 }
                            Label {
                                text: measureData ? (measureData.duration !== undefined ?
                                    "Δt: " + measureData.duration.toFixed(1) + " s" : "—") : "—"
                                color: "#aabbcc"; font.pixelSize: 12
                            }
                            Label {
                                text: measureData ? (measureData.sampleCount !== undefined ?
                                    "n: " + measureData.sampleCount : "—") : "—"
                                color: "#778899"; font.pixelSize: 12
                            }
                        }

                        Item { Layout.fillWidth: true }

                        ToolButton {
                            text: "✕ Clear"
                            onClicked: {
                                showMeasure = false
                                vcChart.selectionStart = -1; vcChart.selectionEnd = -1
                                pwChart.selectionStart = -1; pwChart.selectionEnd = -1
                                vcChart.canvas.requestPaint(); pwChart.canvas.requestPaint()
                            }
                        }
                    }
                }
            }
        }

        // ── Status bar ────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            height: 26
            color: "#0a1020"

            RowLayout {
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                spacing: 8

                Label {
                    text: lastStatus
                    color: lastStatus.startsWith("⚠") ? "#ff6655" : "#8899aa"
                    font.pixelSize: 12; elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Label {
                    text: backend.connected ? ("● " + backend.portName) : "○ Not connected"
                    color: backend.connected ? "#4eff90" : "#556677"
                    font.pixelSize: 12
                }
            }
        }
    }

    // ── File dialogs ───────────────────────────────────────────────────────
    Platform.FileDialog {
        id: csvDialog
        title: "Save CSV"
        nameFilters: ["CSV files (*.csv)", "All files (*)"]
        fileMode: Platform.FileDialog.SaveFile
        defaultSuffix: "csv"
        onAccepted: backend.exportCsv(file.toString())
    }

    Platform.FileDialog {
        id: xlsxDialog
        title: "Save Excel"
        nameFilters: ["Excel files (*.xlsx)", "All files (*)"]
        fileMode: Platform.FileDialog.SaveFile
        defaultSuffix: "xlsx"
        onAccepted: backend.exportExcel(file.toString())
    }

    // ── Update spinboxes when backend setpoints change ────────────────────
    Connections {
        target: backend
        function onSetpointsChanged() {
            if (!setVSpin.activeFocus) setVSpin.value = Math.round(backend.setVoltage * 1000)
            if (!setISpin.activeFocus) setISpin.value = Math.round(backend.setCurrent * 1000)
        }
        function onLimitsChanged() {
            if (!ovpSpin.activeFocus) ovpSpin.value = Math.round(backend.ovpVoltage * 1000)
            if (!ocpSpin.activeFocus) ocpSpin.value = Math.round(backend.ocpCurrent * 1000)
        }
    }
}
