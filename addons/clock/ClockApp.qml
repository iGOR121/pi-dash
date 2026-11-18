import QtQuick
import shell
import "clock.js" as ClockFormat

// Clock dashlet: local clock plus world clocks, with the same settings the
// clock widget uses (shared through the app settings store).
DashletBase {
    id: root

    property bool format24h: setting("format24h", true)
    property bool showSeconds: setting("showSeconds", true)
    property bool analog: setting("analog", false)
    property bool showSystem: setting("showSystem", true)
    property var zones: setting("zones", [])
    property var clocks: []

    readonly property var zoneClocks: (clocks || []).slice(1)
    readonly property var primary: {
        const list = root.clocks || []
        if (list.length === 0)
            return null
        if (root.showSystem)
            return list[0]
        return list.length > 1 ? list[1] : list[0]
    }

    property var cities: [
        { "name": "London", "zone": "Europe/London" },
        { "name": "Paris", "zone": "Europe/Paris" },
        { "name": "Berlin", "zone": "Europe/Berlin" },
        { "name": "Moscow", "zone": "Europe/Moscow" },
        { "name": "Istanbul", "zone": "Europe/Istanbul" },
        { "name": "Dubai", "zone": "Asia/Dubai" },
        { "name": "Mumbai", "zone": "Asia/Kolkata" },
        { "name": "Singapore", "zone": "Asia/Singapore" },
        { "name": "Shanghai", "zone": "Asia/Shanghai" },
        { "name": "Tokyo", "zone": "Asia/Tokyo" },
        { "name": "Sydney", "zone": "Australia/Sydney" },
        { "name": "Auckland", "zone": "Pacific/Auckland" },
        { "name": "Honolulu", "zone": "Pacific/Honolulu" },
        { "name": "Los Angeles", "zone": "America/Los_Angeles" },
        { "name": "Denver", "zone": "America/Denver" },
        { "name": "Chicago", "zone": "America/Chicago" },
        { "name": "New York", "zone": "America/New_York" },
        { "name": "Sao Paulo", "zone": "America/Sao_Paulo" },
        { "name": "UTC", "zone": "Etc/UTC" }
    ]

    function refresh() {
        root.clocks = Host.clockTimes(root.zones)
    }

    function toggleZone(zone) {
        const current = (root.zones || []).slice()
        const index = current.indexOf(zone)
        if (index >= 0)
            current.splice(index, 1)
        else
            current.push(zone)
        root.setSetting("zones", current)
    }

    function removeZone(zone) {
        root.setSetting("zones", (root.zones || []).filter(z => z !== zone))
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    onZonesChanged: refresh()

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

            // ------------------------------------------------------- preview
            Item {
                width: parent.width
                height: 118

                AnalogClock {
                    visible: root.analog && root.primary !== null
                    anchors.verticalCenter: parent.verticalCenter
                    width: 112
                    height: 112
                    hours: root.primary ? root.primary.hour : 0
                    minutes: root.primary ? root.primary.minute : 0
                    seconds: root.primary ? root.primary.second : 0
                    showSeconds: root.showSeconds
                }

                Column {
                    visible: !root.analog
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Text {
                        text: root.primary
                              ? ClockFormat.time(root.primary,
                                                 root.format24h,
                                                 root.showSeconds)
                              : "--:--"
                        color: Theme.textPrimary
                        font.pixelSize: 52
                        font.weight: Font.DemiBold
                    }
                    Text {
                        text: root.primary
                              ? root.primary.label + "   ·   "
                                + ClockFormat.dateText(root.primary)
                              : ""
                        color: Theme.textMuted
                        font.pixelSize: 12
                    }
                }

                Column {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 8

                    Flow {
                        width: 330
                        spacing: 6

                        DashButton {
                            text: "Analog"
                            primary: root.analog
                            onClicked: root.setSetting("analog", !root.analog)
                        }
                        DashButton {
                            text: "24-hour"
                            primary: root.format24h
                            onClicked: root.setSetting("format24h", !root.format24h)
                        }
                        DashButton {
                            text: "Seconds"
                            primary: root.showSeconds
                            onClicked: root.setSetting("showSeconds", !root.showSeconds)
                        }
                        DashButton {
                            text: "Local clock"
                            primary: root.showSystem
                            onClicked: root.setSetting("showSystem", !root.showSystem)
                        }
                    }

                    Text {
                        width: 330
                        horizontalAlignment: Text.AlignRight
                        text: "These settings also apply to the clock widget."
                        color: Theme.textMuted
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // -------------------------------------------------- world clocks
            Text {
                text: "World clocks"
                color: Theme.textPrimary
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Column {
                width: parent.width
                spacing: 4

                Repeater {
                    model: root.clocks

                    delegate: Rectangle {
                        id: zoneRow

                        required property var modelData
                        required property int index

                        width: content.width
                        height: 38
                        radius: 8
                        color: root.glass ? Theme.surfaceGlass : Theme.surface
                        border.width: 1
                        border.color: Theme.surfaceBorder

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            width: 110
                            text: zoneRow.modelData.label
                            color: Theme.textPrimary
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 130
                                verticalCenter: parent.verticalCenter
                            }
                            text: ClockFormat.time(zoneRow.modelData,
                                                   root.format24h,
                                                   root.showSeconds)
                            color: Theme.textPrimary
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 260
                                verticalCenter: parent.verticalCenter
                            }
                            text: ClockFormat.dateText(zoneRow.modelData)
                            color: Theme.textMuted
                            font.pixelSize: 11
                        }

                        Rectangle {
                            visible: zoneRow.modelData.zone !== "local"
                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                rightMargin: 8
                            }
                            width: 28
                            height: 28
                            radius: 14
                            color: removeTap.pressed ? Theme.surfaceBorder : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                color: Theme.bad
                                font.pixelSize: 18
                            }

                            TapHandler {
                                id: removeTap
                                onTapped: root.removeZone(zoneRow.modelData.zone)
                            }
                        }

                        Text {
                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                                rightMargin: 46
                            }
                            visible: zoneRow.modelData.zone === "local"
                            text: "system"
                            color: Theme.textMuted
                            font.pixelSize: 10
                        }
                    }
                }
            }

            // ---------------------------------------------------- add a city
            Text {
                text: "Add a city"
                color: Theme.textPrimary
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                text: "Tap a city to show or hide its clock on the widget and here."
                color: Theme.textMuted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            Flow {
                width: parent.width
                spacing: 6

                Repeater {
                    model: root.cities

                    delegate: DashButton {
                        required property var modelData

                        text: modelData.name
                        primary: (root.zones || []).indexOf(modelData.zone) >= 0
                        onClicked: root.toggleZone(modelData.zone)
                    }
                }
            }

            Item {
                width: 1
                height: 6
            }
        }
    }
}
