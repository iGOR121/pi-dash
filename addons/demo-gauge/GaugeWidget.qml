import QtQuick
import shell

// A demo gauge: draws with Canvas and animates a fake sensor value so the
// addon API (settings, custom drawing) can be exercised without hardware.
WidgetBase {
    id: root

    property string label: setting("label", "Power")
    property string unit: setting("unit", "W")
    property real minV: setting("min", 0)
    property real maxV: setting("max", 100)
    property real value: minV + (maxV - minV) * 0.5
    property bool demo: setting("demo", true)

    readonly property real norm: maxV > minV
        ? Math.max(0, Math.min(1, (value - minV) / (maxV - minV))) : 0

    function valueColor() {
        return norm < 0.5 ? "#3ecf8e" : (norm < 0.8 ? "#f5a623" : "#ef5b6b")
    }

    // Slow animated sweep — swap this for a real sensor source later.
    property real t: 0
    NumberAnimation on t {
        running: root.demo
        loops: Animation.Infinite
        from: 0
        to: 1
        duration: 24000
        easing.type: Easing.InOutSine
    }
    onTChanged: if (demo)
        value = minV + (maxV - minV) * (0.5 + 0.42 * Math.sin(t * Math.PI * 2))

    Canvas {
        id: canvas

        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            bottom: footer.top
            bottomMargin: 4
        }
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.lineWidth = 12
            ctx.lineCap = "round"

            const cx = width / 2
            const cy = height / 2 + height * 0.10
            const r = Math.max(8, Math.min(width / 2, height * 0.62) - 12)
            const a0 = Math.PI * 0.75
            const a1 = Math.PI * 2.25

            ctx.strokeStyle = "#2a3140"
            ctx.beginPath()
            ctx.arc(cx, cy, r, a0, a1)
            ctx.stroke()

            ctx.strokeStyle = root.valueColor()
            ctx.beginPath()
            ctx.arc(cx, cy, r, a0, a0 + (a1 - a0) * root.norm)
            ctx.stroke()
        }

        Connections {
            target: root
            function onNormChanged() { canvas.requestPaint() }
        }
    }

    Column {
        anchors.centerIn: canvas
        anchors.verticalCenterOffset: canvas.height * 0.10
        spacing: 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Math.round(root.value)
            color: Theme.textPrimary
            font.pixelSize: 34
            font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.unit
            color: Theme.textMuted
            font.pixelSize: 13
        }
    }

    Text {
        id: footer

        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 2
        }
        text: root.label
        color: Theme.textMuted
        font.pixelSize: 14
    }

    Text {
        anchors {
            top: parent.top
            right: parent.right
            margins: 2
        }
        visible: root.demo
        text: "DEMO"
        color: Theme.warn
        font.pixelSize: 10
        font.letterSpacing: 1
    }
}
