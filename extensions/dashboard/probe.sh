#!/bin/sh
# Records what this Kindle has, so the dashboard can be tuned to it, plus
# 12 seconds of raw touch events while the Kindle UI is paused (the Home-bar test).
DIR=/mnt/us/extensions/dashboard
URL="api.open-meteo.com/v1/forecast?latitude=35.23&longitude=-80.84&current=temperature_2m&format=csv"
eips 0 38 "Probe running (about 30 s). Don't tap yet."
{
    echo "--- time"; date; date -u
    echo "--- system"; uname -a; id; cat /etc/prettyversion.txt 2>/dev/null
    echo "--- tools"
    for c in curl wget eips fbink openssl awk od dd nohup killall mntroot lipc-set-prop lipc-get-prop python3; do
        printf '%s: ' "$c"; command -v "$c" || echo missing
    done
    echo "--- curl"; curl --version 2>&1 | head -3
    echo "--- eips"; eips -i 2>&1 | head -40
    echo "--- wifi"; lipc-get-prop com.lab126.wifid cmState; lipc-get-prop com.lab126.cmd wirelessEnable
    echo "--- curl http";  curl -s -m 10 "http://$URL" 2>&1 | head -5
    echo "--- curl https"; curl -s -m 10 "https://$URL" 2>&1 | head -5
    echo "--- wget http";  wget -q -T 10 -O - "http://$URL" 2>&1 | head -5
    echo "--- awk"; echo 'a,bc' | awk -F, '{ s = sprintf("[%2d]", 4); print $2, length($2), s }'
    echo "--- od"; printf 'ABCDEFGHIJKLMNOP' | od -An -t d2
    echo "--- upstart"; ls /etc/upstart
    echo "--- input"; cat /proc/bus/input/devices
    echo "--- ui process"; pidof cvm || ps | grep -i cvm
    echo "--- cpu"; grep '^Hardware' /proc/cpuinfo
    echo "--- fbink"; "$DIR/bin/fbink" -e
    echo "--- fonts"; ls /usr/java/lib/fonts
} > "$DIR/probe.txt" 2>&1

# Touch test: the UI is paused so taps only reach us.
echo "--- pause ui" >> "$DIR/probe.txt"
killall -STOP cvm >> "$DIR/probe.txt" 2>&1
eips -c
eips 0 10 "TOUCH TEST (12 seconds)"
eips 0 12 "1. Tap the TOP-LEFT corner"
eips 0 13 "2. Tap the BOTTOM-RIGHT corner"
eips 0 14 "3. Tap the middle of the BOTTOM edge"
pids=""
for e in /dev/input/event*; do
    cat "$e" > "$DIR/touch-${e##*/}.bin" &
    pids="$pids $!"
done
sleep 12
kill $pids 2>/dev/null
echo "--- resume ui" >> "$DIR/probe.txt"
killall -CONT cvm >> "$DIR/probe.txt" 2>&1
ls -l "$DIR"/touch-*.bin >> "$DIR/probe.txt" 2>&1
lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home
sleep 3
eips 0 38 "Probe done. Plug the Kindle into the Mac."
