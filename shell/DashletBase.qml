import QtQuick

// Base type for a dashlet page: a full-page app bundled with an addon.
//
//     import shell
//
//     DashletBase {
//         property string location: setting("location", "Berlin")
//     }
//
// The shell injects `addon`, `settings` and `glass`. Settings are shared
// with every widget of the same addon: setSetting() writes the app store.
Item {
    id: root

    property string addon: ""
    property var settings: ({})
    property bool glass: false

    function setting(key, fallback) {
        if (settings && settings.hasOwnProperty(key))
            return settings[key]
        return fallback
    }

    function setSetting(key, value) {
        if (settings)
            settings[key] = value
        Host.setAppSetting(addon, key, value)
    }

    function notify(title, text) {
        Host.notify(title, text)
    }
}
