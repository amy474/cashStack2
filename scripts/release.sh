#!/bin/zsh
# Build CashStack for TestFlight and upload it, in one go.
#
#   scripts/release.sh staging      # CashStack Staging, against cashstack-api-staging
#   scripts/release.sh production   # CashStack, against cashstack-api — from main only
#
#   --dry-run       print what would happen, change nothing
#   --no-upload     archive only (it still shows up in Xcode's Organizer)
#   --skip-tests    don't run the unit tests first
#
# The build number is the UTC time, yymmddHHMM — 2610191630 for 16:30 on
# 19 October 2026 — so every upload is higher than the last without anything
# to commit, and the server's MIN_APP_BUILD can be compared against it.
#
# Signing uses the Apple account signed in to Xcode. To upload without one
# (on a CI machine, say) set ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID to an
# App Store Connect API key.

set -euo pipefail

cd "${0:A:h}/.."

target=""
dry_run=false
upload=true
tests=true
for arg in "$@"; do
  case $arg in
    staging|production) target=$arg ;;
    --dry-run) dry_run=true ;;
    --no-upload) upload=false ;;
    --skip-tests) tests=false ;;
    *) print -u2 "Unknown argument: $arg"; exit 64 ;;
  esac
done
if [[ -z $target ]]; then
  print -u2 "Usage: scripts/release.sh staging|production [--dry-run] [--no-upload] [--skip-tests]"
  exit 64
fi

if [[ $target == production ]]; then
  configuration=Release
  scheme=CashStack
else
  configuration=Staging
  scheme="CashStack Staging"
fi

team=URYQTTYR57
build=${CASHSTACK_BUILD:-$(date -u +%y%m%d%H%M)}
marketing=$(xcodebuild -project CashStack.xcodeproj -target CashStack -configuration $configuration -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/^ *MARKETING_VERSION = / { print $2; exit }')
tag="ios/$target/$marketing-$build"
archive="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/CashStack $target $marketing ($build).xcarchive"

run() {
  print -- "+ ${(q-)@}"
  $dry_run || "$@"
}

# What's shipped should be what's committed, and production ships from main.
if [[ -n $(git status --porcelain) ]]; then
  print -u2 "There are uncommitted changes. Commit or set them aside first."
  $dry_run || exit 1
fi
branch=$(git rev-parse --abbrev-ref HEAD)
if [[ $target == production && $branch != main ]]; then
  print -u2 "Production builds come from main; this is $branch."
  $dry_run || exit 1
fi

print "CashStack $marketing ($build) — $target, $configuration build of $(git rev-parse --short HEAD) on $branch"

if $tests; then
  run xcodebuild test -project CashStack.xcodeproj -scheme CashStack \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
    -only-testing:CashStackTests -quiet
fi

auth=()
if [[ -n ${ASC_KEY_PATH:-} ]]; then
  auth=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

# Archived where Xcode's Organizer looks, so the dSYMs for symbolicating
# crash reports from this build are kept with it.
run xcodebuild archive -project CashStack.xcodeproj -scheme "$scheme" -configuration $configuration \
  -destination 'generic/platform=iOS' -archivePath "$archive" \
  CURRENT_PROJECT_VERSION=$build -allowProvisioningUpdates $auth -quiet

if $upload; then
  export_options=$(mktemp -d)/ExportOptions.plist
  cat > $export_options <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
  run xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist $export_options \
    -exportPath "$(dirname $export_options)" -allowProvisioningUpdates $auth
fi

run git tag -a "$tag" -m "CashStack $marketing ($build), $target"
if $upload; then
  run git push origin "$tag"
fi

print
print "Done: CashStack $marketing ($build) for $target."
$upload && print "It appears in TestFlight once App Store Connect has processed it, usually within half an hour."
app=$([[ $target == staging ]] && print cashstack-api-staging || print cashstack-api)
print "To turn away older builds:  fly secrets set MIN_APP_BUILD=$build -a $app"
