#!/bin/sh

set -eu

export_path=${1:-}
if [ -z "$export_path" ] || [ ! -d "$export_path" ]; then
  echo "error: Pass the TestFlight export directory to validate." >&2
  exit 1
fi

ipa=$(find "$export_path" -maxdepth 1 -type f -name '*.ipa' -print -quit)
if [ -z "$ipa" ]; then
  echo "error: No IPA was found in $export_path." >&2
  exit 1
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/manna-testflight.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
unzip -q "$ipa" -d "$work_dir"

app=$(find "$work_dir/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)
if [ -z "$app" ]; then
  echo "error: The IPA does not contain an application bundle." >&2
  exit 1
fi

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")
if [ "$bundle_id" != "app.manna-circle.ios" ]; then
  echo "error: Exported bundle identifier is $bundle_id, expected app.manna-circle.ios." >&2
  exit 1
fi

entitlements="$work_dir/app-entitlements.plist"
codesign -d --entitlements :- "$app" > "$entitlements" 2>/dev/null

apns_environment=$(/usr/libexec/PlistBuddy -c 'Print :aps-environment' "$entitlements" 2>/dev/null || true)
if [ "$apns_environment" != "production" ]; then
  echo "error: Exported app APNs entitlement is not production." >&2
  exit 1
fi

get_task_allow=$(/usr/libexec/PlistBuddy -c 'Print :get-task-allow' "$entitlements" 2>/dev/null || true)
if [ "$get_task_allow" = "true" ] || [ "$get_task_allow" = "YES" ]; then
  echo "error: Exported app still permits debugging (get-task-allow)." >&2
  exit 1
fi

if ! /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.applesignin:0' "$entitlements" 2>/dev/null | grep -qx 'Default'; then
  echo "error: Exported app is missing Sign in with Apple." >&2
  exit 1
fi

if ! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups' "$entitlements" 2>/dev/null | grep -q 'group.app.blessingcircle.shared'; then
  echo "error: Exported app is missing the shared App Group." >&2
  exit 1
fi

extension=$(find "$app/PlugIns" -maxdepth 1 -type d -name '*.appex' -print -quit)
if [ -z "$extension" ]; then
  echo "error: Exported app is missing the Live Activity/widget extension." >&2
  exit 1
fi

extension_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$extension/Info.plist")
if [ "$extension_id" != "app.manna-circle.ios.live-activity" ]; then
  echo "error: Exported extension identifier is $extension_id." >&2
  exit 1
fi

extension_entitlements="$work_dir/extension-entitlements.plist"
codesign -d --entitlements :- "$extension" > "$extension_entitlements" 2>/dev/null
if ! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups' "$extension_entitlements" 2>/dev/null | grep -q 'group.app.blessingcircle.shared'; then
  echo "error: Exported extension is missing the shared App Group." >&2
  exit 1
fi

echo "TestFlight export validation passed for $bundle_id."
