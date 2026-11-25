#!/bin/sh
# Undoes ssh_on.sh: stops dropbear and gives USB back to drive mode (after a re-plug).
# Copies the log to the USB drive so the Mac can read it.
SRC=/mnt/us/extensions/ssh
D=/var/local/ssh
exec >> "$D/ssh.log" 2>&1
echo "$(date) ssh off"
[ -f "$D/pid" ] && kill "$(cat "$D/pid")" 2>/dev/null; rm -f "$D/pid"
ifconfig usb0 down 2>/dev/null
lipc-set-prop com.lab126.volumd useUsbForNetwork 0
cp -f "$D/ssh.log" "$SRC/ssh.log" 2>/dev/null
eips 0 30 "SSH off: re-plug for drive" >/dev/null
