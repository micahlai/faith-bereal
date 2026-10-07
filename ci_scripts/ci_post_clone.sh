#!/bin/sh

set -eu

# Xcode Cloud runs this script for every action. Only archive actions produce
# App Store/TestFlight builds, so Debug builds and test actions keep their
# normal local-demo configuration.
if [ "${CI_XCODE_CLOUD:-}" != "TRUE" ] || [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
  exit 0
fi

fail() {
  echo "error: $1" >&2
  exit 1
}

case "${SUPABASE_URL:-}" in
  https://*.supabase.co|https://*.supabase.net) ;;
  "") fail "Set the SUPABASE_URL secret in the Xcode Cloud workflow environment." ;;
  *) fail "SUPABASE_URL must be a hosted HTTPS Supabase project URL." ;;
esac

case "${SUPABASE_PUBLISHABLE_KEY:-}" in
  sb_publishable_*) ;;
  "") fail "Set the SUPABASE_PUBLISHABLE_KEY secret in the Xcode Cloud workflow environment." ;;
  *) fail "SUPABASE_PUBLISHABLE_KEY must be a Supabase publishable key." ;;
esac

repository_path=${CI_PRIMARY_REPOSITORY_PATH:-}
[ -n "$repository_path" ] || fail "Xcode Cloud did not provide CI_PRIMARY_REPOSITORY_PATH."

configuration_path="$repository_path/Configuration"
secrets_path="$configuration_path/Secrets.xcconfig"

umask 077
mkdir -p "$configuration_path"

# xcconfig treats // as a comment, so escape the URL separator without changing
# the runtime value embedded in the app.
{
  printf 'SUPABASE_URL = '
  printf '%s\n' "$SUPABASE_URL" | sed 's#^https://#https:/$()/#'
  printf 'SUPABASE_PUBLISHABLE_KEY = %s\n' "$SUPABASE_PUBLISHABLE_KEY"
} > "$secrets_path"

echo "Prepared hosted Release configuration for the Xcode Cloud archive."
