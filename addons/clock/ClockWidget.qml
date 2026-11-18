import QtQuick
import shell
import "clock.js" as ClockFormat

// Clock widget. Shows the local clock plus any world clocks configured in
// the Clock dashlet. Settings (format, seconds, analog, local visibility)
// are shared with the app.
WidgetBase {
    id: root

    clip: true

    property bool format24h: setting("format24h", true)
    property bool showSeconds: setting("showSeconds", true)
    property bool analog: setting("analog", false)
    property bool showSystem: setting("showSystem", true)
    property var zones: setting("zones", [])
    property var clocks: []
    property date now: new Date()

    readonly property var selectedClocks: {
        const list = root.clocks || []
        if (list.length === 0)
            return []
        const local = list.slice(0, 1)
        const others = list.slice(1)
        return root.showSystem ? local.concat(others) : others
    }

    readonly property var allClocks: selectedClocks.length > 0
        ? selectedClocks
        : (root.clocks && root.clocks.length > 0 ? root.clocks.slice(0, 1) : [])

    readonly property var displayClocks: allClocks.slice(0, 3)
    readonly property int extraCount: Math.max(0, allClocks.length - displayClocks.length)

    function refresh() {
        root.now = new Date()
        root.clocks = Host.clockTimes(root.zones)
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    onZonesChanged: refresh()
    onShowSystemChanged: refresh()

    // ------------------------------------------------------------- digital
    Column {
        visible: !root.analog
        anchors.centerIn: parent
        spacing: 1

        Repeater {
            model: root.displayClocks

            delegate: Column {
                required property var modelData
                required property int index

                spacing: 0

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: index > 0 || modelData.zone !== "local"
                    text: modelData.label
                    color: Theme.textMuted
                    font.pixelSize: index === 0 ? 11 : 9
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: ClockFormat.time(modelData, root.format24h, root.showSeconds)
                    color: Theme.textPrimary
                    font.pixelSize: index === 0 ? 40 : 17
                    font.weight: index === 0 ? Font.DemiBold : Font.Normal
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.extraCount > 0
            text: "+" + root.extraCount + " more"
            color: Theme.textMuted
            font.pixelSize: 10
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.displayClocks.length <= 1
            text: root.now.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
            color: Theme.textMuted
            font.pixelSize: 14
        }
    }

    // -------------------------------------------------------------- analog
    Row {
        visible: root.analog
        anchors.centerIn: parent
        spacing: 10

        Repeater {
            model: root.displayClocks

            delegate: Column {
                required property var modelData
                required property int index

                spacing: 1

                readonly property real dialSize: Math.min(96,
                    (root.width - 20 - (root.displayClocks.length - 1) * 10)
                    / Math.max(1, root.displayClocks.length))

                AnalogClock {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.dialSize
                    height: parent.dialSize
                    hours: modelData.hour
                    minutes: modelData.minute
                    seconds: modelData.second
                    showSeconds: root.showSeconds
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.label
                    color: Theme.textMuted
                    font.pixelSize: 10
                }
            }
        }
    }

    Text {
        visible: root.analog && root.extraCount > 0
        anchors {
            right: parent.right
            bottom: parent.bottom
            rightMargin: 2
            bottomMargin: 1
        }
        text: "+" + root.extraCount + " more"
        color: Theme.textMuted
        font.pixelSize: 9
    }
}
