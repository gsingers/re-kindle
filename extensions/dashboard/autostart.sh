#!/bin/sh
# "on": start the dashboard by itself after every boot. "off": don't.
# The boot job lives in /etc/upstart and only acts while the autostart flag file exists.
DIR=/mnt/us/extensions/dashboard
if [ "$1" = on ]; then
    if [ ! -f /etc/upstart/dashboard.conf ]; then
        mntroot rw && cp "$DIR/dashboard.conf" /etc/upstart/dashboard.conf
        mntroot ro
    fi
    touch "$DIR/autostart"
    msg="Autostart on: 90 s after boot."
else
    rm -f "$DIR/autostart"
    msg="Autostart off."
fi
[ "$1" = on ] && [ ! -f /etc/upstart/dashboard.conf ] && msg="Autostart FAILED: no boot job."
eips 0 30 "$msg"
