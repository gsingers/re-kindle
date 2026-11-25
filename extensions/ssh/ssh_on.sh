#!/bin/sh
# SSH over the USB cable, keys only: the Kindle is 192.168.15.244, the Mac 192.168.15.201.
# Order: UNPLUG, run this, plug in when the screen says so. The USB mode switch only takes
# effect on the next plug-in, and while the Kindle is a USB drive it can't read /mnt/us.
# While SSH is on, USB is a network link instead of a drive. ssh_off.sh undoes everything.
# Runs as root (the WinterBreak scriptlet launcher does). Log: /var/local/ssh/ssh.log,
# copied to $SRC/ssh.log by ssh_off.sh.
SRC=/mnt/us/extensions/ssh   # what the Mac copies over USB (vfat: fails dropbear's permission checks)
D=/var/local/ssh             # ext3 and persistent: binary, host keys, authorized_keys, log
IP=192.168.15.244
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

# Switch USB from drive to network (as Jobman does); usb0 appears once the cable goes in.
lipc-set-prop com.lab126.volumd useUsbForNetwork 1
msg "SSH: plug in the cable now"
i=0; until ifconfig usb0 >/dev/null 2>&1 || [ $i -ge 90 ]; do sleep 1; i=$((i + 1)); done
echo "usb0 after $i s"
ifconfig usb0 "$IP" netmask 255.255.255.0 up || { msg "SSH: no usb0 network"; exit 1; }
# No iptables on this kernel (no ip_tables module), so nothing filters port 22.

[ -f "$D/pid" ] && kill "$(cat "$D/pid")" 2>/dev/null
# -p binds the USB address only, so nothing listens on Wi-Fi. -D: authorized_keys in $D.
"$D/dropbearmulti" dropbear -r "$D/dropbear_ed25519_host_key" -r "$D/dropbear_ecdsa_host_key" \
    -D "$D" -p "$IP:22" -P "$D/pid" -s -g || { msg "SSH: dropbear failed"; exit 1; }
msg "SSH on: root@$IP"

# What the USB network looks like, for debugging (read it after SSH Off, in drive mode).
echo "--- useUsbForNetwork: $(lipc-get-prop com.lab126.volumd useUsbForNetwork 2>&1)"
echo "--- /sys/class/net"; ls /sys/class/net
echo "--- ifconfig -a"; ifconfig -a
echo "--- route"; route -n
echo "--- lsmod"; lsmod
echo "--- listening"; netstat -ltn 2>&1
echo "--- usbnetd.conf"; cat /etc/upstart/usbnetd.conf 2>&1
echo "--- usbnet-autostart.conf"; cat /etc/upstart/usbnet-autostart.conf 2>&1
sleep 20; echo "--- after 20 s"; ifconfig usb0; cat /proc/net/arp
