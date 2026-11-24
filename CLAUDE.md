# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A standalone e-ink weather dashboard for a jailbroken Kindle 7th gen (KT2, firmware 5.12.2.2, 600×800, busybox userland, clock in UTC). It runs on the Kindle as a KUAL extension (`extensions/dashboard/`), fetches Open-Meteo weather and aladhan.com prayer times over Wi-Fi, and draws with FBInk. `server.py` is an older, separate approach (serves an HTML page for the Kindle's browser) and is not part of the extension.

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

Changes only take effect after the user ejects and runs Stop then Start in KUAL. `render.awk` is re-read on every draw but `loop.sh` is not, so a new `render.awk` under an old running loop can render with mismatched tap zones and colours.

## Architecture

- **`loop.sh`** is the only process that draws. It owns the schedule: Wi-Fi on → fetch → Wi-Fi off; render; suspend to RAM with an RTC wake alarm (`echo mem > /sys/power/state`). Knobs at the top (`INTERVAL`, `NIGHT`, `IDLE`, tap zones, `GREY`, `PRAYER_METHOD`). Battery savers: hourly refresh, no refreshes in the `NIGHT` hours, a redraw is skipped when the rendered commands equal `screen.key` (ignoring the "Updated" line), and Wi-Fi-free wakes at prayer times while the prayer card shows. Local time = device UTC + `utc_offset_seconds` from line 2 of `weather.csv`.
- **Touch** is a background `watch_touch` reading raw evdev from `/dev/input/event1` (`dd | od -t d2`; coordinates are screen pixels). It never draws: it writes a request (`today`, `10d`, `card`) to `$DIR/tap`, which the main loop picks up with `mv tap tap.read`. Tapping the place name (top left) runs `stop.sh` = Home. The Kindle UI (`cvm`) is SIGSTOPped while the dashboard runs; `stop.sh` resumes it and undoes Wi-Fi/alarm/screensaver changes.
- **`render.awk`** turns `weather.csv` (Open-Meteo CSV: meta, current, hourly, daily sections separated by blank lines, columns positional) plus `prayer.txt` (second input, detected with `NR != FNR`) into a line protocol, `T|style|px|left|right|top|flags|text`, `R|x|y|w|h|color`, `I|name|x|y`, which `loop.sh`'s `draw_fbink` executes. Text flags: `c` centred, `i` inverted, `g` secondary (`-C $GREY`). New API fields must be appended to the end of the URL's field lists so old CSVs keep their column positions.
- **FBInk v1.25** in `bin/` has no image support: icons are drawn with the Kindle's `eips -g`. It can't right-align or measure text, so widths are estimated in awk (`rtext()`, the big-temperature width heuristic). Overflowing text wraps onto a second line rather than clipping.
- **`tools/preview.py`** mirrors the protocol as SVG with Helvetica (the device uses Amazon Ember), so spacing on the device differs slightly.

## Constraints that have bitten before

- The device awk is **busybox awk**. Never join a variable and a parenthesised expression as `name (expr)`: busybox parses it as a call to function `name` and aborts the render mid-screen. Start with the paren or use a temp variable. Mac awk accepts both, so `check.sh` won't catch this.
- awk counts the UTF-8 `°` as 2 bytes; width estimates count digits/`-` with `gsub` and add the degree sign once.
- The Kindle's clock is UTC; the local date comes from line 5 of `weather.csv` (`cut -c1-10`).
- Prayer times use verified https only (`curl -f`); don't add `-k`. Open-Meteo is fetched over plain http on purpose.
- The loop writes no log file (`start.sh` sends output to `/dev/null`); redirect it to a file there to debug on the device.
- Git: branch `main`; `origin` is the fork `gsingers/re-kindle`, `upstream` is the original `abdenourgnx/re-kindle`.
