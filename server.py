#!/usr/bin/env python3
"""Kindle dashboard: serves a calendar + weather page for the Kindle's browser.

Run: python3 server.py    Self-check: python3 server.py --check
The page is plain HTML and tables because the Kindle's old browser can't be
relied on for JavaScript, flexbox or modern HTTPS, so the Mac fetches everything.
"""
import calendar
import json
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from http.server import BaseHTTPRequestHandler, HTTPServer
from zoneinfo import ZoneInfo

# Tuning knobs
PLACE = "Vienna"
LAT, LON = 48.2049, 16.3662
TIMEZONE = "Europe/Vienna"
PORT = 8080
REFRESH_S = 600  # how often the Kindle reloads the page
CACHE_S = 600  # how long a forecast is reused before asking Open-Meteo again
PAGE_WIDTH_PX = 590  # Kindle screen is 600 wide; lower this if it scrolls sideways
FONT_PX = 20  # every text size scales from this

TZ = ZoneInfo(TIMEZONE)
FORECAST_URL = "https://api.open-meteo.com/v1/forecast?" + urllib.parse.urlencode({
    "latitude": LAT,
    "longitude": LON,
    "timezone": TIMEZONE,
    "forecast_days": 3,
    "current": "temperature_2m,weather_code,relative_humidity_2m",
    "hourly": "temperature_2m,weather_code,precipitation_probability",
    "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
})

# WMO weather codes, as Open-Meteo reports them
CONDITIONS = {
    0: "Clear", 1: "Mostly clear", 2: "Partly cloudy", 3: "Cloudy",
    45: "Fog", 48: "Fog",
    51: "Drizzle", 53: "Drizzle", 55: "Drizzle", 56: "Icy drizzle", 57: "Icy drizzle",
    61: "Light rain", 63: "Rain", 65: "Heavy rain", 66: "Icy rain", 67: "Icy rain",
    71: "Light snow", 73: "Snow", 75: "Heavy snow", 77: "Snow",
    80: "Showers", 81: "Showers", 82: "Heavy showers",
    85: "Snow showers", 86: "Snow showers",
    95: "Storm", 96: "Storm", 99: "Storm",
}

CSS = f"""
body {{ margin: 0; padding: 4px; background: #fff; color: #000;
  font-family: Helvetica, Arial, sans-serif; font-size: {FONT_PX}px; }}
table {{ border-collapse: collapse; width: 100%; table-layout: fixed; }}
td, th {{ padding: 0; text-align: center; font-weight: normal; }}
.page {{ width: {PAGE_WIDTH_PX}px; }}
.left {{ text-align: left; }}
.right {{ text-align: right; }}
.date {{ font-size: 1.5em; font-weight: bold; }}
.small {{ font-size: 0.8em; }}
.temp {{ font-size: 3.6em; font-weight: bold; line-height: 1; }}
.rule {{ border-top: 2px solid #000; margin: 6px 0; }}
.box {{ border: 1px solid #000; margin: 8px 0; }}
.box td {{ padding: 4px 1px; border-left: 1px solid #000; vertical-align: top; }}
.box td.first {{ border-left: 0; }}
.month {{ font-size: 1.1em; font-weight: bold; margin: 8px 0 2px; }}
.cal th {{ font-size: 0.8em; padding-bottom: 2px; }}
.cal td {{ height: 1.7em; }}
.cal td.today {{ background: #000; color: #fff; font-weight: bold; }}
"""


def fmt_pct(value):
    return "-" if value is None else f"{value}%"


def fmt_temp(value):
    return "-" if value is None else f"{round(value)}&deg;"


def condition(code):
    return CONDITIONS.get(code, "-")


def hourly_slots(hourly, now, count=7, step=3):
    """The next `count` forecast hours, `step` hours apart, starting after `now`."""
    stamp = now.strftime("%Y-%m-%dT%H:%M")
    start = next((i for i, t in enumerate(hourly["time"]) if t > stamp), len(hourly["time"]))
    return list(range(start, len(hourly["time"]), step))[:count]


def render_calendar(now):
    weeks = calendar.Calendar(firstweekday=0).monthdayscalendar(now.year, now.month)
    rows = ""
    for week in weeks:
        cells = ""
        for day in week:
            mark = ' class="today"' if day == now.day else ""
            cells += f"<td{mark}>{day or ''}</td>"
        rows += f"<tr>{cells}</tr>"
    head = "".join(f"<th>{d}</th>" for d in ("Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"))
    return (f'<div class="month">{now:%B %Y}</div>'
            f'<table class="cal"><tr>{head}</tr>{rows}</table>')


