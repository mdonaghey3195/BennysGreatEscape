#!/bin/zsh
# Plays whole courses for real — physics, collisions, a bot at the controls —
# one simulator at a time.
#
#   Tools/hitbox-lab/playthroughs.sh SEEDS [SCORE] [SIM]
#   Tools/hitbox-lab/playthroughs.sh 1,2,3 50 "iPhone 17 Pro"
#
# This is the other half of `courses.sh`. That one generates thousands of
# courses and checks what they ask of the player; this one actually plays them,
# at sixty frames a second, so it costs about a minute and a half per course
# and is run on a sample. Several simulators can run it at once, but a busy Mac
# drops frames and the lab counts frames, so keep an eye on the pacing line.
set -e
HERE=${0:a:h}
ROOT=${HERE:h:h}
SEEDS=${1:?seeds, comma separated}
SCORE=${2:-50}
SIM=${3:-"iPhone 17 Pro Max"}
LABEL=$(echo "$SIM" | tr -cd '[:alnum:]')
RUN_DIR=${RUN_DIR:-"$ROOT/build/hitbox-lab/play-$(date +%Y%m%d-%H%M%S)"}
DERIVED="$ROOT/build/hitbox-lab/DerivedData"
mkdir -p "$RUN_DIR/$LABEL"
# The cases play at the lead distances in plan.json, the same as validate.sh —
# without it the bot has no windows to aim at.
cp "$HERE/plan.json" "$RUN_DIR/plan.json"

APP="$DERIVED/Build/Products/Debug-iphonesimulator/BennysGreatEscape.app"
# Always, even though the app is usually already there: the build is
# incremental and cheap, and a run against a stale binary is worse than
# useless — it reports on code that is no longer the code.
#
# SKIP_BUILD=1 for the one case where that is wrong: several of these running
# at once, which is how a batch of seeds is spread over several simulators.
# They share a DerivedData folder, and simultaneous builds into it collide —
# so the caller builds once and sets this.
if [[ -n "$SKIP_BUILD" ]]; then
    [[ -d "$APP" ]] || { echo "SKIP_BUILD set but no app at $APP"; exit 1; }
else
echo "==> Building (Debug)"
xcodebuild -project "$ROOT/BennysGreatEscape.xcodeproj" -scheme BennysGreatEscape \
    -configuration Debug -destination "platform=iOS Simulator,name=$SIM" \
    -derivedDataPath "$DERIVED" build > "$RUN_DIR/build.log" 2>&1 \
    || { tail -30 "$RUN_DIR/build.log"; exit 1; }
fi
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")

UDID=$(xcrun simctl list devices available | grep -F "$SIM (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[[ -n "$UDID" ]] || { echo "no simulator named $SIM"; exit 1; }
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null
xcrun simctl install "$UDID" "$APP"

xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" \
    -HitboxLab cases -LabOnly C- -LabSeeds "$SEEDS" -LabScore "$SCORE" \
    -LabBuild "$LABEL" -LabOut "$RUN_DIR" > /dev/null

START=$SECONDS
while [[ ! -f "$RUN_DIR/$LABEL/DONE" ]]; do
    if (( SECONDS - START > 7200 )); then echo "$SIM: timed out"; exit 1; fi
    sleep 10
done
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
echo "$SIM: finished $(grep -c . "$RUN_DIR/$LABEL/results.jsonl") courses in $((SECONDS - START))s"
