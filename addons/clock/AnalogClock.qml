import QtQuick
import shell

// Small analog dial used by both the clock widget and the clock app.
Item {
    id: clock

    property int hours: 0
    property int minutes: 0
    property int seconds: 0
    property bool showSeconds: true

    Canvas {
        id: canvas

        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()

            const size = Math.min(width, height)
            const cx = width / 2
            const cy = height / 2
            const r = size / 2 - 3

            ctx.fillStyle = Theme.bg
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.fill()
            ctx.strokeStyle = Theme.surfaceBorder
            ctx.lineWidth = 2
            ctx.stroke()

            for (let i = 0; i < 12; ++i) {
                const angle = (i * Math.PI / 6) - Math.PI / 2
                const outer = r * 0.90
                const inner = i % 3 === 0 ? r * 0.76 : r * 0.84
                ctx.beginPath()
                ctx.moveTo(cx + Math.cos(angle) * inner, cy + Math.sin(angle) * inner)
                ctx.lineTo(cx + Math.cos(angle) * outer, cy + Math.sin(angle) * outer)
                ctx.strokeStyle = i % 3 === 0 ? Theme.textMuted : Theme.surfaceBorder
                ctx.lineWidth = i % 3 === 0 ? 2 : 1
                ctx.stroke()
            }

            const hourAngle = ((clock.hours % 12) + clock.minutes / 60)
                              * Math.PI / 6 - Math.PI / 2
            const minuteAngle = (clock.minutes + clock.seconds / 60)
                                * Math.PI / 30 - Math.PI / 2
            const secondAngle = clock.seconds * Math.PI / 30 - Math.PI / 2

            ctx.lineCap = "round"
            ctx.strokeStyle = Theme.textPrimary

            ctx.lineWidth = Math.max(2, r * 0.07)
            ctx.beginPath()
            ctx.moveTo(cx, cy)
            ctx.lineTo(cx + Math.cos(hourAngle) * r * 0.48,
                       cy + Math.sin(hourAngle) * r * 0.48)
            ctx.stroke()

            ctx.lineWidth = Math.max(1.5, r * 0.045)
            ctx.beginPath()
            ctx.moveTo(cx, cy)
            ctx.lineTo(cx + Math.cos(minuteAngle) * r * 0.72,
                       cy + Math.sin(minuteAngle) * r * 0.72)
            ctx.stroke()

            if (clock.showSeconds) {
                ctx.strokeStyle = Theme.accent
                ctx.lineWidth = 1.2
                ctx.beginPath()
                ctx.moveTo(cx, cy)
                ctx.lineTo(cx + Math.cos(secondAngle) * r * 0.80,
                           cy + Math.sin(secondAngle) * r * 0.80)
                ctx.stroke()
            }

            ctx.beginPath()
            ctx.arc(cx, cy, Math.max(1.5, r * 0.05), 0, Math.PI * 2)
            ctx.fillStyle = Theme.accent
            ctx.fill()
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: clock

            function onHoursChanged() { canvas.requestPaint() }
            function onMinutesChanged() { canvas.requestPaint() }
            function onSecondsChanged() { canvas.requestPaint() }
            function onShowSecondsChanged() { canvas.requestPaint() }
        }
    }
}
