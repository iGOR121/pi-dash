import QtQuick
import shell

// Left page: in-app notifications. DE-agnostic — addons post here through
// Host.notify(title, text); nothing talks to a desktop notification daemon.
Item {
    id: page

    property bool glass: false
    property var items: []

    function reload() {
        page.items = Host.notifications()
    }

    Component.onCompleted: reload()

    Connections {
        target: Host
        function onNotificationsChanged() {
            page.reload()
        }
    }

    Column {
        anchors {
            fill: parent
            margins: 16
        }
        spacing: 10

        Item {
            width: parent.width
            height: 44

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Notifications"
                color: Theme.textPrimary
                font.pixelSize: 21
                font.weight: Font.DemiBold
            }

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 148
                    verticalCenter: parent.verticalCenter
                }
                text: page.items.length === 0 ? "" : page.items.length + " total"
                color: Theme.textMuted
                font.pixelSize: 12
            }

            DashButton {
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                visible: page.items.length > 0
                text: "Clear all"
                onClicked: Host.clearNotifications()
            }
        }

        Flickable {
            width: parent.width
            height: parent.height - 54
            contentWidth: width
            contentHeight: list.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: list

                width: parent.width
                spacing: 8

                Text {
                    visible: page.items.length === 0
                    width: parent.width
                    topPadding: 60
                    horizontalAlignment: Text.AlignHCenter
                    text: "You're all caught up.\nApps can post notifications here."
                    color: Theme.textMuted
                    font.pixelSize: 15
                    lineHeight: 1.4
                }

                Repeater {
                    model: page.items

                    delegate: Rectangle {
                        id: card

                        required property var modelData

                        width: list.width
                        height: body.height + 22
                        radius: Theme.radius
                        color: page.glass ? Theme.surfaceGlass : Theme.surface
                        border.width: 1
                        border.color: Theme.surfaceBorder

                        Column {
                            id: body

                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                leftMargin: 14
                                rightMargin: 46
                                topMargin: 11
                            }
                            spacing: 3

                            Text {
                                width: parent.width
                                text: card.modelData.title
                                color: Theme.textPrimary
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: card.modelData.text
                                color: Theme.textMuted
                                font.pixelSize: 13
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                text: card.modelData.time
                                color: Theme.textMuted
                                font.pixelSize: 10
                            }
                        }

                        Rectangle {
                            anchors {
                                top: parent.top
                                right: parent.right
                                margins: 8
                            }
                            width: 28
                            height: 28
                            radius: 14
                            color: dismissTap.pressed ? Theme.surfaceBorder : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                color: Theme.textMuted
                                font.pixelSize: 18
                            }

                            TapHandler {
                                id: dismissTap
                                onTapped: Host.dismissNotification(card.modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
