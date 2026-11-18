import QtQuick
import shell

// Edit-mode manager for the vertical widget pages: reorder, choose the main
// page (opened at startup), add pages above/below the current one, and delete
// empty pages.
Item {
    id: sheet

    anchors.fill: parent
    visible: false
    z: 112

    property var pages: []
    property string currentId: ""

    signal pageCreated(string pageId)

    function open() {
        visible = true
    }

    function close() {
        visible = false
        Host.saveNow()
    }

    function addPage(before) {
        const pageId = Host.addWidgetPage(sheet.currentId, before)
        if (pageId.length > 0)
            sheet.pageCreated(pageId)
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
        width: Math.min(parent.width - 32, 560)
        height: Math.min(parent.height - 32, 430)
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
            text: "Widget pages"
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
            onClicked: sheet.close()
        }

        Text {
            anchors {
                left: title.left
                top: title.bottom
                topMargin: 2
                right: parent.right
                rightMargin: 18
            }
            text: "Swipe up/down between pages. The main page opens at "
                  + "startup; reorder or add pages above/below the current one."
            color: Theme.textMuted
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        Rectangle {
            id: headerLine

            anchors {
                top: parent.top
                topMargin: 76
                left: parent.left
                right: parent.right
            }
            height: 1
            color: Theme.surfaceBorder
        }

        Flickable {
            id: scroll

            anchors {
                top: headerLine.bottom
                topMargin: 8
                left: parent.left
                leftMargin: 14
                right: parent.right
                rightMargin: 14
                bottom: footer.top
                bottomMargin: 8
            }
            contentWidth: width
            contentHeight: list.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: list

                width: scroll.width
                spacing: 6

                Repeater {
                    model: sheet.pages

                    delegate: Rectangle {
                        id: pageRow

                        required property var modelData
                        required property int index

                        width: list.width
                        height: 68
                        radius: 10
                        color: Theme.bg
                        border.width: modelData.id === sheet.currentId ? 2 : 1
                        border.color: modelData.id === sheet.currentId
                                      ? Theme.accent : Theme.surfaceBorder

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 12
                                top: parent.top
                                topMargin: 9
                                right: pageButtons.left
                                rightMargin: 10
                            }
                            text: modelData.name
                            color: Theme.textPrimary
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 12
                                top: parent.top
                                topMargin: 32
                            }
                            text: (modelData.main ? "MAIN  ·  " : "")
                                  + modelData.widgetCount
                                  + (modelData.widgetCount === 1
                                     ? " widget" : " widgets")
                                  + (modelData.id === sheet.currentId
                                     ? "  ·  current" : "")
                            color: modelData.main ? Theme.accent : Theme.textMuted
                            font.pixelSize: 10
                        }

                        Row {
                            id: pageButtons

                            anchors {
                                right: parent.right
                                rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 5

                            DashButton {
                                width: 34
                                height: 30
                                text: "↑"
                                enabled: pageRow.index > 0
                                onClicked: Host.moveWidgetPage(
                                               pageRow.modelData.id, -1)
                            }

                            DashButton {
                                width: 34
                                height: 30
                                text: "↓"
                                enabled: pageRow.index < sheet.pages.length - 1
                                onClicked: Host.moveWidgetPage(
                                               pageRow.modelData.id, 1)
                            }

                            DashButton {
                                height: 30
                                visible: !pageRow.modelData.main
                                text: "Make main"
                                onClicked: Host.setMainWidgetPage(
                                               pageRow.modelData.id)
                            }

                            DashButton {
                                height: 30
                                visible: pageRow.modelData.widgetCount === 0
                                         && sheet.pages.length > 1
                                text: "Delete"
                                onClicked: Host.removeWidgetPage(
                                               pageRow.modelData.id)
                            }
                        }
                    }
                }

                Item {
                    width: 1
                    height: 2
                }
            }
        }

        Rectangle {
            id: footer

            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: 64
            color: "transparent"

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: Theme.surfaceBorder
            }

            Item {
                anchors {
                    fill: parent
                    leftMargin: 14
                    rightMargin: 14
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Add page"
                    color: Theme.textMuted
                    font.pixelSize: 12
                }

                Row {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 6

                    DashButton {
                        height: 32
                        text: "+ Above"
                        onClicked: sheet.addPage(true)
                    }

                    DashButton {
                        height: 32
                        text: "+ Below"
                        onClicked: sheet.addPage(false)
                    }
                }
            }
        }
    }
}
