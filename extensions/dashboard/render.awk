# Turns an Open-Meteo CSV (sections: meta, current, hourly, daily) into drawing
# commands for a 600x800 portrait screen, run by loop.sh through FBInk:
#   T|style|px|left|right|top|flags|text   style R/B; flags: c = centred between margins, i = white text
#   R|x|y|w|h|color                        filled box, color B (black) or W (white)
#   I|name|x|y                             icons/<name>.png
# Plain POSIX awk so busybox on the Kindle runs it.
# Vars: place, stale (1 = last fetch failed), utc (HHMM UTC of the last good fetch), home_top (Home button y),
#       tab ("today" or "10d"), batt (battery %, empty to hide).

function cond(c) {
    c = int(c)
    if (c == 0) return "Clear"
    if (c == 1) return "Mostly clear"
    if (c == 2) return "Partly cloudy"
    if (c == 3) return "Cloudy"
    if (c == 45 || c == 48) return "Fog"
    if (c >= 51 && c <= 57) return "Drizzle"
    if (c >= 61 && c <= 67) return "Rain"
    if (c >= 71 && c <= 77) return "Snow"
    if (c >= 80 && c <= 82) return "Showers"
    if (c == 85 || c == 86) return "Snow showers"
    if (c >= 95) return "Storm"
    return "-"
}

function icon(c, day) {
    c = int(c)
    if (c <= 1) return day == "0" ? "moon" : "sun"
    if (c == 2) return day == "0" ? "partly-night" : "partly"
    if (c == 3) return "cloud"
    if (c == 45 || c == 48) return "fog"
    if (c >= 51 && c <= 57) return "drizzle"
    if ((c >= 61 && c <= 67) || (c >= 80 && c <= 82)) return "rain"
    if ((c >= 71 && c <= 77) || c == 85 || c == 86) return "snow"
    if (c >= 95) return "storm"
    return "cloud"
}

function deg(x) { return x == "" ? "-" : sprintf("%d", x < 0 ? x - 0.5 : x + 0.5) "°" }
function pct(x) { return x == "" ? "-" : x "%" }

function weekday(y, m, d,   t) {  # 0 = Monday
    split("0 3 2 5 0 3 5 1 4 6 2 4", t, " ")
    if (m < 3) y--
    return (y + int(y / 4) - int(y / 100) + int(y / 400) + t[m] + d + 6) % 7
}

function text(style, px, left, right, top, flags, s) { print "T|" style "|" px "|" left "|" right "|" top "|" flags "|" s }
function box(x, y, w, h, color) { print "R|" x "|" y "|" w "|" h "|" color }
function frame(x, y, w, h, t) { box(x, y, w, h, "B"); box(x + t, y + t, w - 2 * t, h - 2 * t, "W") }
function img(name, x, y) { print "I|" name "|" x "|" y }

BEGIN { FS = ","; sec = 0; nh = 0; nd = 0; offset = 0 }  # counters must start numeric: an unset one indexes as ""
{ sub(/\r$/, "") }
/^$/ { sec++; next }
$1 == "time" || $1 == "latitude" { next }
sec == 0 { offset = $4 }
sec == 1 { now = $1; temp = $2; code = $3; hum = $4; isday = $5 }
sec == 2 { ht[nh] = $1; htemp[nh] = $2; hcode[nh] = $3; hrain[nh] = $4; hday[nh] = $5; nh++ }
sec == 3 { dt[nd] = $1; dcode[nd] = $2; dmax[nd] = $3; dmin[nd] = $4; drain[nd] = $5; dsum[nd] = $6; nd++ }

