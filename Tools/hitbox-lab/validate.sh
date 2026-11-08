#!/usr/bin/env bash
#
# Hitbox validation: build the app, run the Hitbox Lab in an iOS simulator or on
# a connected iPhone, and check the results against Tools/hitbox-lab/expected.json.
#
#   Tools/hitbox-lab/validate.sh                       # simulator, all cases, ~6 minutes
#   Tools/hitbox-lab/validate.sh --only J-LOG          # just the cases starting J-LOG
#   Tools/hitbox-lab/validate.sh --device "iPhone 16 Pro"
#   Tools/hitbox-lab/validate.sh --on-device           # the first connected iPhone
#   Tools/hitbox-lab/validate.sh --on-device "Matt's iPhone" --fps 120
#   Tools/hitbox-lab/validate.sh --record              # accept this run as the expected results
#
# Exits 0 when every check passes, 1 when a check fails, 2 when the run itself
# could not happen (build failed, no simulator or phone, timed out).
#
# Results, screenshots and the build log land in build/hitbox-lab/<timestamp>/.
# Leave the machine alone while it runs: the lab counts frames, and dropped
# frames can move a hit by one. On a phone: unlocked, Developer Mode on, not in
# Low Power Mode, and plugged in if you can.
#
# --fps 120 asks for ProMotion's 120 Hz (Debug builds only; the game itself runs
# at 60). There is no expected file for it yet, so it checks the invariants only
# unless --expected names one; --record with it writes expected-120hz.json.

set -euo pipefail

SIM_NAME="iPhone 17 Pro Max"
ON_DEVICE=0
DEVICE_NAME=""
FPS=60
ONLY=""
RECORD=0
SHOTS=0
EXPECTED=""
TIMEOUT=1200

usage() { sed -n '3,24p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --device)    SIM_NAME="$2"; shift 2 ;;
        --on-device)
            ON_DEVICE=1
            if [[ $# -gt 1 && "$2" != --* ]]; then DEVICE_NAME="$2"; shift; fi
            shift ;;
        --fps)       FPS="$2"; shift 2 ;;
        --only)      ONLY="$2"; shift 2 ;;
        --record)    RECORD=1; shift ;;
        --expected)  EXPECTED="$2"; shift 2 ;;
        --screenshots) SHOTS=1; shift ;;
        --timeout)   TIMEOUT="$2"; shift 2 ;;
        -h|--help)   usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 2 ;;
    esac
done

die() { echo "error: $*" >&2; exit 2; }
step() { printf '\n==> %s\n' "$*"; }

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
command -v xcodebuild >/dev/null || die "xcodebuild not found; install Xcode and run xcode-select"
command -v python3 >/dev/null || die "python3 not found"

if [[ -z "$EXPECTED" ]]; then
    if [[ "$FPS" == 60 ]]; then EXPECTED="$HERE/expected.json"; else EXPECTED="$HERE/expected-${FPS}hz.json"; fi
fi

RUN_DIR="$ROOT/build/hitbox-lab/$(date +%Y%m%d-%H%M%S)"
DERIVED="$ROOT/build/hitbox-lab/DerivedData"
OUT="$RUN_DIR/validate"
mkdir -p "$OUT"
# The cases run at the lead distances in plan.json, so every run tests the
# same points the expected results were recorded at.
cp "$HERE/plan.json" "$RUN_DIR/plan.json"

LAB_ARGS=(-HitboxLab cases -LabBuild validate -LabFPS "$FPS")
if [[ -n "$ONLY" ]]; then LAB_ARGS+=(-LabOnly "$ONLY"); fi

# --- Where it runs ----------------------------------------------------------

if (( ON_DEVICE )); then
    step "Finding the iPhone"
    xcrun devicectl list devices --json-output "$RUN_DIR/devices.json" >/dev/null 2>&1 \
        || die "devicectl failed; this needs Xcode 15 or later"
    read -r DEVICE HWUDID DEVLABEL < <(python3 - "$RUN_DIR/devices.json" "$DEVICE_NAME" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))['result']['devices']
want = sys.argv[2]
def name(d): return d.get('deviceProperties', {}).get('name', '')
phones = [d for d in devices
          if d.get('hardwareProperties', {}).get('platform') == 'iOS'
          and d.get('hardwareProperties', {}).get('reality', 'physical') == 'physical'
          and (not want or want in (name(d), d.get('identifier'), d.get('hardwareProperties', {}).get('udid')))]
if not phones:
    sys.exit(1)
phones.sort(key=lambda d: d.get('connectionProperties', {}).get('tunnelState') == 'connected', reverse=True)
d = phones[0]
print(d['identifier'], d['hardwareProperties']['udid'], name(d).replace(' ', '_'))
PY
    ) || die "no paired iPhone${DEVICE_NAME:+ named \"$DEVICE_NAME\"} found (check: xcrun devicectl list devices)"
    echo "${DEVLABEL//_/ } ($HWUDID)"
    DESTINATION="id=$HWUDID"
    PRODUCTS="Debug-iphoneos"
