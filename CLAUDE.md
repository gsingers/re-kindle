# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A standalone e-ink weather dashboard for a jailbroken Kindle (600×800, busybox userland, clock in UTC). It lives in `extensions/dashboard/` on the Kindle, fetches Open-Meteo weather (Charlotte, NC; °F, mph, inches) over Wi-Fi, and draws with FBInk. Upstream wrote it for a 7th gen (KT2, firmware 5.12.2.2) with a prayer-times card; this fork targets the user's **8th gen (KT3, firmware 5.16.2.1.1, soft-float `kindlepw2`)** and has removed the prayer card.

The KT3 is jailbroken with **WinterBreak2** (the modern "hdnext" stack: jb.sh/KMC, KPM). **KUAL does not work on that stack**: the dashboard is launched by scriptlets in `extensions/dashboard/scriptlets/`, copied to `/mnt/us/documents`, where `.sh` files show up as library books (`# Name:` sets the title). `menu.json`/`config.xml` are kept for KUAL devices. Don't upgrade the firmware: 5.16.3+ is hard-float (`kindlehf`) and the bundled FBInk is soft-float. `server.py` is an older, separate approach (serves an HTML page for the Kindle's browser) and is not part of the extension.

## Commands (Mac side)

```sh
sh extensions/dashboard/check.sh          # all checks: render.awk output, scheduling helpers, on-screen bounds; prints "ok"
sh -n extensions/dashboard/loop.sh        # syntax check the device loop
python3 tools/make_icons.py               # regenerate icons/*.png (stdlib PNG writer)
# Preview a screen as SVG/HTML (run from the repo root; icon paths are relative to it):
awk -v place=Vienna -v batt=87 -v utc=1800 -v card=0 -v tab=today \
    -f extensions/dashboard/render.awk weather.csv prayer.txt | python3 tools/preview.py > preview.html
# Screenshot it at the Kindle's size:
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars \
    --window-size=600,800 --screenshot="$PWD/preview.png" "file://$PWD/preview.html"
```

