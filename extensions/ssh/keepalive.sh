#!/bin/sh
# Started by ssh_on.sh (from /var/local/ssh, detached): keeps Wi-Fi from going idle while
# dropbear runs, since the Kindle drops Wi-Fi to save power even with SSH on. Pings the
# router every 20 s and asks for a reconnect if wlan0 loses its address. Exits with dropbear.
D=/var/local/ssh
LOG=$D/ssh.log
wip() { ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p'; }
st() { lipc-get-prop com.lab126.wifid cmState 2>/dev/null; }
n=0
while [ -f "$D/pid" ] && kill -0 "$(cat "$D/pid")" 2>/dev/null; do
    gw=$(route -n | awk '$1 == "0.0.0.0" { print $2; exit }')
    [ -n "$gw" ] && ping -c 1 -W 2 "$gw" >/dev/null 2>&1 && ok=ok || ok=fail
    if [ $n -lt 9 ]; then  # the first 3 minutes, for debugging: state, router ping, who has ARPed us
        echo "$(date) keepalive: wifid $(st) ip $(wip) gw $gw ping $ok arp: $(sed 1d /proc/net/arp | awk '{ printf "%s ", $1 }')" >> "$LOG"
        n=$((n + 1))
    fi
    [ "$(st)" = CONNECTED ] || { echo "$(date) wifid $(st): reconnecting" >> "$LOG"; lipc-set-prop com.lab126.cmd ensureConnection wifi; }
    sleep 20
done
echo "$(date) keepalive: dropbear gone, exiting" >> "$LOG"
