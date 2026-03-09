// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
// RemoteSettingsPanel.qml — REST API + MQTT configuration panel.
import QtQuick
import QtQuick.Controls.Material
import QtQuick.Controls
import QtQuick.Layouts
import QtCore

ColumnLayout {
    id: root
    spacing: 0

    // remoteServer and mqttClient are accessed directly from QML context properties
    // (no required property — using same name would cause a binding loop)

    // ── Persistent settings ─────────────────────────────────────────────
    Settings {
        id: remoteSettings
        category: "remote"
        property string restPort:    "8484"
        property bool restEnabled: false
        property bool mqttEnabled: false
        property string mqttHost:   "localhost"
        property string mqttPort:   "1883"
        property string mqttPrefix: "openps2000"
        property string mqttUser:   ""
        property bool   mqttTls:    false
    }

    // ── REST API section ─────────────────────────────────────────────────
    Label {
        text: "REST API"
        font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.5
        color: "#556677"
        leftPadding: 16; topPadding: 14; bottomPadding: 6
    }

    ColumnLayout {
        Layout.leftMargin: 16
        Layout.rightMargin: 16
        Layout.bottomMargin: 8
        spacing: 8

        RowLayout {
            spacing: 8
            Label { text: qsTr("Enable REST API"); color: "#aabbcc"; font.pixelSize: 13; Layout.fillWidth: true }
            Switch {
                id: restSwitch
                checked: remoteSettings.restEnabled
                onCheckedChanged: {
                    remoteSettings.restEnabled = checked
                    if (checked && remoteServer)
                        remoteServer.start(parseInt(restPortField.text) || 8484, restTokenField.text)
                    else if (!checked && remoteServer)
                        remoteServer.stop()
                }
            }
        }

        RowLayout {
            spacing: 8
            Label { text: qsTr("Port"); color: "#556677"; font.pixelSize: 12; Layout.preferredWidth: 60 }
            TextField {
                id: restPortField
                text: remoteSettings.restPort
                onTextChanged: remoteSettings.restPort = text
                enabled: !(remoteServer && remoteServer.running)
                implicitWidth: 80
                color: "#aabbcc"
                placeholderText: "8484"
                inputMethodHints: Qt.ImhDigitsOnly
                background: Rectangle { color: "#0a1525"; border.color: "#2a4060"; radius: 4 }
            }
        }

        RowLayout {
            spacing: 8
            Label { text: qsTr("Token"); color: "#556677"; font.pixelSize: 12; Layout.preferredWidth: 60 }
            TextField {
                id: restTokenField
                placeholderText: qsTr("(optional bearer token)")
                echoMode: TextInput.Password
                Layout.fillWidth: true
                color: "#aabbcc"
                placeholderTextColor: "#445566"
                background: Rectangle { color: "#0a1525"; border.color: "#2a4060"; radius: 4 }
            }
        }

        // Status indicator
        RowLayout {
            spacing: 6
            Rectangle {
                width: 8; height: 8; radius: 4
                color: (remoteServer && remoteServer.running) ? "#44cc66" : "#cc4444"
            }
            Label {
                text: (remoteServer && remoteServer.running)
                      ? qsTr("Running on port %1").arg(remoteServer.port)
                      : qsTr("Stopped")
                color: "#7799bb"; font.pixelSize: 11
            }
        }
    }

    Rectangle { height: 1; Layout.fillWidth: true; color: "#1e4070" }

    // ── MQTT section ─────────────────────────────────────────────────────
    Label {
        text: "MQTT"
        font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.5
        color: "#556677"
        leftPadding: 16; topPadding: 14; bottomPadding: 6
    }

    ColumnLayout {
        Layout.leftMargin: 16
        Layout.rightMargin: 16
        Layout.bottomMargin: 14
        spacing: 8

        RowLayout {
            spacing: 8
            Label { text: qsTr("Enable MQTT"); color: "#aabbcc"; font.pixelSize: 13; Layout.fillWidth: true }
            Switch {
                id: mqttSwitch
                checked: remoteSettings.mqttEnabled
                onCheckedChanged: remoteSettings.mqttEnabled = checked
            }
        }

        RowLayout {
            spacing: 8
            enabled: mqttSwitch.checked
            Label { text: qsTr("Host"); color: "#556677"; font.pixelSize: 12; Layout.preferredWidth: 60 }
            TextField {
                id: mqttHostField
                text: remoteSettings.mqttHost
                onTextChanged: remoteSettings.mqttHost = text
                Layout.fillWidth: true
                color: "#aabbcc"
                background: Rectangle { color: "#0a1525"; border.color: "#2a4060"; radius: 4 }
            }
        }

        RowLayout {
            spacing: 8
            enabled: mqttSwitch.checked
            Label { text: qsTr("Port"); color: "#556677"; font.pixelSize: 12; Layout.preferredWidth: 60 }
            TextField {
                id: mqttPortField
                text: remoteSettings.mqttPort
                onTextChanged: remoteSettings.mqttPort = text
                implicitWidth: 80
                color: "#aabbcc"
                placeholderText: "1883"
                inputMethodHints: Qt.ImhDigitsOnly
                background: Rectangle { color: "#0a1525"; border.color: "#2a4060"; radius: 4 }
            }
        }

        RowLayout {
            spacing: 8
            enabled: mqttSwitch.checked
            Label { text: qsTr("Prefix"); color: "#556677"; font.pixelSize: 12; Layout.preferredWidth: 60 }
            TextField {
                id: mqttPrefixField
                text: remoteSettings.mqttPrefix
                onTextChanged: remoteSettings.mqttPrefix = text
                Layout.fillWidth: true
                color: "#aabbcc"
                background: Rectangle { color: "#0a1525"; border.color: "#2a4060"; radius: 4 }
            }
        }

        RowLayout {
            spacing: 8
            enabled: mqttSwitch.checked
            Label { text: qsTr("User"); color: "#556677"; font.pixelSize: 12; Layout.preferredWidth: 60 }
            TextField {
                id: mqttUserField
                text: remoteSettings.mqttUser
                onTextChanged: remoteSettings.mqttUser = text
                Layout.fillWidth: true
                color: "#aabbcc"
                background: Rectangle { color: "#0a1525"; border.color: "#2a4060"; radius: 4 }
            }
        }

        RowLayout {
            spacing: 8
            enabled: mqttSwitch.checked
            Label { text: qsTr("Password"); color: "#556677"; font.pixelSize: 12; Layout.preferredWidth: 60 }
            TextField {
                id: mqttPassField
                echoMode: TextInput.Password
                Layout.fillWidth: true
                color: "#aabbcc"
                background: Rectangle { color: "#0a1525"; border.color: "#2a4060"; radius: 4 }
            }
        }

        RowLayout {
            spacing: 8
            enabled: mqttSwitch.checked
            Label { text: qsTr("TLS"); color: "#556677"; font.pixelSize: 12; Layout.preferredWidth: 60 }
            CheckBox {
                id: mqttTlsBox
                checked: remoteSettings.mqttTls
                onCheckedChanged: remoteSettings.mqttTls = checked
                Material.accent: Material.Cyan
            }
        }

        RowLayout {
            spacing: 8
            enabled: mqttSwitch.checked
            Button {
                text: (mqttClient && mqttClient.connected) ? qsTr("Disconnect") : qsTr("Connect")
                highlighted: !(mqttClient && mqttClient.connected)
                onClicked: {
                    if (!mqttClient) return
                    if (mqttClient.connected) {
                        mqttClient.disconnectFromBroker()
                    } else {
                        mqttClient.configure(
                            mqttHostField.text,
                            parseInt(mqttPortField.text) || 1883,
                            mqttPrefixField.text,
                            mqttUserField.text,
                            mqttPassField.text,
                            mqttTlsBox.checked
                        )
                        mqttClient.connectToBroker()
                    }
                }
            }

            // Status indicator
            Rectangle {
                width: 8; height: 8; radius: 4
                color: (mqttClient && mqttClient.connected) ? "#44cc66" : "#cc4444"
            }
            Label {
                text: mqttClient ? mqttClient.status : qsTr("N/A")
                color: "#7799bb"; font.pixelSize: 11
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }
    }
}
