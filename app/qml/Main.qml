// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
// Main.qml — OpenPS2000 main window
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Platform
import QtCore

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

    onClosing: (close) => {
        if (trayManager.minimizeToTray) {
            close.accepted = false
            trayManager.hideToTray()
        }
    }

    Connections {
        target: trayManager
        function onShowRequested() { trayManager.showWindow() }
    }

    // ── Shared chart state ─────────────────────────────────────────────────
    property real sharedWindowSecs: 60
    property real sharedViewLeft:   0
    property bool followMode:       true

    // ── Persistent settings ────────────────────────────────────────────────
    Settings {
        id: appSettings
        category: "ui"
        property string lastPort: ""
    }

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
                statsPopup.clearAndClose()
            }
        }
        function onAlarmTriggered(ovp, ocp, opp, otp) {
            alarmPopup.ovp = ovp; alarmPopup.ocp = ocp
            alarmPopup.opp = opp; alarmPopup.otp = otp
            alarmPopup.open()
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

                // App name — click to open About
                Label {
                    text: "⚡ OpenPS2000"
                    font.pixelSize: 18; font.bold: true
                    color: appNameHover.containsMouse ? "#80ddff" : Material.accent
                    Behavior on color { ColorAnimation { duration: 100 } }
                    ToolTip.text: qsTr("About & device info"); ToolTip.visible: appNameHover.containsMouse
                    MouseArea {
                        id: appNameHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: aboutPopup.open()
                    }
                }

                // Remote mode badge
                Rectangle {
                    visible: isRemoteMode
                    color: "#1a3a5a"; border.color: "#4488bb"; border.width: 1; radius: 4
                    width: remoteLabel.implicitWidth + 12; height: 22
                    Label {
                        id: remoteLabel
                        anchors.centerIn: parent
                        text: qsTr("REMOTE")
                        font.pixelSize: 10; font.bold: true; font.letterSpacing: 1
                        color: "#88ccff"
                    }
                    ToolTip.text: backend.remoteUrl ?? ""
                    ToolTip.visible: remoteBadgeHover.containsMouse
                    MouseArea { id: remoteBadgeHover; anchors.fill: parent; hoverEnabled: true }
                }

                // Port selector
                ComboBox {
                    id: portCombo
                    implicitWidth: 160
                    model: backend.availablePorts()
                    enabled: !backend.connected
                    Material.background: "#1e2a3e"
                    onActivated: appSettings.lastPort = currentText
                    Component.onCompleted: {
                        // Restore last-used port; fall back to first ttyACM/ttyUSB
                        var saved = appSettings.lastPort
                        for (var i = 0; i < model.length; i++) {
                            if (model[i] === saved) { currentIndex = i; return }
                        }
                        for (var j = 0; j < model.length; j++) {
                            if (model[j].indexOf("ttyACM") >= 0 || model[j].indexOf("ttyUSB") >= 0
                                || model[j].indexOf("COM") >= 0) {
                                currentIndex = j; return
                            }
                        }
                    }
                }

                ToolButton {
                    text: "↻"
                    ToolTip.text: qsTr("Refresh port list"); ToolTip.visible: hovered
                    enabled: !backend.connected
                    onClicked: portCombo.model = backend.availablePorts()
                }

                // Connect / Disconnect
                Button {
                    text: backend.connected ? "⏹ " + qsTr("Disconnect") : "▶ " + qsTr("Connect")
                    highlighted: !backend.connected
                    Material.accent: backend.connected ? Material.Red : Material.Cyan
                    onClicked: {
                        if (backend.connected) backend.disconnectDevice()
                        else if (portCombo.currentText !== "") {
                            appSettings.lastPort = portCombo.currentText
                            backend.connectDevice(portCombo.currentText)
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Remote mode toggle
                RowLayout {
                    spacing: 4
                    enabled: backend.connected
                    Label { text: qsTr("Remote"); color: backend.remoteMode ? Material.accent : "#888"; font.pixelSize: 13 }
                    Switch {
                        id: remoteSwitch
                        checked: backend.remoteMode
                        onClicked: backend.setRemoteMode(checked)
                    }
                }

                // Output ON/OFF — confirmation when turning on
                Button {
                    text: backend.outputOn ? qsTr("Output ON") : qsTr("Output OFF")
                    highlighted: backend.outputOn
                    Material.accent: backend.outputOn ? Material.Green : "#555"
                    enabled: backend.connected && backend.remoteMode
                    ToolTip.text: backend.outputOn ? qsTr("Turn off output  [Space]") : qsTr("Turn on output  [Space]")
                    ToolTip.visible: hovered
                    onClicked: {
                        if (backend.outputOn) backend.setOutputOn(false)
                        else if (window.skipOutputConfirm) backend.setOutputOn(true)
                        else outputConfirmDialog.open()
                    }
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
                        ToolTip.text: qsTr("Acknowledge all alarms")
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
                    ToolTip.text: qsTr("Export session data")
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

                // Scrollable controls — stops above the E-stop button
                ScrollView {
                    anchors { top: parent.top; left: parent.left; right: parent.right; bottom: estopArea.top }
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
                                    Label { text: qsTr("Energy:"); color: "#99aabb"; font.pixelSize: 12 }
                                    Label {
                                        text: backend.energyWh.toFixed(4) + " Wh"
                                        color: "#ddeecc"; font.pixelSize: 13; font.bold: true
                                    }
                                    ToolButton {
                                        text: "↺"
                                        ToolTip.text: qsTr("Reset energy counter")
                                        implicitWidth: 28; implicitHeight: 28
                                        font.pixelSize: 14
                                        onClicked: backend.resetEnergy()
                                    }
                                }
                                RowLayout {
                                    Label { text: qsTr("Duration:"); color: "#99aabb"; font.pixelSize: 12 }
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
                            text: qsTr("SET VALUES")
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
                                    Label { text: qsTr("Voltage"); color: "#99aabb"; font.pixelSize: 12; Layout.preferredWidth: 56 }
                                    SpinBox {
                                        id: setVSpin
                                        Layout.fillWidth: true
                                        from: 0; to: Math.round(backend.nomVoltage * 1000)
                                        stepSize: 100  // 0.1 V steps
                                        value: Math.round(backend.setVoltage * 1000)
                                        editable: true
                                        wheelEnabled: true
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
                                    Label { text: qsTr("Current"); color: "#99aabb"; font.pixelSize: 12; Layout.preferredWidth: 56 }
                                    SpinBox {
                                        id: setISpin
                                        Layout.fillWidth: true
                                        from: 0; to: Math.round(backend.nomCurrent * 1000)
                                        stepSize: 10  // 0.01 A steps
                                        value: Math.round(backend.setCurrent * 1000)
                                        editable: true
                                        wheelEnabled: true
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
                            text: qsTr("PROTECTION LIMITS")
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
                                        wheelEnabled: true
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
                                        wheelEnabled: true
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
                            text: qsTr("DEVICE INFO")
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
                                        [qsTr("Model"),  backend.deviceType],
                                        [qsTr("Serial"), backend.serialNo],
                                        [qsTr("FW"),     backend.swVersion],
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
                            text: qsTr("CHART")
                            font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.5
                            color: "#556677"
                            topPadding: 4
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Label { text: qsTr("Window:"); color: "#99aabb"; font.pixelSize: 12 }
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
                            Label { text: qsTr("Follow"); color: "#99aabb"; font.pixelSize: 12 }
                            Switch {
                                checked: window.followMode
                                onCheckedChanged: window.followMode = checked
                                implicitWidth: 44
                            }
                        }

                        Item { height: 8 }  // bottom padding
                    }
                }

                // ── Emergency Stop ────────────────────────────────────────
                Rectangle {
                    id: estopArea
                    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                    height: 116
                    color: "#080e1a"

                    Rectangle {
                        anchors.top: parent.top
                        width: parent.width; height: 1
                        color: "#1e2a3e"
                    }

                    // Outer glow ring (always rendered, opacity changes)
                    Rectangle {
                        anchors.centerIn: parent
                        width: 96; height: 96; radius: 48
                        color: "transparent"
                        border.color: "#ff2222"
                        border.width: estopMa.containsMouse && estopBtn.enabled ? 4 : 2
                        opacity:      estopBtn.enabled ? (estopMa.containsMouse ? 0.7 : 0.3) : 0.1
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        Behavior on border.width { NumberAnimation { duration: 80 } }
                    }

                    // Button body
                    Rectangle {
                        id: estopBtn
                        anchors.centerIn: parent
                        width: 80; height: 80; radius: 40
                        color: {
                            if (!enabled) return "#2a0a0a"
                            if (estopMa.pressed)       return "#881010"
                            if (estopMa.containsMouse) return "#dd1515"
                            return "#bb1111"
                        }
                        border.color: enabled ? "#ff4444" : "#440000"
                        border.width: 2
                        enabled: backend.connected && backend.remoteMode

                        Behavior on color { ColorAnimation { duration: 80 } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 1
                            Label {
                                text: "⏻"
                                font.pixelSize: 30; font.bold: true
                                color: estopBtn.enabled ? "white" : "#553333"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Label {
                                text: qsTr("E-STOP")
                                font.pixelSize: 9; font.bold: true; font.letterSpacing: 2
                                color: estopBtn.enabled ? "#ffaaaa" : "#441111"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }

                        MouseArea {
                            id: estopMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: parent.enabled
                            cursorShape: Qt.ForbiddenCursor
                            onClicked: {
                                backend.setOutputOn(false)
                                lastStatus = qsTr("⚠ Emergency stop — output disabled")
                            }
                        }
                    }
                }
            }

            // ── Divider ───────────────────────────────────────────────────
            Rectangle { width: 1; Layout.fillHeight: true; color: "#1e2a3e" }

            // ── Right area: tabs (Live Monitor + Battery Charger) ────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // ── Tab bar ───────────────────────────────────────────────
                TabBar {
                    id: mainTabBar
                    Layout.fillWidth: true
                    Material.theme: Material.Dark
                    background: Rectangle { color: "#0a1020" }

                    TabButton {
                        text: qsTr("⚡ Live Monitor")
                        Material.theme: Material.Dark
                        font.pixelSize: 13
                    }
                    TabButton {
                        text: qsTr("🔋 Battery Charger")
                        Material.theme: Material.Dark
                        font.pixelSize: 13
                    }
                    TabButton {
                        text: qsTr("〰 Pulse / Cycle")
                        Material.theme: Material.Dark
                        font.pixelSize: 13
                    }
                    TabButton {
                        text: qsTr("📋 Sequence")
                        Material.theme: Material.Dark
                        font.pixelSize: 13
                    }
                }

                Rectangle { height: 1; Layout.fillWidth: true; color: "#1e2a3e" }

                // ── Tab content ───────────────────────────────────────────
                StackLayout {
                    id: mainStack
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: mainTabBar.currentIndex

                    // ── Tab 0: Live Monitor ───────────────────────────────
                    ColumnLayout {
                        spacing: 0

                        // ── V/I chart ─────────────────────────────────────────
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
                        statsPopup.openWithData(t0, t1)
                        pwChart.selectionStart = t0
                        pwChart.selectionEnd   = t1
                        pwChart.repaint()
                    }
                    onSelectionCleared: {
                        pwChart.selectionStart = -1; pwChart.selectionEnd = -1
                        pwChart.repaint(); statsPopup.clearAndClose()
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
                        statsPopup.openWithData(t0, t1)
                        vcChart.selectionStart = t0
                        vcChart.selectionEnd   = t1
                        vcChart.repaint()
                    }
                    onSelectionCleared: {
                        vcChart.selectionStart = -1; vcChart.selectionEnd = -1
                        vcChart.repaint(); statsPopup.clearAndClose()
                    }
                    onViewChanged: (vl, ws) => {
                        window.sharedViewLeft = vl
                        window.sharedWindowSecs = ws
                    }
                }

                    } // end Tab 0: Live Monitor ColumnLayout

                    // ── Tab 1: Battery Charger ────────────────────────────
                    ChargerTab {
                    }

                    // ── Tab 2: Pulse / Cycle Generator ────────────────────
                    PulseTab {
                    }

                    // ── Tab 3: Sequence Program ───────────────────────────
                    SequenceTab {
                    }

                } // end StackLayout
            } // end outer right ColumnLayout
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
                    text: backend.connected ? ("● " + backend.portName) : qsTr("○ Not connected")
                    color: backend.connected ? "#4eff90" : "#556677"
                    font.pixelSize: 12
                }
            }
        }
    }

    // ── Output confirmation preference ────────────────────────────────────
    property bool skipOutputConfirm: false

    // ── Keyboard shortcuts ─────────────────────────────────────────────────
    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        onActivated: {
            // Only act as E-stop when no popup/dialog is consuming Escape
            if (!aboutPopup.visible && !statsPopup.visible && !outputConfirmDialog.visible) {
                if (backend.connected && backend.remoteMode && backend.outputOn) {
                    backend.setOutputOn(false)
                    window.lastStatus = qsTr("⚠ Emergency stop — output disabled  [Esc]")
                }
            }
        }
    }

    Shortcut {
        sequence: "Space"
        context: Qt.WindowShortcut
        onActivated: {
            if (!backend.connected || !backend.remoteMode) return
            if (backend.outputOn) backend.setOutputOn(false)
            else if (window.skipOutputConfirm) backend.setOutputOn(true)
            else outputConfirmDialog.open()
        }
    }

    Shortcut {
        sequence: "Ctrl+Up"
        context: Qt.WindowShortcut
        onActivated: {
            if (!backend.connected || !backend.remoteMode) return
            setVSpin.value = Math.min(setVSpin.to, setVSpin.value + setVSpin.stepSize)
            applyVTimer.restart()
        }
    }

    Shortcut {
        sequence: "Ctrl+Down"
        context: Qt.WindowShortcut
        onActivated: {
            if (!backend.connected || !backend.remoteMode) return
            setVSpin.value = Math.max(setVSpin.from, setVSpin.value - setVSpin.stepSize)
            applyVTimer.restart()
        }
    }

    Shortcut {
        sequence: "Ctrl+Right"
        context: Qt.WindowShortcut
        onActivated: {
            if (!backend.connected || !backend.remoteMode) return
            setISpin.value = Math.min(setISpin.to, setISpin.value + setISpin.stepSize)
            applyITimer.restart()
        }
    }

    Shortcut {
        sequence: "Ctrl+Left"
        context: Qt.WindowShortcut
        onActivated: {
            if (!backend.connected || !backend.remoteMode) return
            setISpin.value = Math.max(setISpin.from, setISpin.value - setISpin.stepSize)
            applyITimer.restart()
        }
    }

    // ── Output-on confirmation dialog ──────────────────────────────────────
    Dialog {
        id: outputConfirmDialog
        title: qsTr("Enable Output?")
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        standardButtons: Dialog.Yes | Dialog.No

        // Enter / Y confirms; N or Escape cancels
        Shortcut {
            sequence: "Return";     enabled: outputConfirmDialog.visible
            onActivated: outputConfirmDialog.accept()
        }
        Shortcut {
            sequence: "Y";          enabled: outputConfirmDialog.visible
            onActivated: outputConfirmDialog.accept()
        }
        Shortcut {
            sequence: "N";          enabled: outputConfirmDialog.visible
            onActivated: outputConfirmDialog.reject()
        }

        onAccepted: {
            if (dontShowCheck.checked) window.skipOutputConfirm = true
            backend.setOutputOn(true)
        }

        contentItem: ColumnLayout {
            spacing: 10

            Label {
                text: qsTr("Turn on output with current setpoints:")
                color: "#dde8f8"; font.pixelSize: 13
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.preferredWidth: 300
            }

            Rectangle {
                Layout.fillWidth: true
                height: 68; radius: 5
                color: "#0d1b2e"; border.color: "#2a5090"

                ColumnLayout {
                    anchors { fill: parent; margins: 10 }
                    spacing: 4
                    Label {
                        text: qsTr("Voltage:  %1 V").arg(backend.setVoltage.toFixed(3))
                        color: "#4dc8ff"; font.pixelSize: 15; font.family: "monospace"; font.bold: true
                    }
                    Label {
                        text: qsTr("I limit:  %1 A").arg(backend.setCurrent.toFixed(4))
                        color: "#ff9940"; font.pixelSize: 15; font.family: "monospace"; font.bold: true
                    }
                }
            }

            Label {
                text: qsTr("⚠  Verify the load can safely handle these settings.")
                color: "#ffaa44"; font.pixelSize: 11
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }

            CheckBox {
                id: dontShowCheck
                text: qsTr("Don't show again for this session")
                checked: false
                Material.accent: Material.Cyan
                contentItem: Label {
                    leftPadding: dontShowCheck.indicator.width + dontShowCheck.spacing
                    text: dontShowCheck.text
                    color: "#99aabb"; font.pixelSize: 11
                    verticalAlignment: Text.AlignVCenter
                }
            }

            Label {
                text: qsTr("Enter / Y = Yes   ·   N / Esc = No")
                color: "#556677"; font.pixelSize: 10; font.family: "monospace"
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }

    // ── About / Device info popup ──────────────────────────────────────────
    Popup {
        id: aboutPopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        padding: 0
        modal: true
        dim: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: "#0e1f38"; border.color: "#2a5090"; border.width: 1; radius: 8
        }

        contentItem: ColumnLayout {
            spacing: 0
            implicitWidth: 380

            // Title bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Label {
                    text: "⚡  OpenPS2000"
                    color: "#4dc8ff"; font.pixelSize: 16; font.bold: true
                    leftPadding: 16; topPadding: 14; bottomPadding: 10
                }
                Item { Layout.fillWidth: true }
                ToolButton {
                    text: "✕"; font.pixelSize: 13
                    implicitWidth: 32; implicitHeight: 32
                    onClicked: aboutPopup.close()
                }
            }

            Rectangle { height: 1; Layout.fillWidth: true; color: "#1e4070" }

            // App info
            ColumnLayout {
                Layout.margins: 16
                spacing: 4

                Repeater {
                    model: [
                        [qsTr("Version"),  "1.0.0"],
                        [qsTr("License"),  "GNU GPL v3.0"],
                        [qsTr("Author"),   "Libor Tomsik, OK1CHP"],
                    ]
                    RowLayout {
                        spacing: 8
                        Label { text: modelData[0] + ":"; color: "#556677"; font.pixelSize: 12; Layout.preferredWidth: 70 }
                        Label { text: modelData[1]; color: "#aabbcc"; font.pixelSize: 12 }
                    }
                }

                RowLayout {
                    spacing: 8
                    Label { text: qsTr("Source") + ":"; color: "#556677"; font.pixelSize: 12; Layout.preferredWidth: 70 }
                    Label {
                        text: "github.com/yeckel/OpenPS2000"
                        color: "#4dc8ff"; font.pixelSize: 12
                        font.underline: ghLinkHover.containsMouse
                        MouseArea {
                            id: ghLinkHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Qt.openUrlExternally("https://github.com/yeckel/OpenPS2000")
                        }
                    }
                }

                RowLayout {
                    spacing: 8
                    Layout.topMargin: 4
                    Label { text: qsTr("Shortcuts") + ":"; color: "#556677"; font.pixelSize: 12; Layout.preferredWidth: 70 }
                    Column {
                        spacing: 2
                        Label { text: qsTr("Escape — Emergency stop (output off)"); color: "#8899aa"; font.pixelSize: 11; font.family: "monospace" }
                        Label { text: qsTr("Space  — Toggle output (with confirmation)"); color: "#8899aa"; font.pixelSize: 11; font.family: "monospace" }
                        Label { text: qsTr("Ctrl+↑/↓ — Voltage ±0.1 V"); color: "#8899aa"; font.pixelSize: 11; font.family: "monospace" }
                        Label { text: qsTr("Ctrl+←/→ — Current ±0.01 A"); color: "#8899aa"; font.pixelSize: 11; font.family: "monospace" }
                    }
                }

                RowLayout {
                    spacing: 8
                    Layout.topMargin: 4
                    Label { text: qsTr("Language") + ":"; color: "#556677"; font.pixelSize: 12; Layout.preferredWidth: 70 }
                    ComboBox {
                        model: langChanger.languageDisplayNames()
                        currentIndex: langChanger.availableLanguages().indexOf(langChanger.currentLanguage)
                        onActivated: langChanger.setLanguage(langChanger.availableLanguages()[currentIndex])
                        implicitWidth: 130
                    }
                }
            }

            // Device section (visible when connected)
            ColumnLayout {
                visible: backend.connected
                spacing: 0
                Layout.fillWidth: true

                Rectangle { height: 1; Layout.fillWidth: true; color: "#1e4070" }

                Label {
                    text: qsTr("CONNECTED DEVICE")
                    font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.5
                    color: "#556677"
                    leftPadding: 16; topPadding: 10; bottomPadding: 6
                }

                GridLayout {
                    columns: 2
                    rowSpacing: 4
                    columnSpacing: 8
                    Layout.leftMargin: 16
                    Layout.rightMargin: 16
                    Layout.bottomMargin: 14

                    Repeater {
                        model: [
                            [qsTr("Model"),        backend.deviceType],
                            [qsTr("Article No."),  backend.articleNo],
                            [qsTr("Serial No."),   backend.serialNo],
                            [qsTr("Firmware"),     backend.swVersion],
                            [qsTr("Nom. Voltage"), backend.nomVoltage.toFixed(1) + " V"],
                            [qsTr("Nom. Current"), backend.nomCurrent.toFixed(2) + " A"],
                            [qsTr("Nom. Power"),   backend.nomPower.toFixed(0) + " W"],
                            [qsTr("Samples"),      backend.sampleCount + "  " + qsTr("(session)")],
                        ]
                        Label { text: modelData[0] + ":"; color: "#556677"; font.pixelSize: 12 }
                        Label { text: modelData[1]; color: "#aabbcc"; font.pixelSize: 12 }
                    }
                }
            }

            // Remote control section (local mode only)
            ColumnLayout {
                visible: !isRemoteMode
                spacing: 0
                Layout.fillWidth: true

                Rectangle { height: 1; Layout.fillWidth: true; color: "#1e4070" }

                RemoteSettingsPanel {
                    Layout.fillWidth: true
                    remoteServer: isRemoteMode ? null : remoteServer
                    mqttClient:   isRemoteMode ? null : mqttClient
                }
            }
        }
    }

    // ── Range statistics popup ─────────────────────────────────────────────
    Popup {
        id: statsPopup
        parent: Overlay.overlay
        x: Math.round(window.width  - width  - 20)
        y: Math.round(54 + 12)
        padding: 0
        modal: false
        dim:   false
        closePolicy: Popup.CloseOnEscape

        // Simple scalar properties avoid QVariantMap binding pitfalls
        property int  statsSamples:  0
        property real statsDuration: 0
        property real statsMeanV:    0;  property real statsMinV: 0;  property real statsMaxV: 0
        property real statsMeanI:    0;  property real statsMinI: 0;  property real statsMaxI: 0
        property real statsMeanP:    0;  property real statsMinP: 0;  property real statsMaxP: 0
        property real statsEnergyWh: 0
        property real statsEnergyMAh: 0

        function openWithData(t0, t1) {
            var r = backend.measureRange(t0, t1)
            if (!r || r.sampleCount <= 0) return
            statsSamples   = r.sampleCount
            statsDuration  = r.duration     || 0
            statsMeanV     = r.meanVoltage  || 0
            statsMinV      = r.minVoltage   || 0
            statsMaxV      = r.peakVoltage  || 0
            statsMeanI     = r.meanCurrent  || 0
            statsMinI      = r.minCurrent   || 0
            statsMaxI      = r.peakCurrent  || 0
            statsMeanP     = r.meanPower    || 0
            statsMinP      = r.minPower     || 0
            statsMaxP      = r.peakPower    || 0
            statsEnergyWh  = r.energyWh     || 0
            statsEnergyMAh = r.energyMAh    || 0
            open()
        }

        function clearAndClose() {
            close()
            vcChart.selectionStart = -1; vcChart.selectionEnd = -1
            pwChart.selectionStart = -1; pwChart.selectionEnd = -1
            vcChart.repaint(); pwChart.repaint()
        }

        background: Rectangle {
            color: "#0e1f38"
            border.color: "#2a5090"
            border.width: 1
            radius: 6
        }

        contentItem: ColumnLayout {
            spacing: 0

            // Title bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Label {
                    text: qsTr("📊  Range Analysis")
                    color: "#dde8f8"; font.pixelSize: 13; font.bold: true
                    leftPadding: 12; topPadding: 8; bottomPadding: 6
                }
                Item { Layout.fillWidth: true }
                Label {
                    text: qsTr("Δt %1 s   n = %2").arg(statsPopup.statsDuration.toFixed(1)).arg(statsPopup.statsSamples)
                    color: "#8899aa"; font.pixelSize: 11
                    topPadding: 8; rightPadding: 4
                }
                ToolButton {
                    text: "✕"
                    implicitWidth: 30; implicitHeight: 30
                    font.pixelSize: 13
                    onClicked: statsPopup.clearAndClose()
                }
            }

            Rectangle { height: 1; Layout.fillWidth: true; color: "#1e4070" }

            // Stats grid
            GridLayout {
                columns: 4
                rowSpacing: 4
                columnSpacing: 20
                Layout.margins: 12
                Layout.topMargin: 8
                Layout.bottomMargin: 10

                // Column headers
                Label { text: qsTr("VOLTAGE"); color: "#4dc8ff"; font.pixelSize: 10; font.letterSpacing: 1 }
                Label { text: qsTr("CURRENT"); color: "#ff9940"; font.pixelSize: 10; font.letterSpacing: 1 }
                Label { text: qsTr("POWER");   color: "#b068ff"; font.pixelSize: 10; font.letterSpacing: 1 }
                Label { text: qsTr("ENERGY");  color: "#66ddaa"; font.pixelSize: 10; font.letterSpacing: 1 }

                // Mean row
                Label { text: qsTr("Mean  %1 V").arg(statsPopup.statsMeanV.toFixed(3)); color: "#aaccee"; font.pixelSize: 12; font.family: "monospace" }
                Label { text: qsTr("Mean  %1 A").arg(statsPopup.statsMeanI.toFixed(4)); color: "#ddaa77"; font.pixelSize: 12; font.family: "monospace" }
                Label { text: qsTr("Mean  %1 W").arg(statsPopup.statsMeanP.toFixed(3)); color: "#cc99ff"; font.pixelSize: 12; font.family: "monospace" }
                Label { text: (statsPopup.statsEnergyWh * 1000.0).toFixed(3) + " mWh"; color: "#88ccaa"; font.pixelSize: 12; font.family: "monospace" }

                // Min row
                Label { text: qsTr("Min   %1 V").arg(statsPopup.statsMinV.toFixed(3)); color: "#7799bb"; font.pixelSize: 12; font.family: "monospace" }
                Label { text: qsTr("Min   %1 A").arg(statsPopup.statsMinI.toFixed(4)); color: "#bb8855"; font.pixelSize: 12; font.family: "monospace" }
                Label { text: qsTr("Min   %1 W").arg(statsPopup.statsMinP.toFixed(3)); color: "#9966cc"; font.pixelSize: 12; font.family: "monospace" }
                Label { text: statsPopup.statsEnergyMAh.toFixed(3) + " mAh"; color: "#66aa88"; font.pixelSize: 12; font.family: "monospace" }

                // Max row
                Label { text: qsTr("Max   %1 V").arg(statsPopup.statsMaxV.toFixed(3)); color: "#7799bb"; font.pixelSize: 12; font.family: "monospace" }
                Label { text: qsTr("Max   %1 A").arg(statsPopup.statsMaxI.toFixed(4)); color: "#bb8855"; font.pixelSize: 12; font.family: "monospace" }
                Label { text: qsTr("Max   %1 W").arg(statsPopup.statsMaxP.toFixed(3)); color: "#9966cc"; font.pixelSize: 12; font.family: "monospace" }
                Item {}
            }
        }
    }

    // ── Alarm popup ────────────────────────────────────────────────────────
    Dialog {
        id: alarmPopup
        title: qsTr("⚠ Protection Alarm Triggered")
        modal: true
        width: 420
        anchors.centerIn: parent
        Material.theme: Material.Dark
        closePolicy: Popup.NoAutoClose   // user must acknowledge

        property bool ovp: false
        property bool ocp: false
        property bool opp: false
        property bool otp: false

        ColumnLayout {
            spacing: 12
            width: parent.width

            // Active alarm badges
            RowLayout {
                spacing: 8
                Rectangle {
                    visible: alarmPopup.ovp
                    width: 48; height: 28; radius: 5; color: "#cc2200"
                    Label { anchors.centerIn: parent; text: "OVP"; font.bold: true; color: "white" }
                }
                Rectangle {
                    visible: alarmPopup.ocp
                    width: 48; height: 28; radius: 5; color: "#cc5500"
                    Label { anchors.centerIn: parent; text: "OCP"; font.bold: true; color: "white" }
                }
                Rectangle {
                    visible: alarmPopup.opp
                    width: 48; height: 28; radius: 5; color: "#884400"
                    Label { anchors.centerIn: parent; text: "OPP"; font.bold: true; color: "white" }
                }
                Rectangle {
                    visible: alarmPopup.otp
                    width: 48; height: 28; radius: 5; color: "#882200"
                    Label { anchors.centerIn: parent; text: "OTP"; font.bold: true; color: "white" }
                }
            }

            Label {
                text: {
                    var msgs = []
                    if (alarmPopup.ovp) msgs.push(qsTr("OVP — Over-Voltage Protection: output voltage exceeded the set limit."))
                    if (alarmPopup.ocp) msgs.push(qsTr("OCP — Over-Current Protection: output current exceeded the set limit."))
                    if (alarmPopup.opp) msgs.push(qsTr("OPP — Over-Power Protection: output power exceeded the set limit."))
                    if (alarmPopup.otp) msgs.push(qsTr("OTP — Over-Temperature Protection: device is too hot."))
                    return msgs.join("\n")
                }
                color: "#ffcc88"; font.pixelSize: 13
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Label {
                text: qsTr("The output has been turned off. Remove the fault condition, then acknowledge the alarm to resume operation.")
                color: "#8899aa"; font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RowLayout {
                spacing: 12
                Layout.topMargin: 4

                Button {
                    text: qsTr("Acknowledge Alarm")
                    highlighted: true
                    Material.theme: Material.Dark
                    Material.accent: Material.Cyan
                    onClicked: {
                        backend.acknowledgeAlarms()
                        alarmPopup.close()
                    }
                }
                Button {
                    text: qsTr("Close")
                    Material.theme: Material.Dark
                    onClicked: alarmPopup.close()
                }
            }
        }
    }

    // ── File dialogs ───────────────────────────────────────────────────────
    Platform.FileDialog {
        id: csvDialog
        title: qsTr("Save CSV")
        nameFilters: ["CSV files (*.csv)", "All files (*)"]
        fileMode: Platform.FileDialog.SaveFile
        defaultSuffix: "csv"
        onAccepted: backend.exportCsv(file.toString())
    }

    Platform.FileDialog {
        id: xlsxDialog
        title: qsTr("Save Excel")
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
