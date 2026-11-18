.pragma library

// Shared WMO code helpers for the weather widget and app.

function describe(code) {
    if (code === 0) return "Clear sky"
    if (code === 1) return "Mainly clear"
    if (code === 2) return "Partly cloudy"
    if (code === 3) return "Overcast"
    if (code === 45 || code === 48) return "Fog"
    if (code === 51) return "Light drizzle"
    if (code === 53) return "Drizzle"
    if (code === 55) return "Heavy drizzle"
    if (code === 56 || code === 57) return "Freezing drizzle"
    if (code === 61) return "Light rain"
    if (code === 63) return "Rain"
    if (code === 65) return "Heavy rain"
    if (code === 66 || code === 67) return "Freezing rain"
    if (code === 71) return "Light snow"
    if (code === 73) return "Snow"
    if (code === 75) return "Heavy snow"
    if (code === 77) return "Snow grains"
    if (code === 80) return "Light showers"
    if (code === 81) return "Showers"
    if (code === 82) return "Heavy showers"
    if (code === 85 || code === 86) return "Snow showers"
    if (code === 95) return "Thunderstorm"
    if (code === 96 || code === 99) return "Thunderstorm, hail"
    return "Unknown"
}

function glyph(code) {
    if (code === 0) return "☀"
    if (code <= 3 || code === 45 || code === 48) return "☁"
    if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return "☂"
    if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "☃"
    if (code >= 95) return "⚡"
    return "•"
}

function shortTime(iso) {
    return (typeof iso === "string" && iso.length >= 16) ? iso.substring(11, 16) : ""
}
