#!/bin/sh
# Mac-side check of render.awk against a fixed forecast: sh extensions/dashboard/check.sh
cd "$(dirname "$0")" || exit 1
fixture() {
    printf 'latitude,longitude,elevation,utc_offset_seconds,timezone,timezone_abbreviation\r\n48.2,16.37,181.0,3600,Europe/Vienna,GMT+1\r\n\r\n'
    printf 'time,temperature_2m (C),weather_code (wmo code),relative_humidity_2m (%%),is_day ()\n2026-11-04T20:45,7.6,61,80,0\n\n'
    printf 'time,temperature_2m (C),weather_code (wmo code),precipitation_probability (%%),is_day ()\n'
    awk 'BEGIN { for (h = 0; h < 48; h++) printf "2026-11-%02dT%02d:00,-3.6,999,,%d\n", 4 + int(h / 24), h % 24, (h % 24 >= 7 && h % 24 < 17) }'
    printf '\ntime,weather_code (wmo code),temperature_2m_max (C),temperature_2m_min (C),precipitation_probability_max (%%),precipitation_sum (mm)\n'
    printf '2026-11-04,3,9.0,2.0,40,0.3\n2026-11-05,0,11.0,3.0,0,0.0\n'
    awk 'BEGIN { for (d = 6; d <= 13; d++) printf "2026-11-%02d,63,12.0,5.0,37,16.2\n", d }'
}
render() { awk -v place=Vienna -v batt=87 "$@" -f render.awk; }
out=$(fixture | render -v stale=0 -v utc=1952)
fail=0
expect() { printf '%s\n' "$1" | grep -qF -- "$2" || { echo "missing: $2"; fail=1; }; }
expect "$out" "T|B|22|20|300|16||Vienna"
expect "$out" "||87%"
expect "$out" "R|493|24|20|9|B"            # 87% of the 24 px battery bar
expect "$out" "R|20|48|560|2|B"           # rule above the tabs
expect "$out" "T|B|22|20|410|60|c|Today"       # active tab is bold
expect "$out" "T|R|22|190|240|60|c|10 days"
expect "$out" "|Updated 20:52"            # device UTC 19:52 + 3600 s
expect "$out" "T|B|124|199|240|140||8°"    # 7.6 rounds up; icon + temp centred left of the Today column
expect "$out" "I|rain-160|43|112"          # current code 61
expect "$(fixture | sed "s/T20:45,7.6/T20:45,-12.3/" | render -v utc=1952)" "T|B|105|160|240|149||-12°"  # shrinks to fit
expect "$out" "|Today 9° / 2°"
expect "$out" "|11° / 3°   0%"             # tomorrow line uses tomorrow's values
expect "$out" "|c|21:00"                   # first slot after 20:45
expect "$out" "|c|-4°"                     # negative temperatures round away from zero
expect "$out" "I|storm-48|"                # unknown codes >= 95 count as storms
expect "$out" "|c|-"                       # missing rain chance
expect "$out" "T|B|180|22|340|556|c|4"     # big day number
expect "$out" "||Wednesday"
expect "$out" "||November"
expect "$out" "||2026"
expect "$(fixture | render -v stale=1 -v utc=1952)" "|Offline · 20:52"
week=$(fixture | render -v stale=0 -v utc=1952 -v tab=10d)
expect "$week" "T|B|22|190|240|60|c|10 days"
expect "$week" "|Today"
expect "$week" "|THU"                      # 5 November
expect "$week" "|FRI"
expect "$week" "I|dots-2|"                 # 40% and 37% -> two dots
expect "$week" "I|dots-0|"                 # 0%
expect "$week" "|40% · <1 mm"
expect "$week" "|dry"
expect "$week" "|37% · 16 mm"
[ "$(printf '%s\n' "$week" | grep -c '^I|dots-')" = 10 ] || { echo "10d tab should have 10 rows"; fail=1; }
case "$week" in *Tomorrow*) echo "10d tab drew the Today view"; fail=1 ;; esac
pray=$(mktemp)
printf 'day,2026-11-04\nFajr,05:01\nSunrise,06:47\nDhuhr,11:38\nAsr,14:05\nMaghrib,16:28\nIsha,18:09\nhijri,26-05-1448\n' > "$pray"
card=$(fixture | awk -v place=Vienna -v batt=87 -v utc=1530 -v card=1 -f render.awk - "$pray")  # 16:30 local
rm -f "$pray"
expect "$card" "|c|Fajr"
expect "$card" "|c|05:01"
expect "$card" "|26 Jumada I 1448"
expect "$card" "R|400|676|169|86|B"        # next prayer (Isha) inverted
expect "$card" "|ci|18:09"
case "$card" in *November*) echo "prayer card also drew the date"; fail=1 ;; esac
expect "$(fixture | render -v utc=1530 -v card=1)" "Not loaded yet"
empty=$(printf '' | render)
expect "$empty" "||Vienna"                 # the place name is the way Home
expect "$empty" "No weather data yet"
# Everything must fit on the 600x800 screen.
printf '%s\n%s\n%s\n' "$out" "$week" "$card" | awk -F'|' '
    $1 == "R" { x = $2; y = $3; r = $2 + $4; b = $3 + $5 }
    $1 == "I" { n = split($2, p, "-"); w = h = p[n] + 0; if ($2 ~ /^dots/) { w = 110; h = 14 }
                x = $3; y = $4; r = $3 + w; b = $4 + h }
    $1 == "T" { x = $4; y = $6; r = 600 - $5; b = $6 + $3 * 1.2 }
    x < 0 || y < 0 || r > 600 || b > 800 { print "off screen: " $0; bad = 1 }
    END { exit bad }' || fail=1
[ $fail = 0 ] && echo ok || { printf '%s\n' "$out" "$week"; exit 1; }
