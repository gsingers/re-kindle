#!/bin/sh
# Name: SSH Off (Wi-Fi)
# Author: re-kindle
# Copied to /mnt/us/documents, where the WinterBreak jailbreak lists .sh files as books.
# In the background, detached: the launcher waits for every process a scriptlet starts,
# so a dropbear daemon left in its process group kept it on a blank screen for good.
S=$(command -v setsid)  # a new session if this busybox has setsid
nohup $S sh /mnt/us/extensions/ssh/ssh_off.sh </dev/null >/dev/null 2>&1 &
