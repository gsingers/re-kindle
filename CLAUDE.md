# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A standalone e-ink weather dashboard for a jailbroken Kindle (600×800, busybox userland, clock in UTC). It lives in `extensions/dashboard/` on the Kindle, fetches Open-Meteo weather (Charlotte, NC; °F, mph, inches) over https, and draws with FBInk. Upstream wrote it for a 7th gen (KT2, firmware 5.12.2.2) with a prayer-times card; this fork targets the user's **8th gen (KT3, firmware 5.16.2.1.1, soft-float `kindlepw2`)** and has removed the prayer card. `extensions/ssh/` adds SSH over Wi-Fi for working on the device. `server.py` is an older, separate approach (an HTML page for the Kindle's browser) and is not part of the extension.

The KT3 is jailbroken with **WinterBreak2** (the modern "hdnext" stack: jb.sh/KMC, KPM). **KUAL does not work on that stack**: everything is launched by scriptlets, `.sh` files in `/mnt/us/documents` that show up as library books (`# Name:` sets the title) and run as root. The repo keeps them in `extensions/*/scriptlets/`; `menu.json`/`config.xml` stay for KUAL devices. **Don't upgrade the firmware**: 5.16.3+ is hard-float (`kindlehf`), the bundled FBInk is soft-float, and WinterBreak2 may not cover it.

## Commands (Mac side)

```sh
sh extensions/dashboard/check.sh          # all checks: render.awk output, scheduling helpers, on-screen bounds; prints "ok"
sh -n extensions/dashboard/loop.sh        # syntax check the device loop (likewise any .sh)
python3 tools/make_icons.py               # regenerate icons/*.png (stdlib PNG writer)
# Preview a screen as SVG/HTML from a real forecast (run from the repo root; icon paths are relative to it).
# Get weather.csv with loop.sh's URL, $LAT/$LON/$TIMEZONE filled in.
awk -v place=Charlotte -v batt=87 -v utc=1800 -v tab=today -v cards=1 \
    -f extensions/dashboard/render.awk weather.csv | python3 tools/preview.py > preview.html
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars \
    --window-size=600,800 --screenshot="$PWD/preview.png" "file://$PWD/preview.html"
sh tools/dropbear/build.sh                # rebuild extensions/ssh/bin/dropbearmulti (Docker, QEMU arm/v7)
```

