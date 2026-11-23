#!/bin/zsh
# Records the feature demos off the Simulator, then frames each one in an
# iPhone and writes an MP4 and a GIF to docs/demos/.
#
#   scripts/record-demos.sh [simulator-udid] [test ...]
#
# The choreography is CashStackUITests/FeatureDemoRecordings.swift; framing is
# scripts/frame-demos.swift. Needs nothing beyond Xcode.
set -euo pipefail

ROOT=${0:A:h:h}
UDID=${1:-$(xcrun simctl list devices booted | grep -m1 "iPhone 17 Pro (" | grep -oE '[0-9A-F-]{36}')}
shift || true
if (( $# )); then TESTS=("$@")
else TESTS=(test1SwipeToPay test2Organise test3Split test4MoneyJars test5TipJar test6SwitchAccounts); fi
WORK=${DEMO_WORK:-$ROOT/build/demos}
DERIVED=${DEMO_DERIVED:-$WORK/derived}
mkdir -p "$WORK/raw" "$WORK/markers" "$ROOT/docs/demos"

now() { python3 -c 'import time; print(f"{time.time():.3f}")' }

echo "Simulator $UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl ui "$UDID" appearance light
xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiMode active \
    --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

if [[ -z ${SKIP_BUILD:-} ]]; then
    xcodebuild -project "$ROOT/CashStack.xcodeproj" -scheme CashStack -sdk iphonesimulator \
        -destination "id=$UDID" -derivedDataPath "$DERIVED" build-for-testing -quiet
fi
XCTESTRUN=$(ls "$DERIVED"/Build/Products/*.xctestrun | head -1)

for t in $TESTS; do
    echo "Recording $t"
    rm -f "$WORK/markers/$t.txt" "$WORK/markers/$t.rec" "$WORK/raw/$t.mp4"
    log="$WORK/raw/$t.log"
    xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$WORK/raw/$t.mp4" >"$log" 2>&1 &
    recorder=$!
    until grep -q "Recording started" "$log" 2>/dev/null; do sleep 0.05; done
    now > "$WORK/markers/$t.rec"

    TEST_RUNNER_DEMO_MARKERS="$WORK/markers" xcodebuild test-without-building \
        -xctestrun "$XCTESTRUN" -destination "id=$UDID" \
        -only-testing:"CashStackUITests/FeatureDemoRecordings/$t" -quiet || echo "  ($t reported a failure)"

    kill -INT $recorder; wait $recorder || true
done

xcrun simctl status_bar "$UDID" clear
swift "$ROOT/scripts/frame-demos.swift" "$WORK" "$ROOT/docs/demos" $TESTS
