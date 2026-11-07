# Turns an Open-Meteo CSV (sections: meta, current, hourly, daily) into drawing
# commands for a 600x800 portrait screen, run by loop.sh through FBInk:
#   T|style|px|left|right|top|flags|text   style R/B; flags: c = centred between margins, i = white text, g = grey text
#   R|x|y|w|h|color                        filled box: B (black), W (white) or an FBInk grey like GRAYA
#   I|name|x|y                             icons/<name>.png
# Plain POSIX awk so busybox on the Kindle runs it.
# Vars: place, stale (1 = last fetch failed), utc (HHMM UTC of the last good fetch),
#       tab ("today" or "10d"), batt (battery %, empty to hide), card (bottom card: 0 date, 1 prayer).
# Input: weather.csv, then optionally prayer.txt (see loop.sh's fetch_prayer).

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
function hm(t) { return substr(t, 12, 5) }  # "2026-11-07T06:58" -> "06:58"

BEGIN { FS = ","; sec = 0; nh = 0; nd = 0; offset = 0 }  # counters must start numeric: an unset one indexes as ""
{ sub(/\r$/, "") }
NR != FNR { pr[$1] = $2; next }  # second file, prayer.txt: day,YYYY-MM-DD / hijri,DD-MM-YYYY / Fajr,HH:MM ...
/^$/ { sec++; next }
$1 == "time" || $1 == "latitude" { next }
sec == 0 { offset = $4 }
sec == 1 { now = $1; temp = $2; code = $3; hum = $4; isday = $5; feel = $6; wind = $7 }
sec == 2 { ht[nh] = $1; htemp[nh] = $2; hcode[nh] = $3; hrain[nh] = $4; hday[nh] = $5; nh++ }
sec == 3 { dt[nd] = $1; dcode[nd] = $2; dmax[nd] = $3; dmin[nd] = $4; drain[nd] = $5; dsum[nd] = $6; drise[nd] = $7; dset[nd] = $8; nd++ }

