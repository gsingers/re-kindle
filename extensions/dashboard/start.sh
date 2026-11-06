#!/bin/sh
DIR=/mnt/us/extensions/dashboard
sh "$DIR/stop.sh"
nohup sh "$DIR/loop.sh" >> "$DIR/log.txt" 2>&1 &
