// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.platform as Platform

// ── SequenceEditorDialog ──────────────────────────────────────────────────────
// Modal popup for editing sequence steps in a table. Opens via openNew() or
// openEdit(). Saves via seqStore.saveProfile on Accept.
Dialog {
    id: root

    title: qsTr("Edit Sequence")
    modal: true
    width: 860; height: 580
    parent: Overlay.overlay
    anchors.centerIn: parent
    Material.theme: Material.Dark
    closePolicy: Dialog.NoAutoClose

    // ── Public API ────────────────────────────────────────────────────────────
    property int profileIndex: -1   // -1 = new
    property var steps: []          // working copy; mutated in-place by delegates

    signal saved()  // emitted after store is updated

    function openNew() {
        profileIndex = -1
        nameField.text = qsTr("New Sequence")
        steps = [{voltage: 5.0, current: 1.0, holdMs: 5000, ramp: false, rampMs: 2000}]
        open()
    }

    function openEdit(idx) {
        profileIndex = idx
        var p = seqStore.getProfile(idx)
        nameField.text = p.name
        steps = JSON.parse(JSON.stringify(p.steps))
        open()
    }

    // ── Column widths ─────────────────────────────────────────────────────────
    // SpinBox in Material style: buttons ~36px each → input area = width−72.
    // At font 12px, "3600000" ≈ 7 chars × 8px = 56px → need SpinBox ≥ 140px.
    readonly property int cIdx:    32
    readonly property int cV:      108
    readonly property int cI:      108
    readonly property int cHold:   158   // SpinBox width = 154, input area = 82px ✓
    readonly property int cRamp:   60
    readonly property int cRampMs: 158
    readonly property int cAct:    82

    // ── Column header tooltips ────────────────────────────────────────────────
    readonly property var headerModel: [
        {lbl: "#",                 w: root.cIdx,    tip: ""},
        {lbl: qsTr("V (V)"),      w: root.cV,     tip: qsTr("Target output voltage for this step (Volts).")},
        {lbl: qsTr("I (A)"),      w: root.cI,     tip: qsTr("Maximum output current for this step (Amperes).")},
        {lbl: qsTr("Hold (ms)"),  w: root.cHold,  tip: qsTr("How long to hold this setpoint (milliseconds). Example: 5000 = 5 seconds, 60000 = 1 minute.")},
        {lbl: qsTr("Ramp"),       w: root.cRamp,  tip: qsTr("When checked, the output smoothly interpolates from the previous step's values over the ramp duration, rather than switching instantly. Not available on step 1.")},
        {lbl: qsTr("Ramp ms"),    w: root.cRampMs,tip: qsTr("Duration of the smooth transition from the previous step (milliseconds). Only active when Ramp is checked.")},
        {lbl: "",                  w: root.cAct,   tip: ""}
    ]

    // ── Content ───────────────────────────────────────────────────────────────
    contentItem: ColumnLayout {
        spacing: 8
        anchors { fill: parent; margins: 12 }

        // Name row
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Label { text: qsTr("Name:"); color: "#8899aa"; font.pixelSize: 12 }
            TextField {
                id: nameField; Layout.fillWidth: true
                Material.theme: Material.Dark
            }
        }

        // Table header
        Rectangle {
            Layout.fillWidth: true; height: 26; color: "#0a0f15"; radius: 3
            Row {
                anchors { fill: parent; leftMargin: 6 }
                spacing: 0
                Repeater {
                    model: root.headerModel
                    Label {
                        width: modelData.w; text: modelData.lbl
                        color: "#64b5f6"; font.pixelSize: 11; font.bold: true
                        verticalAlignment: Text.AlignVCenter; height: parent.height

                        ToolTip.text: modelData.tip
                        ToolTip.delay: 500
                        ToolTip.timeout: 8000
                        ToolTip.visible: modelData.tip.length > 0 && hdrHover.hovered

                        HoverHandler { id: hdrHover }
                    }
                }
            }
        }

        // Step list
        Rectangle {
            Layout.fillWidth: true; Layout.fillHeight: true
            color: "#0a0f15"; radius: 3; clip: true

            ListView {
                id: listView
                anchors.fill: parent
                model: root.steps.length
                clip: true

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Rectangle {
                    width: listView.width - 8
                    x: 4
                    height: 44
                    color: index % 2 === 0 ? "#0d1822" : "#111e2a"

                    Row {
                        anchors { fill: parent; leftMargin: 6; topMargin: 4; bottomMargin: 4 }
                        spacing: 0

                        // #
                        Label {
                            width: root.cIdx
                            text: index + 1
                            color: "#8899aa"; font.pixelSize: 12
                            verticalAlignment: Text.AlignVCenter; height: parent.height
                        }

                        // V (V)
                        TextField {
                            width: root.cV - 4; height: 36
                            leftPadding: 6; rightPadding: 2; font.pixelSize: 12
                            Material.theme: Material.Dark
                            validator: RegularExpressionValidator { regularExpression: /[0-9]*\.?[0-9]*/ }
                            Component.onCompleted: text = root.steps[index].voltage.toFixed(2)
                            onTextChanged: { var v = parseFloat(text); if (!isNaN(v)) root.steps[index].voltage = v }
                            ToolTip.text: qsTr("Target output voltage (Volts)")
                            ToolTip.delay: 600; ToolTip.timeout: 5000; ToolTip.visible: hovered
                        }
                        Item { width: 4; height: 1 }

                        // I (A)
                        TextField {
                            width: root.cI - 4; height: 36
                            leftPadding: 6; rightPadding: 2; font.pixelSize: 12
                            Material.theme: Material.Dark
                            validator: RegularExpressionValidator { regularExpression: /[0-9]*\.?[0-9]*/ }
                            Component.onCompleted: text = root.steps[index].current.toFixed(2)
                            onTextChanged: { var v = parseFloat(text); if (!isNaN(v)) root.steps[index].current = v }
                            ToolTip.text: qsTr("Maximum output current (Amperes)")
                            ToolTip.delay: 600; ToolTip.timeout: 5000; ToolTip.visible: hovered
                        }
                        Item { width: 4; height: 1 }

                        // Hold (ms)
                        SpinBox {
                            width: root.cHold - 4; height: 36
                            from: 500; to: 3600000; stepSize: 500
                            Material.theme: Material.Dark; wheelEnabled: true
                            Component.onCompleted: value = root.steps[index].holdMs
                            onValueModified: root.steps[index].holdMs = value
                            ToolTip.text: qsTr("How long to hold this setpoint (ms). 1000 = 1 s, 60000 = 1 min.")
                            ToolTip.delay: 600; ToolTip.timeout: 6000; ToolTip.visible: hovered
                        }
                        Item { width: 4; height: 1 }

                        // Ramp checkbox
                        CheckBox {
                            id: rampCb
                            width: root.cRamp; height: 36
                            checked: root.steps[index].ramp
                            enabled: index > 0
                            opacity: index > 0 ? 1 : 0.3
                            Material.theme: Material.Dark
                            onToggled: root.steps[index].ramp = checked
                            ToolTip.text: index === 0
                                ? qsTr("Ramp is not available on the first step — there is no previous setpoint to ramp from.")
                                : qsTr("Smoothly interpolate from the previous step's voltage and current instead of switching instantly.")
                            ToolTip.delay: 500; ToolTip.timeout: 8000; ToolTip.visible: rampHover.hovered
                            HoverHandler { id: rampHover }
                        }

                        // Ramp ms
                        SpinBox {
                            width: root.cRampMs - 4; height: 36
                            from: 500; to: 3600000; stepSize: 500
                            enabled: rampCb.checked && index > 0
                            opacity: enabled ? 1 : 0.3
                            Material.theme: Material.Dark; wheelEnabled: true
                            Component.onCompleted: value = root.steps[index].rampMs
                            onValueModified: root.steps[index].rampMs = value
                            ToolTip.text: qsTr("Duration of the smooth ramp from the previous step (ms). Only used when Ramp is checked.")
                            ToolTip.delay: 600; ToolTip.timeout: 6000; ToolTip.visible: hovered
                        }
                        Item { width: 4; height: 1 }

                        // ↑ ↓ ✕
                        Row {
                            spacing: 0; height: 36
                            ToolButton {
                                text: "↑"; width: 26; height: 36; font.pixelSize: 13
                                enabled: index > 0
                                onClicked: {
                                    var s = JSON.parse(JSON.stringify(root.steps))
                                    var t = s[index]; s[index] = s[index-1]; s[index-1] = t
                                    root.steps = s
                                }
                            }
                            ToolButton {
                                text: "↓"; width: 26; height: 36; font.pixelSize: 13
                                enabled: index < root.steps.length - 1
                                onClicked: {
                                    var s = JSON.parse(JSON.stringify(root.steps))
                                    var t = s[index]; s[index] = s[index+1]; s[index+1] = t
                                    root.steps = s
                                }
                            }
                            ToolButton {
                                text: "✕"; width: 26; height: 36; font.pixelSize: 13
                                enabled: root.steps.length > 1
                                onClicked: {
                                    var s = JSON.parse(JSON.stringify(root.steps))
                                    s.splice(index, 1)
                                    root.steps = s
                                }
                            }
                        }
                    }
                }
            }
        }

        // Bottom row: Add step + Import / Export
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Button {
                text: qsTr("+ Add Step")
                Material.theme: Material.Dark
                onClicked: {
                    var s = JSON.parse(JSON.stringify(root.steps))
                    var last = s.length > 0 ? s[s.length - 1] : null
                    s.push({
                        voltage: last ? last.voltage : 5.0,
                        current: last ? last.current : 1.0,
                        holdMs: 5000, ramp: false, rampMs: 2000
                    })
                    root.steps = s
                }
            }
            Item { Layout.fillWidth: true }
            Button {
                text: qsTr("Import…")
                Material.theme: Material.Dark
                onClicked: importDlg.open()
                ToolTip.text: qsTr("Import steps from a CSV file (replaces current steps).")
                ToolTip.delay: 600; ToolTip.timeout: 5000; ToolTip.visible: hovered
            }
            Button {
                text: qsTr("Export…")
                Material.theme: Material.Dark
                enabled: root.steps.length > 0
                onClicked: exportDlg.open()
                ToolTip.text: qsTr("Export steps to CSV, Excel (.xlsx) or ODF Spreadsheet (.ods). Choose the format via the file-type filter in the save dialog.")
                ToolTip.delay: 600; ToolTip.timeout: 7000; ToolTip.visible: hovered
            }
        }

        // Save / Cancel row
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Item { Layout.fillWidth: true }
            Button {
                text: qsTr("Cancel")
                Material.theme: Material.Dark
                onClicked: root.close()
            }
            Button {
                text: qsTr("Save")
                highlighted: true
                Material.theme: Material.Dark
                Material.accent: "#4caf50"
                enabled: nameField.text.length > 0 && root.steps.length > 0
                onClicked: {
                    seqStore.saveProfile({name: nameField.text, steps: root.steps}, root.profileIndex)
                    root.saved()
                    root.close()
                }
            }
        }
    }

    // ── File dialogs (native via Qt.labs.platform) ────────────────────────────
    Platform.FileDialog {
        id: importDlg
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
            if (ok) { root.close(); root.saved() }
            else importErrorDialog.show(seqStore.lastImportError())
        }
    }

    // ── Import error popup ────────────────────────────────────────────────────
    Dialog {
        id: importErrorDialog
        title: qsTr("Import Failed")
        modal: true; width: 400
        parent: Overlay.overlay
        anchors.centerIn: parent
        Material.theme: Material.Dark
        standardButtons: Dialog.Ok

        property alias message: errorLabel.text
        function show(msg) { message = msg; open() }

        Label {
            id: errorLabel
            width: parent.width
            wrapMode: Text.WordWrap
            color: "#ff7070"
        }
    }

    // Single export dialog — format chosen by extension the user types/selects.
    Platform.FileDialog {
        id: exportDlg
        title: qsTr("Export Sequence")
        fileMode: Platform.FileDialog.SaveFile
        defaultSuffix: "csv"
        nameFilters: [
            qsTr("CSV spreadsheet (*.csv)"),
            qsTr("Excel spreadsheet (*.xlsx)"),
            qsTr("ODF Spreadsheet (*.ods)")
        ]
        onAccepted: {
            // Ensure the working copy is saved first
            seqStore.saveProfile({name: nameField.text, steps: root.steps}, root.profileIndex)
            var exportIdx = (root.profileIndex >= 0) ? root.profileIndex : (seqStore.count - 1)
            var path = file.toString()
            var ext  = path.split('.').pop().toLowerCase()
            if      (ext === "xlsx") seqStore.saveToXlsx(exportIdx, file)
            else if (ext === "ods")  seqStore.saveToOds(exportIdx, file)
            else                     seqStore.saveToFile(exportIdx, file)
        }
    }
}

