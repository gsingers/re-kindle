#!/bin/sh
# Undoes ssh_on.sh: stops dropbear and lets the Kindle sleep again. Wi-Fi is left as it is.
# Copies the log to the USB drive so the Mac can read it.
SRC=/mnt/us/extensions/ssh
D=/var/local/ssh
exec >> "$D/ssh.log" 2>&1
echo "$(date) ssh off"
[ -f "$D/pid" ] && kill "$(cat "$D/pid")" 2>/dev/null; rm -f "$D/pid" "$SRC/ip.txt"
lipc-set-prop com.lab126.powerd preventScreenSaver 0
# Earlier USB-network versions switched USB away from drive mode: switch it back.
[ "$(lipc-get-prop com.lab126.volumd useUsbForNetwork 2>/dev/null)" = 1 ] && lipc-set-prop com.lab126.volumd useUsbForNetwork 0
cp -f "$D/ssh.log" "$SRC/ssh.log" 2>/dev/null
eips 0 30 "SSH off" >/dev/null
