import QtQuick
import shell
import "weather.js" as Weather

// Weather dashlet: current conditions, next 24 hours and a 7-day forecast.
// Settings are shared with the dashboard widget (Host routes both to the
// app-level weather settings).
DashletBase {
    id: root

    property string location: setting("location", "Berlin")
    property string units: setting("units", "metric")
    property int refreshMinutes: Math.max(1, Number(setting("refreshMinutes", 30)) || 30)

    property string state: "loading"     // loading | ready | error
    property string errorMessage: ""
    property var place: null
    property var current: null
    property var hours: []
    property var days: []
    property date updated
    property date nextUpdate
    property bool started: false

    property var lifetime: ({ alive: true })
    property var inflight: []

    function unitSymbol() {
        return root.units === "imperial" ? "°F" : "°C"
    }

    function windUnit() {
        return root.units === "imperial" ? "mph" : "km/h"
    }

    function clockTime(date) {
        if (!date || isNaN(date.getTime()))
            return "--:--"
        return Qt.formatDateTime(date, "HH:mm")
    }

    function schedule() {
        refreshTimer.restart()
        root.nextUpdate = new Date(Date.now() + refreshTimer.interval)
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
                    root.state = "error"
                    root.errorMessage = "bad response"
                }
            } else {
                root.state = "error"
                root.errorMessage = "HTTP " + xhr.status
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function fetch() {
        state = "loading"
        errorMessage = ""
        schedule()

        get("https://geocoding-api.open-meteo.com/v1/search?name="
            + encodeURIComponent(location) + "&count=1&language=en&format=json",
            function (geo) {
                const results = geo.results || []
                if (results.length === 0) {
                    root.state = "error"
                    root.errorMessage = "location not found"
                    return
                }
                const found = results[0]

                const unitParam = root.units === "imperial"
                      ? "&temperature_unit=fahrenheit&wind_speed_unit=mph"
                        + "&precipitation_unit=inch"
                      : ""
                get("https://api.open-meteo.com/v1/forecast?latitude="
                    + found.latitude + "&longitude=" + found.longitude
                    + "&current=temperature_2m,apparent_temperature,"
                    + "relative_humidity_2m,wind_speed_10m,precipitation,weather_code"
                    + "&hourly=temperature_2m,precipitation_probability,weather_code"
                    + "&daily=weather_code,temperature_2m_max,temperature_2m_min,"
                    + "precipitation_probability_max,sunrise,sunset"
                    + "&forecast_days=7&timezone=auto" + unitParam,
                    function (wx) {
                        root.place = found
                        root.current = wx.current

                        // 24 hours starting at the location's current hour
                        const currentHour = (wx.current.time || "").slice(0, 13) + ":00"
                        let start = 0
                        for (let i = 0; i < wx.hourly.time.length; ++i) {
                            if (wx.hourly.time[i] >= currentHour) {
                                start = i
                                break
                            }
                        }
                        const hours = []
                        for (let i = start;
                             i < Math.min(start + 24, wx.hourly.time.length); ++i) {
                            hours.push({
                                time: wx.hourly.time[i],
                                temp: wx.hourly.temperature_2m[i],
                                rain: wx.hourly.precipitation_probability
                                      ? wx.hourly.precipitation_probability[i] : 0,
                                code: wx.hourly.weather_code[i],
                            })
                        }
                        root.hours = hours

                        const days = []
                        for (let i = 0; i < wx.daily.time.length; ++i) {
                            days.push({
                                date: wx.daily.time[i],
                                min: wx.daily.temperature_2m_min[i],
                                max: wx.daily.temperature_2m_max[i],
                                rain: wx.daily.precipitation_probability_max
                                      ? wx.daily.precipitation_probability_max[i] : 0,
                                code: wx.daily.weather_code[i],
                                sunrise: wx.daily.sunrise ? wx.daily.sunrise[i] : "",
                                sunset: wx.daily.sunset ? wx.daily.sunset[i] : "",
                            })
                        }
                        root.days = days
                        root.updated = new Date()
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

    Flickable {
        anchors.fill: parent
        anchors.margins: 14
        contentWidth: width
        contentHeight: content.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content

            width: parent.width
            spacing: 6

            // ------------------------------------------------------ current
            Item {
                width: parent.width
                height: 64

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text {
                        text: root.state === "ready"
                              ? Weather.glyph(root.current.weather_code) : "…"
                        color: Theme.textPrimary
                        font.pixelSize: 40
                    }

                    Text {
                        visible: root.state === "ready"
                        text: root.state === "ready"
                              ? Math.round(root.current.temperature_2m) + unitSymbol() : ""
                        color: Theme.textPrimary
                        font.pixelSize: 32
                        font.weight: Font.DemiBold
                    }
                }

                Column {
                    anchors {
                        left: parent.left
                        leftMargin: 118
                        right: sideInfo.left
                        rightMargin: 12
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 2

                    Text {
                        width: parent.width
                        text: root.state === "ready"
                              ? root.place.name
                                + (root.place.country ? ", " + root.place.country : "")
                              : (root.state === "error" ? root.errorMessage : "Loading…")
                        color: root.state === "error" ? Theme.bad : Theme.textPrimary
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        visible: root.state === "ready"
                        text: root.state === "ready"
                              ? Weather.describe(root.current.weather_code) : ""
                        color: Theme.accent
                        font.pixelSize: 14
                    }

                    Text {
                        width: parent.width
                        visible: root.state === "ready"
                        text: root.state === "ready"
                              ? "Feels like "
                                + Math.round(root.current.apparent_temperature) + unitSymbol()
                                + "   ·   Humidity "
                                + Math.round(root.current.relative_humidity_2m) + "%"
                                + "   ·   Wind "
                                + Math.round(root.current.wind_speed_10m) + " " + windUnit()
                              : ""
                        color: Theme.textMuted
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }

                Column {
                    id: sideInfo

                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 2

                    Text {
                        anchors.right: parent.right
                        text: root.state === "ready"
                              ? "Updated " + root.clockTime(root.updated) : ""
                        color: Theme.textMuted
                        font.pixelSize: 10
                    }

                    Text {
                        anchors.right: parent.right
                        text: "Next " + root.clockTime(root.nextUpdate)
                        color: Theme.textMuted
                        font.pixelSize: 10
                    }

                    DashButton {
                        anchors.right: parent.right
                        height: 32
                        text: "↻ Refresh"
                        onClicked: root.fetch()
                    }
                }
            }

            // ------------------------------------------------------- hourly
            Text {
                visible: root.state === "ready"
                text: "Next 24 hours"
                color: Theme.textPrimary
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Flickable {
                visible: root.state === "ready"
                width: parent.width
                height: 74
                contentWidth: hourRow.width
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: hourRow
                    spacing: 6

                    Repeater {
                        model: root.hours

                        delegate: Rectangle {
                            id: hourCard

                            required property var modelData
                            required property int index

                            width: 54
                            height: 72
                            radius: 8
                            color: Theme.surface
                            border.width: 1
                            border.color: index === 0 ? Theme.accent : Theme.surfaceBorder

                            Column {
                                anchors.centerIn: parent
                                spacing: 1

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: hourCard.modelData.time.substring(11, 16)
                                    color: Theme.textMuted
                                    font.pixelSize: 10
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Weather.glyph(hourCard.modelData.code)
                                    color: Theme.textPrimary
                                    font.pixelSize: 20
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Math.round(hourCard.modelData.temp) + "°"
                                    color: Theme.textPrimary
                                    font.pixelSize: 15
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: hourCard.modelData.rain > 0
                                          ? "☂ " + Math.round(hourCard.modelData.rain) + "%" : " "
                                    color: Theme.accent
                                    font.pixelSize: 9
                                }
                            }
                        }
                    }
                }
            }

            // -------------------------------------------------------- daily
            Text {
                visible: root.state === "ready"
                text: "7-day forecast"
                color: Theme.textPrimary
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Column {
                width: parent.width
                visible: root.state === "ready"

                Repeater {
                    model: root.days

                    delegate: Item {
                        id: dayRow

                        required property var modelData
                        required property int index

                        width: content.width
                        height: 23

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 100
                            text: dayRow.index === 0
                                  ? "Today"
                                  : new Date(dayRow.modelData.date + "T12:00")
                                        .toLocaleDateString(Qt.locale(), "ddd")
                            color: Theme.textPrimary
                            font.pixelSize: 13
                        }

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 104
                                verticalCenter: parent.verticalCenter
                            }
                            text: Weather.glyph(dayRow.modelData.code)
                            color: Theme.textPrimary
                            font.pixelSize: 16
                        }

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 138
                                verticalCenter: parent.verticalCenter
                            }
                            text: Math.round(dayRow.modelData.min) + "°  /  "
                                  + Math.round(dayRow.modelData.max) + "°"
                            color: Theme.textMuted
                            font.pixelSize: 13
                        }

                        Text {
                            anchors {
                                right: parent.right
                                verticalCenter: parent.verticalCenter
                            }
                            text: dayRow.modelData.rain > 0
                                  ? "☂ " + Math.round(dayRow.modelData.rain) + "%" : ""
                            color: Theme.accent
                            font.pixelSize: 12
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: 1
                            color: Theme.surfaceBorder
                            opacity: 0.6
                        }
                    }
                }
            }

            Text {
                visible: root.state === "error"
                width: parent.width
                text: "Tap Refresh to try again, or adjust the shared weather "
                      + "settings with the gear above."
                color: Theme.textMuted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            Item {
                width: 1
                height: 4
            }
        }
    }
}
