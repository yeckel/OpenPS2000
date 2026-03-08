// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Qt.labs.platform as Platform

// ── Sequence / Program Tab ────────────────────────────────────────────────────
Rectangle {
    id: root
    color: "#0d1117"

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

    // ── Editor dialog ─────────────────────────────────────────────────────────
    SequenceEditorDialog {
        id: editorDialog
        onSaved: {
            // Select the newly created / edited profile
            seqCombo.currentIndex = (editorDialog.profileIndex >= 0)
                ? editorDialog.profileIndex
                : seqStore.count - 1
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
                    enabled: backend.connected && seqCombo.currentIndex >= 0
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
                        }
                        RoundButton {
                            text: "+"; width: 36; height: 36; Material.theme: Material.Dark
                            ToolTip.visible: hovered; ToolTip.text: qsTr("New sequence")
                            onClicked: editorDialog.openNew()
                        }
                        RoundButton {
                            text: "✏"; width: 36; height: 36; Material.theme: Material.Dark
                            enabled: seqCombo.currentIndex >= 0
                            ToolTip.visible: hovered; ToolTip.text: qsTr("Edit sequence")
                            onClicked: editorDialog.openEdit(seqCombo.currentIndex)
                        }
                        RoundButton {
                            text: "🗑"; width: 36; height: 36; Material.theme: Material.Dark
                            enabled: seqCombo.currentIndex >= 0
                            ToolTip.visible: hovered; ToolTip.text: qsTr("Delete sequence")
                            onClicked: deleteDialog.open()
                        }
                    }

                    // Import / Export row
                    RowLayout {
                        Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12
                        Layout.topMargin: 4; spacing: 6
                        Button {
                            Layout.fillWidth: true; text: qsTr("Import…")
                            font.pixelSize: 11; Material.theme: Material.Dark
                            onClicked: importOnlyDlg.open()
                            ToolTip.text: qsTr("Import steps from a CSV file")
                            ToolTip.delay: 600; ToolTip.timeout: 5000; ToolTip.visible: hovered
                        }
                        Button {
                            Layout.fillWidth: true; text: qsTr("Export…")
                            font.pixelSize: 11; Material.theme: Material.Dark
                            enabled: seqCombo.currentIndex >= 0
                            onClicked: exportOnlyDlg.open()
                            ToolTip.text: qsTr("Export to CSV, Excel or ODF Spreadsheet — choose format via the file-type filter.")
                            ToolTip.delay: 600; ToolTip.timeout: 6000; ToolTip.visible: hovered
                        }
                    }

                    // ── Delete confirm ─────────────────────────────────────
                    Dialog {
                        id: deleteDialog
                        parent: Overlay.overlay
                        anchors.centerIn: parent
                        width: 320; modal: true
                        title: qsTr("Delete Sequence")
                        Material.theme: Material.Dark
                        standardButtons: Dialog.Yes | Dialog.Cancel
                        Label {
                            text: qsTr("Delete \"%1\"?").arg(seqCombo.currentText)
                            color: "#e0e8f0"; wrapMode: Text.WordWrap; width: parent.width
                        }
                        onAccepted: seqStore.deleteProfile(seqCombo.currentIndex)
                    }

                    // ── File dialogs (native via Qt.labs.platform) ────────────
                    Platform.FileDialog {
                        id: importOnlyDlg
                        title: qsTr("Import Sequence")
                        fileMode: Platform.FileDialog.OpenFile
                        nameFilters: [
                            qsTr("All supported (*.csv *.xlsx *.ods)"),
                            qsTr("CSV spreadsheet (*.csv)"),
                            qsTr("Excel spreadsheet (*.xlsx)"),
                            qsTr("ODF Spreadsheet (*.ods)"),
                            "All files (*)"
                        ]
                        onAccepted: {
                            var path = file.toString()
                            var ext  = path.split('.').pop().toLowerCase()
                            var ok
                            if      (ext === "xlsx") ok = seqStore.loadFromXlsx(file)
                            else if (ext === "ods")  ok = seqStore.loadFromOds(file)
                            else                     ok = seqStore.loadFromFile(file)
                            if (ok) seqCombo.currentIndex = seqStore.count - 1
                            else tabImportErrorDialog.show(seqStore.lastImportError())
                        }
                    }

                    // Import error popup
                    Dialog {
                        id: tabImportErrorDialog
                        title: qsTr("Import Failed")
                        modal: true; width: 400
                        parent: Overlay.overlay
                        anchors.centerIn: parent
                        Material.theme: Material.Dark
                        standardButtons: Dialog.Ok
                        property alias message: tabErrorLabel.text
                        function show(msg) { message = msg; open() }
                        Label {
                            id: tabErrorLabel
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: "#ff7070"
                        }
                    }
                    Platform.FileDialog {
                        id: exportOnlyDlg
                        title: qsTr("Export Sequence")
                        fileMode: Platform.FileDialog.SaveFile
                        defaultSuffix: "csv"
                        nameFilters: [
                            qsTr("CSV spreadsheet (*.csv)"),
                            qsTr("Excel spreadsheet (*.xlsx)"),
                            qsTr("ODF Spreadsheet (*.ods)")
                        ]
                        onAccepted: {
                            var path = file.toString()
                            var ext  = path.split('.').pop().toLowerCase()
                            if      (ext === "xlsx") seqStore.saveToXlsx(seqCombo.currentIndex, file)
                            else if (ext === "ods")  seqStore.saveToOds(seqCombo.currentIndex, file)
                            else                     seqStore.saveToFile(seqCombo.currentIndex, file)
                        }
                    }

                    // ── Step summary list ──────────────────────────────────
                    Item { Layout.fillWidth: true; height: 10 }
                    Rectangle { Layout.fillWidth: true; height: 1; color: "#1e2d3d" }
                    Item { Layout.fillWidth: true; height: 6 }

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
                                          modelData.current.toFixed(2) + "A"
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

                    // ── Progress / status ──────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true; Layout.leftMargin: 12; Layout.rightMargin: 12; spacing: 4

                        Label { text: qsTr("Progress"); font.pixelSize: 11; font.bold: true; color: "#ffb74d" }
                        Item { Layout.fillWidth: true; height: 2 }

                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Label { text: qsTr("Step:"); color: "#8899aa"; font.pixelSize: 11; Layout.preferredWidth: 50 }
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
                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Label { text: qsTr("Total:"); color: "#8899aa"; font.pixelSize: 11; Layout.preferredWidth: 50 }
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
                                    ? (sequencer.currentStep + 1) + " / " + sequencer.totalSteps : "—" }

                            Label { text: qsTr("Elapsed:"); color: "#8899aa"; font.pixelSize: 11 }
                            Label { font.pixelSize: 11; color: "#e0e8f0"
                                text: fmtTime(sequencer.elapsedSecs)
                                property var _t: sequencer.tick }
                        }

                        Label {
                            id: statusLabel
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            font.pixelSize: 11; color: "#64b5f6"
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
}