else
    step "Finding the \"$SIM_NAME\" simulator"
    UDID="$(python3 - "$SIM_NAME" <<'PY'
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
    )" || die "no available simulator named \"$SIM_NAME\" (see: xcrun simctl list devices available)"
    echo "$UDID"
    step "Booting it"
    xcrun simctl boot "$UDID" 2>/dev/null || true
    xcrun simctl bootstatus "$UDID" -b >/dev/null
    open -a Simulator --args -CurrentDeviceUDID "$UDID" || true
    DESTINATION="id=$UDID"
    PRODUCTS="Debug-iphonesimulator"
fi

# --- Build -----------------------------------------------------------------

step "Building (Debug)"
if ! xcodebuild \
        -project "$ROOT/BennysGreatEscape.xcodeproj" \
        -scheme BennysGreatEscape \
        -configuration Debug \
        -destination "$DESTINATION" \
        -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates \
        build > "$RUN_DIR/build.log" 2>&1; then
    tail -40 "$RUN_DIR/build.log"
    die "build failed; full log in $RUN_DIR/build.log"
fi
APP="$DERIVED/Build/Products/$PRODUCTS/BennysGreatEscape.app"
BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist")"
echo "$APP"

# --- Install and run -------------------------------------------------------

step "Installing $BUNDLE"
if (( ON_DEVICE )); then
    xcrun devicectl device install app --device "$DEVICE" "$APP" > "$RUN_DIR/install.log" 2>&1 \
        || { cat "$RUN_DIR/install.log"; die "install failed (is the phone unlocked and trusting this Mac?)"; }
else
    xcrun simctl install "$UDID" "$APP"
fi

# A file on the phone, read back into the run folder. Fails quietly if the
# file isn't there yet.
fetch() {
    xcrun devicectl device copy from --device "$DEVICE" \
        --domain-type appDataContainer --domain-identifier "$BUNDLE" \
        --source "Documents/HitboxLab/validate/$1" --destination "$OUT/$1" >/dev/null 2>&1
}

step "Running the Hitbox Lab at $FPS fps"
if (( ON_DEVICE )); then
    # The phone can't read plan.json from this Mac, so it travels in the
    # environment instead.
    ENV_JSON="$(python3 -c 'import json,sys; print(json.dumps({"LAB_PLAN": open(sys.argv[1]).read()}))' "$HERE/plan.json")"
    xcrun devicectl device process launch --device "$DEVICE" --terminate-existing \
        --environment-variables "$ENV_JSON" "$BUNDLE" "${LAB_ARGS[@]}" > "$RUN_DIR/launch.log" 2>&1 \
        || { cat "$RUN_DIR/launch.log"; die "launch failed (is the phone unlocked?)"; }
    POLL=15
else
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" "${LAB_ARGS[@]}" -LabOut "$RUN_DIR" >/dev/null
    POLL=5
fi

START=$SECONDS
while :; do
    if (( ON_DEVICE )); then
        fetch STATUS.txt || true
        if fetch DONE; then break; fi
    elif [[ -f "$OUT/DONE" ]]; then
        break
    fi
    if (( SECONDS - START > TIMEOUT )); then
        die "timed out after ${TIMEOUT}s; last status: $(cat "$OUT/STATUS.txt" 2>/dev/null || echo none)"
    fi
    STATUS="$(cut -d' ' -f4- "$OUT/STATUS.txt" 2>/dev/null || echo starting)"
    printf '\r  %4ds  %-60s' $((SECONDS - START)) "$STATUS"
    sleep "$POLL"
done
printf '\r  %4ds  %-60s\n' $((SECONDS - START)) "done"

if (( ON_DEVICE )); then
    step "Fetching the results from the phone"
    fetch results.jsonl || die "could not copy results.jsonl off the phone"
    fetch device.json || true
    if (( SHOTS )) && fetch files.txt; then
        COUNT=0
        while read -r f; do
            [[ -n "$f" ]] && fetch "$f" && COUNT=$((COUNT + 1))
        done < "$OUT/files.txt"
        echo "  $COUNT screenshots"
    else
        echo "  (screenshots left on the phone; add --screenshots to copy them)"
    fi
    xcrun devicectl device process terminate --device "$DEVICE" --bundle-identifier "$BUNDLE" >/dev/null 2>&1 || true
else
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
fi

# --- Check -----------------------------------------------------------------

step "Checking"
CHECK=(python3 "$HERE/check.py" "$OUT" --expected "$EXPECTED")
if (( RECORD )); then
    CHECK+=(--record)
else
    [[ -n "$ONLY" ]] && CHECK+=(--partial)
    if [[ ! -f "$EXPECTED" ]]; then
        echo "  no $(basename "$EXPECTED") yet; checking invariants only (--record to create it)"
        CHECK+=(--invariants-only)
    fi
fi
set +e
"${CHECK[@]}"
RESULT=$?
set -e
echo "Results: $OUT"
exit $RESULT
