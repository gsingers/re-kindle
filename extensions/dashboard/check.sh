#!/bin/sh
# Mac-side check of render.awk against a fixed forecast: sh extensions/dashboard/check.sh
cd "$(dirname "$0")" || exit 1
fixture() {
    printf 'latitude,longitude,elevation,utc_offset_seconds,timezone,timezone_abbreviation\r\n48.2,16.37,181.0,3600,Europe/Vienna,GMT+1\r\n\r\n'
    printf 'time,temperature_2m (C),weather_code (wmo code),relative_humidity_2m (%%),is_day (),apparent_temperature (C),wind_speed_10m (mp/h)\n2026-11-04T20:45,7.6,61,80,0,4.6,12.4\n\n'
    printf 'time,temperature_2m (C),weather_code (wmo code),precipitation_probability (%%),is_day ()\n'
    awk 'BEGIN { for (h = 0; h < 48; h++) printf "2026-11-%02dT%02d:00,-3.6,999,,%d\n", 4 + int(h / 24), h % 24, (h % 24 >= 7 && h % 24 < 17) }'
    printf '\ntime,weather_code (wmo code),temperature_2m_max (C),temperature_2m_min (C),precipitation_probability_max (%%),precipitation_sum (inch),sunrise (iso8601),sunset (iso8601)\n'
    printf '2026-11-04,3,9.0,2.0,40,0.03,2026-11-04T06:45,2026-11-04T16:31\n2026-11-05,0,11.0,3.0,0,0.0,,\n'
    awk 'BEGIN { for (d = 6; d <= 13; d++) printf "2026-11-%02d,63,12.0,5.0,37,0.64,,\n", d }'
}
render() { awk -v place=Vienna -v batt=87 "$@" -f render.awk; }
out=$(fixture | render -v stale=0 -v utc=1952)
fail=0
expect() { printf '%s\n' "$1" | grep -qF -- "$2" || { echo "missing: $2"; fail=1; }; }
expect "$out" "T|B|22|20|300|16||Vienna"
expect "$out" "||87%"
expect "$out" "R|493|24|20|9|B"            # 87% of the 24 px battery bar
expect "$out" "R|20|48|560|1|B"           # rule above the tabs
expect "$out" "T|B|22|20|300|60|c|Today"       # active tab is bold, tabs split the width
expect "$out" "T|R|22|300|20|60|cg|10 days"    # inactive tab is grey
expect "$out" "|g|Updated 20:52"          # device UTC 19:52 + 3600 s
expect "$out" "T|B|124|199|240|132||8°"    # 7.6 rounds up; icon + temp centred left of the Today column
expect "$out" "I|rain-160|43|104"          # current code 61
expect "$out" "|cg|Feels like 5° · Humidity 80%"
expect "$(fixture | sed "s/T20:45,7.6/T20:45,-12.3/" | render -v utc=1952)" "T|B|105|160|240|141||-12°"  # shrinks to fit
expect "$out" "||9° / 2°"
expect "$out" "|g|40% rain · 12 mph"
expect "$out" "||11° / 3°"                 # tomorrow uses tomorrow's values
expect "$out" "|g|0% rain"
expect "$out" "|cg|21:00"                  # first slot after 20:45
expect "$out" "|c|-4°"                     # negative temperatures round away from zero
expect "$out" "I|storm-48|"                # unknown codes >= 95 count as storms
expect "$out" "|cg|-"                      # missing rain chance
expect "$out" "T|B|180|22|340|532|c|4"     # big day number
expect "$out" "R|20|334|560|1|B"          # single rules between widgets, no boxes
expect "$out" "R|20|506|560|1|B"
case "$out" in *"|560|162|"*|*"|560|274|"*) echo "widgets should not be boxed"; fail=1 ;; esac
expect "$out" "||Wednesday"
expect "$out" "||November"
expect "$out" "|g|2026"
expect "$out" "|g|Sunrise 06:45 · Sunset 16:31"
expect "$(fixture | render -v stale=1 -v utc=1952)" "T|B|18|330|120|19||Offline · 20:52"
expect "$(fixture | render -v utc=1952 -v batt=15)" "T|B|18|528|20|19||15%"  # low battery in bold
week=$(fixture | render -v stale=0 -v utc=1952 -v tab=10d)
expect "$week" "T|B|22|300|20|60|c|10 days"
expect "$week" "|Today"
expect "$week" "|g|Thu"                    # 5 November
expect "$week" "|g|Fri"
expect "$week" "I|dots-2|"                 # 40% and 37% -> two dots
expect "$week" "I|dots-0|"                 # 0%
expect "$week" "|g|<0.1 in"
expect "$week" "|g|dry"
expect "$week" "|g|0.6 in"
expect "$week" "R|434|131|80|6|GRAYD"      # range track on the first row
expect "$week" "R|434|131|56|6|B"          # today 2-9 within the 10 days' 2-12
[ "$(printf '%s\n' "$week" | grep -c '^I|dots-')" = 10 ] || { echo "10d tab should have 10 rows"; fail=1; }
case "$week" in *Tomorrow*) echo "10d tab drew the Today view"; fail=1 ;; esac
case "$out" in *"R|286|768|"*) echo "one card: no card dots"; fail=1 ;; esac
expect "$(fixture | render -v utc=1952 -v cards=2)" "R|286|768|8|8|B"  # first of two dots filled
expect "$(fixture | render -v utc=1952 -v cards=2 -v card=1)" "R|306|768|8|8|B"
empty=$(printf '' | render)
expect "$empty" "||Vienna"                 # the place name is the way Home
expect "$empty" "No weather data yet"
# Battery scheduling from loop.sh: hourly refreshes, none at night.
eval "$(sed -n '/^utc_offset()/p;/^next_refresh()/,/^}/p' loop.sh)"
DIR=$(mktemp -d); fixture > "$DIR/weather.csv"  # UTC+1
INTERVAL=3600; NIGHT="23 6"
same() { [ "$1" = "$2" ] || { echo "$3: got $1, want $2"; fail=1; }; }
same "$(next_refresh 1793821500)" 1793825100 "20:45 local -> 21:45"
same "$(next_refresh 1793827800)" 1793854800 "22:30 local -> 06:00 next morning"
same "$(next_refresh 1793754000)" 1793768400 "02:00 local -> 06:00 same morning"
NIGHT=""; same "$(next_refresh 1793827800)" 1793831400 "no night window -> 23:30"
rm -rf "$DIR"
# Everything must fit on the 600x800 screen.
printf '%s\n%s\n' "$out" "$week" | awk -F'|' '
    $1 == "R" { x = $2; y = $3; r = $2 + $4; b = $3 + $5 }
    $1 == "I" { n = split($2, p, "-"); w = h = p[n] + 0; if ($2 ~ /^dots/) { w = 110; h = 14 }
                x = $3; y = $4; r = $3 + w; b = $4 + h }
    $1 == "T" { x = $4; y = $6; r = 600 - $5; b = $6 + $3 * 1.2 }
    x < 0 || y < 0 || r > 600 || b > 800 { print "off screen: " $0; bad = 1 }
    END { exit bad }' || fail=1
[ $fail = 0 ] && echo ok || { printf '%s\n' "$out" "$week"; exit 1; }
