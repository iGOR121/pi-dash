import QtQuick
import shell

// One grid cell: a card + a Loader that instantiates the addon's QML.
// The addon receives instanceId/addon/settings as initial properties,
// so they are valid inside its Component.onCompleted.
//
// Interaction:
//   normal mode   addon gets all input; long-press asks the shell to enter
//                 edit mode (see Main.qml)
//   edit mode     addon is disabled; drag the card to move it, drag the
//                 bottom-right grip to resize, the sliders button opens
//                 settings, × removes
Rectangle {
    id: slot

    property string instanceId: ""
    property string addonId: ""
    property string addonName: ""
    property url entryUrl: ""
    property var settings: ({})
    property var schema: []
    property bool missing: false
    property bool hasApp: false
    property bool editMode: false
    property bool glass: false   // translucent card over a wallpaper

    // grid metrics, injected by WidgetGrid so drag/resize can snap to cells
    property real cellW: 100
    property real cellH: 80
    property real gridGap: 8
    property int gridCols: 8
    property int gridRows: 5
    property int minW: 1
    property int minH: 1
    // committed cell geometry (from dashboard.json, via WidgetGrid)
    property int gridX: 0
    property int gridY: 0
    property int gridW: 1
    property int gridH: 1

    // true while the user is dragging the resize grip (keeps the move
    // handler out of the gesture)
    property bool resizing: false
    property real dragDx: 0
    property real dragDy: 0

    signal editRequested()
    signal settingsRequested(string instanceId, string addonName, var schema, var settings)
    signal appRequested(string addonId)

    radius: Theme.radius
    color: glass ? Theme.surfaceGlass : Theme.surface
    border.width: editMode ? 2 : 1
    border.color: missing ? Theme.bad
                          : (editMode ? Theme.accent : Theme.surfaceBorder)

    transform: Translate {
        x: slot.dragDx
        y: slot.dragDy
    }

    Loader {
        id: loader

        anchors.fill: parent
        anchors.margins: Theme.padding
        active: !slot.missing && slot.entryUrl.toString().length > 0
        enabled: !slot.editMode
    }

    Component.onCompleted: {
        if (loader.active && !loader.item)
            loader.setSource(slot.entryUrl, {
                "instanceId": slot.instanceId,
                "addon": slot.addonId,
                "settings": slot.settings,
            })
    }

    // Settings changed from the sheet (or elsewhere): hand the widget a fresh
    // settings object so its `setting(...)` bindings re-evaluate live.
    Connections {
        target: Host

        function onSettingsChanged(instanceId, settings) {
            if (instanceId !== slot.instanceId)
                return
            slot.settings = settings   // keep the sheet's snapshot fresh
            if (loader.item)
                loader.item.settings = settings
        }
    }

    // Long-press = "I want to rearrange things" (works on desktop too).
    // A plain tap on a dashlet-backed widget opens its app.
    TapHandler {
        enabled: !slot.editMode
        onLongPressed: slot.editRequested()
        onTapped: if (slot.hasApp) slot.appRequested(slot.addonId)
    }

    // Darken the addon while editing and buffer stray taps.
    Rectangle {
        anchors.fill: parent
        radius: slot.radius
        color: "#59000000"
        visible: slot.editMode
    }

    // ------------------------------------------------------------ move drag
    DragHandler {
        target: null
        enabled: slot.editMode && !slot.resizing

        // Live grid snap: the card jumps one whole cell at a time and stays
        // inside the grid while the finger is down.
        onTranslationChanged: {
            const stepX = slot.cellW + slot.gridGap
            const stepY = slot.cellH + slot.gridGap
            let sx = Math.round(translation.x / stepX) * stepX
            let sy = Math.round(translation.y / stepY) * stepY
            const minX = -slot.gridX * stepX
            const maxX = (slot.gridCols - slot.gridX - slot.gridW) * stepX
            const minY = -slot.gridY * stepY
            const maxY = (slot.gridRows - slot.gridY - slot.gridH) * stepY
            slot.dragDx = Math.max(minX, Math.min(maxX, sx))
            slot.dragDy = Math.max(minY, Math.min(maxY, sy))
        }

        onActiveChanged: {
            if (!active)
                slot.commitMove()
        }
    }

    function commitMove() {
        if (!slot.editMode) {
            slot.dragDx = 0
            slot.dragDy = 0
            return
        }
        const stepX = slot.cellW + slot.gridGap
        const stepY = slot.cellH + slot.gridGap
        const cellDx = Math.round(slot.dragDx / stepX)
        const cellDy = Math.round(slot.dragDy / stepY)

        slot.dragDx = 0
        slot.dragDy = 0

        const tx = Math.max(0, Math.min(slot.gridCols - slot.gridW,
                                        slot.gridX + cellDx))
        const ty = Math.max(0, Math.min(slot.gridRows - slot.gridH,
                                        slot.gridY + cellDy))
        if (tx === slot.gridX && ty === slot.gridY)
            return   // dropped on the same cell: nothing to persist or rebuild

        Host.moveWidget(slot.instanceId, tx, ty)
    }

    // ---------------------------------------------------------- resize grip
    Rectangle {
        id: resizeHandle

        visible: slot.editMode
        width: 42
        height: 42
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: 2
        }
        radius: 10
        color: resizeDrag.active ? Theme.accent : "transparent"

        property real baseW: 0
        property real baseH: 0

        Canvas {
            anchors.centerIn: parent
            width: 16
            height: 16

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = resizeDrag.active ? Theme.bg : Theme.accent
                ctx.lineWidth = 2
                ctx.lineCap = "round"
                for (let i = 0; i < 3; ++i) {
                    const d = 3 + i * 5
                    ctx.beginPath()
                    ctx.moveTo(width - d, height - 2)
                    ctx.lineTo(width - 2, height - d)
                    ctx.stroke()
                }
            }
        }

        // Claims the gesture before the move drag can activate.
        TapHandler {
            onPressedChanged: slot.resizing = pressed
        }

        DragHandler {
            id: resizeDrag

            target: null

            onActiveChanged: {
                if (active) {
                    resizeHandle.baseW = slot.width
                    resizeHandle.baseH = slot.height
                } else {
                    slot.commitResize()
                }
            }

            onTranslationChanged: {
                if (!active)
                    return
                const stepX = slot.cellW + slot.gridGap
                const stepY = slot.cellH + slot.gridGap
                const minPxW = slot.minW * slot.cellW + (slot.minW - 1) * slot.gridGap
                const minPxH = slot.minH * slot.cellH + (slot.minH - 1) * slot.gridGap
                const maxPxW = slot.parent ? slot.parent.width - slot.x : slot.width
                const maxPxH = slot.parent ? slot.parent.height - slot.y : slot.height
                // snap to whole cells while dragging
                const dx = Math.round(translation.x / stepX) * stepX
                const dy = Math.round(translation.y / stepY) * stepY
                slot.width = Math.max(minPxW, Math.min(maxPxW,
                                                       resizeHandle.baseW + dx))
                slot.height = Math.max(minPxH, Math.min(maxPxH,
                                                         resizeHandle.baseH + dy))
            }
        }
    }

    function commitResize() {
        if (!slot.editMode)
            return
        const stepX = slot.cellW + slot.gridGap
        const stepY = slot.cellH + slot.gridGap
        const nw = Math.max(slot.minW, Math.round((slot.width + slot.gridGap) / stepX))
        const nh = Math.max(slot.minH, Math.round((slot.height + slot.gridGap) / stepY))
        Host.resizeWidget(slot.instanceId, nw, nh)
    }

    // --------------------------------------------------------------- badges
    Rectangle {
        visible: slot.editMode && !slot.missing
        width: 34
        height: 34
        radius: 17
        x: 5
        y: 5
        color: Theme.surface
        border.width: 1
        border.color: Theme.accent

        // Drawn "sliders" icon: no font or emoji coverage needed on the Pi.
        Canvas {
            anchors.centerIn: parent
            width: 20
            height: 20

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = Theme.accent
                ctx.lineWidth = 2
                ctx.lineCap = "round"
                const rows = [5, 10, 15]
                const knobs = [13, 7, 11]
                for (let i = 0; i < rows.length; ++i) {
                    ctx.beginPath()
                    ctx.moveTo(2, rows[i])
                    ctx.lineTo(width - 2, rows[i])
                    ctx.stroke()

                    ctx.fillStyle = Theme.surface
                    ctx.beginPath()
                    ctx.arc(knobs[i], rows[i], 3, 0, Math.PI * 2)
                    ctx.fill()
                    ctx.stroke()
                }
            }
        }

        TapHandler {
            onTapped: slot.settingsRequested(slot.instanceId, slot.addonName,
                                             slot.schema, slot.settings)
        }
    }

    Rectangle {
        visible: slot.editMode
        width: 34
        height: 34
        radius: 17
        anchors {
            top: parent.top
            right: parent.right
            margins: 5
        }
        color: Theme.surface
        border.width: 1
        border.color: Theme.bad

        Text {
            anchors.centerIn: parent
            y: -1
            text: "×"
            color: Theme.bad
            font.pixelSize: 22
        }

        TapHandler {
            onTapped: Host.removeWidget(slot.instanceId)
        }
    }

    // Placeholder for widgets whose addon folder isn't installed.
    Column {
        anchors.centerIn: parent
        visible: slot.missing
        spacing: 6

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "⚠"
            color: Theme.warn
            font.pixelSize: 28
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "addon not found:\n" + slot.addonName
            color: Theme.textMuted
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
