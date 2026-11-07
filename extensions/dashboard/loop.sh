#!/bin/sh
# Fetches the weather over Wi-Fi and draws the dashboard with FBInk, forever.
# Pauses the Kindle's own UI (cvm) so nothing draws over it; tapping the Home
# place name at the top left (e.g. "Vienna") runs stop.sh, which resumes the UI and goes to the home screen.
# To save battery, between refreshes Wi-Fi is off and the Kindle is suspended (the e-ink
# keeps showing the dashboard); an RTC alarm wakes it for the next refresh. Taps don't
# work while it sleeps: the power button wakes it for IDLE seconds of tabs/Home.

# Tuning knobs
PLACE="Vienna"
LAT=48.2049
LON=16.3662
TIMEZONE="Europe%2FVienna"
INTERVAL=900                # seconds between weather refreshes
IDLE=60                     # seconds after the last touch (or a power-button wake) before going
                            # back to Today and to sleep
WIFI_WAIT=60                # longest wait for Wi-Fi to bring data after turning it on; the fetch
                            # happens as soon as it works
SLEEP=1                     # 1 = suspend between refreshes, 0 = stay awake (Wi-Fi still goes off)
TOUCH=/dev/input/event1     # touchscreen device
HOME_ZONE="220 52"          # touching the place name (left of x=220, above y=52) goes Home
TABS_BOTTOM=98              # touches from y=52 to here pick a tab: left half Today, right half 10 days
CARD_TOP=512                # on Today, touches below this y switch the bottom card (date / prayer times)
CARDS=2                     # number of bottom cards (see render.awk)
PRAYER_METHOD=3             # aladhan.com calculation method: 3 = Muslim World League, 13 = Diyanet,
                            # 2 = ISNA, 4 = Umm al-Qura (full list: aladhan.com/calculation-methods)
FONT=""                     # leave empty to pick a Kindle system font automatically
FONT_BOLD=""
GREY=GRAY7                  # shade of secondary text: GRAY1 (darkest) to GRAYE (lightest)

DIR=${DASH_DIR:-/mnt/us/extensions/dashboard}  # overridable for a Mac rehearsal
POWER_STATE=${POWER_STATE:-/sys/power/state}
RTC=${RTC:-/sys/class/rtc}
FBINK="$DIR/bin/fbink"
# Plain http on purpose: the Kindle's old TLS stack may not manage modern https.
URL="http://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&timezone=$TIMEZONE&forecast_days=10&format=csv&current=temperature_2m,weather_code,relative_humidity_2m,is_day,apparent_temperature,wind_speed_10m&hourly=temperature_2m,weather_code,precipitation_probability,is_day&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,sunrise,sunset"

fetch() {
    curl -s -f -m 15 -o "$1" "$URL" 2>/dev/null || wget -q -T 15 -O "$1" "$URL"
}

# Today's prayer times from aladhan.com (https only), saved as "name,HH:MM" lines in
# prayer.txt with "day,YYYY-MM-DD" first, so it is fetched once a day. $1 = local date.
fetch_prayer() {
    u="https://api.aladhan.com/v1/timings/$(echo "$1" | awk -F- '{ print $3 "-" $2 "-" $1 }')?latitude=$LAT&longitude=$LON&method=$PRAYER_METHOD&timezonestring=$TIMEZONE"
    curl -s -S -f -m 15 -o "$DIR/prayer.json" "$u" || { echo "$(date) prayer times: fetch failed"; return; }
    grep -oE '"(Fajr|Sunrise|Dhuhr|Asr|Maghrib|Isha)":"[0-9]{2}:[0-9]{2}|"hijri":\{"date":"[0-9-]+' "$DIR/prayer.json" \
        | sed 's/"hijri":{"date":"/hijri,/; s/"//g; s/:/,/' > "$DIR/prayer.new"
    [ "$(grep -c , "$DIR/prayer.new")" -ge 6 ] || { echo "$(date) prayer times: unexpected reply"; return; }
    { echo "day,$1"; cat "$DIR/prayer.new"; } > "$DIR/prayer.txt"
}

pick_font() {  # first /usr/java/lib/fonts TTF matching one of the patterns, in order
    for want in "$@"; do
        f=$(ls /usr/java/lib/fonts 2>/dev/null | grep -i '\.ttf$' | grep -vi italic | grep -i -e "$want" | head -1)
        [ -n "$f" ] && { echo "/usr/java/lib/fonts/$f"; return; }
    done
}

