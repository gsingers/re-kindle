#!/bin/sh
# Undoes ssh_on.sh: stops dropbear and gives USB back to drive mode.
SRC=/mnt/us/extensions/ssh
D=/var/local/ssh
exec >> "$SRC/ssh.log" 2>&1
echo "$(date) ssh off"
[ -f "$D/pid" ] && kill "$(cat "$D/pid")" 2>/dev/null; rm -f "$D/pid"
iptables -D INPUT -i usb0 -p tcp --dport 22 -j ACCEPT 2>/dev/null
ifconfig usb0 down 2>/dev/null
lipc-set-prop com.lab126.volumd useUsbForNetwork 0
eips 0 30 "SSH off" >/dev/null
