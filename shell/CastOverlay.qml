import QtQuick
import shell

// Fullscreen AirPlay video surface. Opened automatically by the shell when
// UxPlay starts delivering mirrored video frames. The grey × is always on
// top and stops the receiver.
Item {
    id: overlay

    z: 150
    property int tick: 0

    signal closeRequested()

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    Text {
        anchors.centerIn: parent
        text: "Casting…"
        color: "#8a93a7"
        font.pixelSize: 16
    }

    Image {
        anchors.fill: parent
        source: overlay.tick > 0 ? "image://cast/frame?" + overlay.tick : ""
        cache: false
        asynchronous: false
        fillMode: Image.PreserveAspectFit
    }

    // swallow input so pages/widgets do not react behind the cast
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    Connections {
        target: UxPlay

        function onFrameReady() {
            overlay.tick++
        }
    }

    // Grey close cross, always visible in the upper-right corner.
    Rectangle {
        width: 46
        height: 46
        radius: 23
        anchors {
            top: parent.top
            right: parent.right
            margins: 14
        }
        color: "#80000000"
        border.width: 1
        border.color: "#59ffffff"
        z: 2

        Text {
            anchors.centerIn: parent
            text: "×"
            color: "#aab0bb"
            font.pixelSize: 28
        }

        TapHandler {
            onTapped: overlay.closeRequested()
        }
    }
}
