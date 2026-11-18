import QtQuick
import shell

// A demo switch: touch input + per-instance persisted state. Copy this
// folder as a starting point for real device toggles later on.
WidgetBase {
    id: root

    property string label: setting("label", "Toggle")
    property bool on: setting("state", false)

    function toggle() {
        root.on = !root.on
        setSetting("state", root.on)   // survives a restart (see dashboard.json)
    }

    Column {
        anchors.centerIn: parent
        spacing: 12

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Theme.textPrimary
            font.pixelSize: 19
            font.weight: Font.DemiBold
        }

        Rectangle {
            id: pill

            anchors.horizontalCenter: parent.horizontalCenter
            width: 92
            height: 48
            radius: 24
            color: root.on ? Theme.accent : Theme.track
            border.width: 1
            border.color: root.on ? Theme.accent : Theme.surfaceBorder

            Behavior on color { ColorAnimation { duration: 140 } }

            Rectangle {
                id: knob

                width: 40
                height: 40
                radius: 20
                anchors.verticalCenter: parent.verticalCenter
                x: root.on ? parent.width - width - 4 : 4
                color: "#f2f5fa"

                Behavior on x {
                    NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                }
            }

            TapHandler { onTapped: root.toggle() }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.on ? "ON" : "OFF"
            color: root.on ? Theme.good : Theme.textMuted
            font.pixelSize: 13
            font.letterSpacing: 1.2
        }
    }
}
