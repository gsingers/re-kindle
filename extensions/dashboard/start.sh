#!/bin/sh
DIR=/mnt/us/extensions/dashboard
sh "$DIR/stop.sh"
nohup sh "$DIR/loop.sh" > /dev/null 2>&1 &  # no log file: send to a file here to debug
