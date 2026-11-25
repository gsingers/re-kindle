#!/bin/sh
# Undoes ssh_on.sh: stops dropbear and lets the Kindle sleep again. Wi-Fi is left as it is.
# Copies the log to the USB drive so the Mac can read it.
SRC=/mnt/us/extensions/ssh
D=/var/local/ssh
LOG=$D/ssh.log
echo "$(date) ssh off" >> "$LOG"
echo "SSH: stopping"
[ -f "$D/pid" ] && kill "$(cat "$D/pid")" 2>/dev/null; rm -f "$D/pid" "$SRC/ip.txt"
lipc-set-prop com.lab126.powerd preventScreenSaver 0 >> "$LOG" 2>&1
# Earlier USB-network versions switched USB away from drive mode: switch it back.
[ "$(lipc-get-prop com.lab126.volumd useUsbForNetwork 2>/dev/null)" = 1 ] && lipc-set-prop com.lab126.volumd useUsbForNetwork 0
cp -f "$LOG" "$SRC/ssh.log" 2>/dev/null; sync
echo "SSH off. Back to Home in a few seconds."
sleep 4; lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home