There is no single-test runner: `check.sh` is one script of `expect "<output>" "<substring>"` lines; add a case there next to the feature it covers. Run checks with `sh` (the Kindle's shell), not zsh: zsh doesn't word-split `$NIGHT`, so the scheduling helpers give wrong answers under it.

Commit from a git worktree (`git worktree add .claude/worktrees/<branch> -b <branch>`): a hook blocks commits and pushes in the main checkout.

## Deploying to the Kindle

**Over USB** (Kindle mounted at `/Volumes/Kindle`): copy each changed file to a temp name and rename it (a new inode, so a running `loop.sh` isn't corrupted mid-read), verify, delete macOS `._*` files, eject:

```sh
K=/Volumes/Kindle/extensions/dashboard
cp -X f "$K/f.tmp" && mv -f "$K/f.tmp" "$K/f" && cmp f "$K/f"
find /Volumes/Kindle/extensions /Volumes/Kindle/documents -name '._*' -delete
diskutil eject /Volumes/Kindle
```

Scriptlets go to `/Volumes/Kindle/documents/`; the SSH key to `extensions/ssh/authorized_keys` (`cp ~/.ssh/kindle_ed25519.pub`, gitignored). Read any device log (`extensions/ssh/ssh.log`, `probe.txt`) *before* ejecting. Plugging in while the dashboard runs may not offer the drive: tap the place name (Home) first.

**Over SSH** (after SSH On, see below): `scp -O -i ~/.ssh/kindle_ed25519 f root@<ip>:/mnt/us/extensions/dashboard/f.tmp`, then `mv` it into place in an `ssh` command.

Changes take effect after Dashboard Stop then Dashboard Start from the library. `render.awk` is re-read on every draw but `loop.sh` is not, so a new `render.awk` under an old running loop can render with mismatched tap zones and colours.

## Architecture

- **`loop.sh`** is the only process that draws. It owns the schedule: Wi-Fi on → fetch → Wi-Fi off; render; suspend to RAM with an RTC wake alarm (`echo mem > /sys/power/state`). Knobs at the top (`PLACE`/`LAT`/`LON`/`TIMEZONE`, `INTERVAL`, `NIGHT`, `IDLE`, `TOUCH`, tap zones, `CARDS`, `GREY`). Battery savers: hourly refresh, no refreshes in the `NIGHT` hours, and a redraw is skipped when the rendered commands equal `screen.key` (ignoring the "Updated" line). Taps only work while awake: after `IDLE` s without a tap it sleeps (the power button wakes it for another `IDLE` s); at start the idle clock begins when the first screen appears, since the first fetch can outlast `IDLE`. Local time = device UTC + `utc_offset_seconds` from line 2 of `weather.csv`.
- **Touch** is a background `watch_touch` reading raw evdev from `/dev/input/event0` (zforce2 on the KT3; `event1` on the KT2) with `dd | od -t d2`; coordinates are screen pixels. It never draws: it writes a request (`today`, `10d`, `card`) to `$DIR/tap`, which the main loop picks up with `mv tap tap.read`. Tapping the place name (top left) runs `stop.sh` = Home. The Kindle UI (`cvm`) is SIGSTOPped while the dashboard runs; `stop.sh` resumes it and undoes Wi-Fi/alarm/screensaver changes.
- **`render.awk`** turns `weather.csv` (Open-Meteo CSV: meta, current, hourly, daily sections separated by blank lines, columns positional) into a line protocol, `T|style|px|left|right|top|flags|text`, `R|x|y|w|h|color`, `I|name|x|y`, which `loop.sh`'s `draw_fbink` executes. Text flags: `c` centred, `i` inverted, `g` secondary (`-C $GREY`). New API fields must be appended to the end of the URL's field lists so old CSVs keep their column positions (unit parameters like `temperature_unit` don't move columns).
- **Bottom card** is a slot for future widgets: `CARDS` in `loop.sh` (now 1, the date card) and `card`/`cards` in `render.awk` (dots show only when `cards > 1`). Add a card as a new `card == N` branch, with its data fetched in `refresh()` and passed as an extra awk input; upstream's prayer card (git history, before `c8dad9b`) is a full example, including a daily cache and timed wakeups.
- **FBInk v1.25** in `bin/` has no image support: icons are drawn with the Kindle's `eips -g`. It can't right-align or measure text, so widths are estimated in awk (`rtext()`, the big-temperature width heuristic, which also shrinks 3-digit °F). Overflowing text wraps onto a second line rather than clipping.
- **`tools/preview.py`** mirrors the protocol as SVG with Helvetica (the device uses Amazon Ember), so spacing on the device differs slightly.
- **`probe.sh`** (Dashboard Probe) records the device's tools, framebuffer, fonts, input devices, http/https fetches and 12 s of raw touch events into `probe.txt` / `touch-*.bin`. The KT3's results are archived outside the repo in `~/projects/kindle/probe-2026-11-24/`.

## SSH (`extensions/ssh/`)

- **Use:** the user opens **SSH On (Wi-Fi)**; it shows its progress on the launcher screen, ends with `SSH on: root@<ip>`, then returns to Home. Connect with `ssh -i ~/.ssh/kindle_ed25519 -o IdentitiesOnly=yes root@<ip>` (DHCP, was `192.168.1.154`; the Wi-Fi MAC is `50:F5:DA:B2:FF:21`, so a ping sweep plus `arp -an` finds it). **SSH Off (Wi-Fi)** stops it and copies the log to `extensions/ssh/ssh.log`. SSH On keeps the Kindle awake, and the dashboard turns Wi-Fi off and suspends, so use SSH with the dashboard stopped. Copy files with `scp -O` (no sftp-server).
- **`ssh_on.sh`:** makes Wi-Fi really connect (Settings can say Connected while wifid is idle: it waits for `lipc-get-prop com.lab126.wifid cmState` = `CONNECTED`, not just an address on wlan0, which can keep a stale one; it asks `ensureConnection wifi`, then cycles `wirelessEnable`), turns Wi-Fi power saving off (`iwconfig wlan0 power off`: with it on, incoming connections were lost), sets `preventScreenSaver 1`, and starts dropbear on port 22 (keys only, passwords compiled out) plus `keepalive.sh`, both detached with `setsid`/`nohup` so the launcher never waits on them.
- **`keepalive.sh`:** every 5 s pings the router; if wifid isn't `CONNECTED` twice running it cycles Wi-Fi; logs state changes; exits with dropbear.
- **Paths:** binary, host keys and log in `/var/local/ssh` (ext3, persistent). `authorized_keys` is copied on each start to `/var/dropbear` (tmpfs, root 700), because dropbear refuses keys under group/other-writable dirs and `/var/local` is `framework:javauser 2775` (root's home `/tmp/root` is under world-writable `/tmp`). The session PATH starts with `/var/local/ssh` (holds the `scp` link; `/var/local/kmc` is `chattr +i`).
- **`dropbearmulti`:** static musl build of dropbear 2026.94 (`tools/dropbear/`: `build.sh`, `localoptions.h`, `BUILD.md`, `e2e-test.sh`).
- **Abandoned:** USB networking (`useUsbForNetwork`, usb0 at 192.168.15.244): the mode switch only takes effect on the next plug-in, and usb0 received but never transmitted. Jobman (the stack's SSH tool) needs firmware 5.16.3+.

## Constraints that have bitten before

- The device awk is **busybox awk**. Never join a variable and a parenthesised expression as `name (expr)`: busybox parses it as a call to function `name` and aborts the render mid-screen. Start with the paren or use a temp variable. Mac awk accepts both, so `check.sh` won't catch this.
- awk counts the UTF-8 `°` as 2 bytes; width estimates count digits/`-` with `gsub` and add the degree sign once.
- The Kindle's clock is UTC; the local date comes from line 5 of `weather.csv` (`cut -c1-10`).
- Open-Meteo is fetched over https (verified on the KT3: curl 7.86 with OpenSSL 1.0.2q). Never add `curl -k`.
- `eips` text cells are 16×24 px on this firmware: rows 0-32, 37 columns. Longer or lower text (upstream's `eips 0 38`) floods the screen with `pixel_in_range` errors.
- **Scriptlet launcher:** it shows a script's output on a screen of its own, which stays (blank if there is no output) until something else takes the screen. Dashboard scriptlets send output to /dev/null (the dashboard then draws); SSH scripts print progress and end by starting Home (`lipc-set-prop com.lab126.appmgrd start app://com.lab126.booklet.home`). If the user is stuck on a blank launcher screen, holding power ~40 s restarts the Kindle.
- **USB drive mode:** while the Kindle is a USB drive, the Kindle itself can't read `/mnt/us`, and vfat writes still in its cache are lost when the Mac takes the drive, so scripts `sync` after writing anything the Mac should read, and keep state in `/var/local`.
- The dashboard loop writes no log file (`start.sh` sends output to `/dev/null`); redirect it to a file there to debug on the device, or watch it over SSH.
- The kernel has no `ip_tables` module: no firewall.
- **Mac side:** if every LAN host but the router fails with "No route to host" while ARP resolves, the app hosting the Claude session lacks macOS **Local Network** permission (System Settings → Privacy & Security → Local Network; enabled for VS Code). Testing from Terminal.app tells it apart from a network problem. The Mac also runs Aikido Endpoint Protection.
- Git: `origin` is the fork `gsingers/re-kindle`, `upstream` is the original `abdenourgnx/re-kindle`.
