#!/usr/bin/env bash
#
# gen-signing.sh — turn the signing values in the gitignored `.env` into `Local.xcconfig`.
#
# Signing is manual and its two values are nobody's to publish, so they live in `.env` beside the
# service constants and this script writes the xcconfig that `ATReader.xcconfig` includes. Both files
# are gitignored. Missing values are not an error: a simulator build needs neither.
#
# It has to run before xcodebuild rather than as a build phase, because a project-level xcconfig is
# read when build settings are evaluated, which is before any phase of the build runs.
#
# Usage:
#   Scripts/gen-signing.sh          # regenerate Local.xcconfig from .env
#
# Run automatically by Scripts/app.sh; safe to run by hand at any time.
# Copyright © 2026 Alexander Babaev. MIT licence — see LICENSE.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO/.env"
OUT="$REPO/Local.xcconfig"

team=""
profile=""

if [ -f "$ENV_FILE" ]; then
  # Read as data, not as shell: a profile name carries spaces and parentheses.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      \#* | "") continue ;;
    esac
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      AT_DEVELOPMENT_TEAM) team="$value" ;;
      AT_PROVISIONING_PROFILE_DEV) profile="$value" ;;
    esac
  done <"$ENV_FILE"
fi

generated=$(
  cat <<EOF
// GENERATED FILE — DO NOT EDIT. Produced by Scripts/gen-signing.sh from .env.
//
// Gitignored, like the .env it comes from. Edit the values there.

DEVELOPMENT_TEAM = $team
AT_PROVISIONING_PROFILE_DEV = $profile
EOF
)

# Only rewrite when the contents actually change, so builds are not invalidated needlessly.
if [ ! -f "$OUT" ] || [ "$(cat "$OUT")" != "$generated" ]; then
  if ! printf '%s\n' "$generated" >"$OUT"; then
    echo "gen-signing: failed to write $OUT" >&2
    exit 1
  fi
fi

if [ -n "$team" ] && [ -n "$profile" ]; then
  echo "gen-signing ✅ configured"
else
  echo "gen-signing ⚠️  unconfigured (simulator only)"
fi