# Runs render.awk's commands (see the top of render.awk) through FBInk.
# Every text argument goes after "--" so a leading "-" (like -4°) isn't read as an option.
draw_fbink() {
    "$FBINK" -q -b -k
    while IFS='|' read -r kind a b c d e f text; do
        case "$kind" in
        R)  case "$e" in B) bg=BLACK ;; W) bg=WHITE ;; *) bg=$e ;; esac
            "$FBINK" -q -b -B "$bg" -k "top=$b,left=$a,width=$c,height=$d" ;;
        # This FBInk build has no image support, so icons go through the Kindle's own eips.
        I)  eips -g "$DIR/icons/$a.png" -x "$b" -y "$c" >/dev/null ;;
        T)  font=$FONT; [ "$a" = B ] && font=$FONT_BOLD
            set -- -q -b -O
            case "$f" in *c*) set -- "$@" -m ;; esac
            case "$f" in *i*) set -- "$@" -h ;; esac
            case "$f" in *g*) set -- "$@" -C "$GREY" ;; esac
            "$FBINK" "$@" -t "regular=$font,px=$b,top=$e,left=$c,right=$d" -- "$text" ;;
        esac
    done
    # Full flashing refresh, and wait (-w) until the panel has finished it: suspending
    # mid-update would leave a half-drawn screen until the next refresh.
    "$FBINK" -q -f -s -w
}

draw_eips() {  # fallback when FBInk can't run: plain text
    eips -c
    eips 1 2 "FBInk failed: see dashboard/log.txt" >/dev/null
    eips 1 4 "$(sed -n 5p "$DIR/weather.csv" 2>/dev/null | cut -d, -f1,2)" >/dev/null
    eips 1 23 "Tap the top-left corner for the Kindle Home" >/dev/null
}

# Reads raw touch events (16 bytes each on this 32-bit Kindle). Fields after od:
# sec sec usec usec type code value value. Acts once per new touch position:
# place name -> stop.sh (Home); otherwise writes the wanted tab ("-" = no change) to $DIR/tap
# for the main loop, which does all the drawing. The device stays open on fd 3:
# evdev only queues events for an open reader.
watch_touch() {
    x=-1; y=-1; moved=0; last_card=0
    while :; do
        set -- $(dd bs=16 count=1 2>/dev/null <&3 | od -An -t d2)
        [ $# -ge 7 ] || { sleep 1; continue; }
        if [ "$5" = 3 ]; then  # EV_ABS (check the type first: type 0 code 0 is SYN_REPORT)
            case "$6" in 53|0) x=$7; moved=1 ;; 54|1) y=$7; moved=1 ;; esac
        elif [ "$5" = 0 ] && [ "$moved" = 1 ] && [ "$y" -ge 0 ]; then
            moved=0
            set -- $HOME_ZONE
            if [ "$x" -ge 0 ] && [ "$x" -lt "$1" ] && [ "$y" -lt "$2" ]; then
                echo "$(date) home tapped (x=$x y=$y)"
                sh "$DIR/stop.sh"
                exit 0
            fi
            t=-
            if [ "$y" -ge "$2" ] && [ "$y" -lt "$TABS_BOTTOM" ] && [ "$x" -ge 0 ]; then
                if [ "$x" -lt 300 ]; then t=today; else t=10d; fi
                echo "$(date) tab tap (x=$x y=$y) -> $t"
            elif [ "$y" -ge "$CARD_TOP" ]; then
                # A card tap toggles, and one tap sends several reports: act once per 2 s.
                n=$(date +%s)
                [ $((n - last_card)) -ge 2 ] || continue
                last_card=$n; t=card
                echo "$(date) card tap (x=$x y=$y)"
            fi
            echo "$t" > "$DIR/tap"
        fi
    done
}

echo $$ > "$DIR/pid"
echo "$(date) starting"
[ -n "$FONT" ] || FONT=$(pick_font 'ember.*regular' 'helvetica.*55' 'helvetica.*roman' 'futura.*book' 'futura.*medium' 'caecilia.*55' 'caecilia.*roman' '.')
[ -n "$FONT_BOLD" ] || FONT_BOLD=$(pick_font 'ember.*bold' 'helvetica.*75' 'helvetica.*bold' 'futura.*bold' 'caecilia.*75' 'caecilia.*bold')
[ -n "$FONT_BOLD" ] || FONT_BOLD=$FONT
echo "fonts: $FONT / $FONT_BOLD"
grep -m1 '^Hardware' /proc/cpuinfo
if "$FBINK" -e > "$DIR/fbink-info.txt" 2>&1 && [ -n "$FONT" ]; then draw=draw_fbink; else draw=draw_eips; echo "fbink or fonts unavailable, using eips"; fi

# Let KUAL close cleanly before the UI is paused.
sleep 5
# Only pause the Kindle UI when the Home button can work; otherwise there'd be no way back.
# (A failed "exec 3<" would end this shell, so check the device first.)
if [ -c "$TOUCH" ] && [ -r "$TOUCH" ] && exec 3< "$TOUCH"; then
    killall -STOP cvm 2>/dev/null
    watch_touch &
    echo $! > "$DIR/touch.pid"
else
    echo "$(date) can't open $TOUCH: Kindle UI left running, no Home button"
fi

