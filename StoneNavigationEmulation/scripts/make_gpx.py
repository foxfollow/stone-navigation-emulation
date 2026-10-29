#!/usr/bin/env python3
"""GPX-трек уздовж записаного маршруту: точка щосекунди, 50 км/год.

Запуск: python3 scripts/make_gpx.py NavigationCore/Tests/NavigationCoreTests/Fixtures
"""
import json
import math
import sys
from datetime import datetime, timedelta, timezone

SPEED = 50 / 3.6          # м/с
INTERVAL = 1.0            # с
START = datetime(2026, 10, 24, 9, 0, 0, tzinfo=timezone.utc)
R = 6371008.8


def distance(a, b):
    la1, la2 = math.radians(a[0]), math.radians(b[0])
    dla, dlo = la2 - la1, math.radians(b[1] - a[1])
    h = math.sin(dla / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin(dlo / 2) ** 2
    return 2 * R * math.asin(min(1, math.sqrt(h)))


def bearing(a, b):
    la1, la2 = math.radians(a[0]), math.radians(b[0])
    dlo = math.radians(b[1] - a[1])
    y = math.sin(dlo) * math.cos(la2)
    x = math.cos(la1) * math.sin(la2) - math.sin(la1) * math.cos(la2) * math.cos(dlo)
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def main(folder):
    route = json.load(open(f"{folder}/test_route.json"))
    pts = [(c["latitude"], c["longitude"]) for c in route["coordinates"]]
    cum = [0.0]
    for a, b in zip(pts, pts[1:]):
        cum.append(cum[-1] + distance(a, b))
    total = cum[-1]
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<gpx version="1.1" creator="StoneNavigationEmulation" xmlns="http://www.topografix.com/GPX/1/1">',
        "  <trk>",
        f"    <name>{route['name']} (50 км/год)</name>",
        "    <trkseg>",
    ]
    along, i, n = 0.0, 0, 0
    while True:
        while i < len(pts) - 2 and cum[i + 1] < along:
            i += 1
        seg = cum[i + 1] - cum[i]
        t = 0 if seg == 0 else (along - cum[i]) / seg
        lat = pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t
        lon = pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t
        stamp = (START + timedelta(seconds=n * INTERVAL)).strftime("%Y-%m-%dT%H:%M:%SZ")
        lines += [
            f'      <trkpt lat="{lat:.7f}" lon="{lon:.7f}">',
            f"        <time>{stamp}</time>",
            "        <extensions>",
            f"          <speed>{SPEED:.2f}</speed>",
            f"          <course>{bearing(pts[i], pts[i + 1]):.1f}</course>",
            "        </extensions>",
            "      </trkpt>",
        ]
        if total - along < 0.01:
            break
        along = min(total, along + SPEED * INTERVAL)
        n += 1
    lines += ["    </trkseg>", "  </trk>", "</gpx>", ""]
    open(f"{folder}/test_track.gpx", "w").write("\n".join(lines))
    print(f"test_track.gpx: {n + 1} точок, {total:.0f} м")


if __name__ == "__main__":
    main(sys.argv[1])
