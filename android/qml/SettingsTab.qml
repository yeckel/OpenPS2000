// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls
import QtQuick.Layouts
import QtCore

// ── Settings / Connection Tab ─────────────────────────────────────────────
// USB device picker, REST URL entry, connect/disconnect.
Rectangle {
    color: "#0d1117"

    // Persist last-used connection settings
    property string savedRestUrl:   restUrlField.text
    property bool   usbTabSelected: connectionTabs.currentIndex === 0

    // ── USB permission request ────────────────────────────────────────────
    function requestUsbPermission() {
        // Calls Java: UsbSerial.requestPermission(context, pendingIntent)
        // Handled natively; the permission result triggers open() automatically.
        // On Qt for Android, we trigger via the backendFactory.
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: parent.width
            spacing: 0

            Item { Layout.fillWidth: true; height: 16 }

            // ── Connection type tabs ──────────────────────────────────────
            TabBar {
                id: connectionTabs
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                Material.background: "#111820"

                TabButton { text: qsTr("USB (Direct)"); font.pixelSize: 13 }
                TabButton { text: qsTr("REST (Network)"); font.pixelSize: 13 }
            }

            Item { Layout.fillWidth: true; height: 12 }

            // ── USB panel ─────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                spacing: 8
                visible: connectionTabs.currentIndex === 0

                // Poll for USB permission grant after requesting it
                Timer {
                    id: permissionPollTimer
                    interval: 500; repeat: true
                    onTriggered: {
                        if (backendFactory.isUsbPermissionGranted()) {
                            stop()
                            usbStatusLabel.text = qsTr("✅ USB access granted — tap Connect")
                            usbStatusLabel.color = "#81c784"
                            // Re-scan so device appears in list
                            usbDeviceModel.clear()
                            var devs = backendFactory.listUsbDevices()
                            for (var i = 0; i < devs.length; i++) {
                                var parts = devs[i].split("|")
                                usbDeviceModel.append({ "display": parts.length > 1 ? parts[1] : devs[i],
                                                        "devName": parts[0] })
                            }
                            if (usbDeviceModel.count > 0)
                                usbDeviceList.currentIndex = 0
                        }
                    }
                }

                Label {
                    text: qsTr("Connect via USB OTG cable")
                    font.pixelSize: 13; font.bold: true; color: "#64b5f6"
                }
                Label {
                    text: qsTr("Plug the EA-PS into your phone's USB-C port\n(USB OTG / Host adapter required)")
                    font.pixelSize: 12; color: "#8899aa"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                // Permission banner — shown when EA device found but no permission
                Rectangle {
                    Layout.fillWidth: true
                    height: 48; radius: 8
                    visible: usbDeviceModel.count === 0 && !backendFactory.hasUsbPermission()
                             && permissionPollTimer.running
                    color: "#1a1a00"; border.color: "#888800"; border.width: 1
                    Label {
                        anchors { fill: parent; margins: 10 }
                        text: qsTr("⏳ Waiting for USB permission — please tap Allow in the system dialog")
                        font.pixelSize: 12; color: "#cccc44"
                        wrapMode: Text.WordWrap
                    }
                }

                // Status label for scan / permission feedback
                Label {
                    id: usbStatusLabel
                    Layout.fillWidth: true
                    visible: text.length > 0
                    font.pixelSize: 12; color: "#8899aa"
                    wrapMode: Text.WordWrap
                }

                // Device list
                Label {
                    text: qsTr("Detected devices")
                    font.pixelSize: 12; color: "#8899aa"
                    visible: usbDeviceModel.count > 0
                }

                ListView {
                    id: usbDeviceList
                    Layout.fillWidth: true
                    height: Math.min(contentHeight, 160)
                    visible: usbDeviceModel.count > 0
                    clip: true
                    model: ListModel { id: usbDeviceModel }

                    delegate: ItemDelegate {
                        width: ListView.view.width
                        text: model.display
                        font.pixelSize: 12
                        Material.theme: Material.Dark
                        highlighted: usbDeviceList.currentIndex === index
                        onClicked: usbDeviceList.currentIndex = index
                    }
                }

                Label {
                    visible: usbDeviceModel.count === 0 && !permissionPollTimer.running
                    text: qsTr("No EA-PS devices found.\nPlug in via OTG cable and tap Scan.")
                    font.pixelSize: 12; color: "#607d8b"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    spacing: 8

                    Button {
                        text: qsTr("🔍 Scan")
                        Material.theme: Material.Dark
                        onClicked: {
                            permissionPollTimer.stop()
                            usbStatusLabel.text = ""
                            usbDeviceModel.clear()
                            var devs = backendFactory.listUsbDevices()
                            for (var i = 0; i < devs.length; i++) {
                                var parts = devs[i].split("|")
                                usbDeviceModel.append({ "display": parts.length > 1 ? parts[1] : devs[i],
                                                        "devName": parts[0] })
                            }
                            if (usbDeviceModel.count > 0) {
                                usbDeviceList.currentIndex = 0
                                // Check / request permission
                                if (!backendFactory.hasUsbPermission()) {
                                    backendFactory.requestUsbPermission()
                                    usbStatusLabel.text = qsTr("⏳ Requesting USB access — tap Allow in the dialog…")
                                    usbStatusLabel.color = "#cccc44"
                                    permissionPollTimer.start()
                                } else {
                                    usbStatusLabel.text = qsTr("✅ USB access already granted")
                                    usbStatusLabel.color = "#81c784"
                                }
                            } else {
                                usbStatusLabel.text = qsTr("No EA-PS device found. Check OTG cable.")
                                usbStatusLabel.color = "#ef9a9a"
                            }
                        }
                    }

                    Button {
                        text: qsTr("🔌 Connect")
                        highlighted: true
                        Material.theme: Material.Dark; Material.accent: "#4caf50"
                        enabled: !backend.connected && usbDeviceModel.count > 0
                                 && backendFactory.hasUsbPermission()
                        onClicked: {
                            permissionPollTimer.stop()
                            var devName = usbDeviceList.currentIndex >= 0
                                ? usbDeviceModel.get(usbDeviceList.currentIndex).devName
                                : ""
                            backendFactory.switchToUsb(devName)
                        }
                    }
                }
            }

            // ── REST panel ────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                spacing: 8
                visible: connectionTabs.currentIndex === 1

                Label {
                    text: qsTr("Connect to a running OpenPS2000 server")
                    font.pixelSize: 13; font.bold: true; color: "#64b5f6"
                }
                Label {
                    text: qsTr("Start OpenPS2000 on the PC with REST enabled\n(Settings → Remote → REST API toggle ON)")
                    font.pixelSize: 12; color: "#8899aa"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Label { text: qsTr("Server address"); font.pixelSize: 12; color: "#8899aa" }
                TextField {
                    id: restUrlField
                    Layout.fillWidth: true
                    text:             restSettings.restUrl
                    placeholderText:  "192.168.1.x or hostname"
                    font.pixelSize:   15; color: "#e0e8f0"
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
                    background: Rectangle {
                        color: "#111820"; radius: 8
                        border.color: "#1e4060"; border.width: 1
                    }
                    onTextChanged: restSettings.restUrl = text
                }

                Label { text: qsTr("Bearer token (optional)"); font.pixelSize: 12; color: "#8899aa" }
                TextField {
                    id: tokenField
                    Layout.fillWidth: true
                    text:             restSettings.restToken
                    placeholderText:  qsTr("Leave empty for no auth")
                    font.pixelSize:   14; color: "#e0e8f0"
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                    echoMode:         TextInput.PasswordEchoOnEdit
                    background: Rectangle {
                        color: "#111820"; radius: 8
                        border.color: "#1e2d3d"; border.width: 1
                    }
                    onTextChanged: restSettings.restToken = text
                }

                Button {
                    Layout.fillWidth: true
                    text: qsTr("🌐 Connect via REST")
                    highlighted: true
                    Material.theme: Material.Dark; Material.accent: "#64b5f6"
                    enabled: !backend.connected && restSettings.restUrl.length > 0
                    onClicked: backendFactory.switchToRest(restUrlField.text)
                }
            }

            Item { Layout.fillWidth: true; height: 16 }
            Rectangle { Layout.fillWidth: true; height: 1; color: "#1e2d3d" }
            Item { Layout.fillWidth: true; height: 12 }

            // ── Connected status + Disconnect ─────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 16; Layout.rightMargin: 16
                height: 72; radius: 10
                color: backend.connected ? "#0d2a1a" : "#111820"
                border.color: backend.connected ? "#2e7d32" : "#1e2d3d"; border.width: 1

                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 12

                    Rectangle {
                        width: 12; height: 12; radius: 6
                        color: backend.connected ? "#4caf50" : "#616161"
                    }
                    ColumnLayout {
                        spacing: 2; Layout.fillWidth: true
                        Label {
                            text: backend.connected
                                  ? qsTr("Connected — %1").arg(backend.deviceType || (backendFactory.isRemote ? "REST" : "USB"))
                                  : qsTr("Disconnected")
                            font.pixelSize: 14; font.bold: true
                            color: backend.connected ? "#81c784" : "#757575"
                        }
                        Label {
                            visible: backend.connected
                            text: backendFactory.isRemote
                                  ? qsTr("REST: %1").arg(restUrlField.text)
                                  : qsTr("USB: %1 V / %2 A").arg(backend.nomVoltage.toFixed(0)).arg(backend.nomCurrent.toFixed(0))
                            font.pixelSize: 11; color: "#4a7a4a"
                        }
                    }
                    Button {
                        text: qsTr("Disconnect")
                        visible: backend.connected
                        Material.theme: Material.Dark; Material.accent: "#ef5350"
                        onClicked: backendFactory.disconnect()
                    }
                }
            }

            Item { Layout.fillWidth: true; height: 24 }
        }
    }

    // Persist REST settings
    Settings {
        id: restSettings
        category: "android_connection"
        property string restUrl:   ""
        property string restToken: ""
    }
}
