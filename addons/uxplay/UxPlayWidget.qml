import QtQuick
import shell

// AirPlay receiver status. Tap to open the AirPlay dashlet.
WidgetBase {
    id: root

    readonly property bool running: UxPlay.running
    readonly property bool casting: UxPlay.videoActive
    readonly property var now: UxPlay.nowPlaying

    readonly property string track: {
        if (!now)
            return ""
        const title = now.title || ""
        const artist = now.artist || ""
        if (title && artist)
            return title + " — " + artist
        return title || artist || ""
    }

    Column {
        anchors.centerIn: parent
        width: root.width - 10
        spacing: 3

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "AirPlay"
            color: Theme.textPrimary
            font.pixelSize: 17
            font.weight: Font.DemiBold
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: !root.running
                  ? "Receiver off"
                  : (root.casting
                     ? "Casting video"
                     : (root.track.length > 0 ? "Receiving audio"
                                              : "Waiting for a client"))
            color: !root.running ? Theme.textMuted
                                 : (root.casting ? Theme.accent : Theme.good)
            font.pixelSize: 12
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: root.track.length > 0
            text: root.track
            color: Theme.textMuted
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.setting("serverName", "pi-dash")
            color: Theme.textMuted
            font.pixelSize: 9
        }
    }
}
