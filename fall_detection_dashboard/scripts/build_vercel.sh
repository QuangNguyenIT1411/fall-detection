#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

required=(MQTT_HOST MQTT_PORT MQTT_USERNAME MQTT_PASSWORD MQTT_USE_TLS MQTT_WEBSOCKET_PATH MQTT_DEVICE_CODE SUPABASE_URL SUPABASE_ANON_KEY)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    printf 'Missing required Vercel environment variable: %s\n' "$name" >&2
    exit 1
  fi
done

if [[ "$MQTT_PORT" != "8884" || "$MQTT_USE_TLS" != "true" || "$MQTT_WEBSOCKET_PATH" != "/mqtt" ]]; then
  echo 'Production MQTT must use WSS on port 8884 with path /mqtt.' >&2
  exit 1
fi
if [[ "$MQTT_HOST" == *://* || "$MQTT_HOST" == */* || "$MQTT_HOST" == *:* ]]; then
  echo 'MQTT_HOST must be a hostname without scheme, port, or path.' >&2
  exit 1
fi
if [[ "$SUPABASE_URL" != 'https://nuwcsqdedelgfkjpmrsj.supabase.co' ]]; then
  echo 'SUPABASE_URL does not match the Phase 8 Supabase project.' >&2
  exit 1
fi
if [[ "$SUPABASE_ANON_KEY" != sb_publishable_* ]]; then
  if ! node -e '
    try {
      const parts = process.env.SUPABASE_ANON_KEY.split(".");
      if (parts.length !== 3) process.exit(1);
      const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf8"));
      if (payload.role !== "anon") process.exit(1);
    } catch (_) { process.exit(1); }
  '; then
    echo 'SUPABASE_ANON_KEY must be a publishable key or anon-role JWT.' >&2
    exit 1
  fi
fi

flutter_version='3.47.4'
flutter_sha256='5b45f0ceda99b9bebdc873e7e69f6450aeb4c30f454b505e2e62fc9255a907d3'
flutter_archive_url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${flutter_version}-stable.tar.xz"
sdk_root="${TMPDIR:-/tmp}/fallguard-flutter-${flutter_version}"
flutter_bin="$sdk_root/flutter/bin/flutter"

if [[ ! -x "$flutter_bin" ]]; then
  mkdir -p "$sdk_root"
  archive="$sdk_root/flutter.tar.xz"
  curl --fail --location --retry 3 --silent --show-error "$flutter_archive_url" --output "$archive"
  printf '%s  %s\n' "$flutter_sha256" "$archive" | sha256sum --check --status
  tar --no-same-owner -xf "$archive" -C "$sdk_root"
  rm "$archive"
fi

git config --global --add safe.directory "$sdk_root/flutter"
export PATH="$sdk_root/flutter/bin:$PATH"
export PUB_CACHE="${PUB_CACHE:-${TMPDIR:-/tmp}/fallguard-pub-cache}"
"$flutter_bin" --version
"$flutter_bin" pub get
"$flutter_bin" build web --release \
  --dart-define="PRODUCTION_BUILD=true" \
  --dart-define="MQTT_HOST=$MQTT_HOST" \
  --dart-define="MQTT_PORT=$MQTT_PORT" \
  --dart-define="MQTT_USERNAME=$MQTT_USERNAME" \
  --dart-define="MQTT_PASSWORD=$MQTT_PASSWORD" \
  --dart-define="MQTT_USE_TLS=$MQTT_USE_TLS" \
  --dart-define="MQTT_WEBSOCKET_PATH=$MQTT_WEBSOCKET_PATH" \
  --dart-define="MQTT_DEVICE_CODE=$MQTT_DEVICE_CODE" \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY"
