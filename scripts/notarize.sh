#!/usr/bin/env bash
# Phase 4 notarization. Reuses the suite's established Apple credentials
# (kept out of this repo) — same method as Blip/Stash Makefiles.
# Secrets are sourced, never printed; no `set -x`.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="$(pwd)/Fetch.app"
ZIP="$(pwd)/Fetch-notarize.zip"
SECRETS="${SECRETS:-$HOME/Development/Apps/Blip/.env.apple}"

[ -d "$APP" ] || { echo "ERROR: $APP not found — run make-app.sh first"; exit 1; }
[ -f "$SECRETS" ] || { echo "ERROR: secrets file $SECRETS not found"; exit 1; }

set -a; . "$SECRETS"; set +a
: "${APPLE_ID:?APPLE_ID missing}" "${APPLE_TEAM_ID:?APPLE_TEAM_ID missing}" "${APPLE_PASSWORD:?APPLE_PASSWORD missing}"

echo "→ zipping app"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "→ submitting to Apple notary (this can take several minutes)…"
xcrun notarytool submit "$ZIP" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_PASSWORD" \
    --wait

echo "→ stapling ticket to Fetch.app"
xcrun stapler staple "$APP"
rm -f "$ZIP"

echo "→ verification"
xcrun stapler validate "$APP"
spctl -a -vv "$APP" 2>&1 | head -3
echo "✓ notarized + stapled"
