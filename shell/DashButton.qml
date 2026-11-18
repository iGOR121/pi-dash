import QtQuick
import shell

// Small touch-friendly button used by the shell chrome and settings sheets.
Rectangle {
    id: btn

    property string text: ""
    property bool primary: false

    signal clicked()

    implicitWidth: label.implicitWidth + 34
    implicitHeight: 40
    width: implicitWidth
    height: implicitHeight
    radius: 10
    color: btn.primary
           ? (tap.pressed ? Qt.darker(Theme.accent, 1.15) : Theme.accent)
           : (tap.pressed ? Theme.surfaceBorder : "transparent")
    border.width: btn.primary ? 0 : 1
    border.color: Theme.surfaceBorder

    Text {
        id: label

        anchors.centerIn: parent
        text: btn.text
        color: btn.primary ? Theme.bg : Theme.textPrimary
        font.pixelSize: 15
        font.weight: Font.DemiBold
    }

    TapHandler {
        id: tap

        onTapped: btn.clicked()
    }
}
