#!/bin/sh

set -eu

if [ "${CONFIGURATION:-}" != "Release" ]; then
  exit 0
fi

fail() {
  echo "error: $1" >&2
  exit 1
}

case "${SUPABASE_URL:-}" in
  https://*.supabase.co|https://*.supabase.net) ;;
  "") fail "Release requires SUPABASE_URL in Configuration/Secrets.xcconfig." ;;
  *) fail "SUPABASE_URL must be a hosted HTTPS Supabase project URL for Release." ;;
esac

case "${SUPABASE_PUBLISHABLE_KEY:-}" in
  sb_publishable_*) ;;
  "") fail "Release requires SUPABASE_PUBLISHABLE_KEY in Configuration/Secrets.xcconfig." ;;
  *) fail "SUPABASE_PUBLISHABLE_KEY must be a Supabase publishable key for Release." ;;
esac

if [ "${PRODUCT_BUNDLE_IDENTIFIER:-}" != "app.manna-circle.ios" ]; then
  fail "Release app bundle identifier must be app.manna-circle.ios."
fi

if [ "${APNS_ENVIRONMENT:-}" != "production" ]; then
  fail "Release requires APNS_ENVIRONMENT=production."
fi

echo "Hosted Release configuration validated for ${PRODUCT_BUNDLE_IDENTIFIER}."
