#!/bin/sh
# Started by ssh_on.sh (from /var/local/ssh, detached): keeps Wi-Fi up while dropbear runs.
# The Kindle drops Wi-Fi when idle even with SSH on, and its radio power-saves between its
# own transmissions, so incoming SSH gets lost. Every 5 s: ping the router; if wifid isn't
# CONNECTED twice running, cycle Wi-Fi (ensureConnection alone left it PENDING). Logs state
# changes. Exits with dropbear.
D=/var/local/ssh
LOG=$D/ssh.log
wip() { ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p'; }
st() { lipc-get-prop com.lab126.wifid cmState 2>/dev/null; }
nopower() {  # Wi-Fi power saving off, with whichever tool this firmware has
    iwconfig wlan0 power off 2>/dev/null; command -v wl >/dev/null && wl PM 0 2>/dev/null
}
last=""; down=0
while [ -f "$D/pid" ] && kill -0 "$(cat "$D/pid")" 2>/dev/null; do
    s=$(st)
    [ "$s" != "$last" ] && { echo "$(date) keepalive: wifid $s ip $(wip)" >> "$LOG"; [ "$s" = CONNECTED ] && nopower; last=$s; }
    if [ "$s" = CONNECTED ]; then
        down=0
        gw=$(route -n | awk '$1 == "0.0.0.0" { print $2; exit }')
        [ -n "$gw" ] && ping -c 1 -W 2 "$gw" >/dev/null 2>&1
    else
        down=$((down + 1))
        if [ $down -ge 2 ]; then
            echo "$(date) keepalive: wifid $s, cycling Wi-Fi" >> "$LOG"
            lipc-set-prop com.lab126.cmd wirelessEnable 0; sleep 3; lipc-set-prop com.lab126.cmd wirelessEnable 1
            down=-6  # give the reconnect ~40 s before trying again
        fi
    fi
    sleep 5
done
echo "$(date) keepalive: dropbear gone, exiting" >> "$LOG"
