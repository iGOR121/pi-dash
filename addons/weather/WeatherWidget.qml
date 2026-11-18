import QtQuick
import shell
import "weather.js" as Weather

// Weather via Open-Meteo (https://open-meteo.com) — free, no API key.
// Pure QML: no Python code involved, which is the point of the addon
// contract — drop a folder in addons/ and it works.
//
// Shows current conditions plus description, humidity, wind, sunrise/sunset,
// when it was last updated and when the next automatic update is due. The ↻
// button refreshes immediately (and restarts the interval).
WidgetBase {
    id: root

    property string location: setting("location", "Berlin")
    property string units: setting("units", "metric")
    property int refreshMinutes: Math.max(1, Number(setting("refreshMinutes", 30)) || 30)

    property string state: "loading"     // loading | ready | error
    property string errorMessage: ""
    property var weather: null
    property date updated
    property date nextUpdate
    property bool started: false
    property bool errorNotified: false

    // A layout change rebuilds widgets, but an in-flight request outlives the
    // item. `lifetime` lets late callbacks bail out instead of touching a
    // destroyed QML object (which throws and floods the log).
    property var lifetime: ({ alive: true })
    property var inflight: []

    readonly property bool showRain: root.state === "ready"
                                     && root.weather.wx.current.precipitation > 0

    function unitSymbol() {
        return root.units === "imperial" ? "°F" : "°C"
    }

    function windUnit() {
        return root.units === "imperial" ? "mph" : "km/h"
    }

    function rainUnit() {
        return root.units === "imperial" ? "in" : "mm"
    }

    function clockTime(date) {
        if (!date || isNaN(date.getTime()))
            return "--:--"
        return Qt.formatDateTime(date, "HH:mm")
    }

    // Surface the first failure in the notification centre (deduped: a broken
    // connection retried every 30 min should not spam the page).
    function fail(message) {
        root.state = "error"
        root.errorMessage = message
        if (!root.errorNotified) {
            root.errorNotified = true
            root.notify("Weather", "Update failed: " + message)
        }
    }

    function get(url, done) {
        const xhr = new XMLHttpRequest()
        const life = lifetime
        inflight.push(xhr)
        xhr.onreadystatechange = function () {
            if (!life.alive || xhr.readyState !== XMLHttpRequest.DONE)
                return
            const index = inflight.indexOf(xhr)
            if (index >= 0)
                inflight.splice(index, 1)
            if (xhr.status === 200) {
                try {
                    done(JSON.parse(xhr.responseText))
                } catch (err) {
                    root.fail("bad response")
                }
            } else {
                root.fail("HTTP " + xhr.status)
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    // Every fetch (automatic or manual) restarts the interval, so the next
    // update is always `refreshMinutes` from the latest attempt.
    function schedule() {
        refreshTimer.restart()
        root.nextUpdate = new Date(Date.now() + refreshTimer.interval)
    }

    function fetch() {
        state = "loading"
        errorMessage = ""
        schedule()

        // 1) resolve city name -> coordinates
        get("https://geocoding-api.open-meteo.com/v1/search?name="
            + encodeURIComponent(location) + "&count=1&language=en&format=json",
            function (geo) {
                const results = geo.results || []
                if (results.length === 0) {
                    root.fail("location not found")
                    return
                }
                const place = results[0]

                // 2) current conditions + today's min/max + sun times
                const unitParam = root.units === "imperial"
                      ? "&temperature_unit=fahrenheit&wind_speed_unit=mph"
                        + "&precipitation_unit=inch"
                      : ""
                get("https://api.open-meteo.com/v1/forecast?latitude="
                    + place.latitude + "&longitude=" + place.longitude
                    + "&current=temperature_2m,apparent_temperature,"
                    + "relative_humidity_2m,wind_speed_10m,precipitation,weather_code"
                    + "&daily=weather_code,temperature_2m_max,temperature_2m_min,"
                    + "sunrise,sunset"
                    + "&forecast_days=1&timezone=auto" + unitParam,
                    function (wx) {
                        root.weather = { place: place, wx: wx }
                        root.updated = new Date()
                        root.errorNotified = false
                        root.state = "ready"
                    })
            })
    }

    Timer {
        id: refreshTimer

        interval: root.refreshMinutes * 60000
        repeat: false
        onTriggered: root.fetch()
    }

    // Coalesce location/units changes into one request.
    Timer {
        id: reloadTimer
        interval: 300
        onTriggered: root.fetch()
    }

    Component.onDestruction: {
        lifetime.alive = false
        for (let i = 0; i < inflight.length; ++i)
            inflight[i].abort()
        inflight = []
    }

    onLocationChanged: if (started) reloadTimer.restart()
    onUnitsChanged: if (started) reloadTimer.restart()
    onRefreshMinutesChanged: if (started) schedule()

    Component.onCompleted: {
        started = true
        fetch()
    }

    // Tap anywhere on an errored widget to retry immediately.
    TapHandler {
        enabled: root.state === "error"
        onTapped: root.fetch()
    }

    Row {
        id: row

        anchors.fill: parent
        spacing: 18

        Column {
            id: leftColumn

            width: 110
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.state === "ready"
                      ? Weather.glyph(root.weather.wx.current.weather_code) : "…"
                color: Theme.textPrimary
                font.pixelSize: 52
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.state === "ready"
                      ? Math.round(root.weather.wx.current.temperature_2m) + "°" : ""
                color: Theme.textPrimary
                font.pixelSize: 40
                font.weight: Font.DemiBold
            }
        }

        Column {
            id: details

            width: Math.max(0, row.width - leftColumn.width - row.spacing - 38)
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: {
                    if (root.state === "ready") {
                        const place = root.weather.place
                        return place.country ? place.name + ", " + place.country : place.name
                    }
                    return root.state === "error" ? root.errorMessage : root.location + "…"
                }
                color: root.state === "error" ? Theme.bad : Theme.textPrimary
                font.pixelSize: 19
                font.weight: Font.DemiBold
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                visible: root.state === "ready"
                text: root.state === "ready"
                      ? Weather.describe(root.weather.wx.current.weather_code) : ""
                color: Theme.accent
                font.pixelSize: 14
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                visible: root.state === "ready"
                text: root.state === "ready"
                      ? "Feels like "
                        + Math.round(root.weather.wx.current.apparent_temperature)
                        + unitSymbol()
                        + "   ·   ↑ " + Math.round(root.weather.wx.daily.temperature_2m_max[0]) + "°"
                        + "   ↓ " + Math.round(root.weather.wx.daily.temperature_2m_min[0]) + "°"
                      : ""
                color: Theme.textMuted
                font.pixelSize: 13
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                visible: root.state === "ready"
                text: root.state === "ready"
                      ? "Humidity " + Math.round(root.weather.wx.current.relative_humidity_2m)
                        + "%   ·   Wind " + Math.round(root.weather.wx.current.wind_speed_10m)
                        + " " + windUnit()
                      : ""
                color: Theme.textMuted
                font.pixelSize: 13
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                visible: root.showRain
                text: root.showRain
                      ? "Precipitation " + root.weather.wx.current.precipitation
                        + " " + rainUnit()
                      : ""
                color: Theme.textMuted
                font.pixelSize: 13
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                visible: root.state === "ready"
                text: root.state === "ready"
                      ? "Sunrise " + Weather.shortTime(root.weather.wx.daily.sunrise[0])
                        + "   ·   Sunset " + Weather.shortTime(root.weather.wx.daily.sunset[0])
                      : ""
                color: Theme.textMuted
                font.pixelSize: 12
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                text: {
                    if (root.state === "ready")
                        return "Updated " + root.clockTime(root.updated)
                               + "   ·   next " + root.clockTime(root.nextUpdate)
                    if (root.state === "error")
                        return "Retry at " + root.clockTime(root.nextUpdate)
                    return "Updating…   ·   next " + root.clockTime(root.nextUpdate)
                }
                color: Theme.textMuted
                font.pixelSize: 10
            }

            Text {
                width: parent.width
                elide: Text.ElideRight
                visible: root.state === "error"
                text: "Tap the widget to retry now"
                color: Theme.textMuted
                font.pixelSize: 11
            }
        }
    }

    // Manual refresh. Spins while a request is in flight.
    Rectangle {
        id: refreshButton

        anchors {
            top: parent.top
            right: parent.right
        }
        width: 32
        height: 32
        radius: 16
        color: refreshTap.pressed ? Theme.surfaceBorder : "transparent"
        border.width: 1
        border.color: Theme.surfaceBorder
        opacity: root.state === "loading" ? 0.5 : 1

        Text {
            anchors.centerIn: parent
            text: "↻"
            color: Theme.accent
            font.pixelSize: 19

            RotationAnimator on rotation {
                running: root.state === "loading"
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: 900
            }
        }

        TapHandler {
            id: refreshTap

            enabled: root.state !== "loading"
            onTapped: root.fetch()
        }
    }
}