There is no single-test runner: `check.sh` is one script of `expect "<output>" "<substring>"` lines; add a case there next to the feature it covers. Run checks with `sh` (the Kindle's shell), not zsh: zsh doesn't word-split `$NIGHT`, so the scheduling helpers give wrong answers under it.

## Deploying to the Kindle

With the Kindle mounted over USB at `/Volumes/Kindle`, copy each changed file to a temp name and rename it (a new inode, so a running `loop.sh` isn't corrupted mid-read), verify, then delete macOS `._*` files:

```sh
K=/Volumes/Kindle/extensions/dashboard
cp -X f "$K/f.tmp" && mv -f "$K/f.tmp" "$K/f" && cmp f "$K/f"
find /Volumes/Kindle/extensions -name '._*' -delete
```

Scriptlets go to `/Volumes/Kindle/documents/`. Changes only take effect after the user ejects and runs Dashboard Stop then Dashboard Start from the library. `render.awk` is re-read on every draw but `loop.sh` is not, so a new `render.awk` under an old running loop can render with mismatched tap zones and colours.

## Architecture

- **`loop.sh`** is the only process that draws. It owns the schedule: Wi-Fi on → fetch → Wi-Fi off; render; suspend to RAM with an RTC wake alarm (`echo mem > /sys/power/state`). Knobs at the top (`INTERVAL`, `NIGHT`, `IDLE`, tap zones, `GREY`, `PRAYER_METHOD`). Battery savers: hourly refresh, no refreshes in the `NIGHT` hours, and a redraw is skipped when the rendered commands equal `screen.key` (ignoring the "Updated" line). Local time = device UTC + `utc_offset_seconds` from line 2 of `weather.csv`.
- **Touch** is a background `watch_touch` reading raw evdev from `/dev/input/event0` (zforce2 on the KT3; it was `event1` on the KT2) (`dd | od -t d2`; coordinates are screen pixels). It never draws: it writes a request (`today`, `10d`, `card`) to `$DIR/tap`, which the main loop picks up with `mv tap tap.read`. Tapping the place name (top left) runs `stop.sh` = Home. The Kindle UI (`cvm`) is SIGSTOPped while the dashboard runs; `stop.sh` resumes it and undoes Wi-Fi/alarm/screensaver changes.
- **`render.awk`** turns `weather.csv` (Open-Meteo CSV: meta, current, hourly, daily sections separated by blank lines, columns positional) into a line protocol, `T|style|px|left|right|top|flags|text`, `R|x|y|w|h|color`, `I|name|x|y`, which `loop.sh`'s `draw_fbink` executes. Text flags: `c` centred, `i` inverted, `g` secondary (`-C $GREY`). New API fields must be appended to the end of the URL's field lists so old CSVs keep their column positions. The bottom card is a slot for future widgets: `CARDS` in `loop.sh` (now 1, the date card) and `card`/`cards` in `render.awk`; add a card as a new `card == N` branch, with its data fetched in `refresh()` and passed as an extra awk input (upstream's prayer card, in git history, is a full example).
- **FBInk v1.25** in `bin/` has no image support: icons are drawn with the Kindle's `eips -g`. It can't right-align or measure text, so widths are estimated in awk (`rtext()`, the big-temperature width heuristic). Overflowing text wraps onto a second line rather than clipping.
- **`tools/preview.py`** mirrors the protocol as SVG with Helvetica (the device uses Amazon Ember), so spacing on the device differs slightly.

## SSH (`extensions/ssh/`)

Library scriptlets **SSH On (Wi-Fi)** / **SSH Off (Wi-Fi)** run `ssh_on.sh` / `ssh_off.sh` (detached with `nohup setsid`: the launcher waits for every process a scriptlet starts, so a daemon left attached froze it on a blank screen). SSH On turns Wi-Fi on, sets `preventScreenSaver 1`, and runs `bin/dropbearmulti` bound to the Wi-Fi address only, keys only; the address is shown on screen and written to `extensions/ssh/ip.txt`. Use it while the dashboard is stopped (the dashboard turns Wi-Fi off and suspends). Everything runs from `/var/local/ssh` (ext3, persistent; log `ssh.log`, copied to `extensions/ssh/` by SSH Off): `/mnt/us` is vfat and fails dropbear's permission checks, and it is unreadable on the Kindle while it is a USB drive. The Mac key is `~/.ssh/kindle_ed25519`; its `.pub` is copied to `extensions/ssh/authorized_keys` at deploy time (gitignored). Connect with `ssh -i ~/.ssh/kindle_ed25519 root@<ip>`; the Kindle's Wi-Fi MAC is `50:F5:DA:B2:FF:21` if the IP is unknown. Copy with `scp -O` (no sftp-server). USB networking (`useUsbForNetwork`, usb0 at 192.168.15.244) was tried and abandoned: the mode switch needs a re-plug at the right moment, and usb0 received but never transmitted. `dropbearmulti` is a static musl build of dropbear 2026.94: rebuild with `sh tools/dropbear/build.sh` (Docker, QEMU arm/v7; see `tools/dropbear/BUILD.md`).

## Constraints that have bitten before

- The device awk is **busybox awk**. Never join a variable and a parenthesised expression as `name (expr)`: busybox parses it as a call to function `name` and aborts the render mid-screen. Start with the paren or use a temp variable. Mac awk accepts both, so `check.sh` won't catch this.
- awk counts the UTF-8 `°` as 2 bytes; width estimates count digits/`-` with `gsub` and add the degree sign once.
- The Kindle's clock is UTC; the local date comes from line 5 of `weather.csv` (`cut -c1-10`).
- Open-Meteo is fetched over https (verified on the KT3 with `probe.sh`; upstream used plain http for the KT2's older TLS). Never add `curl -k`.
- eips text rows are 24 px on this firmware, so rows run 0-32; `eips 0 38` (upstream's status row) is off screen and floods the launcher with errors.
- Scriptlet launchers print a script's output on screen, so each one sends its output to /dev/null.
- The loop writes no log file (`start.sh` sends output to `/dev/null`); redirect it to a file there to debug on the device.
- Git: branch `main`; `origin` is the fork `gsingers/re-kindle`, `upstream` is the original `abdenourgnx/re-kindle`.
