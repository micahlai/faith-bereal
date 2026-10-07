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

if ! /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.associated-domains' "$entitlements" 2>/dev/null | grep -q 'applinks:manna-circle.micahlai.com'; then
  echo "error: Exported app is missing the manna circle Universal Link domain." >&2
  exit 1
fi

if ! /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups' "$entitlements" 2>/dev/null | grep -q 'group.app.blessingcircle.shared'; then
  echo "error: Exported app is missing the shared App Group." >&2
  exit 1
fi

extension="$app/PlugIns/BlessingCircleLiveActivity.appex"
if [ ! -d "$extension" ]; then
  echo "error: Exported app is missing the Live Activity/widget extension." >&2
  exit 1
fi
if ! codesign --verify --strict "$extension" 2>/dev/null; then
  echo "error: Exported Live Activity/widget extension has an invalid signature." >&2
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

notification_extension="$app/PlugIns/BlessingCircleNotificationService.appex"
if [ ! -d "$notification_extension" ]; then
  echo "error: Exported app is missing the notification service extension." >&2
  exit 1
fi
if ! codesign --verify --strict "$notification_extension" 2>/dev/null; then
  echo "error: Exported notification service extension has an invalid signature." >&2
  exit 1
fi

notification_extension_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$notification_extension/Info.plist")
if [ "$notification_extension_id" != "app.manna-circle.ios.notification-service" ]; then
  echo "error: Exported notification extension identifier is $notification_extension_id." >&2
  exit 1
fi

notification_extension_point=$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "$notification_extension/Info.plist")
if [ "$notification_extension_point" != "com.apple.usernotifications.service" ]; then
  echo "error: Exported notification extension has the wrong extension point." >&2
  exit 1
fi

if [ ! -f "$notification_extension/NotificationLogo.png" ]; then
  echo "error: Exported notification extension is missing NotificationLogo.png." >&2
  exit 1
fi

echo "TestFlight export validation passed for $bundle_id."
