#!/usr/bin/env bash
#
# gen-secrets.sh — turn the gitignored `.env` into a Swift constant file for the app target.
#
# The two author.today service constants are not committed (see .env.example for what they are and
# where to get them). This script reads them from `.env` and writes them into a generated source file
# that is itself gitignored. Missing values are not an error: the app still builds, browses and
# searches, and says plainly that it cannot open chapters.
#
# Usage:
#   Scripts/gen-secrets.sh          # regenerate from .env
#
# Run automatically as a build phase; safe to run by hand at any time.
# Copyright © 2026 Alexander Babaev. MIT licence — see LICENSE.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO/.env"
OUT_DIR="$REPO/Code/Generated"
OUT="$OUT_DIR/ATSecrets.generated.swift"

certificate=""
salt=""

if [ -f "$ENV_FILE" ]; then
  # Read as data, not as shell: values contain `$`, `{` and `(`, which must not be expanded.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      \#* | "") continue ;;
    esac
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      AT_CERTIFICATE) certificate="$value" ;;
      AT_CHAPTER_SALT) salt="$value" ;;
    esac
  done <"$ENV_FILE"
else
  echo "gen-secrets: no .env found — building without chapter decryption (see .env.example)" >&2
fi

if [ -z "$certificate" ] || [ -z "$salt" ]; then
  echo "gen-secrets: AT_CERTIFICATE / AT_CHAPTER_SALT unset — chapters will not open" >&2
fi

# Escape for a Swift string literal: backslashes first, then quotes.
escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# Build the file in memory. Writing a temporary sibling would be denied: user-script sandboxing
# permits writing only the declared output file.
mkdir -p "$OUT_DIR"
generated=$(
  cat <<EOF
//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//
//  GENERATED FILE — DO NOT EDIT. Produced by Scripts/gen-secrets.sh from .env.
//

/// Service constants read from the gitignored \`.env\`. Empty when the build was not configured.
enum ATSecrets {
    static let certificate = "$(escape "$certificate")"
    static let chapterSalt = "$(escape "$salt")"

    static var isConfigured: Bool { !certificate.isEmpty && !chapterSalt.isEmpty }
}
EOF
)

# Only rewrite when the contents actually change, so builds are not invalidated needlessly.
if [ ! -f "$OUT" ] || [ "$(cat "$OUT")" != "$generated" ]; then
  if ! printf '%s\n' "$generated" >"$OUT"; then
    echo "gen-secrets: failed to write $OUT" >&2
    exit 1
  fi
fi

if [ -n "$certificate" ] && [ -n "$salt" ]; then
  echo "gen-secrets ✅ configured"
else
  echo "gen-secrets ⚠️  unconfigured (browse/search only)"
fi
