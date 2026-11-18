pragma Singleton
import QtQuick

// Shared look & feel. Addons import it via `import shell` and read these
// tokens so third-party widgets match the rest of the dashboard.
QtObject {
    // palette
    readonly property color bg: "#0d1017"
    readonly property color surface: "#161b24"
    readonly property color surfaceGlass: "#d1161b24"   // translucent card over wallpaper
    readonly property color surfaceBorder: "#232a37"
    readonly property color textPrimary: "#e9edf4"
    readonly property color textMuted: "#8a93a7"
    readonly property color accent: "#4f9cf9"
    readonly property color good: "#3ecf8e"
    readonly property color warn: "#f5a623"
    readonly property color bad: "#ef5b6b"
    readonly property color track: "#2a3140"      // "off" state / gauge track

    // metrics
    readonly property int radius: 14
    readonly property int gap: 8
    readonly property int padding: 10
}
