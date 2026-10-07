#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
archive_path=${TESTFLIGHT_ARCHIVE_PATH:-"$project_root/build/manna-circle.xcarchive"}
export_path=${TESTFLIGHT_EXPORT_PATH:-"$project_root/build/TestFlight"}
build_number=${TESTFLIGHT_BUILD_NUMBER:-}
simulator_name=${TESTFLIGHT_SIMULATOR_NAME:-"iPhone 17e"}

case "$build_number" in
  ""|*[!0-9]*)
    echo "error: Set TESTFLIGHT_BUILD_NUMBER to a new positive integer for this upload." >&2
    exit 1
    ;;
  0)
    echo "error: TESTFLIGHT_BUILD_NUMBER must be greater than zero." >&2
    exit 1
    ;;
esac

cd "$project_root"

xcodegen generate
node Scripts/test-live-activity-payload.mjs
node Scripts/test-notification-payload.mjs

SUPABASE_URL='' SUPABASE_PUBLISHABLE_KEY='' xcodebuild \
  -project BlessingCircle.xcodeproj \
  -scheme BlessingCircle \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=$simulator_name" \
  -only-testing:BlessingCircleTests \
  test

xcodebuild \
  -project BlessingCircle.xcodeproj \
  -scheme BlessingCircle \
  -configuration Release \
  -destination "platform=iOS Simulator,name=$simulator_name" \
  ENABLE_TESTABILITY=YES \
  -only-testing:BlessingCircleTests \
  test

SUPABASE_URL='' SUPABASE_PUBLISHABLE_KEY='' xcodebuild \
  -project BlessingCircle.xcodeproj \
  -scheme BlessingCircle \
  -configuration Debug \
  -destination "platform=iOS Simulator,name=$simulator_name" \
  -only-testing:BlessingCircleUITests \
  test

xcodebuild \
  -project BlessingCircle.xcodeproj \
  -scheme BlessingCircle \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$build_number" \
  archive

xcodebuild \
  -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist Configuration/ExportOptions-TestFlight.plist \
  -allowProvisioningUpdates

"$script_dir/validate-testflight-export.sh" "$export_path"

echo "TestFlight candidate exported to $export_path"
