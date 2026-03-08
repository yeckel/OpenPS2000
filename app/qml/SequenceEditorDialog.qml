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
    width: 710; height: 560
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

    // ── Column widths (must sum ≤ 670 to fit content margins) ────────────────
    readonly property int cIdx:    30
    readonly property int cV:      92
    readonly property int cI:      92
    readonly property int cHold:   112
    readonly property int cRamp:   52
    readonly property int cRampMs: 112
    readonly property int cAct:    78

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
                    model: [
                        {lbl: "#",          w: root.cIdx},
                        {lbl: qsTr("V (V)"),   w: root.cV},
                        {lbl: qsTr("I (A)"),   w: root.cI},
                        {lbl: qsTr("Hold (ms)"),w: root.cHold},
                        {lbl: qsTr("Ramp"),    w: root.cRamp},
                        {lbl: qsTr("Ramp ms"), w: root.cRampMs},
                        {lbl: "",           w: root.cAct},
                    ]
                    Label {
                        width: modelData.w; text: modelData.lbl
                        color: "#64b5f6"; font.pixelSize: 11; font.bold: true
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
                        }
                        Item { width: 4; height: 1 }

                        // Hold (ms)
                        SpinBox {
                            width: root.cHold - 4; height: 36
                            from: 500; to: 3600000; stepSize: 500
                            Material.theme: Material.Dark; wheelEnabled: true
                            Component.onCompleted: value = root.steps[index].holdMs
                            onValueModified: root.steps[index].holdMs = value
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

        // Bottom row: Add step + CSV
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
                text: qsTr("Import CSV…")
                Material.theme: Material.Dark
                onClicked: importDlg.open()
            }
            Button {
                text: qsTr("Export CSV…")
                Material.theme: Material.Dark
                enabled: root.steps.length > 0
                onClicked: exportDlg.open()
            }
            Button {
                text: qsTr("Export XLSX…")
                Material.theme: Material.Dark
                enabled: root.steps.length > 0
                onClicked: exportXlsxDlg.open()
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
        title: qsTr("Import CSV Sequence")
        fileMode: Platform.FileDialog.OpenFile
        nameFilters: ["CSV files (*.csv)", "All files (*)"]
        onAccepted: {
            if (!seqStore.loadFromFile(file))
                console.warn("CSV import failed:", file)
        }
    }

    Platform.FileDialog {
        id: exportDlg
        title: qsTr("Export Sequence as CSV")
        fileMode: Platform.FileDialog.SaveFile
        defaultSuffix: "csv"
        nameFilters: ["CSV files (*.csv)", "All files (*)"]
        onAccepted: {
            seqStore.saveProfile({name: nameField.text, steps: root.steps}, root.profileIndex)
            var exportIdx = (root.profileIndex >= 0) ? root.profileIndex : (seqStore.count - 1)
            if (!seqStore.saveToFile(exportIdx, file))
                console.warn("CSV export failed:", file)
        }
    }

    Platform.FileDialog {
        id: exportXlsxDlg
        title: qsTr("Export Sequence as Excel")
        fileMode: Platform.FileDialog.SaveFile
        defaultSuffix: "xlsx"
        nameFilters: ["Excel files (*.xlsx)", "All files (*)"]
        onAccepted: {
            seqStore.saveProfile({name: nameField.text, steps: root.steps}, root.profileIndex)
            var exportIdx = (root.profileIndex >= 0) ? root.profileIndex : (seqStore.count - 1)
            if (!seqStore.saveToXlsx(exportIdx, file))
                console.warn("XLSX export failed:", file)
        }
    }
}