END {
    if (home_top == "") home_top = 722
    # Home button, always drawn so there's a way back.
    frame(20, home_top, 560, 64, 2)
    text("B", 26, 22, 22, home_top + 17, "c", "Home")
    if (now == "") { text("B", 28, 20, 20, 20, "", "No weather data yet"); exit }

    split("Monday Tuesday Wednesday Thursday Friday Saturday Sunday", dayname, " ")
    split("January February March April May June July August September October November December", monname, " ")
    y = substr(now, 1, 4) + 0; m = substr(now, 6, 2) + 0; d = substr(now, 9, 2) + 0
    today = substr(now, 1, 10); ti = -1
    for (i = 0; i < nd; i++) if (dt[i] == today) ti = i

    # Header: place, update time, then the tabs (loop.sh maps taps above y=110 to them).
    text("B", 22, 20, 300, 16, "", place)
    if (utc != "") {
        mins = (int(utc / 100) * 60 + utc % 100 + int(offset / 60) + 1440) % 1440
        stamp = sprintf("%02d:%02d", int(mins / 60), mins % 60)
    } else stamp = substr(now, 12, 5)
    text("R", 18, 340, 120, 19, "", stale ? "Offline · " stamp : "Updated " stamp)
    if (batt != "") {  # battery outline with a level bar, then the percentage
        frame(490, 21, 30, 15, 2); box(520, 25, 3, 7, "B")
        box(493, 24, int(24 * (batt > 100 ? 100 : batt) / 100), 9, "B")
        text("R", 18, 528, 20, 19, "", batt "%")
    }
    box(20, 48, 560, 2, "B")  # separates the place/update row from the tabs
    week = tab == "10d"
    text(week ? "R" : "B", 22, 20, 410, 60, "c", "Today")
    text(week ? "B" : "R", 22, 190, 240, 60, "c", "10 days")
    box(week ? 225 : 55, 92, 100, 4, "B")
    box(20, 96, 560, 2, "B")

    if (week) {
        # One row per day: label, icon, min, rain dots, rain text, max.
        for (k = 0; k < 10 && ti >= 0 && ti + k < nd; k++) {
            i = ti + k; r = 106 + 60 * k
            if (k == 0) text("B", 24, 20, 470, r + 16, "", "Today")
            else {
                dd = substr(dt[i], 9, 2) + 0
                text("R", 16, 20, 520, r + 22, "", toupper(substr(dayname[weekday(substr(dt[i], 1, 4) + 0, substr(dt[i], 6, 2) + 0, dd) + 1], 1, 3)))
                text("B", 26, 64, 470, r + 14, "", dd)
            }
            img(icon(dcode[i], 1) "-48", 128, r + 6)
            text("R", 26, 192, 330, r + 15, "", deg(dmin[i]))
            dots = int((drain[i] + 10) / 20); if (dots > 5) dots = 5
            img("dots-" dots, 256, r + 23)
            if (dsum[i] == "" || dsum[i] < 0.05) rain = "dry"
            else rain = pct(drain[i]) " · " (dsum[i] < 0.5 ? "<1" : sprintf("%.0f", dsum[i])) " mm"
            text("R", 18, 380, 120, r + 19, "", rain)
            text("B", 30, 490, 20, r + 12, "c", deg(dmax[i]))
            box(20, r + 59, 560, 1, "B")
        }
        if (ti < 0) text("R", 22, 20, 20, 130, "", "No forecast for today")
        exit
    }

    # Now: big icon and temperature, then today and tomorrow.
    # Icon + temperature centred as a group between the frame line (x=20) and the
    # Today column (x=360). FBInk can't measure text, so estimate the temperature's
    # width from Amazon Ember Bold's rough advances (digits ~0.56 em, "-" ~0.36, "°" ~0.40).
    # Count digits and "-" only: awk counts the UTF-8 "°" as 2 bytes, so add it once.
    t = deg(temp); n = t; tw = 0.40
    tw += 0.56 * gsub(/[0-9]/, "", n) + 0.36 * gsub(/-/, "", n)
    gx = int(20 + (340 - (92 + 12 + tw * 92)) / 2)  # icon art is ~92 px wide inside its 120 px box, 14 px in
    img(icon(code, isday) "-120", gx - 14, 112)
    text("B", 92, gx + 104, 240, 124, "", t)
    text("R", 22, 20, 240, 232, "c", cond(code))
    if (ti < 0) text("R", 20, 360, 20, 112, "", "No forecast for today")
    else {
        text("B", 24, 360, 20, 112, "", "Today " deg(dmax[ti]) " / " deg(dmin[ti]))
        text("R", 18, 360, 20, 146, "", cond(dcode[ti]))
        text("R", 18, 360, 20, 170, "", "Rain " pct(drain[ti]) "   Humidity " pct(hum))
        if (ti + 1 < nd) {
            img(icon(dcode[ti + 1], 1) "-48", 356, 204)
            text("R", 18, 414, 20, 204, "", "Tomorrow")
            text("B", 22, 414, 20, 228, "", deg(dmax[ti + 1]) " / " deg(dmin[ti + 1]) "   " pct(drain[ti + 1]))
        }
    }

    # Next hours, every 3 h, in a bordered strip.
    frame(20, 272, 560, 172, 2)
    start = nh
    for (i = nh - 1; i >= 0; i--) if (ht[i] > now) start = i
    for (s = 0; s < 7 && start + 3 * s < nh; s++) {
        i = start + 3 * s; x = 20 + 80 * s; r = 600 - x - 80
        text("R", 18, x, r, 284, "c", substr(ht[i], 12, 5))
        img(icon(hcode[i], hday[i]) "-48", x + 16, 312)
        text("B", 24, x, r, 366, "c", deg(htemp[i]))
        text("R", 18, x, r, 404, "c", pct(hrain[i]))
    }

    # Date card: big day number; weekday, month and a small year beside it.
    frame(20, 456, 560, 252, 2)
    text("B", 180, 22, 340, 486, "c", d)
    text("R", 28, 270, 22, 504, "", dayname[weekday(y, m, d) + 1])
    text("B", 50, 270, 22, 544, "", monname[m])  # "September" is the widest; it must stay on one line
    text("R", 26, 272, 22, 612, "", y)
}
