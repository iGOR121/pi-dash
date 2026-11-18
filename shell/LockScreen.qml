import QtQuick
import shell

// Boot lock screen: the wallpaper at full sharpness, a large clock, and a
// swipe-up / tap / any-key unlock. The dashboard underneath uses a blurred
// copy of the same wallpaper (see Main.qml).
Item {
    id: lock

    anchors.fill: parent
    z: 200
    focus: true
    visible: active

    property bool active: false
    property string wallpaperUrl: ""
    property int fillMode: Image.PreserveAspectCrop
    property string activeAppsText: ""
    property real dragOffset: 0
    property bool animating: false
    property date now: new Date()

    signal unlocked()

    onActiveChanged: {
        if (active) {
            dragOffset = 0
            animating = false
            now = new Date()
            forceActiveFocus()
        }
    }

    Component.onCompleted: {
        if (active)
            forceActiveFocus()
    }

    function unlock() {
        if (!active || animating)
            return
        animating = true
        unlockAnim.start()
    }

    NumberAnimation {
        id: unlockAnim

        target: lock
        property: "dragOffset"
        to: -lock.height
        duration: 280
        easing.type: Easing.InCubic

        onFinished: {
            lock.animating = false
            lock.unlocked()
        }
    }

    NumberAnimation {
        id: returnAnim

        target: lock
        property: "dragOffset"
        to: 0
        duration: 180
        easing.type: Easing.OutCubic
    }

    Timer {
        interval: 1000
        running: lock.active
        repeat: true
        triggeredOnStart: true
        onTriggered: lock.now = new Date()
    }

    Item {
        id: content

        anchors.fill: parent
        transform: Translate {
            y: lock.dragOffset
        }

        // Fallback when no wallpaper is configured.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#1c2533" }
                GradientStop { position: 0.6; color: "#121721" }
                GradientStop { position: 1.0; color: "#0d1017" }
            }
        }

        // The wallpaper, sharp.
        Image {
            anchors.fill: parent
            visible: lock.wallpaperUrl !== ""
            source: lock.wallpaperUrl
            sourceSize.width: 1600   // enough for 800x480, saves Pi RAM
            fillMode: lock.fillMode
            asynchronous: true
            cache: true
        }

        // Darken top/bottom so the clock and hint stay readable.
        Rectangle {
            anchors.fill: parent
            visible: lock.wallpaperUrl !== ""
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#4d000000" }
                GradientStop { position: 0.45; color: "#00000000" }
                GradientStop { position: 1.0; color: "#b30d1017" }
            }
        }

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -16
            spacing: 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(lock.now, "hh:mm")
                color: "#ffffff"
                font.pixelSize: 96
                font.weight: Font.DemiBold
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: lock.now.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
                color: "#dbe2ee"
                font.pixelSize: 18
            }
        }

        Column {
            anchors {
                bottom: parent.bottom
                bottomMargin: 26
                horizontalCenter: parent.horizontalCenter
            }
            spacing: 6

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "↑"
                color: "#ffffff"
                font.pixelSize: 26
                transform: Translate {
                    id: arrowMove
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Swipe up or tap to unlock"
                color: "#c7d0df"
                font.pixelSize: 14
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: lock.activeAppsText.length > 0
                text: lock.activeAppsText
                color: "#9fb0c9"
                font.pixelSize: 11
            }
        }

        SequentialAnimation {
            loops: Animation.Infinite
            running: lock.active

            NumberAnimation {
                target: arrowMove
                property: "y"
                to: -6
                duration: 700
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                target: arrowMove
                property: "y"
                to: 0
                duration: 700
                easing.type: Easing.InOutSine
            }
        }
    }

    // Swipe up to unlock: the sheet follows the finger and slides away.
    DragHandler {
        target: null

        onTranslationChanged: {
            if (!lock.active || lock.animating)
                return
            returnAnim.stop()
            lock.dragOffset = Math.min(0, translation.y)
        }

        onActiveChanged: {
            if (active || !lock.active || lock.animating)
                return
            if (lock.dragOffset < -70)
                lock.unlock()
            else
                returnAnim.start()
        }
    }

    TapHandler {
        onTapped: lock.unlock()
    }

    Keys.onPressed: function (event) {
        if (lock.active) {
            lock.unlock()
            event.accepted = true
        }
    }
}
