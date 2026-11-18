import QtQuick
import shell

// Lays widget slots out on a fixed grid. The grid is defined in
// dashboard.json (cols/rows + x/y/w/h per widget); this item just turns
// grid coordinates into pixels.
Item {
    id: grid

    property int cols: 8
    property int rows: 5
    property var model: []
    property real gap: Theme.gap
    property bool editMode: false
    property bool hasWallpaper: false

    signal editRequested()
    signal settingsRequested(string instanceId, string addonName, var schema, var settings)
    signal appRequested(string addonId)

    readonly property real cellW: cols > 0 ? (width - gap * (cols + 1)) / cols : 0
    readonly property real cellH: rows > 0 ? (height - gap * (rows + 1)) / rows : 0

    // Faint cell outlines, only while editing, so the grid is visible.
    Canvas {
        id: gridOverlay

        anchors.fill: parent
        visible: grid.editMode
        opacity: 0.5

        onPaint: {
            if (!grid.editMode)
                return
            const ctx = getContext("2d")
            ctx.reset()
            ctx.strokeStyle = Theme.surfaceBorder
            ctx.lineWidth = 1
            for (let c = 0; c < grid.cols; ++c) {
                for (let r = 0; r < grid.rows; ++r) {
                    const x = grid.gap + c * (grid.cellW + grid.gap)
                    const y = grid.gap + r * (grid.cellH + grid.gap)
                    ctx.strokeRect(Math.round(x) + 0.5, Math.round(y) + 0.5,
                                   Math.round(grid.cellW), Math.round(grid.cellH))
                }
            }
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: grid

            function onEditModeChanged() { gridOverlay.requestPaint() }
            function onCellWChanged() { gridOverlay.requestPaint() }
            function onCellHChanged() { gridOverlay.requestPaint() }
        }
    }

    Repeater {
        model: grid.model

        WidgetSlot {
            id: slot

            required property var modelData

            x: grid.gap + modelData.x * (grid.cellW + grid.gap)
            y: grid.gap + modelData.y * (grid.cellH + grid.gap)
            width: modelData.w * grid.cellW + (modelData.w - 1) * grid.gap
            height: modelData.h * grid.cellH + (modelData.h - 1) * grid.gap

            instanceId: modelData.instanceId
            addonId: modelData.addon
            addonName: modelData.addonName
            entryUrl: modelData.entryUrl !== undefined ? modelData.entryUrl : ""
            settings: modelData.settings !== undefined ? modelData.settings : ({})
            schema: modelData.schema !== undefined ? modelData.schema : []
            minW: modelData.minW !== undefined ? modelData.minW : 1
            minH: modelData.minH !== undefined ? modelData.minH : 1
            missing: modelData.missing === true
            hasApp: modelData.hasApp === true
            editMode: grid.editMode
            glass: grid.hasWallpaper

            cellW: grid.cellW
            cellH: grid.cellH
            gridGap: grid.gap
            gridCols: grid.cols
            gridRows: grid.rows
            gridX: modelData.x
            gridY: modelData.y
            gridW: modelData.w
            gridH: modelData.h

            onEditRequested: grid.editRequested()
            onSettingsRequested: function (instanceId, addonName, schema, settings) {
                grid.settingsRequested(instanceId, addonName, schema, settings)
            }
            onAppRequested: function (addonId) {
                grid.appRequested(addonId)
            }
        }
    }
}
