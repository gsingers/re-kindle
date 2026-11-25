#!/bin/sh
# SSH over the USB cable, keys only: the Kindle is 192.168.15.244, the Mac 192.168.15.201.
# While it is on, USB is a network link instead of a drive. ssh_off.sh undoes everything.
# Run as root (the WinterBreak scriptlet launcher runs as root). Log: $SRC/ssh.log.
SRC=/mnt/us/extensions/ssh   # what the Mac copies over USB (vfat: fails dropbear's permission checks)
D=/var/local/ssh             # ext3 and persistent: binary, host keys, authorized_keys
IP=192.168.15.244
exec > "$SRC/ssh.log" 2>&1
echo "$(date) ssh on"
msg() { eips 0 30 "$1" >/dev/null; echo "$1"; }

[ -f "$SRC/authorized_keys" ] || { msg "SSH: no authorized_keys"; exit 1; }
mkdir -p "$D" && chmod 700 "$D"
cp -f "$SRC/bin/dropbearmulti" "$D/dropbearmulti" && chmod 700 "$D/dropbearmulti" || { msg "SSH: copy failed"; exit 1; }
cp -f "$SRC/authorized_keys" "$D/authorized_keys" && chmod 600 "$D/authorized_keys"
ln -sf "$D/dropbearmulti" "$D/scp"  # first on the session PATH, for scp -O from the Mac
for t in ed25519 ecdsa; do
    [ -f "$D/dropbear_${t}_host_key" ] || "$D/dropbearmulti" dropbearkey -t "$t" -f "$D/dropbear_${t}_host_key"
done

# Switch USB from drive to network (as Jobman does), then give usb0 its address.
lipc-set-prop com.lab126.volumd useUsbForNetwork 1
i=0; until ifconfig usb0 >/dev/null 2>&1 || [ $i -ge 10 ]; do sleep 1; i=$((i + 1)); done
ifconfig usb0 "$IP" netmask 255.255.255.0 up || { msg "SSH: no usb0 network"; exit 1; }
iptables -C INPUT -i usb0 -p tcp --dport 22 -j ACCEPT 2>/dev/null || iptables -I INPUT -i usb0 -p tcp --dport 22 -j ACCEPT

[ -f "$D/pid" ] && kill "$(cat "$D/pid")" 2>/dev/null
# -p binds the USB address only, so nothing listens on Wi-Fi. -D: authorized_keys in $D.
"$D/dropbearmulti" dropbear -r "$D/dropbear_ed25519_host_key" -r "$D/dropbear_ecdsa_host_key" \
    -D "$D" -p "$IP:22" -P "$D/pid" -s -g || { msg "SSH: dropbear failed"; exit 1; }
msg "SSH on: root@$IP (USB)"
