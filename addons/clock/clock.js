.pragma library

function pad(value) {
    return value < 10 ? "0" + value : "" + value
}

function time(clock, format24h, showSeconds) {
    if (!clock)
        return ""
    let hour = clock.hour
    let text
    if (format24h) {
        text = pad(hour) + ":" + pad(clock.minute)
    } else {
        const suffix = hour >= 12 ? "PM" : "AM"
        hour = hour % 12
        if (hour === 0)
            hour = 12
        text = hour + ":" + pad(clock.minute) + " " + suffix
    }
    if (showSeconds)
        text += ":" + pad(clock.second)
    return text
}

function dateText(clock) {
    return clock ? clock.day + " " + clock.date : ""
}
