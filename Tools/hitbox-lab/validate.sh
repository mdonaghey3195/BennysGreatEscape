#!/usr/bin/env bash
#
# Hitbox validation: build the app, run the Hitbox Lab in an iOS simulator, and
# check the results against Tools/hitbox-lab/expected.json.
#
#   Tools/hitbox-lab/validate.sh                    # the full set, ~6 minutes
#   Tools/hitbox-lab/validate.sh --only J-LOG       # just the cases starting J-LOG
#   Tools/hitbox-lab/validate.sh --device "iPhone 16 Pro"
#   Tools/hitbox-lab/validate.sh --record           # accept this run as the new expected results
#
# Exits 0 when every check passes, 1 when a check fails, 2 when the run itself
# could not happen (build failed, no simulator, timed out).
#
# Results, screenshots and the build log land in build/hitbox-lab/<timestamp>/.
# Leave the Mac alone while it runs: the lab times things in frames, and a busy
# machine that drops frames can move a hit by one.

set -euo pipefail

DEVICE="iPhone 17 Pro Max"
ONLY=""
RECORD=0
TIMEOUT=1200

usage() { sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --device)  DEVICE="$2"; shift 2 ;;
        --only)    ONLY="$2"; shift 2 ;;
        --record)  RECORD=1; shift ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 2 ;;
    esac
done

die() { echo "error: $*" >&2; exit 2; }
step() { printf '\n==> %s\n' "$*"; }

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
command -v xcodebuild >/dev/null || die "xcodebuild not found; install Xcode and run xcode-select"
command -v python3 >/dev/null || die "python3 not found"

RUN_DIR="$ROOT/build/hitbox-lab/$(date +%Y%m%d-%H%M%S)"
DERIVED="$ROOT/build/hitbox-lab/DerivedData"
mkdir -p "$RUN_DIR"
# The cases are run at the lead distances in plan.json, so every run tests the
# same points the expected results were recorded at.
cp "$HERE/plan.json" "$RUN_DIR/plan.json"

step "Finding the \"$DEVICE\" simulator"
UDID="$(python3 - "$DEVICE" <<'PY'
import json, subprocess, sys
name = sys.argv[1]
data = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))
found = [(runtime, d) for runtime, devices in data['devices'].items() if 'iOS' in runtime
         for d in devices if d['name'] == name]
if not found:
    sys.exit(1)
# A booted one if there is one, otherwise the newest iOS runtime.
found.sort(key=lambda rd: (rd[1]['state'] == 'Booted', rd[0]))
print(found[-1][1]['udid'])
PY
)" || die "no available simulator named \"$DEVICE\" (see: xcrun simctl list devices available)"
echo "$UDID"

step "Booting it"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null
open -a Simulator --args -CurrentDeviceUDID "$UDID" || true

step "Building (Debug)"
if ! xcodebuild \
        -project "$ROOT/BennysGreatEscape.xcodeproj" \
        -scheme BennysGreatEscape \
        -configuration Debug \
        -destination "id=$UDID" \
        -derivedDataPath "$DERIVED" \
        build > "$RUN_DIR/build.log" 2>&1; then
    tail -40 "$RUN_DIR/build.log"
    die "build failed; full log in $RUN_DIR/build.log"
fi
APP="$DERIVED/Build/Products/Debug-iphonesimulator/BennysGreatEscape.app"
BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
echo "$APP"

step "Installing $BUNDLE"
xcrun simctl install "$UDID" "$APP"

step "Running the Hitbox Lab"
ARGS=(-HitboxLab cases -LabBuild validate -LabOut "$RUN_DIR")
if [[ -n "$ONLY" ]]; then ARGS+=(-LabOnly "$ONLY"); fi
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" "${ARGS[@]}" >/dev/null

OUT="$RUN_DIR/validate"
START=$SECONDS
until [[ -f "$OUT/DONE" ]]; do
    if (( SECONDS - START > TIMEOUT )); then
        xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
        die "timed out after ${TIMEOUT}s; last status: $(cat "$OUT/STATUS.txt" 2>/dev/null || echo none)"
    fi
    STATUS="$(cut -d' ' -f4- "$OUT/STATUS.txt" 2>/dev/null || echo starting)"
    printf '\r  %4ds  %-60s' $((SECONDS - START)) "$STATUS"
    sleep 5
done
printf '\r  %4ds  %-60s\n' $((SECONDS - START)) "done"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true

step "Checking"
CHECK=(python3 "$HERE/check.py" "$OUT")
if (( RECORD )); then
    CHECK+=(--record)
elif [[ -n "$ONLY" ]]; then
    CHECK+=(--partial)
fi
set +e
"${CHECK[@]}"
RESULT=$?
set -e
echo "Results and screenshots: $OUT"
exit $RESULT