END {
    # The place name doubles as the Home button (loop.sh maps taps on it), so draw it first.
    text("B", 22, 20, 300, 16, "", place)
    if (now == "") {
        text("B", 28, 20, 20, 90, "", "No weather data yet")
        text("R", 20, 20, 20, 134, "g", "It appears after the first refresh over Wi-Fi.")
        exit
    }

    split("Monday Tuesday Wednesday Thursday Friday Saturday Sunday", dayname, " ")
    split("January February March April May June July August September October November December", monname, " ")
    y = substr(now, 1, 4) + 0; m = substr(now, 6, 2) + 0; d = substr(now, 9, 2) + 0
    today = substr(now, 1, 10); ti = -1
    for (i = 0; i < nd; i++) if (dt[i] == today) ti = i

    # Header: update time and battery beside the place, then the tabs (loop.sh maps taps
    # between y=52 and y=110 to them: left half Today, right half 10 days).
    if (utc != "") {
        mins = (int(utc / 100) * 60 + utc % 100 + int(offset / 60) + 1440) % 1440
        stamp = sprintf("%02d:%02d", int(mins / 60), mins % 60)
    } else stamp = substr(now, 12, 5)
    if (stale) text("B", 18, 330, 120, 19, "", "Offline · " stamp)
    else text("R", 18, 330, 120, 19, "g", "Updated " stamp)
    if (batt != "") {  # battery outline with a level bar, then the percentage (bold when low)
        frame(490, 21, 30, 15, 2); box(520, 25, 3, 7, "B")
        box(493, 24, int(24 * (batt > 100 ? 100 : batt) / 100), 9, "B")
        text(batt <= 20 ? "B" : "R", 18, 528, 20, 19, "", batt "%")
    }
    box(20, 48, 560, 1, "B")  # separates the place/update row from the tabs
    week = tab == "10d"
    text(week ? "R" : "B", 22, 20, 300, 60, week ? "cg" : "c", "Today")
    text(week ? "B" : "R", 22, 300, 20, 60, week ? "c" : "cg", "10 days")
    box(week ? 370 : 90, 90, 140, 4, "B")
    box(20, 94, 560, 1, "B")

    if (week) {
        # One row per day: label, icon, rain-chance dots, rain amount, then min, a bar
        # placing the day's range within the 10 days' coldest-to-warmest, and max.
        lo = 999; hi = -999
        for (k = 0; k < 10 && ti >= 0 && ti + k < nd; k++) {
            i = ti + k
            if (dmin[i] != "" && dmin[i] + 0 < lo) lo = dmin[i] + 0
            if (dmax[i] != "" && dmax[i] + 0 > hi) hi = dmax[i] + 0
        }
        for (k = 0; k < 10 && ti >= 0 && ti + k < nd; k++) {
            i = ti + k; r = 100 + 68 * k
            if (k == 0) text("B", 24, 20, 470, r + 20, "", "Today")
            else {
                dd = substr(dt[i], 9, 2) + 0
                text("R", 22, 20, 500, r + 22, "g", substr(dayname[weekday(substr(dt[i], 1, 4) + 0, substr(dt[i], 6, 2) + 0, dd) + 1], 1, 3))
                text("B", 24, 72, 480, r + 20, "", dd)
            }
            img(icon(dcode[i], 1) "-48", 124, r + 10)
            dots = int((drain[i] + 10) / 20); if (dots > 5) dots = 5
            img("dots-" dots, 184, r + 27)
            if (dsum[i] == "" || dsum[i] < 0.05) rain = dots ? "0 mm" : "dry"  # "dry" beside filled dots reads as a contradiction
            else rain = (dsum[i] < 0.5 ? "<1" : sprintf("%.0f", dsum[i])) " mm"
            text("R", 18, 304, 228, r + 24, "g", rain)
            text("R", 26, 364, 172, r + 21, "c", deg(dmin[i]))
            text("R", 26, 520, 20, r + 21, "c", deg(dmax[i]))
            box(434, r + 31, 80, 6, "GRAYD")
            if (dmin[i] != "" && dmax[i] != "") {
                span = hi > lo ? hi - lo : 1
                x1 = 434 + int((dmin[i] - lo) * 80 / span + 0.5); x2 = 434 + int((dmax[i] - lo) * 80 / span + 0.5)
                if (x2 - x1 < 6) { x1 = x2 - 6 < 434 ? 434 : x2 - 6; x2 = x1 + 6 }
                box(x1, r + 31, x2 - x1, 6, "B")
            }
            if (k < 9) box(20, r + 67, 560, 1, "GRAYA")
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
    # Icon art is ~124 px wide inside its 160 px box, 18 px in; 14 px gap to the number.
    # Shrink the number when it wouldn't fit (like -12°) instead of running into the column.
    px = 124; if (124 + 14 + tw * px > 336) px = int((336 - 138) / tw)
    gx = int(20 + (340 - (138 + tw * px)) / 2)
    img(icon(code, isday) "-160", gx - 18, 104)
    text("B", px, gx + 138, 240, 132 + int((124 - px) / 2), "", t)
    text("R", 26, 20, 240, 268, "c", cond(code))
    s = feel == "" ? "" : "Feels like " deg(feel)
    if (hum != "") s = s (s == "" ? "" : " · ") "Humidity " pct(hum)
    text("R", 20, 20, 240, 304, "cg", s)
    if (ti < 0) text("R", 22, 360, 20, 120, "", "No forecast for today")
    else {
        text("R", 18, 360, 20, 112, "g", "Today")
        text("B", 32, 360, 20, 132, "", deg(dmax[ti]) " / " deg(dmin[ti]))
        text("R", 22, 360, 20, 174, "", cond(dcode[ti]))
        text("R", 18, 360, 20, 204, "g", pct(drain[ti]) " rain" (wind == "" ? "" : " · " sprintf("%.0f", wind) " km/h"))
        if (ti + 1 < nd) {
            box(360, 238, 220, 1, "GRAYA")
            img(icon(dcode[ti + 1], 1) "-48", 356, 256)
            text("R", 18, 414, 20, 248, "g", "Tomorrow")
            text("B", 24, 414, 20, 270, "", deg(dmax[ti + 1]) " / " deg(dmin[ti + 1]))
            text("R", 18, 414, 20, 302, "g", pct(drain[ti + 1]) " rain")
        }
    }

    # Next hours, every 3 h, in a bordered strip.
    frame(20, 338, 560, 162, 2)
    start = nh
    for (i = nh - 1; i >= 0; i--) if (ht[i] > now) start = i
    for (s = 0; s < 7 && start + 3 * s < nh; s++) {
        i = start + 3 * s; x = 20 + 80 * s; r = 600 - x - 80
        text("R", 18, x, r, 350, "cg", hm(ht[i]))
        img(icon(hcode[i], hday[i]) "-48", x + 16, 374)
        text("B", 24, x, r, 426, "c", deg(htemp[i]))
        text("R", 18, x, r, 462, "cg", pct(hrain[i]))
    }

    # Bottom card, switched by tapping it: 0 = date, 1 = prayer times. Dots show which.
    frame(20, 512, 560, 274, 2)
    if (card == 1) prayer_card(today, stamp)
    else {
        text("B", 180, 22, 340, 532, "c", d)
        text("R", 28, 270, 22, 560, "", dayname[weekday(y, m, d) + 1])
        text("B", 50, 270, 22, 598, "", monname[m])  # "September" is the widest; it must stay on one line
        text("R", 26, 272, 22, 664, "g", y)
        if (ti >= 0 && drise[ti] != "") text("R", 18, 272, 22, 710, "g", "Sunrise " hm(drise[ti]) " · Sunset " hm(dset[ti]))
    }
    for (j = 0; j < 2; j++) if (j == card + 0) box(286 + 20 * j, 768, 8, 8, "B"); else frame(286 + 20 * j, 768, 8, 8, 2)
}

# Today's prayers in a 3 x 2 grid: the next one inverted, the ones already past in grey.
function prayer_card(today, stamp,   names, hd, k, c, r, x, y, nexti, now_m, f, g, live) {
    text("B", 24, 40, 300, 530, "", "Prayer times")
    if (pr["Fajr"] == "") { text("R", 22, 40, 40, 630, "cg", "Not loaded yet, needs Wi-Fi"); return }
    live = pr["day"] == today
    if (!live) text("R", 20, 232, 40, 534, "g", "for " pr["day"])
    else if (split(pr["hijri"], hd, "-") == 3) {
        split("Muharram,Safar,Rabi I,Rabi II,Jumada I,Jumada II,Rajab,Shaban,Ramadan,Shawwal,Dhul Qadah,Dhul Hijjah", names, ",")
        text("R", 20, 232, 40, 534, "g", (hd[1] + 0) " " names[hd[2] + 0] " " hd[3])
    }
    split("Fajr Sunrise Dhuhr Asr Maghrib Isha", names, " ")
    now_m = substr(stamp, 1, 2) * 60 + substr(stamp, 4, 2)
    nexti = 7  # first prayer still ahead today (Sunrise isn't a prayer); 7 = all past
    for (k = 6; k >= 1; k--) if (k != 2 && pr[names[k]] != "" && substr(pr[names[k]], 1, 2) * 60 + substr(pr[names[k]], 4, 2) > now_m) nexti = k
    for (k = 1; k <= 6; k++) {
        c = (k - 1) % 3; r = int((k - 1) / 3)
        x = 22 + 185 * c; y = 570 + 94 * r; f = "c"; g = "cg"
        if (live && k == nexti) { box(x + 8, y, 169, 88, "B"); f = g = "ci" }
        else if (live && k < nexti) f = "cg"
        text("R", 22, x, 600 - x - 185, y + 8, g, names[k])
        text("B", 40, x, 600 - x - 185, y + 34, f, pr[names[k]] == "" ? "-" : pr[names[k]])
    }
}
