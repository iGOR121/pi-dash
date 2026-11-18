import QtQuick
import shell

// Bluetooth status. Tap to open the Bluetooth dashlet.
WidgetBase {
    id: root

    readonly property var adapter: Bluetooth.adapter
    readonly property var paired: Bluetooth.paired
    readonly property bool available: Bluetooth.available

    readonly property int connectedCount: {
        let count = 0
        const list = root.paired || []
        for (let i = 0; i < list.length; ++i)
            if (list[i].connected)
                count++
        return count
    }

    readonly property string stateText: {
        if (!root.available)
            return "Not installed"
        if (!root.adapter || !root.adapter.present)
            return "No adapter"
        if (!root.adapter.powered)
            return "Off"
        return root.connectedCount > 0
               ? root.connectedCount + " connected" : "Ready"
    }

    Column {
        anchors.centerIn: parent
        width: root.width - 10
        spacing: 3

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Bluetooth"
            color: Theme.textPrimary
            font.pixelSize: 17
            font.weight: Font.DemiBold
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.stateText
            color: (root.available && root.adapter && root.adapter.powered)
                   ? Theme.good : Theme.textMuted
            font.pixelSize: 12
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            visible: root.adapter && root.adapter.present
            text: root.adapter
                  ? (root.adapter.alias || root.adapter.name || "") : ""
            color: Theme.textMuted
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }
}
