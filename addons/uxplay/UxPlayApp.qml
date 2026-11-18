import QtQuick
import shell

// AirPlay dashlet: controls the UxPlay receiver, shows the current track and
// explains how to connect. Video casting is shown by the shell overlay.
DashletBase {
    id: root

    readonly property bool running: UxPlay.running
    readonly property bool casting: UxPlay.videoActive
    readonly property var now: UxPlay.nowPlaying
    readonly property string cover: UxPlay.coverUrl
    readonly property string errorText: UxPlay.lastError
    readonly property bool hasTrack: !!now && !!(now.title || now.artist)
    readonly property string serverName: setting("serverName", "pi-dash")
    readonly property int videoPort: setting("videoPort", 5010)

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

            // ------------------------------------------------------ status
            Rectangle {
                width: parent.width
                height: 84
                radius: Theme.radius
                color: root.glass ? Theme.surfaceGlass : Theme.surface
                border.width: 1
                border.color: Theme.surfaceBorder

                Item {
                    anchors.fill: parent
                    anchors.margins: 14

                    Rectangle {
                        id: statusDot

                        anchors.verticalCenter: parent.verticalCenter
                        width: 12
                        height: 12
                        radius: 6
                        color: !root.running ? Theme.textMuted
                                             : (root.casting ? Theme.accent
                                                             : Theme.good)
                    }

                    Column {
                        anchors {
                            left: statusDot.right
                            leftMargin: 12
                            verticalCenter: parent.verticalCenter
                            right: action.left
                            rightMargin: 12
                        }
                        spacing: 3

                        Text {
                            width: parent.width
                            text: !root.running
                                  ? "Receiver stopped"
                                  : (root.casting
                                     ? "Casting video"
                                     : (root.hasTrack ? "Receiving audio"
                                                      : "Waiting for an AirPlay client"))
                            color: Theme.textPrimary
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.serverName + "  ·  video port " + root.videoPort
                            color: Theme.textMuted
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }

                    DashButton {
                        id: action

                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        text: root.running ? "Stop" : "Start"
                        primary: !root.running
                        onClicked: root.running ? UxPlay.stop() : UxPlay.start()
                    }
                }
            }

            // -------------------------------------------------- instructions
            Text {
                visible: !root.running
                width: parent.width
                text: "On your iPhone, iPad or Mac open Control Center → "
                      + "Screen Mirroring (or the AirPlay menu) and choose "
                      + "“" + root.serverName + "”. Audio and screen mirroring "
                      + "both work."
                color: Theme.textMuted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            // --------------------------------------------------- now playing
            Rectangle {
                visible: root.hasTrack
                width: parent.width
                height: 98
                radius: Theme.radius
                color: root.glass ? Theme.surfaceGlass : Theme.surface
                border.width: 1
                border.color: Theme.surfaceBorder

                Row {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 12

                    Rectangle {
                        width: 78
                        height: 78
                        radius: 8
                        color: Theme.bg
                        clip: true

                        Image {
                            anchors.fill: parent
                            visible: root.cover.length > 0
                            source: root.cover
                            sourceSize.width: 200
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.cover.length === 0
                            text: "♪"
                            color: Theme.textMuted
                            font.pixelSize: 30
                        }
                    }

                    Column {
                        width: parent.width - 90
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Text {
                            width: parent.width
                            text: root.now.title || ""
                            color: Theme.textPrimary
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.now.artist || ""
                            color: Theme.accent
                            font.pixelSize: 14
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: root.now.album || ""
                            color: Theme.textMuted
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // -------------------------------------------------------- error
            Text {
                visible: root.errorText.length > 0
                width: parent.width
                text: root.errorText
                color: Theme.bad
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            // ---------------------------------------------------- auto start
            Item {
                width: parent.width
                height: 40

                DashButton {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Auto-start at boot"
                    primary: root.setting("autoStart", false)
                    onClicked: root.setSetting("autoStart",
                                               !root.setting("autoStart", false))
                }

                Text {
                    anchors {
                        left: parent.left
                        leftMargin: 190
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    text: "applies on the next launch"
                    color: Theme.textMuted
                    font.pixelSize: 10
                }
            }

            // -------------------------------------------------------- notes
            Text {
                width: parent.width
                text: "Audio metadata is posted to Notifications. When a "
                      + "mirrored video starts it opens fullscreen; the grey × "
                      + "in the top-right corner closes the cast (and stops the "
                      + "receiver)."
                color: Theme.textMuted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            Text {
                width: parent.width
                text: "UxPlay 1.73+ is required for embedded video (-vrtp); "
                      + "GStreamer tools are needed for the video receiver."
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
