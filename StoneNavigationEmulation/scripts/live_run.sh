#!/bin/zsh
# Живий прогін без фейків: справжній CoreLocation у симуляторі, рух через `simctl location`,
# потім `simctl location clear` (GPS зник). Показує журнал категорії Mode.
#
#   scripts/live_run.sh [<UDID симулятора, за замовчуванням booted>] [<шлях до .app>]
#
# Застосунок стартує з `-loadRoute test`: записаний маршрут Майдан → Дарницька площа,
# решта портів справжні (CLLocationManager, CoreMotion, AVSpeech, MapKit).
set -euo pipefail

cd "$(dirname "$0")/.."
DEVICE=${1:-booted}
APP=${2:-}
ROUTE=NavigationCore/Tests/NavigationCoreTests/Fixtures/test_route.json
SPEED=14            # м/с, ≈50 км/год
DRIVE_SECONDS=30    # скільки їдемо з GPS
LOST_SECONDS=30     # скільки спостерігаємо без GPS
LOG=${LIVE_LOG:-/tmp/stone-live-run.log}

if [[ -z "$APP" ]]; then
  APP=$(find ~/Library/Developer/Xcode/DerivedData -path "*Debug-iphonesimulator/StoneNavigationEmulation.app" -maxdepth 6 | head -1)
fi
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")

xcrun simctl boot "$DEVICE" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE" -b >/dev/null
xcrun simctl terminate "$DEVICE" "$BUNDLE" 2>/dev/null || true
xcrun simctl install "$DEVICE" "$APP"

echo "== Дозвіл на геолокацію «Завжди» без запиту"
xcrun simctl privacy "$DEVICE" grant location-always "$BUNDLE"

# Точки маршруту для перших ~3 км (кожна точка polyline, щоб рух ішов по дорозі).
WAYPOINTS=("${(@f)$(python3 -I - "$ROUTE" <<'EOF'
import json, math, sys
r = json.load(open(sys.argv[1]))
pts = [(c["latitude"], c["longitude"]) for c in r["coordinates"]]
def d(a, b):
    la1, la2 = math.radians(a[0]), math.radians(b[0])
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin(math.radians(b[1] - a[1]) / 2) ** 2
    return 2 * 6371008.8 * math.asin(math.sqrt(h))
total = 0
out = [pts[0]]
for a, b in zip(pts, pts[1:]):
    total += d(a, b)
    out.append(b)
    if total > 3000:
        break
for lat, lon in out:
    print(f"{lat:.6f},{lon:.6f}")
EOF
)}")

echo "== Журнал subsystem=$BUNDLE category=Mode → $LOG"
xcrun simctl spawn "$DEVICE" log stream --level info --style compact \
  --predicate "subsystem == \"$BUNDLE\" AND category == \"Mode\"" > "$LOG" 2>&1 &
LOG_PID=$!
sleep 2

echo "== Рух уздовж маршруту: ${#WAYPOINTS[@]} точок, $SPEED м/с"
xcrun simctl location "$DEVICE" start --speed=$SPEED --interval=1 "${WAYPOINTS[@]}"
xcrun simctl launch "$DEVICE" "$BUNDLE" -loadRoute test -resetState -AppleLanguages "(uk)" -AppleLocale uk_UA
sleep $DRIVE_SECONDS

echo "== GPS зник: simctl location clear"
xcrun simctl location "$DEVICE" clear
sleep $LOST_SECONDS

kill $LOG_PID 2>/dev/null || true
echo "== Журнал категорії Mode"
cat "$LOG"
