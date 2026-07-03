#!/bin/bash
# Publish NightShift.rbxlx to Roblox via the Open Cloud API.
# Usage: ROBLOX_API_KEY="<key>" ./publish.sh
# Requires the environment's network policy to allow apis.roblox.com.
set -e
UNIVERSE_ID=10440164192
PLACE_ID=129932135691270
RBXLX="$(dirname "$0")/NightShift.rbxlx"

if [ -z "$ROBLOX_API_KEY" ]; then
  echo "ERROR: set ROBLOX_API_KEY env var (never commit the key to the repo)" >&2
  exit 1
fi

# Roblox rejects place files with any bytes after </roblox> ("Invalid
# Content stream"), so strip trailing newlines before uploading.
BODY="$(cat "${RBXLX}")"

printf '%s' "$BODY" | curl -sS -X POST \
  "https://apis.roblox.com/universes/v1/${UNIVERSE_ID}/places/${PLACE_ID}/versions?versionType=Published" \
  -H "x-api-key: ${ROBLOX_API_KEY}" \
  -H "Content-Type: application/xml" \
  -H "Expect:" \
  --data-binary @- \
  -w "\nHTTP %{http_code}\n"
