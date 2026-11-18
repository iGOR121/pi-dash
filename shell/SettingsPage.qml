import QtQuick
import shell

// App-wide settings, opened from the edit toolbar. Changes apply and persist
// immediately (via Host) and are reflected live behind the page.
Item {
    id: page

    anchors.fill: parent
    visible: false
    z: 120

    property var catalog: []
    property string currentWallpaper: ""
    property string currentMode: "fill"
    property bool lockAtBoot: true
    property int autoLockSeconds: 0

    signal lockNow()

    function refresh() {
        page.catalog = Host.wallpaperCatalog()
        page.currentWallpaper = Host.wallpaperUrl()
        page.currentMode = Host.wallpaperMode()
        page.lockAtBoot = Host.startLocked()
        page.autoLockSeconds = Host.autoLockSeconds()
    }

    function open() {
        page.refresh()
        visible = true
    }

    function close() {
        visible = false
        Host.saveNow()   // flush debounced wallpaper/lock changes
    }

    Connections {
        target: Host

        function onWallpaperChanged() {
            page.refresh()
        }

        function onOptionsChanged() {
            page.refresh()
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#b3000000"

        MouseArea {
            anchors.fill: parent
            onClicked: page.close()
        }
    }

    Rectangle {
        id: panel

        anchors.fill: parent
        anchors.margins: 10
        radius: Theme.radius
        color: Theme.surface
        border.width: 1
        border.color: Theme.surfaceBorder

        MouseArea {
            anchors.fill: parent
        }

        // -------------------------------------------------------------- header
        Text {
            id: heading

            anchors {
                left: parent.left
                top: parent.top
                leftMargin: 18
                topMargin: 14
            }
            text: "Settings"
            color: Theme.textPrimary
            font.pixelSize: 19
            font.weight: Font.DemiBold
        }

        DashButton {
            anchors {
                right: parent.right
                top: parent.top
                rightMargin: 14
                topMargin: 10
            }
            text: "Done"
            primary: true
            onClicked: page.close()
        }

        Rectangle {
            id: headerLine

            anchors {
                top: parent.top
                topMargin: 58
                left: parent.left
                right: parent.right
            }
            height: 1
            color: Theme.surfaceBorder
        }

        // -------------------------------------------------------------- content
        Flickable {
            id: scroll

            anchors {
                top: headerLine.bottom
                topMargin: 10
                left: parent.left
                leftMargin: 18
                right: parent.right
                rightMargin: 18
                bottom: parent.bottom
                bottomMargin: 12
            }
            contentWidth: width
            contentHeight: content.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: content

                width: scroll.width
                spacing: 4

                Text {
                    text: "Wallpaper"
                    color: Theme.textPrimary
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }

                Text {
                    width: parent.width
                    text: "Images in assets/ — drop a JPG, PNG, WEBP or BMP there to add more."
                    color: Theme.textMuted
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }

                Item {
                    width: 1
                    height: 4
                }

                Flickable {
                    width: parent.width
                    height: 92
                    contentWidth: strip.width
                    contentHeight: height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Row {
                        id: strip
                        spacing: 10

                        // no wallpaper / gradient
                        Rectangle {
                            width: 120
                            height: 92
                            radius: 10
                            color: "transparent"
                            border.width: page.currentWallpaper === "" ? 2 : 1
                            border.color: page.currentWallpaper === "" ? Theme.accent
                                                                       : Theme.surfaceBorder

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 2
                                radius: 8
                                clip: true
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: "#1c2533" }
                                    GradientStop { position: 1.0; color: "#0d1017" }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "No wallpaper"
                                    color: Theme.textMuted
                                    font.pixelSize: 12
                                }
                            }

                            TapHandler {
                                onTapped: Host.setWallpaper("")
                            }
                        }

                        Rectangle {
                            visible: page.catalog.length === 0
                            width: 360
                            height: 92
                            radius: 10
                            color: "transparent"
                            border.width: 1
                            border.color: Theme.surfaceBorder

                            Text {
                                anchors.centerIn: parent
                                text: "No images in assets/ yet"
                                color: Theme.textMuted
                                font.pixelSize: 13
                            }
                        }

                        Repeater {
                            model: page.catalog

                            delegate: Rectangle {
                                id: thumb

                                required property var modelData

                                width: 140
                                height: 92
                                radius: 10
                                color: "transparent"
                                border.width: page.currentWallpaper === thumb.modelData.url ? 2 : 1
                                border.color: page.currentWallpaper === thumb.modelData.url
                                              ? Theme.accent : Theme.surfaceBorder

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    radius: 8
                                    clip: true
                                    color: Theme.bg

                                    Image {
                                        anchors.fill: parent
                                        source: thumb.modelData.url
                                        sourceSize.width: 220
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: true
                                    }

                                    Rectangle {
                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            bottom: parent.bottom
                                        }
                                        height: 22
                                        color: "#a6000000"
                                    }

                                    Text {
                                        anchors {
                                            left: parent.left
                                            right: parent.right
                                            bottom: parent.bottom
                                            leftMargin: 8
                                            rightMargin: 8
                                            bottomMargin: 4
                                        }
                                        text: thumb.modelData.name
                                        color: "#ffffff"
                                        font.pixelSize: 10
                                        elide: Text.ElideRight
                                    }
                                }

                                TapHandler {
                                    onTapped: Host.setWallpaper(thumb.modelData.value)
                                }
                            }
                        }
                    }
                }

                Item {
                    width: 1
                    height: 4
                }

                Item {
                    width: parent.width
                    height: 42

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Fit mode"
                        color: Theme.textPrimary
                        font.pixelSize: 15
                    }

                    Row {
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 8

                        Repeater {
                            model: [
                                { "label": "Fill", "value": "fill" },
                                { "label": "Align", "value": "align" },
                                { "label": "Stretch", "value": "stretch" }
                            ]

                            delegate: DashButton {
                                required property var modelData

                                text: modelData.label
                                primary: page.currentMode === modelData.value
                                onClicked: Host.setWallpaperMode(modelData.value)
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.surfaceBorder
                }

                Item {
                    width: 1
                    height: 8
                }

                Text {
                    text: "Lock screen"
                    color: Theme.textPrimary
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }

                Item {
                    width: parent.width
                    height: 42

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Show lock screen at startup"
                        color: Theme.textPrimary
                        font.pixelSize: 15
                    }

                    Rectangle {
                        id: lockToggle

                        width: 84
                        height: 40
                        radius: 20
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        color: page.lockAtBoot ? Theme.accent : Theme.track
                        border.width: 1
                        border.color: page.lockAtBoot ? Theme.accent : Theme.surfaceBorder

                        Rectangle {
                            width: 32
                            height: 32
                            radius: 16
                            anchors.verticalCenter: parent.verticalCenter
                            x: page.lockAtBoot ? parent.width - width - 4 : 4
                            color: "#f2f5fa"

                            Behavior on x {
                                NumberAnimation { duration: 120 }
                            }
                        }

                        TapHandler {
                            onTapped: {
                                page.lockAtBoot = !page.lockAtBoot
                                Host.setLockScreen(page.lockAtBoot)
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 42

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Auto-lock after"
                        color: Theme.textPrimary
                        font.pixelSize: 15
                    }

                    Row {
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 8

                        Repeater {
                            model: [
                                { "label": "Off", "value": 0 },
                                { "label": "1m", "value": 60 },
                                { "label": "5m", "value": 300 },
                                { "label": "15m", "value": 900 },
                                { "label": "30m", "value": 1800 }
                            ]

                            delegate: DashButton {
                                required property var modelData

                                text: modelData.label
                                primary: page.autoLockSeconds === modelData.value
                                onClicked: {
                                    page.autoLockSeconds = modelData.value
                                    Host.setAutoLockSeconds(modelData.value)
                                }
                            }
                        }
                    }
                }

                DashButton {
                    text: "Lock now"
                    onClicked: page.lockNow()
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.surfaceBorder
                }

                Item {
                    width: 1
                    height: 6
                }

                Text {
                    text: "Notifications"
                    color: Theme.textPrimary
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }

                Text {
                    width: parent.width
                    text: "In-app and DE-agnostic: apps call Host.notify(), no "
                          + "desktop notification daemon involved."
                    color: Theme.textMuted
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }

                Item {
                    width: parent.width
                    height: 40

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        DashButton {
                            text: "Send test notification"
                            onClicked: Host.notify("pi-dash",
                                                   "Notifications are working")
                        }

                        DashButton {
                            text: "Clear all"
                            onClicked: Host.clearNotifications()
                        }
                    }
                }

                Item {
                    width: 1
                    height: 4
                }
            }
        }
    }
}
