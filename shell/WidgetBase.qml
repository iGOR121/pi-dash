import QtQuick

// Base type for every addon widget. The shell loads an addon's entry QML
// and its root component must be a WidgetBase:
//
//     import shell
//
//     WidgetBase {
//         property string label: setting("label", "Hello")
//         ...
//     }
//
// The shell injects these properties before Component.onCompleted runs.
Item {
    id: root

    property string instanceId: ""
    property string addon: ""
    property var settings: ({})

    // Read a setting with a fallback (used when the key is missing).
    function setting(key, fallback) {
        if (settings && settings.hasOwnProperty(key))
            return settings[key]
        return fallback
    }

    // Change + persist a setting for this instance into dashboard.json.
    // Note: this mutates the settings object in place; update any local
    // properties bound to it yourself. For addons that ship a dashlet, the
    // host routes this into the shared app settings instead.
    function setSetting(key, value) {
        if (settings)
            settings[key] = value
        Host.setSetting(instanceId, key, value)
    }

    // Post an in-app (DE-agnostic) notification.
    function notify(title, text) {
        Host.notify(title, text)
    }
}
