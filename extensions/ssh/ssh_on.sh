#!/bin/sh
# SSH over Wi-Fi, keys only: dropbear on the Kindle's Wi-Fi address, port 22. The address is
# shown on screen and written to $SRC/ip.txt; the Mac can also find it by the Kindle's MAC.
# Use it while the dashboard is stopped (the dashboard turns Wi-Fi off and suspends).
# USB networking was tried first: it needs a re-plug at the right moment and usb0 never
# answered, so this uses Wi-Fi and leaves USB as a drive.
# Runs as root (the WinterBreak scriptlet launcher does). Log: /var/local/ssh/ssh.log.
SRC=/mnt/us/extensions/ssh   # what the Mac copies over USB (vfat: fails dropbear's permission checks)
D=/var/local/ssh             # ext3 and persistent: binary, host keys, authorized_keys, log
mkdir -p "$D" && chmod 700 "$D"
exec >> "$D/ssh.log" 2>&1
echo "$(date) ssh on"
msg() { eips 0 30 "$1" >/dev/null; echo "$1"; }

[ -f "$SRC/authorized_keys" ] || { msg "SSH: unplug USB, then retry"; exit 1; }
cp -f "$SRC/bin/dropbearmulti" "$D/dropbearmulti" && chmod 700 "$D/dropbearmulti" || { msg "SSH: copy failed"; exit 1; }
cp -f "$SRC/authorized_keys" "$D/authorized_keys" && chmod 600 "$D/authorized_keys"
ln -sf "$D/dropbearmulti" "$D/scp"  # first on the session PATH, for scp -O from the Mac
for t in ed25519 ecdsa; do
    [ -f "$D/dropbear_${t}_host_key" ] || "$D/dropbearmulti" dropbearkey -t "$t" -f "$D/dropbear_${t}_host_key"
done

# Earlier USB-network versions switched USB away from drive mode: keep it a drive.
[ "$(lipc-get-prop com.lab126.volumd useUsbForNetwork 2>/dev/null)" = 1 ] && lipc-set-prop com.lab126.volumd useUsbForNetwork 0
lipc-set-prop com.lab126.cmd wirelessEnable 1
wip() { ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p'; }
i=0; until [ -n "$(wip)" ] || [ $i -ge 60 ]; do sleep 1; i=$((i + 1)); done
IP=$(wip)
[ -n "$IP" ] || { msg "SSH: no Wi-Fi address"; exit 1; }
# Stay awake while SSH is on: a suspended Kindle drops the connection. ssh_off.sh undoes it.
lipc-set-prop com.lab126.powerd preventScreenSaver 1

[ -f "$D/pid" ] && kill "$(cat "$D/pid")" 2>/dev/null
# -p binds the Wi-Fi address only. No iptables on this kernel, so nothing filters port 22;
# password logins are compiled out, so only the key in authorized_keys gets in.
"$D/dropbearmulti" dropbear -r "$D/dropbear_ed25519_host_key" -r "$D/dropbear_ecdsa_host_key" \
    -D "$D" -p "$IP:22" -P "$D/pid" -s -g || { msg "SSH: dropbear failed"; exit 1; }
echo "$IP" > "$SRC/ip.txt"
msg "SSH on: root@$IP"
sleep 4; eips 0 30 "SSH on: root@$IP" >/dev/null  # again, after the library redraws over it