def render_weather(weather, now):
    if weather is None:
        return f"<p><b>Weather unavailable</b><br>Couldn't reach Open-Meteo for {PLACE}.</p>"

    current, hourly, daily = weather["current"], weather["hourly"], weather["daily"]
    today, tomorrow = now.strftime("%Y-%m-%d"), (now + timedelta(days=1)).strftime("%Y-%m-%d")
    t0, t1 = daily["time"].index(today), daily["time"].index(tomorrow)

    cells = ""
    for n, i in enumerate(hourly_slots(hourly, now)):
        cls = ' class="first"' if n == 0 else ""
        cells += (f"<td{cls}>{hourly['time'][i][11:13]}:00<br>"
                  f'<span class="small">{condition(hourly["weather_code"][i])}</span><br>'
                  f"<b>{fmt_temp(hourly['temperature_2m'][i])}</b><br>"
                  f'<span class="small">{fmt_pct(hourly["precipitation_probability"][i])}</span></td>')

    return f"""
<table><tr>
  <td class="left" style="width:42%">
    <div class="small">{PLACE}</div>
    <div class="temp">{fmt_temp(current['temperature_2m'])}</div>
    <div>{condition(current['weather_code'])}</div>
  </td>
  <td class="left">
    <div><b>Today {fmt_temp(daily['temperature_2m_max'][t0])} / {fmt_temp(daily['temperature_2m_min'][t0])}</b></div>
    <div class="small">{condition(daily['weather_code'][t0])}</div>
    <div class="small">Rain {fmt_pct(daily['precipitation_probability_max'][t0])},
      humidity {fmt_pct(current['relative_humidity_2m'])}</div>
    <div style="margin-top:6px"><b>Tomorrow {fmt_temp(daily['temperature_2m_max'][t1])} / {fmt_temp(daily['temperature_2m_min'][t1])}</b></div>
    <div class="small">{condition(daily['weather_code'][t1])},
      rain {fmt_pct(daily['precipitation_probability_max'][t1])}</div>
  </td>
</tr></table>
<table class="box"><tr>{cells}</tr></table>"""


def render_page(weather, now, weather_age_s=0):
    # A stale forecast is only worth showing if it says it's stale.
    stale = ""
    if weather is not None and weather_age_s > 2 * CACHE_S:
        stale = f'<div class="small"><b>Offline: weather is {weather_age_s // 60} min old</b></div>'
    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<meta http-equiv="refresh" content="{REFRESH_S}">
<meta name="viewport" content="width=device-width">
<title>Dashboard</title><style>{CSS}</style></head>
<body><div class="page">
<table><tr>
  <td class="left date" style="width:70%">{now:%A, %-d %B}</td>
  <td class="right small">Updated {now:%H:%M}</td>
</tr></table>
<div class="rule"></div>
{render_weather(weather, now)}{stale}
{render_calendar(now)}
</div></body></html>"""


_cache = {"weather": None, "fetched": 0.0}


def get_weather():
    """Returns (forecast or None, age in seconds). Falls back to the last good forecast."""
    if time.time() - _cache["fetched"] > CACHE_S:
        try:
            with urllib.request.urlopen(FORECAST_URL, timeout=10) as response:
                _cache.update(weather=json.load(response), fetched=time.time())
        except (OSError, ValueError) as error:
            print(f"weather fetch failed: {error}", file=sys.stderr)
    return _cache["weather"], int(time.time() - _cache["fetched"])


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/":
            self.send_error(404)
            return
        now = datetime.now(TZ)
        weather, age = get_weather()
        try:
            body = render_page(weather, now, age).encode()
        except (KeyError, ValueError, IndexError) as error:
            # Unexpected API shape, or a forecast too old to cover today: keep the calendar up.
            print(f"weather render failed: {error}", file=sys.stderr)
            body = render_page(None, now).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


def check():
    now = datetime(2026, 11, 4, 20, 52, tzinfo=TZ)  # November 2026 starts on a Sunday
    hours = [(now.replace(hour=0, minute=0) + timedelta(hours=h)).strftime("%Y-%m-%dT%H:00")
             for h in range(72)]
    weather = {
        "current": {"temperature_2m": 7.6, "weather_code": 61, "relative_humidity_2m": 80},
        "hourly": {"time": hours, "temperature_2m": [-0.4] * 72, "weather_code": [999] * 72,
                   "precipitation_probability": [None] * 72},
        "daily": {"time": ["2026-11-04", "2026-11-05", "2026-11-06"],
                  "weather_code": [3, 0, 0], "temperature_2m_max": [9.0, 11.0, 12.0],
                  "temperature_2m_min": [2.0, 3.0, 4.0],
                  "precipitation_probability_max": [40, 0, 0]},
    }

    slots = hourly_slots(weather["hourly"], now)
    assert [hours[i][11:13] for i in slots] == ["21", "00", "03", "06", "09", "12", "15"], slots
    assert hourly_slots(weather["hourly"], now + timedelta(days=9)) == []

    grid = render_calendar(now)
    assert grid.count("<td") == 42, "November 2026 spans six Monday-first weeks"
    assert '<td class="today">4</td>' in grid and grid.count("today") == 1
    assert "<td>30</td>" in grid

    page = render_page(weather, now)
    assert "Wednesday, 4 November" in page and "8&deg;" in page and "Light rain" in page
    assert "Offline" not in page
    assert "Offline: weather is 30 min old" in render_page(weather, now, 1800)
    assert "Weather unavailable" in render_page(None, now)
    print("ok")


if __name__ == "__main__":
    if "--check" in sys.argv:
        check()
    else:
        print(f"Serving on port {PORT}")
        HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
