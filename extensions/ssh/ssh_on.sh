#!/bin/sh
# SSH over Wi-Fi, keys only: dropbear on the Kindle's Wi-Fi address, port 22. The address is
# shown on screen and written to $SRC/ip.txt; the Mac can also find it by the Kindle's MAC.
# Use it while the dashboard is stopped (the dashboard turns Wi-Fi off and suspends).
# USB networking was tried first: it needs a re-plug at the right moment and usb0 never
# answered, so this uses Wi-Fi and leaves USB as a drive.
# Runs as root from the scriptlet launcher, which shows this script's output on screen, so it
# prints its progress, then goes back to Home. Log: /var/local/ssh/ssh.log, copied to $SRC/ssh.log.
SRC=/mnt/us/extensions/ssh   # what the Mac copies over USB (vfat: fails dropbear's permission checks)
D=/var/local/ssh             # ext3 and persistent: binary, host keys, authorized_keys, log
mkdir -p "$D" && chmod 700 "$D"
LOG=$D/ssh.log
echo "$(date) ssh on" >> "$LOG"
say() { echo "$1"; echo "$1" >> "$LOG"; }  # on screen and in the log
msg() { say "$1"; }
# Leaves the launcher screen: copy the log for the Mac, then show Home after a pause to read.
home() { cp -f "$LOG" "$SRC/ssh.log" 2>/dev/null; sync; sleep 6; lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home; }

say "SSH: starting"
[ -f "$SRC/authorized_keys" ] || { msg "SSH: unplug USB, then retry"; home; exit 1; }
cp -f "$SRC/bin/dropbearmulti" "$D/dropbearmulti" && chmod 700 "$D/dropbearmulti" || { msg "SSH: copy failed"; home; exit 1; }
cp -f "$SRC/authorized_keys" "$D/authorized_keys" && chmod 600 "$D/authorized_keys"
ln -sf "$D/dropbearmulti" "$D/scp"  # first on the session PATH, for scp -O from the Mac
for t in ed25519 ecdsa; do
    [ -f "$D/dropbear_${t}_host_key" ] || { say "Making $t host key"; "$D/dropbearmulti" dropbearkey -t "$t" -f "$D/dropbear_${t}_host_key" >> "$LOG" 2>&1; }
done

# Earlier USB-network versions switched USB away from drive mode: keep it a drive.
[ "$(lipc-get-prop com.lab126.volumd useUsbForNetwork 2>/dev/null)" = 1 ] && lipc-set-prop com.lab126.volumd useUsbForNetwork 0
# Settings can say "Connected" while wifid is idle (cmState PENDING, wlan0 without carrier):
# the Kindle drops Wi-Fi to save power and reconnects only when asked. Ask; if that doesn't
# bring an address, cycle Wi-Fi off and on, which is what the dashboard does every refresh.
wip() { ifconfig wlan0 2>/dev/null | sed -n 's/.*inet addr:\([0-9.]*\).*/\1/p'; }
waitip() { i=0; until [ -n "$(wip)" ] || [ $i -ge "$1" ]; do sleep 1; i=$((i + 1)); done; }
say "Connecting Wi-Fi"
lipc-set-prop com.lab126.cmd wirelessEnable 1 >> "$LOG" 2>&1
lipc-set-prop com.lab126.cmd ensureConnection wifi >> "$LOG" 2>&1
waitip 20
if [ -z "$(wip)" ]; then
    say "Restarting Wi-Fi (60 s)"
    lipc-set-prop com.lab126.cmd wirelessEnable 0 >> "$LOG" 2>&1; sleep 3
    lipc-set-prop com.lab126.cmd wirelessEnable 1 >> "$LOG" 2>&1
    waitip 60
fi
echo "wifid cmState: $(lipc-get-prop com.lab126.wifid cmState 2>&1)" >> "$LOG"
IP=$(wip)
[ -n "$IP" ] || {
    msg "SSH: no Wi-Fi address. Airplane mode?"
    { echo "--- wifid cmState: $(lipc-get-prop com.lab126.wifid cmState 2>&1)"
      echo "--- /sys/class/net: $(ls /sys/class/net)"; echo "--- ifconfig -a"; ifconfig -a
      echo "--- ip addr"; ip addr 2>&1; echo "--- route"; route -n; echo "--- PATH=$PATH"; } >> "$LOG" 2>&1
    home; exit 1; }
# Stay awake while SSH is on: a suspended Kindle drops the connection. ssh_off.sh undoes it.
lipc-set-prop com.lab126.powerd preventScreenSaver 1 >> "$LOG" 2>&1

[ -f "$D/pid" ] && kill "$(cat "$D/pid")" 2>/dev/null
# -p binds the Wi-Fi address only. No iptables on this kernel, so nothing filters port 22;
# password logins are compiled out, so only the key in authorized_keys gets in.
# Fully detached (new session, no shared output) so the launcher never waits on it.
S=$(command -v setsid)
$S "$D/dropbearmulti" dropbear -r "$D/dropbear_ed25519_host_key" -r "$D/dropbear_ecdsa_host_key" \
    -D "$D" -p "$IP:22" -P "$D/pid" -s -g </dev/null >> "$LOG" 2>&1 || { msg "SSH: dropbear failed"; home; exit 1; }
echo "$IP" > "$SRC/ip.txt"; sync  # flush: vfat writes are lost if USB takes the drive first
msg "SSH on: root@$IP"
say "Back to Home in a few seconds."
home
sleep 4; eips 0 30 "SSH on: root@$IP" >/dev/null  # on Home too, once it has drawn
