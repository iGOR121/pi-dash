// Hello — the starter addon. Copy this whole folder to make your own:
//
//     cp -r addons/hello addons/my-widget
//
// then edit manifest.json + this file, add an entry to
// config/dashboard.json, and restart. That's the whole addon story.
// See docs/addon-dev.md for the full reference.

import QtQuick
import shell

WidgetBase {
    id: root

    // Reads: manifest default <- dashboard.json "settings" override
    property string text: setting("text", "Hello, addon!")

    // Example of persisted per-instance state (written to dashboard.json).
    property int taps: setting("taps", 0)

    Column {
        anchors.centerIn: parent
        spacing: 8

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.text
            color: Theme.textPrimary
            font.pixelSize: 22
            font.weight: Font.DemiBold
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "instance: " + root.instanceId
            color: Theme.textMuted
            font.pixelSize: 12
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "tapped " + root.taps + "× (saved)"
            color: Theme.textMuted
            font.pixelSize: 12
        }
    }

    TapHandler {
        onTapped: {
            root.taps++
            root.setSetting("taps", root.taps)
        }
    }
}
