import QtQuick
import shell

// Modal settings form, generated from an addon manifest's `settings` schema.
//
// The shell opens it with (instanceId, title, schema, values); every edit is
// pushed straight to Host.setSetting(), which persists to dashboard.json and
// notifies the live widget instance (see WidgetSlot/WidgetBase).
Item {
    id: sheet

    anchors.fill: parent
    visible: false
    z: 100

    property string instanceId: ""
    property string addonName: ""
    property var schema: []
    property var values: ({})
    // True when editing a dashlet's shared settings from its app page.
    property bool appMode: false
    // True when a widget's settings are shared with its dashlet app.
    property bool shared: false
    property string targetAddon: ""

    function open(instanceId, addonName, schema, values, shared) {
        sheet.instanceId = instanceId
        sheet.addonName = addonName || instanceId
        sheet.schema = schema || []
        sheet.values = Object.assign({}, values || ({}))
        sheet.appMode = false
        sheet.shared = shared === true
        sheet.targetAddon = ""
        visible = true
    }

    function openForApp(addonId, addonName, schema, values) {
        sheet.instanceId = addonId
        sheet.targetAddon = addonId
        sheet.addonName = addonName || addonId
        sheet.schema = schema || []
        sheet.values = Object.assign({}, values || ({}))
        sheet.appMode = true
        visible = true
    }

    function close() {
        visible = false
        Host.saveNow()   // flush the debounced write immediately
    }

    function valueFor(key, fallback) {
        const value = sheet.values[key]
        return (value === undefined || value === null) ? fallback : value
    }

    function boolValue(key, fallback) {
        const value = sheet.values[key]
        if (value === undefined || value === null)
            return fallback === true
        return value === true
    }

    function stringValue(key, fallback) {
        const value = sheet.values[key]
        if (value === undefined || value === null)
            return (fallback === undefined || fallback === null) ? "" : String(fallback)
        return String(value)
    }

    function numberText(spec) {
        const fallback = (spec.default === undefined || spec.default === null) ? 0 : spec.default
        const value = Number(valueFor(spec.key, fallback))
        if (!isFinite(value))
            return "0"
        return spec.type === "int" ? String(Math.round(value)) : String(Math.round(value * 10) / 10)
    }

    function stepNumber(spec, direction) {
        const fallback = (spec.default === undefined || spec.default === null) ? 0 : spec.default
        let value = Number(valueFor(spec.key, fallback))
        if (!isFinite(value))
            value = 0
        value += direction
        value = spec.type === "int" ? Math.round(value) : Math.round(value * 10) / 10
        setValue(spec.key, value)
    }

    function setValue(key, value) {
        const next = Object.assign({}, sheet.values)
        next[key] = value
        sheet.values = next
        if (sheet.appMode)
            Host.setAppSetting(sheet.targetAddon, key, value)
        else
            Host.setSetting(sheet.instanceId, key, value)
    }

    // ------------------------------------------------------------------ backdrop
    Rectangle {
        anchors.fill: parent
        color: "#b3000000"

        MouseArea {
            anchors.fill: parent
            onClicked: sheet.close()
        }
    }

    // --------------------------------------------------------------------- card
    Rectangle {
        id: card

        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 520)
        height: Math.min(parent.height - 32, 430)
        radius: Theme.radius
        color: Theme.surface
        border.width: 1
        border.color: Theme.surfaceBorder

        // swallow taps so the backdrop below does not close the sheet
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
            text: sheet.addonName
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
            text: sheet.appMode
                  ? "shared with the " + sheet.addonName + " widgets"
                  : (sheet.shared
                     ? "shared with the " + sheet.addonName + " app and widgets"
                     : "instance " + sheet.instanceId)
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

        // ------------------------------------------------------------------ body
        Item {
            id: body

            anchors {
                top: title.bottom
                topMargin: 44
                left: parent.left
                right: parent.right
                bottom: footer.top
                bottomMargin: 8
            }
            clip: true

            Text {
                anchors.centerIn: parent
                visible: sheet.schema.length === 0
                text: "This addon has no settings."
                color: Theme.textMuted
                font.pixelSize: 15
            }

            Flickable {
                id: flick

                anchors.fill: parent
                contentWidth: width
                contentHeight: form.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: form

                    width: flick.width
                    spacing: 2

                    Repeater {
                        model: sheet.schema

                        delegate: Rectangle {
                            id: row

                            required property var modelData

                            width: form.width
                            height: 64
                            color: "transparent"

                            Text {
                                anchors {
                                    left: parent.left
                                    leftMargin: 18
                                    top: parent.top
                                    topMargin: 9
                                    right: controlArea.left
                                    rightMargin: 12
                                }
                                text: row.modelData.label || row.modelData.key
                                color: Theme.textPrimary
                                font.pixelSize: 15
                                elide: Text.ElideRight
                            }

                            Text {
                                anchors {
                                    left: parent.left
                                    leftMargin: 18
                                    bottom: parent.bottom
                                    bottomMargin: 9
                                }
                                text: row.modelData.key
                                color: Theme.textMuted
                                font.pixelSize: 10
                            }

                            Item {
                                id: controlArea

                                anchors {
                                    right: parent.right
                                    rightMargin: 14
                                    verticalCenter: parent.verticalCenter
                                }
                                width: 240
                                height: 44

                                // -- bool ---------------------------------------
                                Rectangle {
                                    id: boolControl

                                    visible: row.modelData.type === "bool"
                                    anchors {
                                        right: parent.right
                                        verticalCenter: parent.verticalCenter
                                    }
                                    width: 84
                                    height: 40
                                    radius: 20
                                    color: boolControl.value ? Theme.accent : Theme.track
                                    border.width: 1
                                    border.color: boolControl.value ? Theme.accent : Theme.surfaceBorder

                                    readonly property bool value: sheet.boolValue(
                                        row.modelData.key, row.modelData.default)

                                    Rectangle {
                                        width: 32
                                        height: 32
                                        radius: 16
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: boolControl.value ? parent.width - width - 4 : 4
                                        color: "#f2f5fa"

                                        Behavior on x {
                                            NumberAnimation { duration: 120 }
                                        }
                                    }

                                    TapHandler {
                                        onTapped: sheet.setValue(row.modelData.key, !boolControl.value)
                                    }
                                }

                                // -- int / real ---------------------------------
                                Row {
                                    visible: row.modelData.type === "int" || row.modelData.type === "real"
                                    anchors {
                                        right: parent.right
                                        verticalCenter: parent.verticalCenter
                                    }
                                    spacing: 8

                                    DashButton {
                                        width: 40
                                        height: 40
                                        text: "−"
                                        onClicked: sheet.stepNumber(row.modelData, -1)
                                    }

                                    Text {
                                        width: 80
                                        anchors.verticalCenter: parent.verticalCenter
                                        horizontalAlignment: Text.AlignHCenter
                                        text: sheet.numberText(row.modelData)
                                        color: Theme.textPrimary
                                        font.pixelSize: 18
                                        font.weight: Font.DemiBold
                                    }

                                    DashButton {
                                        width: 40
                                        height: 40
                                        text: "+"
                                        onClicked: sheet.stepNumber(row.modelData, 1)
                                    }
                                }

                                // -- string -------------------------------------
                                Rectangle {
                                    visible: row.modelData.type === "string"
                                    anchors {
                                        right: parent.right
                                        verticalCenter: parent.verticalCenter
                                    }
                                    width: 240
                                    height: 42
                                    radius: 9
                                    color: Theme.bg
                                    border.width: 1
                                    border.color: stringInput.activeFocus ? Theme.accent : Theme.surfaceBorder
                                    clip: true

                                    TextInput {
                                        id: stringInput

                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: Theme.textPrimary
                                        font.pixelSize: 15
                                        selectByMouse: true

                                        Component.onCompleted: text = sheet.stringValue(
                                            row.modelData.key, row.modelData.default)

                                        function commit() {
                                            if (text !== sheet.stringValue(row.modelData.key,
                                                                           row.modelData.default))
                                                sheet.setValue(row.modelData.key, text)
                                        }

                                        onEditingFinished: commit()
                                        onActiveFocusChanged: if (!activeFocus) commit()
                                        Keys.onReturnPressed: {
                                            commit()
                                            focus = false
                                        }
                                        Keys.onEscapePressed: {
                                            text = sheet.stringValue(row.modelData.key,
                                                                     row.modelData.default)
                                            focus = false
                                        }

                                        Connections {
                                            target: sheet

                                            function onValuesChanged() {
                                                if (!stringInput.activeFocus)
                                                    stringInput.text = sheet.stringValue(
                                                        row.modelData.key, row.modelData.default)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---------------------------------------------------------------- footer
        Rectangle {
            id: footer

            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: 62
            color: "transparent"

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: Theme.surfaceBorder
            }

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 18
                    verticalCenter: parent.verticalCenter
                }
                text: "Changes save automatically"
                color: Theme.textMuted
                font.pixelSize: 12
            }

            DashButton {
                anchors {
                    right: parent.right
                    rightMargin: 14
                    verticalCenter: parent.verticalCenter
                }
                text: "Done"
                primary: true
                onClicked: sheet.close()
            }
        }
    }
}
