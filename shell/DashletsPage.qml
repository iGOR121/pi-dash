import QtQuick
import shell

// Right page: launcher for dashlets — the full-page apps bundled with
// addons. Tapping one asks the shell to open it.
Item {
    id: page

    property var model: []
    property bool glass: false

    signal openAppRequested(string addonId)

    Column {
        anchors {
            fill: parent
            margins: 16
        }
        spacing: 8

        Text {
            text: "Dashlets"
            color: Theme.textPrimary
            font.pixelSize: 21
            font.weight: Font.DemiBold
        }

        Text {
            width: parent.width
            text: "Apps built for pi-dash. They share their settings with the "
                  + "matching widgets on the dashboard."
            color: Theme.textMuted
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        Flickable {
            width: parent.width
            height: parent.height - 56
            contentWidth: width
            contentHeight: list.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: list

                width: parent.width
                spacing: 8

                Text {
                    visible: page.model.length === 0
                    width: parent.width
                    topPadding: 40
                    horizontalAlignment: Text.AlignHCenter
                    text: "No dashlets installed."
                    color: Theme.textMuted
                    font.pixelSize: 15
                }

                Repeater {
                    model: page.model

                    delegate: Rectangle {
                        id: card

                        required property var modelData

                        width: list.width
                        height: 72
                        radius: Theme.radius
                        color: page.glass ? Theme.surfaceGlass : Theme.surface
                        border.width: 1
                        border.color: openTap.pressed ? Theme.accent : Theme.surfaceBorder

                        Text {
                            id: icon

                            anchors {
                                left: parent.left
                                leftMargin: 14
                                verticalCenter: parent.verticalCenter
                            }
                            text: card.modelData.icon.length > 0 ? card.modelData.icon : "▦"
                            color: Theme.accent
                            font.pixelSize: 30
                        }

                        Text {
                            anchors {
                                left: icon.right
                                leftMargin: 14
                                top: parent.top
                                topMargin: 13
                                right: chevron.left
                                rightMargin: 10
                            }
                            text: card.modelData.name
                            color: Theme.textPrimary
                            font.pixelSize: 17
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            anchors {
                                left: icon.right
                                leftMargin: 14
                                top: parent.top
                                topMargin: 38
                                right: chevron.left
                                rightMargin: 10
                            }
                            text: card.modelData.description
                            color: Theme.textMuted
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Text {
                            id: chevron

                            anchors {
                                right: parent.right
                                rightMargin: 16
                                verticalCenter: parent.verticalCenter
                            }
                            text: "›"
                            color: Theme.textMuted
                            font.pixelSize: 24
                        }

                        TapHandler {
                            id: openTap
                            onTapped: page.openAppRequested(card.modelData.id)
                        }
                    }
                }
            }
        }
    }
}
