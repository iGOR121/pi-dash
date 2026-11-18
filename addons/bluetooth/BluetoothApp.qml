import QtQuick
import shell

// Bluetooth dashlet: adapter, pairing (HID and audio), A2DP roles and codec
// picker. Works with Raspberry Pi OS's BlueZ + WirePlumber (PipeWire).
DashletBase {
    id: root

    readonly property var adapter: Bluetooth.adapter
    readonly property var paired: Bluetooth.paired
    readonly property var nearby: Bluetooth.nearby
    readonly property bool scanning: Bluetooth.scanning
    readonly property bool busy: Bluetooth.busy
    readonly property string message: Bluetooth.message
    readonly property bool available: Bluetooth.available
    readonly property var catalog: Bluetooth.codecCatalog
    readonly property string adapterName: setting("adapterName", "pi-dash")

    readonly property var audioDevice: {
        const list = root.paired || []
        for (let i = 0; i < list.length; ++i)
            if (list[i].kind === "audio" && list[i].connected)
                return list[i]
        return null
    }

    property var pendingCodecs: []

    function reloadCodecs() {
        root.pendingCodecs = (Bluetooth.codecs || []).slice()
    }

    function toggleCodec(id, mandatory, supported) {
        if (mandatory || !supported || root.busy)
            return
        const list = (root.pendingCodecs || []).slice()
        const index = list.indexOf(id)
        if (index >= 0)
            list.splice(index, 1)
        else
            list.push(id)
        root.pendingCodecs = list
    }

    function selectedCodec(id) {
        return (root.pendingCodecs || []).indexOf(id) >= 0
    }

    function messageIsError() {
        const text = (root.message || "").toLowerCase()
        return text.indexOf("fail") >= 0 || text.indexOf("error") >= 0
               || text.indexOf("timed out") >= 0
               || text.indexOf("not found") >= 0
               || text.startsWith("no ")
    }

    Component.onCompleted: {
        Bluetooth.requestRefresh()
        root.reloadCodecs()
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: 14
        contentWidth: width
        contentHeight: content.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content

            width: parent.width
            spacing: 10

            // ------------------------------------------------------ adapter
            Rectangle {
                width: parent.width
                height: 98
                radius: Theme.radius
                color: root.glass ? Theme.surfaceGlass : Theme.surface
                border.width: 1
                border.color: Theme.surfaceBorder

                Item {
                    anchors.fill: parent
                    anchors.margins: 14

                    Rectangle {
                        id: powerDot

                        anchors.verticalCenter: parent.verticalCenter
                        width: 12
                        height: 12
                        radius: 6
                        color: (!root.adapter || !root.adapter.present)
                               ? Theme.textMuted
                               : (root.adapter.powered ? Theme.good
                                                       : Theme.track)
                    }

                    Column {
                        anchors {
                            left: powerDot.right
                            leftMargin: 12
                            right: buttons.left
                            rightMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 3

                        Text {
                            width: parent.width
                            text: !root.available
                                  ? "Bluetooth unavailable"
                                  : (!root.adapter || !root.adapter.present)
                                    ? "No Bluetooth adapter"
                                    : (root.adapter.alias || root.adapter.name
                                       || "Bluetooth")
                            color: Theme.textPrimary
                            font.pixelSize: 19
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            visible: root.adapter && root.adapter.present
                            text: (root.adapter.address || "") + "   ·   "
                                  + (root.adapter.powered ? "on" : "off")
                                  + (root.adapter.discoverable ? "  ·  visible" : "")
                            color: Theme.textMuted
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            visible: !root.adapter || !root.adapter.present
                            text: root.available
                                  ? "Power on the adapter to scan and pair."
                                  : "Install BlueZ (bluetoothctl) on the Pi."
                            color: Theme.textMuted
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                        }
                    }

                    Row {
                        id: buttons

                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 6

                        DashButton {
                            height: 32
                            text: root.adapter && root.adapter.powered
                                  ? "Power off" : "Power on"
                            enabled: root.available && root.adapter
                                     && root.adapter.present && !root.busy
                            onClicked: Bluetooth.setPowered(
                                !(root.adapter && root.adapter.powered))
                        }

                        DashButton {
                            height: 32
                            text: root.scanning ? "Scanning…" : "Scan"
                            primary: !root.scanning
                            enabled: root.available && root.adapter
                                     && root.adapter.present && root.adapter.powered
                                     && !root.scanning && !root.busy
                            onClicked: Bluetooth.scan()
                        }

                        DashButton {
                            height: 32
                            text: "Refresh"
                            enabled: root.available && !root.busy
                            onClicked: Bluetooth.requestRefresh()
                        }
                    }
                }
            }

            // visibility / pairability
            Row {
                width: parent.width
                spacing: 8
                visible: root.adapter && root.adapter.present

                DashButton {
                    height: 32
                    text: "Visible"
                    primary: root.adapter && root.adapter.discoverable
                    enabled: !root.busy
                    onClicked: Bluetooth.setDiscoverable(
                        !(root.adapter && root.adapter.discoverable))
                }

                DashButton {
                    height: 32
                    text: "Pairable"
                    primary: root.adapter && root.adapter.pairable
                    enabled: !root.busy
                    onClicked: Bluetooth.setPairable(
                        !(root.adapter && root.adapter.pairable))
                }

                DashButton {
                    height: 32
                    text: "Set name"
                    visible: root.adapter && root.adapter.present
                             && root.adapter.alias !== root.adapterName
                    enabled: !root.busy
                    onClicked: Bluetooth.setAlias(root.adapterName)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Visible lets a phone find the Pi (for speaker mode)."
                    color: Theme.textMuted
                    font.pixelSize: 10
                }
            }

            // status message
            Text {
                width: parent.width
                visible: root.message.length > 0
                text: root.message
                color: root.messageIsError() ? Theme.bad : Theme.textMuted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            // -------------------------------------------------- paired list
            Item {
                width: parent.width
                height: 24

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Paired devices"
                    color: Theme.textPrimary
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    text: (root.paired || []).length
                    color: Theme.textMuted
                    font.pixelSize: 11
                }
            }

            Text {
                visible: (root.paired || []).length === 0
                width: parent.width
                text: "No paired devices yet. Put a keyboard, mouse or "
                      + "headset in pairing mode, then press Scan."
                color: Theme.textMuted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: root.paired

                delegate: Rectangle {
                    id: deviceCard

                    required property var modelData

                    width: content.width
                    height: 92
                    radius: Theme.radius
                    color: root.glass ? Theme.surfaceGlass : Theme.surface
                    border.width: 1
                    border.color: Theme.surfaceBorder

                    Item {
                        anchors.fill: parent
                        anchors.margins: 12

                        Rectangle {
                            id: kindBadge

                            width: 46
                            height: 18
                            radius: 9
                            color: Theme.track

                            Text {
                                anchors.centerIn: parent
                                text: deviceCard.modelData.kind === "hid" ? "HID"
                                      : deviceCard.modelData.kind === "audio"
                                        ? (deviceCard.modelData.phone ? "PHONE"
                                                                      : "AUDIO")
                                        : "DEVICE"
                                color: deviceCard.modelData.kind === "hid"
                                       ? Theme.accent
                                       : deviceCard.modelData.kind === "audio"
                                         ? Theme.good : Theme.textMuted
                                font.pixelSize: 8
                                font.weight: Font.Bold
                            }
                        }

                        Rectangle {
                            anchors {
                                left: kindBadge.right
                                leftMargin: 8
                                verticalCenter: kindBadge.verticalCenter
                            }
                            width: 8
                            height: 8
                            radius: 4
                            color: deviceCard.modelData.connected
                                   ? Theme.good : Theme.track
                        }

                        Text {
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: kindBadge.bottom
                                topMargin: 5
                            }
                            text: deviceCard.modelData.name
                            color: Theme.textPrimary
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: kindBadge.bottom
                                topMargin: 27
                            }
                            text: deviceCard.modelData.address
                                  + "   ·   "
                                  + (deviceCard.modelData.connected
                                     ? "connected" : "not connected")
                                  + (deviceCard.modelData.codec
                                     ? "   ·   " + deviceCard.modelData.codec
                                       + " codec" : "")
                            color: Theme.textMuted
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }

                        Row {
                            anchors {
                                right: parent.right
                                bottom: parent.bottom
                            }
                            spacing: 6

                            DashButton {
                                height: 30
                                text: deviceCard.modelData.connected
                                      ? "Disconnect" : "Connect"
                                enabled: !root.busy
                                onClicked: deviceCard.modelData.connected
                                           ? Bluetooth.disconnectDevice(
                                                 deviceCard.modelData.address)
                                           : Bluetooth.connectDevice(
                                                 deviceCard.modelData.address)
                            }

                            DashButton {
                                height: 30
                                visible: deviceCard.modelData.kind === "audio"
                                         && !deviceCard.modelData.phone
                                text: "Use output"
                                enabled: !root.busy
                                onClicked: Bluetooth.useAsOutput(
                                    deviceCard.modelData.address)
                            }

                            DashButton {
                                height: 30
                                text: "Forget"
                                enabled: !root.busy
                                onClicked: Bluetooth.forget(
                                    deviceCard.modelData.address)
                            }
                        }
                    }
                }
            }

            // -------------------------------------------------- nearby list
            Text {
                visible: root.scanning || (root.nearby || []).length > 0
                width: parent.width
                text: root.scanning ? "Nearby devices — scanning…"
                                    : "Nearby devices"
                color: Theme.textPrimary
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            Text {
                visible: root.scanning && (root.nearby || []).length === 0
                text: "Looking for pairable devices…"
                color: Theme.textMuted
                font.pixelSize: 11
            }

            Repeater {
                model: root.nearby

                delegate: Rectangle {
                    id: nearCard

                    required property var modelData

                    width: content.width
                    height: 54
                    radius: 10
                    color: root.glass ? Theme.surfaceGlass : Theme.surface
                    border.width: 1
                    border.color: Theme.surfaceBorder

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 12
                            right: pairButton.left
                            rightMargin: 12
                            top: parent.top
                            topMargin: 9
                        }
                        text: nearCard.modelData.name
                        color: Theme.textPrimary
                        font.pixelSize: 14
                        elide: Text.ElideRight
                    }

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 12
                            top: parent.top
                            topMargin: 29
                        }
                        text: nearCard.modelData.address
                        color: Theme.textMuted
                        font.pixelSize: 9
                    }

                    DashButton {
                        id: pairButton

                        anchors {
                            right: parent.right
                            rightMargin: 10
                            verticalCenter: parent.verticalCenter
                        }
                        height: 32
                        text: "Pair"
                        primary: true
                        enabled: !root.busy
                        onClicked: Bluetooth.pair(nearCard.modelData.address)
                    }
                }
            }

            Text {
                visible: root.scanning || (root.nearby || []).length > 0
                width: parent.width
                text: "Keyboards/mice: put the device in pairing mode first. "
                      + "If the device shows a code, confirm/type it there."
                color: Theme.textMuted
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }

            // ------------------------------------------------------- audio
            Rectangle {
                width: parent.width
                height: 1
                color: Theme.surfaceBorder
            }

            Text {
                text: "Audio"
                color: Theme.textPrimary
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                text: "Both A2DP roles are enabled: connect headphones or a "
                      + "speaker and use them as output, or make the Pi "
                      + "visible and pair from a phone to use it as a speaker."
                color: Theme.textMuted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            Text {
                visible: root.audioDevice
                width: parent.width
                text: root.audioDevice
                      ? "Connected: " + root.audioDevice.name
                        + (root.audioDevice.codec
                           ? "  ·  " + root.audioDevice.codec + " codec" : "")
                      : ""
                color: Theme.good
                font.pixelSize: 11
                elide: Text.ElideRight
            }

            Text {
                text: "A2DP codecs"
                color: Theme.textPrimary
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }

            Flow {
                width: parent.width
                spacing: 6

                Repeater {
                    model: root.catalog

                    delegate: DashButton {
                        required property var modelData

                        height: 32
                        text: modelData.label
                        primary: modelData.mandatory
                                 || root.selectedCodec(modelData.id)
                        enabled: modelData.supported && !root.busy
                        opacity: modelData.supported ? 1 : 0.35
                        onClicked: root.toggleCodec(modelData.id,
                                                    modelData.mandatory,
                                                    modelData.supported)
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 10

                DashButton {
                    height: 32
                    text: "Apply codecs"
                    primary: true
                    enabled: !root.busy
                    onClicked: Bluetooth.applyCodecs(root.pendingCodecs)
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 130
                    text: "SBC is always on. The remote device must support "
                          + "the codecs you enable; restarting WirePlumber "
                          + "reconnects audio."
                    color: Theme.textMuted
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }
            }

            Text {
                width: parent.width
                text: "To use the Pi as a speaker: press Visible, then pair "
                      + "with “" + root.adapterName + "” from the phone and "
                      + "play audio. The Pi's default output is used."
                color: Theme.textMuted
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }

            Item {
                width: 1
                height: 4
            }
        }
    }
}
