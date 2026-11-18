import QtQuick
import shell

// Edit-mode picker: lists every installed addon. Tapping one asks the host
// to place it in the first free grid cell.
Item {
    id: sheet

    anchors.fill: parent
    visible: false
    z: 105

    property var catalog: []
    property string pageId: ""
    property string message: ""

    signal added()

    function open(catalog, pageId) {
        sheet.catalog = catalog || []
        sheet.pageId = pageId || ""
        sheet.message = ""
        visible = true
    }

    function close() {
        visible = false
    }

    Rectangle {
        anchors.fill: parent
        color: "#b3000000"

        MouseArea {
            anchors.fill: parent
            onClicked: sheet.close()
        }
    }

    Rectangle {
        id: card

        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 520)
        height: Math.min(parent.height - 32, 410)
        radius: Theme.radius
        color: Theme.surface
        border.width: 1
        border.color: Theme.surfaceBorder

        MouseArea {
            anchors.fill: parent
        }

        Text {
            id: title

            anchors {
                left: parent.left
                top: parent.top
                leftMargin: 18
                topMargin: 14
            }
            text: "Add a widget"
            color: Theme.textPrimary
            font.pixelSize: 19
            font.weight: Font.DemiBold
        }

        Text {
            anchors {
                left: title.left
                top: title.bottom
                topMargin: 2
            }
            text: sheet.catalog.length + " addons installed"
            color: Theme.textMuted
            font.pixelSize: 12
        }

        Rectangle {
            anchors {
                right: parent.right
                top: parent.top
                margins: 10
            }
            width: 38
            height: 38
            radius: 19
            color: closeTap.pressed ? Theme.surfaceBorder : "transparent"

            Text {
                anchors.centerIn: parent
                text: "×"
                color: Theme.textMuted
                font.pixelSize: 22
            }

            TapHandler {
                id: closeTap

                onTapped: sheet.close()
            }
        }

        Flickable {
            id: flick

            anchors {
                top: title.bottom
                topMargin: 40
                left: parent.left
                right: parent.right
                bottom: hint.top
                bottomMargin: 6
            }
            contentWidth: width
            contentHeight: list.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: list

                width: flick.width
                spacing: 6

                Repeater {
                    model: sheet.catalog

                    delegate: Rectangle {
                        id: entry

                        required property var modelData

                        x: 12
                        width: list.width - 24
                        height: 62
                        radius: 10
                        color: entryTap.pressed ? Theme.surfaceBorder : "transparent"
                        border.width: 1
                        border.color: Theme.surfaceBorder

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 12
                                top: parent.top
                                topMargin: 9
                            }
                            text: entry.modelData.name
                            color: Theme.textPrimary
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                        }

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 12
                                bottom: parent.bottom
                                bottomMargin: 9
                            }
                            text: entry.modelData.id + "  v" + entry.modelData.version
                                  + "  ·  " + entry.modelData.w + "×" + entry.modelData.h
                            color: Theme.textMuted
                            font.pixelSize: 11
                        }

                        Text {
                            anchors {
                                right: parent.right
                                rightMargin: 14
                                verticalCenter: parent.verticalCenter
                            }
                            text: "+ Add"
                            color: Theme.accent
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }

                        TapHandler {
                            id: entryTap

                            onTapped: {
                                const instanceId = Host.addWidgetToPage(
                                    entry.modelData.id, sheet.pageId)
                                if (instanceId.length > 0) {
                                    sheet.close()
                                    sheet.added()
                                } else {
                                    sheet.message = "No free space for " + entry.modelData.name
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            id: hint

            anchors {
                left: parent.left
                leftMargin: 18
                bottom: parent.bottom
                bottomMargin: 20
            }
            text: sheet.message.length > 0
                  ? sheet.message
                  : "New widgets land in the first free cell."
            color: sheet.message.length > 0 ? Theme.warn : Theme.textMuted
            font.pixelSize: 12
        }
    }
}