wifi() { lipc-set-prop com.lab126.cmd wirelessEnable "$1" 2>/dev/null; }

# Wi-Fi on, fetch as soon as it works (or give up after WIFI_WAIT), Wi-Fi off.
refresh() {
    wifi 1
    t0=$(date +%s); stale=1
    while :; do
        if fetch "$DIR/weather.new" && grep -q '^time' "$DIR/weather.new"; then
            mv "$DIR/weather.new" "$DIR/weather.csv"
            stale=0; good_utc=$(date -u +%H%M)
            # Prayer times once a day, while Wi-Fi is on anyway. The local date comes from
            # the weather data (the Kindle's clock is UTC).
            day=$(sed -n 5p "$DIR/weather.csv" | cut -c1-10)
            [ "$(sed -n 's/^day,//p' "$DIR/prayer.txt" 2>/dev/null)" = "$day" ] || fetch_prayer "$day"
            break
        fi
        [ $(($(date +%s) - t0)) -ge "$WIFI_WAIT" ] && { echo "$(date) fetch failed for $WIFI_WAIT s"; break; }
        sleep 5
    done
    wifi 0
    [ -f "$DIR/weather.csv" ] || : > "$DIR/weather.csv"
    batt=$(lipc-get-prop com.lab126.powerd battLevel 2>/dev/null)
    echo "$(date) refreshed in $(($(date +%s) - t0)) s, battery $batt%"
}

# Suspends until epoch $1 (RTC alarm) or the power button, whichever comes first.
# After 3 suspends in a row that fail or return at once, stays awake for good (SLEEP=0).
suspend_until() {
    left=$(($1 - $(date +%s)))
    [ "$left" -gt 10 ] || return
    for a in "$RTC"/rtc*/wakealarm; do echo 0 > "$a" && echo "+$left" > "$a"; done
    sync
    t0=$(date +%s)
    if echo mem > "$POWER_STATE" && [ $(($(date +%s) - t0)) -ge 3 ]; then
        fails=0
        now=$(date +%s)
        echo "$(date) slept $((now - t0)) of $left s, powerd $(lipc-get-prop com.lab126.powerd state 2>/dev/null)"
        # Woken well before the alarm: the power button. Give the user IDLE seconds.
        [ "$now" -lt $(($1 - 10)) ] && touched=$now
    else
        fails=$((fails + 1))
        echo "$(date) suspend failed ($fails)"
        [ "$fails" -ge 3 ] && { SLEEP=0; echo "$(date) can't suspend: staying awake between refreshes"; }
    fi
}

# What this Kindle offers for sleeping, for tuning (first runs only need it).
id
for r in "$RTC"/rtc*; do echo "$r: $(cat "$r/name" 2>/dev/null)"; done
lipc-probe -v com.lab126.powerd > "$DIR/powerd.txt" 2>&1

# One loop does all the drawing, so the touch watcher never draws over it.
# Awake, it checks for taps every second; once idle on Today it sleeps until the next refresh.
tab=today; card=0; touched=$(date +%s); due=0; stale=0; good_utc=""; fails=0
rm -f "$DIR/tap"
[ -f "$DIR/prayer.txt" ] || : > "$DIR/prayer.txt"  # awk needs it to exist
# Keep powerd from blanking the screen or suspending on its own timer while we are awake.
lipc-set-prop com.lab126.powerd preventScreenSaver 1
while :; do
    now=$(date +%s); redraw=""
    if mv -f "$DIR/tap" "$DIR/tap.read" 2>/dev/null; then
        touched=$now
        t=$(cat "$DIR/tap.read")
        if [ "$t" = card ]; then
            [ "$tab" = today ] && { card=$(((card + 1) % CARDS)); redraw=1; }
        elif [ "$t" != - ] && [ "$t" != "$tab" ]; then tab=$t; redraw=1; fi
    fi
    if [ "$tab" != today ] && [ $((now - touched)) -ge "$IDLE" ]; then tab=today; redraw=1; fi
    if [ "$now" -ge "$due" ]; then
        due=$((now + INTERVAL))
        refresh
        redraw=1
        # Keep the log from filling the Kindle.
        [ "$(wc -c < "$DIR/log.txt")" -gt 100000 ] && : > "$DIR/log.txt"
    fi
    if [ -n "$redraw" ]; then
        t0=$(date +%s)
        awk -v place="$PLACE" -v stale="$stale" -v utc="$good_utc" -v clock="$(date -u +%H%M)" -v tab="$tab" -v batt="$batt" -v card="$card" \
            -f "$DIR/render.awk" "$DIR/weather.csv" "$DIR/prayer.txt" | $draw
        echo "$(date) drew $tab in $(($(date +%s) - t0)) s"
    fi
    if [ "$SLEEP" = 1 ] && [ "$tab" = today ] && [ $(($(date +%s) - touched)) -ge "$IDLE" ]; then
        suspend_until "$due"
    else
        sleep 1
    fi
done
