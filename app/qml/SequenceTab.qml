// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls
import QtQuick.Layouts

// ── Sequence / Program Tab ────────────────────────────────────────────────────
// Lets the user build a list of V/I steps (with optional ramps) and execute them.
Rectangle {
    id: root
    color: "#0d1117"

    // ── State ────────────────────────────────────────────────────────────────
    property int    editProfileIdx: -1
    property bool   editMode:       false
    property string editName:       ""
    property var    editSteps:      []   // copy of steps being edited

    function fmtTime(s) {
        var sec = Math.floor(s)
        var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), r = sec % 60
        if (h > 0) return h + "h " + m + "m " + r + "s"
        if (m > 0) return m + "m " + r + "s"
        return r + "s"
    }
    function fmtMs(ms) {
        if (ms >= 60000) return (ms / 60000).toFixed(1) + " min"
        if (ms >= 1000)  return (ms / 1000).toFixed(1) + " s"
        return ms + " ms"
    }
    function totalMs() {
        var t = 0
        for (var i = 0; i < editSteps.length; i++) {
            var s = editSteps[i]
            if (s.ramp) t += s.rampMs
            t += s.holdMs
        }
        return t
    }

    // ── Connections ──────────────────────────────────────────────────────────
    Connections {
        target: sequencer
        function onNewPoint(t, v, i)     { seqChart.addActual(t, v, i) }
        function onPlannedPoint(t, v, i) { seqChart.addPlanned(t, v, i) }
        function onFinished()            { statusLabel.text = qsTr("Sequence complete") }
        function onFaulted(msg)          { statusLabel.text = qsTr("Fault: ") + msg }
        function onStepChanged(step) {
            statusLabel.text = qsTr("Step %1 of %2").arg(step + 1).arg(sequencer.totalSteps)
        }
    }

    // ── Layout ───────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent; spacing: 0

        // ── Left panel ───────────────────────────────────────────────────────
        Rectangle {
            Layout.preferredWidth: 340; Layout.fillHeight: true
            color: "#111820"
            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: "#1e2d3d" }

            // START/STOP bar at bottom
            Rectangle {
                id: startStopBar
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 64; color: "#0d1117"
                Button {
                    anchors { fill: parent; margins: 10 }
                    text: (sequencer.state === 0 || sequencer.state === 3 || sequencer.state === 4)
                          ? qsTr("▶ RUN") : qsTr("■ STOP")
                    font.pixelSize: 15; font.bold: true; highlighted: true
                    Material.theme: Material.Dark
                    Material.accent: (sequencer.state === 0 || sequencer.state === 3 || sequencer.state === 4)
                                     ? "#4caf50" : "#f44336"
                    enabled: backend.connected && seqCombo.currentIndex >= 0 && !editMode
                    onClicked: {
                        if (sequencer.state === 0 || sequencer.state === 3 || sequencer.state === 4) {
                            seqChart.clearAll()
                            statusLabel.text = ""
                            var profile = seqStore.getProfile(seqCombo.currentIndex)
                            sequencer.start(profile.steps)
                        } else {
                            sequencer.stop()
                        }
                    }
                }
            }

            ScrollView {
                anchors { fill: parent; bottomMargin: startStopBar.height }
                contentWidth: availableWidth; clip: true

                ColumnLayout {
                    width: parent.width; spacing: 0

                    // ── Header ─────────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true; height: 48; color: "#0d1117"
                        Label {
                            anchors.centerIn: parent
                            text: "📋 " + qsTr("Sequence Program")
                            font.pixelSize: 14; font.bold: true; color: "#e0e8f0"
                        }
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#1e2d3d" }
                    Item { Layout.fillWidth: true; height: 8 }

                    // ── Profile selector ───────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12
                        spacing: 6
                        ComboBox {
                            id: seqCombo; Layout.fillWidth: true
                            model: seqStore.names
                            Material.theme: Material.Dark
                            enabled: !editMode
                            onCurrentIndexChanged: {
                                if (currentIndex >= 0 && !editMode) loadForView(currentIndex)
                            }
                        }
                        // New
                        RoundButton { text: "+"; Material.theme: Material.Dark; implicitWidth: 36; implicitHeight: 36
                            enabled: !editMode
                            onClicked: {
                                editProfileIdx = -1
                                editName = qsTr("New Sequence")
                                editSteps = [Qt.createQmlObject('import QtQuick 2.0; QtObject{}', root)]
                                editSteps = seqStore.defaultStep ? [seqStore.defaultStep()] : [{voltage:5,current:1,holdMs:5000,ramp:false,rampMs:2000}]
                                editMode = true
                            }
                        }
                        // Edit
                        RoundButton { text: "✏"; Material.theme: Material.Dark; implicitWidth: 36; implicitHeight: 36
                            enabled: !editMode && seqCombo.currentIndex >= 0
                            onClicked: {
                                editProfileIdx = seqCombo.currentIndex
                                var p = seqStore.getProfile(seqCombo.currentIndex)
                                editName = p.name
                                editSteps = JSON.parse(JSON.stringify(p.steps))
                                editMode = true
                            }
                        }
                        // Delete
                        RoundButton { text: "🗑"; Material.theme: Material.Dark; implicitWidth: 36; implicitHeight: 36
                            enabled: !editMode && seqCombo.currentIndex >= 0
                            onClicked: deleteDialog.open()
                        }
                    }

                    // ── Delete confirm ─────────────────────────────────────
                    Dialog {
                        id: deleteDialog
                        parent: Overlay.overlay
                        anchors.centerIn: parent
                        modal: true; title: qsTr("Delete Sequence")
                        Material.theme: Material.Dark
                        standardButtons: Dialog.Yes | Dialog.Cancel
                        Label { text: qsTr("Delete \"%1\"?").arg(seqCombo.currentText); color: "#e0e8f0" }
                        onAccepted: seqStore.deleteProfile(seqCombo.currentIndex)
                    }

                    // ══ Edit mode ══════════════════════════════════════════
                    ColumnLayout {
                        visible: editMode
                        Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; spacing: 4

                        Item { Layout.fillWidth: true; height: 8 }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#2a4a6a" }
                        Item { Layout.fillWidth: true; height: 4 }

                        Label { text: qsTr("Sequence name"); color: "#8899aa"; font.pixelSize: 11 }
                        TextField {
                            id: nameField; Layout.fillWidth: true; text: editName
                            Material.theme: Material.Dark
                            onTextChanged: editName = text
                        }

                        Item { Layout.fillWidth: true; height: 6 }

                        // Step list header
                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: qsTr("Steps"); font.pixelSize: 12; font.bold: true; color: "#64b5f6"; Layout.fillWidth: true }
                            Label { text: qsTr("Total: ") + fmtMs(totalMs()); font.pixelSize: 11; color: "#8899aa" }
                        }

                        // Steps
                        Repeater {
                            id: stepsRepeater
                            model: editSteps.length

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                height: stepCol.implicitHeight + 12
                                color: index % 2 === 0 ? "#0d1822" : "#111e2a"
                                radius: 4
                                border.color: "#1e2d3d"; border.width: 1

                                ColumnLayout {
                                    id: stepCol
                                    anchors { fill: parent; margins: 8 }
                                    spacing: 4

                                    // Step header row
                                    RowLayout {
                                        spacing: 4
                                        Label {
                                            text: qsTr("Step %1").arg(index + 1)
                                            font.pixelSize: 11; font.bold: true; color: "#ce93d8"
                                            Layout.fillWidth: true
                                        }
                                        // Move up
                                        ToolButton { text: "↑"; font.pixelSize: 11; implicitWidth: 28; implicitHeight: 24
                                            enabled: index > 0
                                            onClicked: {
                                                var s = JSON.parse(JSON.stringify(editSteps))
                                                var tmp = s[index]; s[index] = s[index-1]; s[index-1] = tmp
                                                editSteps = s
                                            }
                                        }
                                        // Move down
                                        ToolButton { text: "↓"; font.pixelSize: 11; implicitWidth: 28; implicitHeight: 24
                                            enabled: index < editSteps.length - 1
                                            onClicked: {
                                                var s = JSON.parse(JSON.stringify(editSteps))
                                                var tmp = s[index]; s[index] = s[index+1]; s[index+1] = tmp
                                                editSteps = s
                                            }
                                        }
                                        // Delete step
                                        ToolButton { text: "✕"; font.pixelSize: 11; implicitWidth: 28; implicitHeight: 24
                                            enabled: editSteps.length > 1
                                            onClicked: {
                                                var s = JSON.parse(JSON.stringify(editSteps))
                                                s.splice(index, 1)
                                                editSteps = s
                                            }
                                        }
                                    }

                                    // V / I row
                                    RowLayout {
                                        spacing: 6; Layout.fillWidth: true
                                        ColumnLayout { spacing: 2; Layout.fillWidth: true
                                            Label { text: qsTr("V (V)"); color: "#8899aa"; font.pixelSize: 10 }
                                            SpinBox {
                                                Layout.fillWidth: true; Layout.minimumWidth: 100
                                                from: 0; to: Math.round(backend.nominalVoltage * 1000)
                                                stepSize: 100; value: Math.round(editSteps[index].voltage * 1000)
                                                Material.theme: Material.Dark; wheelEnabled: true
                                                textFromValue: function(v) { return (v/1000).toFixed(2) }
                                                valueFromText: function(t) { return Math.round(parseFloat(t)*1000) }
                                                validator: RegularExpressionValidator { regularExpression: /[0-9]*\.?[0-9]*/ }
                                                onValueModified: {
                                                    var s = JSON.parse(JSON.stringify(editSteps))
                                                    s[index].voltage = value / 1000.0
                                                    editSteps = s
                                                }
                                            }
                                        }
                                        ColumnLayout { spacing: 2; Layout.fillWidth: true
                                            Label { text: qsTr("I (A)"); color: "#8899aa"; font.pixelSize: 10 }
                                            SpinBox {
                                                Layout.fillWidth: true; Layout.minimumWidth: 100
                                                from: 0; to: Math.round(backend.nominalCurrent * 1000)
                                                stepSize: 10; value: Math.round(editSteps[index].current * 1000)
                                                Material.theme: Material.Dark; wheelEnabled: true
                                                textFromValue: function(v) { return (v/1000).toFixed(3) }
                                                valueFromText: function(t) { return Math.round(parseFloat(t)*1000) }
                                                validator: RegularExpressionValidator { regularExpression: /[0-9]*\.?[0-9]*/ }
                                                onValueModified: {
                                                    var s = JSON.parse(JSON.stringify(editSteps))
                                                    s[index].current = value / 1000.0
                                                    editSteps = s
                                                }
                                            }
                                        }
                                    }

                                    // Ramp + hold row
                                    RowLayout {
                                        spacing: 6; Layout.fillWidth: true
                                        CheckBox {
                                            id: rampCheck
                                            text: qsTr("Ramp"); font.pixelSize: 10
                                            checked: editSteps[index].ramp
                                            enabled: index > 0
                                            Material.theme: Material.Dark
                                            onToggled: {
                                                var s = JSON.parse(JSON.stringify(editSteps))
                                                s[index].ramp = checked
                                                editSteps = s
                                            }
                                        }
                                        ColumnLayout {
                                            spacing: 2; Layout.fillWidth: true
                                            visible: editSteps[index].ramp && index > 0
                                            Label { text: qsTr("Ramp (ms)"); color: "#8899aa"; font.pixelSize: 10 }
                                            SpinBox {
                                                Layout.fillWidth: true; Layout.minimumWidth: 90
                                                from: 500; to: 3600000; stepSize: 500
                                                value: editSteps[index].rampMs
                                                Material.theme: Material.Dark; wheelEnabled: true
                                                onValueModified: {
                                                    var s = JSON.parse(JSON.stringify(editSteps))
                                                    s[index].rampMs = value
                                                    editSteps = s
                                                }
                                            }
                                        }
                                        ColumnLayout {
                                            spacing: 2; Layout.fillWidth: true
                                            Label { text: qsTr("Hold (ms)"); color: "#8899aa"; font.pixelSize: 10 }
                                            SpinBox {
                                                Layout.fillWidth: true; Layout.minimumWidth: 90
                                                from: 500; to: 3600000; stepSize: 500
                                                value: editSteps[index].holdMs
                                                Material.theme: Material.Dark; wheelEnabled: true
                                                onValueModified: {
                                                    var s = JSON.parse(JSON.stringify(editSteps))
                                                    s[index].holdMs = value
                                                    editSteps = s
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Add step button
                        Button {
                            Layout.fillWidth: true; text: qsTr("+ Add Step")
                            Material.theme: Material.Dark
                            onClicked: {
                                var s = JSON.parse(JSON.stringify(editSteps))
                                var last = s.length > 0 ? s[s.length-1] : null
                                s.push({voltage: last ? last.voltage : 5.0,
                                        current: last ? last.current : 1.0,
                                        holdMs: 5000, ramp: false, rampMs: 2000})
                                editSteps = s
                            }
                        }

                        // Save / Cancel
                        RowLayout {
                            Layout.fillWidth: true; spacing: 8
                            Button {
                                Layout.fillWidth: true; text: qsTr("Save")
                                highlighted: true; Material.theme: Material.Dark; Material.accent: "#4caf50"
                                enabled: editName.length > 0 && editSteps.length > 0
                                onClicked: {
                                    seqStore.saveProfile({name: editName, steps: editSteps}, editProfileIdx)
                                    editMode = false
                                    seqCombo.currentIndex = editProfileIdx < 0
                                        ? seqStore.count - 1 : editProfileIdx
                                }
                            }
                            Button {
                                Layout.fillWidth: true; text: qsTr("Cancel")
                                Material.theme: Material.Dark
                                onClicked: { editMode = false }
                            }
                        }
                        Item { Layout.fillWidth: true; height: 8 }
                    }

                    // ══ View mode ══════════════════════════════════════════
                    ColumnLayout {
                        visible: !editMode
                        Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; spacing: 2

                        Item { Layout.fillWidth: true; height: 8 }

                        // Step summary list
                        Repeater {
                            model: seqCombo.currentIndex >= 0
                                   ? seqStore.getProfile(seqCombo.currentIndex).steps : []
                            delegate: Rectangle {
                                Layout.fillWidth: true; height: 28; radius: 3
                                color: sequencer.state !== 0 && sequencer.currentStep === index
                                       ? "#1a3050" : (index % 2 === 0 ? "#0d1822" : "#111e2a")
                                border.color: sequencer.state !== 0 && sequencer.currentStep === index
                                              ? "#4fc3f7" : "transparent"
                                border.width: 1
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
                                    Label {
                                        text: (index + 1) + ". " +
                                              modelData.voltage.toFixed(2) + "V / " +
                                              modelData.current.toFixed(3) + "A"
                                        font.pixelSize: 11; color: "#b0bec5"; Layout.fillWidth: true
                                    }
                                    Label {
                                        text: (modelData.ramp ? ("↗" + fmtMs(modelData.rampMs) + " + ") : "") +
                                              fmtMs(modelData.holdMs)
                                        font.pixelSize: 10; color: "#607d8b"
                                    }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true; height: 10 }
                        Rectangle { Layout.fillWidth: true; height: 1; color: "#1e2d3d" }
                        Item { Layout.fillWidth: true; height: 8 }

                        // ── Progress / status ──────────────────────────────
                        Label { text: qsTr("Progress"); font.pixelSize: 11; font.bold: true; color: "#ffb74d" }
                        Item { Layout.fillWidth: true; height: 4 }

                        // Step progress bar
                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Label { text: qsTr("Step:"); color: "#8899aa"; font.pixelSize: 11; implicitWidth: 50 }
                            Rectangle {
                                Layout.fillWidth: true; height: 8; radius: 4; color: "#1e2d3d"
                                Rectangle {
                                    width: parent.width * sequencer.stepProgress
                                    height: parent.height; radius: 4
                                    color: sequencer.state === 1 ? "#ff9800" : "#4caf50"
                                    property var _t: sequencer.tick
                                }
                            }
                        }
                        // Total progress bar
                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Label { text: qsTr("Total:"); color: "#8899aa"; font.pixelSize: 11; implicitWidth: 50 }
                            Rectangle {
                                Layout.fillWidth: true; height: 8; radius: 4; color: "#1e2d3d"
                                Rectangle {
                                    width: parent.width * sequencer.totalProgress
                                    height: parent.height; radius: 4; color: "#64b5f6"
                                    property var _t: sequencer.tick
                                }
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: true; columns: 2; rowSpacing: 4; columnSpacing: 8

                            Label { text: qsTr("Phase:"); color: "#8899aa"; font.pixelSize: 11 }
                            Label { font.pixelSize: 11; font.bold: true
                                color: sequencer.state === 1 ? "#ff9800"
                                     : sequencer.state === 2 ? "#4caf50"
                                     : sequencer.state === 3 ? "#64b5f6" : "#8899aa"
                                text: sequencer.phaseName }

                            Label { text: qsTr("Step:"); color: "#8899aa"; font.pixelSize: 11 }
                            Label { font.pixelSize: 11; color: "#e0e8f0"
                                text: sequencer.totalSteps > 0
                                    ? (sequencer.currentStep + 1) + " / " + sequencer.totalSteps
                                    : "—" }

                            Label { text: qsTr("Elapsed:"); color: "#8899aa"; font.pixelSize: 11 }
                            Label { font.pixelSize: 11; color: "#e0e8f0"
                                text: fmtTime(sequencer.elapsedSecs)
                                property var _t: sequencer.tick }
                        }

                        Label {
                            id: statusLabel
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            font.pixelSize: 11; color: "#64b5f6"; text: ""
                        }

                        Label {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            font.pixelSize: 11; color: "#ef9a9a"
                            visible: !backend.connected
                            text: qsTr("⚠ Device not connected")
                        }

                        Item { Layout.fillWidth: true; height: 16 }
                    }
                }
            }
        }

        // ── Right: chart ─────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true; color: "#0d1117"
            ColumnLayout {
                anchors.fill: parent; spacing: 0
                Rectangle {
                    Layout.fillWidth: true; height: 36; color: "#111820"
                    Label {
                        anchors.centerIn: parent
                        text: qsTr("Sequence Chart")
                        font.pixelSize: 13; font.bold: true; color: "#b0bec5"
                    }
                }
                SequenceChart {
                    id: seqChart
                    Layout.fillWidth: true; Layout.fillHeight: true
                }
            }
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    function loadForView(index) {
        // nothing to do — step list re-evaluates via model binding
    }
}
