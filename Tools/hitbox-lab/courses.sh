#!/bin/zsh
# Generates whole courses through the game's own spawner and checks every one.
#
#   Tools/hitbox-lab/courses.sh [COUNT] [SCORE] [FIRST_SEED]
#
# Defaults to 1000 courses played to score 60 from seed 1. Results and the
# report go to build/hitbox-lab/courses-<timestamp>/.
#
# This is the spawner's half of the testing. It says what each course asked of
# the player — the timing on every obstacle, the room under every duck piece,
# the ground between one and the next — across far more courses than could ever
# be played in real time. What it cannot say is whether a jump connects, which
# is what validate.sh measures on a handful of staged ones.
set -e
HERE=${0:a:h}
ROOT=${HERE:h:h}
COUNT=${1:-1000}
SCORE=${2:-60}
FIRST=${3:-1}
SIM=${SIM:-"iPhone 17 Pro Max"}
RUN_DIR="$ROOT/build/hitbox-lab/courses-$(date +%Y%m%d-%H%M%S)"
DERIVED="$ROOT/build/hitbox-lab/DerivedData"
mkdir -p "$RUN_DIR/courses"

echo "==> Building (Debug)"
xcodebuild -project "$ROOT/BennysGreatEscape.xcodeproj" -scheme BennysGreatEscape \
    -configuration Debug -destination "platform=iOS Simulator,name=$SIM" \
    -derivedDataPath "$DERIVED" build > "$RUN_DIR/build.log" 2>&1 \
    || { tail -30 "$RUN_DIR/build.log"; echo "build failed; see $RUN_DIR/build.log"; exit 1; }
APP="$DERIVED/Build/Products/Debug-iphonesimulator/BennysGreatEscape.app"
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")

UDID=$(xcrun simctl list devices available | grep -F "$SIM (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[[ -n "$UDID" ]] || { echo "no simulator named $SIM"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null
xcrun simctl install "$UDID" "$APP"

echo "==> Generating $COUNT courses to score $SCORE (seeds $FIRST..$((FIRST + COUNT - 1)))"
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" \
    -HitboxLab courses -LabCourses "$COUNT" -LabScore "$SCORE" -LabFirstSeed "$FIRST" \
    -LabBuild courses -LabOut "$RUN_DIR" > /dev/null

START=$SECONDS
while [[ ! -f "$RUN_DIR/courses/DONE" ]]; do
    if (( SECONDS - START > 3600 )); then echo "timed out"; exit 1; fi
    printf '\r  %4ds  %-60s' $((SECONDS - START)) "$(cut -d' ' -f4- "$RUN_DIR/courses/STATUS.txt" 2>/dev/null || echo starting)"
    sleep 5
done
printf '\r  %4ds  %-60s\n' $((SECONDS - START)) "done"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true

echo "==> Checking"
python3 "$HERE/check_courses.py" "$RUN_DIR/courses/courses.jsonl" | tee "$RUN_DIR/report.txt"
echo "Results: $RUN_DIR"
