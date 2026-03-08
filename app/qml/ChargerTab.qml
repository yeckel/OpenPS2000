// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls
import QtQuick.Layouts
import QtCore

// ── Battery charger tab ──────────────────────────────────────────────────────
Rectangle {
    id: root
    color: "#0d1117"

    // backend and charger are available as global QML context properties

    Settings {
        id: chargerSettings
        property bool disclaimerAccepted: false
    }

    onVisibleChanged: {
        if (visible && !chargerSettings.disclaimerAccepted)
            disclaimerPopup.open()
    }

    // ── Disclaimer ───────────────────────────────────────────────────────────
    Dialog {
        id: disclaimerPopup
        anchors.centerIn: parent
        width: Math.min(480, parent.width - 40)
        modal: true
        closePolicy: Popup.NoAutoClose
        title: "⚠️ " + qsTr("Experimental Feature")

        background: Rectangle {
            color: "#1c2a3a"; radius: 8
            border.color: "#e8a800"; border.width: 2
        }
        header: Rectangle {
            color: "#1c2a3a"; radius: 8
            height: 44
            Label {
                anchors.centerIn: parent
                text: "⚠️ " + qsTr("Experimental Feature")
                font.pixelSize: 15; font.bold: true; color: "#e8a800"
            }
        }

        ColumnLayout {
            width: parent.width
            spacing: 12

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                font.pixelSize: 13
                color: "#d0d8e0"
                text: qsTr("The battery charging feature is <b>experimental</b>.<br><br>" +
                           "Always supervise charging sessions. Never leave batteries unattended " +
                           "while charging. Use proper fusing and fire-resistant containers.<br><br>" +
                           "The author provides this software <b>without any warranty</b> and accepts " +
                           "<b>no liability</b> for damage to equipment, batteries, property or persons " +
                           "resulting from its use.")
            }

            Rectangle {
                Layout.fillWidth: true; height: 1; color: "#2d3d50"
            }

            RowLayout {
                spacing: 8
                CheckBox {
                    id: dontShowAgain
                    text: qsTr("I understand — don't show again")
                    font.pixelSize: 12; Material.theme: Material.Dark
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 8
                Button {
                    text: qsTr("I Accept")
                    Material.theme: Material.Dark
                    Material.accent: "#4caf50"
                    highlighted: true
                    onClicked: {
                        if (dontShowAgain.checked)
                            chargerSettings.disclaimerAccepted = true
                        disclaimerPopup.close()
                    }
                }
                Button {
                    text: qsTr("Go Back")
                    Material.theme: Material.Dark
                    onClicked: disclaimerPopup.close()
                }
            }
        }
    }

    // ── Edit mode state ─────────────────────────────────────────────────────
    property bool  editMode:    false
    property bool  isNewProfile:false
    property int   editIndex:   -1
    // Editable fields
    property string  editName:           ""
    property string  editChemistry:      "LiPo"
    property int     editCells:          1
    property real    editCapacityMah:    1000
    property real    editChargeRateC:    1.0
    property real    editCutoffCurrentC: 0.05
    property real    editCvVoltPerCell:  4.20
    property real    editFloatVoltPerCell:0.0
    property real    editMaxCellVoltage: 4.25
    property real    editDeltavMv:       5.0
    property int     editMaxTimeMin:     120

    // ── Helpers ─────────────────────────────────────────────────────────────
    readonly property var chemistries: ["LiPo", "LiFe", "Pb", "NiCd", "NiMH"]

    function formatTime(secs) {
        var s = Math.floor(secs)
        var h = Math.floor(s / 3600)
        var m = Math.floor((s % 3600) / 60)
        var sec = s % 60
        if (h > 0) return h + "h " + m + "m " + sec + "s"
        if (m > 0) return m + "m " + sec + "s"
        return sec + "s"
    }

    function openEditor(index, isNew) {
        isNewProfile = isNew
        editIndex = index
        editMode = true
        var p = isNew ? charger.defaultsForChemistry("LiPo") : charger.getProfile(index)
        editName           = isNew ? "" : p.name
        editChemistry      = p.chemistry      || "LiPo"
        editCells          = p.cells          || 1
        editCapacityMah    = p.capacityMah    || 1000
        editChargeRateC    = p.chargeRateC    || 1.0
        editCutoffCurrentC = p.cutoffCurrentC || 0.05
        editCvVoltPerCell  = p.cvVoltPerCell  || 4.20
        editFloatVoltPerCell = p.floatVoltPerCell || 0.0
        editMaxCellVoltage = p.maxCellVoltage || 4.25
        editDeltavMv       = p.deltavMvPerCell|| 5.0
        editMaxTimeMin     = p.maxTimeMinutes || 120
    }

    function applyChemistryDefaults(chem) {
        var d = charger.defaultsForChemistry(chem)
        editCvVoltPerCell   = d.cvVoltPerCell
        editFloatVoltPerCell= d.floatVoltPerCell
        editMaxCellVoltage  = d.maxCellVoltage
        editDeltavMv        = d.deltavMvPerCell
        editCutoffCurrentC  = d.cutoffCurrentC
        editChargeRateC     = d.chargeRateC
        editMaxTimeMin      = d.maxTimeMinutes
    }

    function saveEditor() {
        charger.saveProfile({
            "name":             editName,
            "chemistry":        editChemistry,
            "cells":            editCells,
            "capacityMah":      editCapacityMah,
            "chargeRateC":      editChargeRateC,
            "cutoffCurrentC":   editCutoffCurrentC,
            "cvVoltPerCell":    editCvVoltPerCell,
            "floatVoltPerCell": editFloatVoltPerCell,
            "maxCellVoltage":   editMaxCellVoltage,
            "deltavMvPerCell":  editDeltavMv,
            "maxTimeMinutes":   editMaxTimeMin
        }, isNewProfile ? -1 : editIndex)
        editMode = false
    }

    // ── Connections ──────────────────────────────────────────────────────────
    Connections {
        target: charger
        function onNewChargingPoint(t, v, i) { chargingChart.addPoint(t, v, i) }
        function onPhaseMarker(t, stateInt, label) { chargingChart.addPhaseMarker(t, stateInt, label) }
        function onStateChanged() {
            // Clear chart when new session starts (state goes from Idle → CC)
            if (charger.state === 1) chargingChart.clearAll()
        }
    }

    // ── Layout ───────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Left sidebar ─────────────────────────────────────────────────────
        Rectangle {
            Layout.preferredWidth: 310
            Layout.fillHeight: true
            color: "#0a1020"

            ScrollView {
                anchors { left: parent.left; right: parent.right; top: parent.top; bottom: startStopArea.top }
                contentWidth: availableWidth
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: 0

                    // ── Profile selector ──────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        color: "#141c2b"
                        height: profileHeader.height + 16
                        Layout.topMargin: 8

                        ColumnLayout {
                            id: profileHeader
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 6

                            Label {
                                text: qsTr("Battery Profile")
                                color: "#8899aa"; font.pixelSize: 11; font.capitalization: Font.AllUppercase
                            }

                            ComboBox {
                                id: profileCombo
                                Layout.fillWidth: true
                                model: charger.profileNames()
                                Material.theme: Material.Dark

                                Connections {
                                    target: charger
                                    function onProfilesChanged() {
                                        profileCombo.model = charger.profileNames()
                                    }
                                }
                            }

                            RowLayout {
                                spacing: 6
                                Button {
                                    text: qsTr("New")
                                    Material.theme: Material.Dark
                                    font.pixelSize: 12; padding: 6
                                    enabled: charger.state === 0
                                    onClicked: openEditor(-1, true)
                                }
                                Button {
                                    text: qsTr("Edit")
                                    Material.theme: Material.Dark
                                    font.pixelSize: 12; padding: 6
                                    enabled: charger.state === 0 && profileCombo.currentIndex >= 0
                                    onClicked: openEditor(profileCombo.currentIndex, false)
                                }
                                Button {
                                    text: qsTr("Delete")
                                    Material.theme: Material.Dark
                                    font.pixelSize: 12; padding: 6
                                    enabled: charger.state === 0 && profileCombo.currentIndex >= 0
                                    onClicked: deleteConfirm.open()
                                }
                            }
                        }
                    }

                    // ── Profile editor ────────────────────────────────────────
                    Rectangle {
                        visible: editMode
                        Layout.fillWidth: true
                        color: "#10182a"
                        height: visible ? editorColumn.height + 20 : 0

                        ColumnLayout {
                            id: editorColumn
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 4

                            Label {
                                text: isNewProfile ? qsTr("New Profile") : qsTr("Edit Profile")
                                color: "#4dc8ff"; font.pixelSize: 13; font.bold: true
                                Layout.topMargin: 4
                            }

                            // Name
                            Label { text: qsTr("Name"); color: "#8899aa"; font.pixelSize: 11 }
                            TextField {
                                Layout.fillWidth: true
                                text: editName
                                Material.theme: Material.Dark
                                onTextEdited: editName = text
                            }

                            // Chemistry
                            Label { text: qsTr("Chemistry"); color: "#8899aa"; font.pixelSize: 11 }
                            ComboBox {
                                id: chemCombo
                                Layout.fillWidth: true
                                model: root.chemistries
                                currentIndex: root.chemistries.indexOf(editChemistry)
                                Material.theme: Material.Dark
                                onActivated: {
                                    editChemistry = root.chemistries[currentIndex]
                                    applyChemistryDefaults(editChemistry)
                                }
                            }

                            // Cells + Capacity row
                            RowLayout {
                                spacing: 8; Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 2; Layout.preferredWidth: 120
                                    Label { text: qsTr("Cells"); color: "#8899aa"; font.pixelSize: 11 }
                                    SpinBox {
                                        Layout.fillWidth: true; from: 1; to: 24
                                        value: editCells; Material.theme: Material.Dark
                                        wheelEnabled: true
                                        onValueModified: editCells = value
                                    }
                                }
                                ColumnLayout {
                                    spacing: 2; Layout.fillWidth: true
                                    Label { text: qsTr("Capacity (mAh)"); color: "#8899aa"; font.pixelSize: 11 }
                                    SpinBox {
                                        Layout.fillWidth: true; from: 50; to: 100000; stepSize: 100
                                        value: editCapacityMah; Material.theme: Material.Dark
                                        wheelEnabled: true
                                        onValueModified: editCapacityMah = value
                                        textFromValue: function(v) { return v.toString() }
                                    }
                                }
                            }

                            // Charge rate
                            Label { text: qsTr("Charge rate (C) — e.g. 1.0 = 1C"); color: "#8899aa"; font.pixelSize: 11 }
                            SpinBox {
                                Layout.fillWidth: true; from: 1; to: 500; stepSize: 5
                                value: Math.round(editChargeRateC * 100); Material.theme: Material.Dark
                                wheelEnabled: true
                                onValueModified: editChargeRateC = value / 100.0
                                textFromValue: function(v) { return (v/100).toFixed(2) + "C" }
                            }

                            // CV voltage per cell
                            Label { text: qsTr("Target voltage per cell (V)"); color: "#8899aa"; font.pixelSize: 11 }
                            SpinBox {
                                Layout.fillWidth: true; from: 100; to: 500; stepSize: 5
                                value: Math.round(editCvVoltPerCell * 100); Material.theme: Material.Dark
                                wheelEnabled: true
                                onValueModified: editCvVoltPerCell = value / 100.0
                                textFromValue: function(v) { return (v/100).toFixed(2) + " V" }
                            }

                            // Cutoff current (CC/CV only)
                            Label {
                                text: qsTr("Cutoff current (C) — end of CV phase")
                                color: "#8899aa"; font.pixelSize: 11
                                visible: editChemistry !== "NiCd" && editChemistry !== "NiMH"
                            }
                            SpinBox {
                                visible: editChemistry !== "NiCd" && editChemistry !== "NiMH"
                                Layout.fillWidth: true; from: 1; to: 50; stepSize: 1
                                value: Math.round(editCutoffCurrentC * 100); Material.theme: Material.Dark
                                wheelEnabled: true
                                onValueModified: editCutoffCurrentC = value / 100.0
                                textFromValue: function(v) { return (v/100).toFixed(2) + "C" }
                            }

                            // Float voltage (Pb only)
                            Label {
                                text: qsTr("Float voltage per cell (V, 0 = off)")
                                color: "#8899aa"; font.pixelSize: 11
                                visible: editChemistry === "Pb"
                            }
                            SpinBox {
                                visible: editChemistry === "Pb"
                                Layout.fillWidth: true; from: 0; to: 350; stepSize: 5
                                value: Math.round(editFloatVoltPerCell * 100); Material.theme: Material.Dark
                                wheelEnabled: true
                                onValueModified: editFloatVoltPerCell = value / 100.0
                                textFromValue: function(v) { return v === 0 ? qsTr("off") : (v/100).toFixed(2) + " V" }
                            }

                            // -ΔV threshold (NiCd/NiMH only)
                            Label {
                                text: qsTr("–ΔV threshold per cell (mV)")
                                color: "#8899aa"; font.pixelSize: 11
                                visible: editChemistry === "NiCd" || editChemistry === "NiMH"
                            }
                            SpinBox {
                                visible: editChemistry === "NiCd" || editChemistry === "NiMH"
                                Layout.fillWidth: true; from: 1; to: 20
                                value: Math.round(editDeltavMv); Material.theme: Material.Dark
                                wheelEnabled: true
                                onValueModified: editDeltavMv = value
                                textFromValue: function(v) { return v + " mV" }
                            }

                            // OVP per cell
                            Label { text: qsTr("Max cell voltage / OVP (V)"); color: "#8899aa"; font.pixelSize: 11 }
                            SpinBox {
                                Layout.fillWidth: true; from: 100; to: 600; stepSize: 5
                                value: Math.round(editMaxCellVoltage * 100); Material.theme: Material.Dark
                                wheelEnabled: true
                                onValueModified: editMaxCellVoltage = value / 100.0
                                textFromValue: function(v) { return (v/100).toFixed(2) + " V" }
                            }

                            // Timeout
                            Label { text: qsTr("Safety timeout (min)"); color: "#8899aa"; font.pixelSize: 11 }
                            SpinBox {
                                Layout.fillWidth: true; from: 10; to: 1440; stepSize: 10
                                value: editMaxTimeMin; Material.theme: Material.Dark
                                wheelEnabled: true
                                onValueModified: editMaxTimeMin = value
                                textFromValue: function(v) { return v < 60 ? v + " min" : (v/60).toFixed(1) + " h" }
                            }

                            // Save / Cancel
                            RowLayout {
                                spacing: 8; Layout.topMargin: 4; Layout.bottomMargin: 8
                                Button {
                                    text: qsTr("Save")
                                    highlighted: true; Material.theme: Material.Dark
                                    Material.accent: Material.Cyan
                                    font.pixelSize: 12; padding: 8
                                    enabled: editName.length > 0
                                    onClicked: saveEditor()
                                }
                                Button {
                                    text: qsTr("Cancel")
                                    Material.theme: Material.Dark
                                    font.pixelSize: 12; padding: 8
                                    onClicked: editMode = false
                                }
                            }
                        }
                    }

                    // ── Computed profile summary ──────────────────────────────
                    Rectangle {
                        visible: !editMode && profileCombo.currentIndex >= 0
                        Layout.fillWidth: true
                        color: "#0d1420"
                        height: visible ? profileSummary.height + 16 : 0

                        property var prof: profileCombo.currentIndex >= 0
                                           ? charger.getProfile(profileCombo.currentIndex)
                                           : null

                        ColumnLayout {
                            id: profileSummary
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 2

                            Label {
                                text: qsTr("Profile Settings")
                                color: "#8899aa"; font.pixelSize: 11; font.capitalization: Font.AllUppercase
                            }

                            property var p: parent.parent.prof

                            GridLayout {
                                columns: 2; rowSpacing: 1; columnSpacing: 8
                                Layout.fillWidth: true

                                Label { text: qsTr("Chemistry"); color: "#556677"; font.pixelSize: 11 }
                                Label { text: profileSummary.p ? profileSummary.p.chemistry : "—"; color: "#ccd8e8"; font.pixelSize: 11 }

                                Label { text: qsTr("Cells"); color: "#556677"; font.pixelSize: 11 }
                                Label { text: profileSummary.p ? profileSummary.p.cells : "—"; color: "#ccd8e8"; font.pixelSize: 11 }

                                Label { text: qsTr("Capacity"); color: "#556677"; font.pixelSize: 11 }
                                Label {
                                    text: profileSummary.p ? (profileSummary.p.capacityMah >= 1000
                                          ? (profileSummary.p.capacityMah/1000).toFixed(1)+"Ah"
                                          : profileSummary.p.capacityMah+"mAh") : "—"
                                    color: "#ccd8e8"; font.pixelSize: 11
                                }

                                Label { text: qsTr("Charge V"); color: "#556677"; font.pixelSize: 11 }
                                Label {
                                    text: profileSummary.p
                                          ? (profileSummary.p.cells * profileSummary.p.cvVoltPerCell).toFixed(2) + " V"
                                          : "—"
                                    color: "#4dc8ff"; font.pixelSize: 11
                                }

                                Label { text: qsTr("Charge I"); color: "#556677"; font.pixelSize: 11 }
                                Label {
                                    text: profileSummary.p
                                          ? (profileSummary.p.capacityMah / 1000 * profileSummary.p.chargeRateC).toFixed(3) + " A"
                                          : "—"
                                    color: "#ff9940"; font.pixelSize: 11
                                }

                                Label { text: qsTr("OVP"); color: "#556677"; font.pixelSize: 11 }
                                Label {
                                    text: profileSummary.p
                                          ? (profileSummary.p.cells * profileSummary.p.maxCellVoltage).toFixed(2) + " V"
                                          : "—"
                                    color: "#ff6655"; font.pixelSize: 11
                                }
                            }

                            // Warning if exceeds device limits
                            Label {
                                visible: {
                                    if (!profileSummary.p || !backend.connected) return false
                                    var cv = profileSummary.p.cells * profileSummary.p.cvVoltPerCell
                                    var ci = profileSummary.p.capacityMah / 1000 * profileSummary.p.chargeRateC
                                    return cv > backend.nomVoltage || ci > backend.nomCurrent
                                }
                                text: qsTr("⚠ Exceeds device limits!")
                                color: "#ff8833"; font.pixelSize: 11
                                Layout.topMargin: 4
                            }
                        }
                    }

                    // ── Status during charging ────────────────────────────────
                    Rectangle {
                        visible: charger.state !== 0
                        Layout.fillWidth: true
                        color: "#0d1a10"
                        height: visible ? statusColumn.height + 16 : 0

                        ColumnLayout {
                            id: statusColumn
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 2

                            Label {
                                text: qsTr("Charging Status")
                                color: "#8899aa"; font.pixelSize: 11; font.capitalization: Font.AllUppercase
                            }

                            GridLayout {
                                columns: 2; rowSpacing: 2; columnSpacing: 8
                                Layout.fillWidth: true

                                Label { text: qsTr("Phase"); color: "#556677"; font.pixelSize: 12 }
                                Label {
                                    text: charger.stateString
                                    color: {
                                        if (charger.state === 1) return "#4dc8ff"
                                        if (charger.state === 2) return "#ff9940"
                                        if (charger.state === 3) return "#44cc88"
                                        if (charger.state === 4) return "#44ff90"
                                        if (charger.state === 5) return "#ff4444"
                                        return "#aaaaaa"
                                    }
                                    font.pixelSize: 12; font.bold: true
                                }

                                Label { text: qsTr("Elapsed"); color: "#556677"; font.pixelSize: 12 }
                                Label { text: formatTime(charger.elapsedSecs); color: "#ccd8e8"; font.pixelSize: 12 }

                                Label { text: qsTr("Charged"); color: "#556677"; font.pixelSize: 12 }
                                Label {
                                    text: charger.mAhCharged.toFixed(0) + " mAh"
                                    color: "#b068ff"; font.pixelSize: 12; font.bold: true
                                }

                                Label { text: qsTr("Energy"); color: "#556677"; font.pixelSize: 12 }
                                Label { text: charger.whCharged.toFixed(3) + " Wh"; color: "#ccd8e8"; font.pixelSize: 12 }

                                Label { text: qsTr("Peak V"); color: "#556677"; font.pixelSize: 12 }
                                Label { text: charger.peakVoltage.toFixed(3) + " V"; color: "#4dc8ff"; font.pixelSize: 12 }

                                Label { text: qsTr("Peak I"); color: "#556677"; font.pixelSize: 12 }
                                Label { text: charger.peakCurrent.toFixed(3) + " A"; color: "#ff9940"; font.pixelSize: 12 }
                            }

                            // Fault message
                            Label {
                                visible: charger.state === 5
                                text: charger.faultReason
                                color: "#ff4444"; font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }
                    }

                    Item { height: 8 }
                } // end ColumnLayout in ScrollView
            } // end ScrollView

            // ── Start / Stop button ───────────────────────────────────────────
            Rectangle {
                id: startStopArea
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 72
                color: "#0a1020"

                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 1; color: "#1e2a3e"
                }

                Button {
                    anchors.centerIn: parent
                    width: parent.width - 24; height: 52
                    text: charger.state === 0 ? qsTr("▶  START CHARGING") : qsTr("■  STOP CHARGING")
                    font.pixelSize: 14; font.bold: true
                    Material.theme: Material.Dark
                    Material.background: {
                        if (!enabled) return "#223344"
                        return charger.state === 0 ? "#00994d" : "#bb3300"
                    }
                    highlighted: true
                    enabled: backend.connected && !editMode
                             && (charger.state === 0 || (charger.state >= 1 && charger.state <= 3))
                    onClicked: {
                        if (charger.state === 0) {
                            // Safety check
                            var prof = charger.getProfile(profileCombo.currentIndex)
                            if (!prof) return
                            var cv = prof.cells * prof.cvVoltPerCell
                            var ci = prof.capacityMah / 1000 * prof.chargeRateC
                            if (cv > backend.nomVoltage || ci > backend.nomCurrent) {
                                overRangePopup.open()
                                return
                            }
                            charger.startCharging(profileCombo.currentIndex)
                        } else {
                            charger.stopCharging()
                        }
                    }
                }
            }
        }

        // ── Divider ───────────────────────────────────────────────────────────
        Rectangle { width: 1; Layout.fillHeight: true; color: "#1e2a3e" }

        // ── Right: charging chart + completed stats ───────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Not connected hint
            Rectangle {
                visible: !backend.connected
                Layout.fillWidth: true; Layout.fillHeight: true
                color: "transparent"
                Label {
                    anchors.centerIn: parent
                    text: qsTr("Connect to device to start charging")
                    color: "#334455"; font.pixelSize: 16
                }
            }

            ChargingChart {
                id: chargingChart
                visible: backend.connected
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 200
            }

            // ── Completed session summary bar ─────────────────────────────────
            Rectangle {
                visible: charger.state === 4 || charger.state === 5
                Layout.fillWidth: true
                height: 40
                color: charger.state === 4 ? "#0d2010" : "#200d0d"

                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                    spacing: 24

                    Label {
                        text: charger.state === 4 ? qsTr("✓ Completed") : qsTr("✗ Fault")
                        color: charger.state === 4 ? "#44ff90" : "#ff4444"
                        font.pixelSize: 13; font.bold: true
                    }
                    Label {
                        text: charger.mAhCharged.toFixed(0) + " mAh"
                        color: "#b068ff"; font.pixelSize: 13
                    }
                    Label {
                        text: charger.whCharged.toFixed(3) + " Wh"
                        color: "#ccd8e8"; font.pixelSize: 13
                    }
                    Label {
                        text: formatTime(charger.elapsedSecs)
                        color: "#ccd8e8"; font.pixelSize: 13
                    }
                    Label {
                        text: qsTr("Peak: %1 V / %2 A")
                              .arg(charger.peakVoltage.toFixed(2))
                              .arg(charger.peakCurrent.toFixed(2))
                        color: "#8899aa"; font.pixelSize: 13
                    }
                    Item { Layout.fillWidth: true }
                }
            }
        }
    }

    // ── Delete confirmation ───────────────────────────────────────────────────
    Dialog {
        id: deleteConfirm
        title: qsTr("Delete Profile")
        standardButtons: Dialog.Yes | Dialog.No
        modal: true
        anchors.centerIn: parent
        width: 320
        Material.theme: Material.Dark

        Label {
            text: qsTr("Delete profile \"%1\"?").arg(
                  profileCombo.currentIndex >= 0
                  ? (charger.getProfile(profileCombo.currentIndex) || {name:""}).name
                  : "")
            color: "#ccd8e8"; wrapMode: Text.WordWrap
        }
        onAccepted: {
            charger.deleteProfile(profileCombo.currentIndex)
            profileCombo.currentIndex = 0
        }
    }

    // ── Over-range warning ────────────────────────────────────────────────────
    Dialog {
        id: overRangePopup
        title: qsTr("⚠ Profile Exceeds Device Limits")
        standardButtons: Dialog.Ok
        modal: true
        anchors.centerIn: parent
        width: 380
        Material.theme: Material.Dark

        Label {
            text: qsTr("The selected profile requires voltage or current beyond this device's rated limits.\n"
                       + "Please edit the profile or choose a different one.")
            color: "#ff8833"; wrapMode: Text.WordWrap; width: 300
        }
    }
}
