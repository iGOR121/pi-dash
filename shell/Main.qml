import QtQuick
import shell

Window {
    id: win

    width: 800
    height: 480
    minimumWidth: 480
    minimumHeight: 320
    visible: true
    title: "pi-dash"
    color: Theme.bg

    // Pulled from Host imperatively: keeping Host out of property bindings
    // avoids QML re-evaluating them while the engine tears down.
    property int gridCols: 8
    property int gridRows: 5
    property var widgetModel: []
    property bool editMode: false
    property string wallpaperUrl: ""
    property string wallpaperMode: "fill"
    property bool locked: true
    property int autoLockSeconds: 0

    // Pages: 0 = notifications, 1 = widgets, 2 = dashlets
    property int currentPage: 1
    property int pendingPage: -1
    // Exposed for tests / debugging: exact pixel offset of the pager.
    readonly property real pageOffset: pager.contentX
    property var appCatalog: []
    property int notificationCount: 0
    property bool appsExpanded: false

    // Open dashlet (full-page app)
    property string openApp: ""
    property string openAppName: ""
    property string openAppUrl: ""
    property int appSchemaLen: 0

    readonly property int wallpaperFillMode: {
        if (win.wallpaperMode === "stretch")
            return Image.Stretch
        if (win.wallpaperMode === "align")
            return Image.PreserveAspectFit
        return Image.PreserveAspectCrop
    }

    readonly property var activeApps: {
        const out = []
        for (let i = 0; i < win.appCatalog.length; ++i) {
            const app = win.appCatalog[i]
            let active = win.openApp === app.id
            if (!active) {
                for (let j = 0; j < win.widgetModel.length; ++j) {
                    if (win.widgetModel[j].addon === app.id) {
                        active = true
                        break
                    }
                }
            }
            if (active)
                out.push(app)
        }
        return out
    }

    readonly property string activeAppsText: {
        if (activeApps.length === 0)
            return ""
        if (activeApps.length === 1)
            return activeApps[0].name
        return activeApps.length + " active dashlets"
    }

    function refreshModel() {
        win.widgetModel = Host.widgetModel()
    }

    function setLocked(value) {
        win.locked = value
    }

    function goToPage(index) {
        index = Math.max(0, Math.min(2, index))
        win.currentPage = index
        win.appsExpanded = false
        if (pager.width <= 0) {
            // called before layout (e.g. from a tool); apply on first resize
            win.pendingPage = index
            return
        }
        snapAnim.stop()
        snapAnim.from = pager.contentX
        snapAnim.to = index * pager.width
        snapAnim.start()
    }

    function openSettingsFor(instanceId) {
        for (let i = 0; i < win.widgetModel.length; ++i) {
            const widget = win.widgetModel[i]
            if (widget.instanceId === instanceId) {
                settingsSheet.open(widget.instanceId, widget.addonName,
                                   widget.schema || [], widget.settings || ({}),
                                   widget.hasApp === true)
                return
            }
        }
        console.warn("openSettingsFor: no widget with id", instanceId)
    }

    function openAppSettings(addonId) {
        const schema = Host.appSchema(addonId)
        const values = Host.appSettings(addonId)
        let name = addonId
        for (let i = 0; i < win.appCatalog.length; ++i)
            if (win.appCatalog[i].id === addonId)
                name = win.appCatalog[i].name
        settingsSheet.openForApp(addonId, name, schema, values)
    }

    function openAddSheet() {
        addSheet.open(Host.addonCatalog())
    }

    function openSettings() {
        settingsPage.open()
    }

    function openDashlet(addonId) {
        if (win.openApp === addonId) {
            win.goToPage(2)
            return
        }
        for (let i = 0; i < win.appCatalog.length; ++i) {
            const app = win.appCatalog[i]
            if (app.id !== addonId)
                continue
            win.openApp = app.id
            win.openAppName = app.name
            win.openAppUrl = app.entryUrl
            win.appSchemaLen = Host.appSchema(app.id).length
            appLoader.setSource(app.entryUrl, {
                "addon": app.id,
                "settings": Host.appSettings(app.id),
                "glass": win.wallpaperUrl !== "",
            })
            win.goToPage(2)
            return
        }
        console.warn("openDashlet: unknown dashlet", addonId)
    }

    function closeDashlet() {
        appLoader.setSource("")
        win.openApp = ""
        win.openAppName = ""
        win.openAppUrl = ""
        win.appSchemaLen = 0
    }

    // ---------------------------------------------------------------- state
    Component.onCompleted: {
        win.gridCols = Host.gridCols()
        win.gridRows = Host.gridRows()
        win.refreshModel()
        win.wallpaperUrl = Host.wallpaperUrl()
        win.wallpaperMode = Host.wallpaperMode()
        win.autoLockSeconds = Host.autoLockSeconds()
        win.appCatalog = Host.appCatalog()
        win.notificationCount = Host.notificationCount()
        win.locked = Host.startLocked()
        Qt.callLater(function () {
            pager.contentX = win.currentPage * pager.width
        })
    }

    onLockedChanged: {
        if (win.locked) {
            win.editMode = false
            win.appsExpanded = false
            settingsSheet.close()
            addSheet.close()
            settingsPage.close()
        }
    }

    Connections {
        target: Host

        function onLayoutChanged() {
            Qt.callLater(win.refreshModel)
        }

        function onWallpaperChanged() {
            win.wallpaperUrl = Host.wallpaperUrl()
            win.wallpaperMode = Host.wallpaperMode()
        }

        function onOptionsChanged() {
            win.autoLockSeconds = Host.autoLockSeconds()
        }

        function onNotificationsChanged() {
            win.notificationCount = Host.notificationCount()
        }

        function onAppSettingsChanged(addon, settings) {
            if (addon === win.openApp && appLoader.item)
                appLoader.item.settings = settings
        }
    }

    // ----------------------------------------------------------------- auto-lock
    Timer {
        id: idleTimer

        interval: Math.max(1, win.autoLockSeconds) * 1000
        running: !win.locked && win.autoLockSeconds > 0
        repeat: false
        onTriggered: win.setLocked(true)
    }

    Connections {
        target: Activity

        function onActivity() {
            if (!win.locked && idleTimer.running)
                idleTimer.restart()
        }
    }

    Shortcut {
        sequence: "Ctrl+L"
        onActivated: win.setLocked(!win.locked)
    }

    // ------------------------------------------------------------- background
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.bg }
            GradientStop { position: 1.0; color: "#131923" }
        }
    }

    // Blurred wallpaper: decode small, scale up — cheap and backend-agnostic.
    Image {
        id: wallpaperBlur

        anchors.fill: parent
        visible: win.wallpaperUrl !== ""
        source: win.wallpaperUrl
        sourceSize.width: 64
        fillMode: win.wallpaperFillMode
        smooth: true
        mipmap: true
        asynchronous: true
        cache: true
    }

    Rectangle {
        anchors.fill: parent
        visible: wallpaperBlur.visible
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#73101822" }
            GradientStop { position: 1.0; color: "#cc0d1017" }
        }
    }

    // Empty-dashboard hint (widgets page only).
    Rectangle {
        id: backdrop

        anchors.fill: parent
        color: "transparent"
        enabled: !win.locked && win.currentPage === 1

        Column {
            anchors.centerIn: parent
            visible: win.widgetModel.length === 0 && !win.editMode
                     && win.currentPage === 1
            spacing: 8

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No widgets yet"
                color: Theme.textPrimary
                font.pixelSize: 20
                font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Long-press anywhere to open edit mode"
                color: Theme.textMuted
                font.pixelSize: 14
            }
        }
    }

    // ------------------------------------------------------------------ pages
    Flickable {
        id: pager

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            bottomMargin: win.editMode ? 0 : 44
        }
        contentWidth: width * 3
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: !win.locked && !win.editMode && win.openApp === ""

        // Always settle on a page boundary, even after a short drag that did
        // not change the nearest page (otherwise it stops between pages).
        onMovementEnded: {
            const index = Math.max(0, Math.min(2, Math.round(contentX / width)))
            win.goToPage(index)
        }

        onContentXChanged: {
            if (snapAnim.running)
                return
            const index = Math.round(contentX / Math.max(1, width))
            if (index !== win.currentPage && index >= 0 && index <= 2)
                win.currentPage = index
        }

        onWidthChanged: {
            if (win.pendingPage >= 0) {
                win.currentPage = win.pendingPage
                contentX = win.pendingPage * width
                win.pendingPage = -1
            } else {
                contentX = win.currentPage * width
            }
        }

        NumberAnimation {
            id: snapAnim
            target: pager
            property: "contentX"
            duration: 220
            easing.type: Easing.OutCubic
            onStopped: win.currentPage = Math.round(pager.contentX / Math.max(1, pager.width))
        }

        // page 0 — notifications
        Item {
            x: 0
            width: pager.width
            height: pager.height

            NotificationsPage {
                anchors.fill: parent
                glass: win.wallpaperUrl !== ""
            }
        }

        // page 1 — widgets
        Item {
            x: pager.width
            width: pager.width
            height: pager.height

            // Long-press empty space (no widget under the finger) to edit.
            TapHandler {
                enabled: !win.editMode && !win.locked
                onLongPressed: win.editMode = true
            }

            WidgetGrid {
                id: grid

                anchors.fill: parent
                anchors.topMargin: win.editMode ? 54 : 0
                anchors.bottomMargin: win.editMode ? 62 : 0
                enabled: !win.locked
                cols: win.gridCols
                rows: win.gridRows
                model: win.widgetModel
                editMode: win.editMode
                hasWallpaper: win.wallpaperUrl !== ""

                onEditRequested: {
                    win.goToPage(1)
                    win.editMode = true
                }
                onSettingsRequested: function (instanceId, addonName, schema, settings) {
                    let shared = false
                    for (let i = 0; i < win.widgetModel.length; ++i)
                        if (win.widgetModel[i].instanceId === instanceId)
                            shared = win.widgetModel[i].hasApp === true
                    settingsSheet.open(instanceId, addonName, schema, settings, shared)
                }
                onAppRequested: function (addonId) {
                    win.openDashlet(addonId)
                }
            }
        }

        // page 2 — dashlets
        Item {
            x: pager.width * 2
            width: pager.width
            height: pager.height

            DashletsPage {
                anchors.fill: parent
                visible: win.openApp === ""
                model: win.appCatalog
                glass: win.wallpaperUrl !== ""
                onOpenAppRequested: function (addonId) {
                    win.openDashlet(addonId)
                }
            }

            Item {
                anchors.fill: parent
                visible: win.openApp !== ""

                Rectangle {
                    id: appHeader

                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                    }
                    height: 46
                    color: Theme.surface

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: Theme.surfaceBorder
                    }

                    DashButton {
                        anchors {
                            left: parent.left
                            leftMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        text: "← Dashlets"
                        onClicked: win.closeDashlet()
                    }

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 140
                            right: gear.left
                            rightMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        text: win.openAppName
                        color: Theme.textPrimary
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    DashButton {
                        id: gear

                        anchors {
                            right: parent.right
                            rightMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        visible: win.appSchemaLen > 0
                        text: "Settings"
                        onClicked: win.openAppSettings(win.openApp)
                    }
                }

                Rectangle {
                    anchors {
                        top: appHeader.bottom
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    color: win.wallpaperUrl !== "" ? "#e60d1017" : Theme.bg
                }

                Loader {
                    id: appLoader

                    anchors {
                        top: appHeader.bottom
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ system bar
    Rectangle {
        id: systemBar

        visible: !win.locked && !win.editMode
        anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
        }
        height: 44
        color: win.wallpaperUrl !== "" ? Theme.surfaceGlass : Theme.surface
        z: 5

        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 1
            color: Theme.surfaceBorder
        }

        Text {
            anchors {
                left: parent.left
                leftMargin: 14
                verticalCenter: parent.verticalCenter
            }
            text: ["Notifications", "Widgets", "Dashlets"][win.currentPage] || ""
            color: Theme.textMuted
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        // page dots
        Row {
            anchors.centerIn: parent
            spacing: 2

            Repeater {
                model: 3

                delegate: Item {
                    id: dot

                    required property int index

                    width: 34
                    height: 34

                    Rectangle {
                        anchors.centerIn: parent
                        width: dot.index === win.currentPage ? 10 : 8
                        height: width
                        radius: width / 2
                        color: dot.index === win.currentPage ? Theme.accent : Theme.track

                        Behavior on width {
                            NumberAnimation { duration: 120 }
                        }
                    }

                    Rectangle {
                        visible: dot.index === 0 && win.notificationCount > 0
                        anchors {
                            horizontalCenter: parent.horizontalCenter
                            horizontalCenterOffset: 8
                            top: parent.top
                            topMargin: 2
                        }
                        width: 15
                        height: 15
                        radius: 7.5
                        color: Theme.bad

                        Text {
                            anchors.centerIn: parent
                            text: win.notificationCount > 9 ? "9+" : win.notificationCount
                            color: "#ffffff"
                            font.pixelSize: 8
                            font.weight: Font.Bold
                        }
                    }

                    TapHandler {
                        onTapped: win.goToPage(dot.index)
                    }
                }
            }
        }

        // active dashlets
        Item {
            anchors {
                right: parent.right
                rightMargin: 10
                verticalCenter: parent.verticalCenter
            }
            width: Math.min(280, activeLabel.implicitWidth + 16)
            height: 32
            visible: win.activeAppsText.length > 0

            Text {
                id: activeLabel

                anchors.centerIn: parent
                width: parent.width - 16
                text: win.activeAppsText
                color: win.appsExpanded ? Theme.accent : Theme.textMuted
                font.pixelSize: 12
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
            }

            TapHandler {
                onTapped: win.appsExpanded = !win.appsExpanded
            }
        }
    }

    // expanded list of active dashlets
    Rectangle {
        id: appsPopup

        visible: win.appsExpanded && win.activeApps.length > 0
        anchors {
            right: parent.right
            rightMargin: 12
            bottom: systemBar.top
            bottomMargin: 8
        }
        width: 240
        height: popupColumn.height + 20
        radius: 10
        color: Theme.surface
        border.width: 1
        border.color: Theme.surfaceBorder
        z: 6

        Column {
            id: popupColumn

            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 10
            }
            spacing: 2

            Text {
                text: "Active dashlets"
                color: Theme.textMuted
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }

            Repeater {
                model: win.activeApps

                delegate: Item {
                    required property var modelData

                    width: popupColumn.width
                    height: 36

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        color: Theme.textPrimary
                        font.pixelSize: 14
                    }

                    Text {
                        anchors {
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                        }
                        text: "Open ›"
                        color: Theme.accent
                        font.pixelSize: 12
                    }

                    TapHandler {
                        onTapped: {
                            win.appsExpanded = false
                            win.openDashlet(modelData.id)
                        }
                    }
                }
            }
        }
    }

    // click-away to close the active-dashlets popup
    MouseArea {
        anchors.fill: parent
        visible: win.appsExpanded
        z: 4
        onClicked: win.appsExpanded = false
    }

    // ------------------------------------------------------- edit-mode chrome
    Rectangle {
        id: topBar

        visible: win.editMode
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: 52
        color: Theme.surface
        z: 5

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.surfaceBorder
        }

        Text {
            anchors {
                left: parent.left
                leftMargin: 16
                verticalCenter: parent.verticalCenter
            }
            text: "Edit layout"
            color: Theme.textPrimary
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }

        Text {
            anchors {
                left: parent.left
                leftMargin: 132
                verticalCenter: parent.verticalCenter
            }
            visible: win.width >= 720
            text: "drag to move  ·  corner resize  ·  settings  ·  × remove"
            color: Theme.textMuted
            font.pixelSize: 11
        }

        DashButton {
            id: doneButton

            anchors {
                right: parent.right
                rightMargin: 12
                verticalCenter: parent.verticalCenter
            }
            text: "Done"
            primary: true
            onClicked: win.editMode = false
        }

        DashButton {
            id: lockButton

            anchors {
                right: doneButton.left
                rightMargin: 8
                verticalCenter: parent.verticalCenter
            }
            text: "Lock"
            onClicked: win.setLocked(true)
        }

        DashButton {
            anchors {
                right: lockButton.left
                rightMargin: 8
                verticalCenter: parent.verticalCenter
            }
            text: "Settings"
            onClicked: win.openSettings()
        }
    }

    Rectangle {
        id: bottomBar

        visible: win.editMode
        anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
        }
        height: 60
        color: Theme.surface
        z: 5

        Rectangle {
            anchors.top: parent.top
            width: parent.width
            height: 1
            color: Theme.surfaceBorder
        }

        DashButton {
            anchors.centerIn: parent
            text: "+  Add widget"
            onClicked: win.openAddSheet()
        }
    }

    SettingsSheet {
        id: settingsSheet
        anchors.fill: parent
    }

    AddWidgetSheet {
        id: addSheet
        anchors.fill: parent
        onAdded: Qt.callLater(win.refreshModel)
    }

    SettingsPage {
        id: settingsPage
        anchors.fill: parent
        onLockNow: win.setLocked(true)
    }

    LockScreen {
        id: lockScreen
        anchors.fill: parent
        active: win.locked
        wallpaperUrl: win.wallpaperUrl
        fillMode: win.wallpaperFillMode
        activeAppsText: win.activeAppsText
        onUnlocked: win.setLocked(false)
    }
}
