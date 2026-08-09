#!/usr/bin/env bash
#
# format-bash.sh — reformat (or check) the project shell scripts to the shared bash style.
#
# The bash analogue of format.sh. Don't call shfmt directly — go through this script (or Scripts/check.sh,
# which runs it as one of its steps). The style lives in the repo-root .editorconfig (2-space indent, indented
# `case` patterns, K&R braces); shfmt reads it from each file's directory.
#
# Usage (from anywhere; defaults to every *.sh under Scripts/ and FeediqPusher/):
#   Scripts/format-bash.sh                # rewrite the project scripts in place
#   Scripts/format-bash.sh --check        # report scripts that are NOT formatted; modify nothing (exit 1 if any)
#   Scripts/format-bash.sh PATH ...       # restrict to the given files/dirs
#
# The vendored StyleRespace build tree is skipped (it is Swift, not ours to format).
#
# Copyright © 2026 Alexander Babaev. MIT licence — see LICENSE.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FMT_BIN="${SHFMT:-shfmt}"
if ! command -v "$FMT_BIN" >/dev/null 2>&1; then
  echo "format-bash.sh: '$FMT_BIN' not found (install via \`brew install shfmt\`)" >&2
  exit 2
fi

CHECK=0
PATHS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    -h | --help)
      sed -n '2,17p' "$0"
      exit 0
      ;;
    *) PATHS+=("$1") ;;
  esac
  shift
done

if [ ${#PATHS[@]} -eq 0 ]; then PATHS+=("$REPO/Scripts" "$REPO/FeediqPusher"); fi

FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(
  find "${PATHS[@]}" -type f -name '*.sh' \
    -not -path '*/.build/*' -not -path '*/.build-linux/*' -not -path '*/.build-static/*' 2>/dev/null | sort
)
if [ ${#FILES[@]} -eq 0 ]; then
  echo "format-bash.sh: no *.sh files found"
  exit 0
fi

if [ "$CHECK" = 1 ]; then
  UNFORMATTED="$("$FMT_BIN" -l "${FILES[@]}" 2>/dev/null)"
  if [ -z "$UNFORMATTED" ]; then
    echo "format-bash ✅ all ${#FILES[@]} script(s) already formatted"
    exit 0
  fi
  echo "format-bash ❌ $(printf '%s\n' "$UNFORMATTED" | grep -c .) of ${#FILES[@]} script(s) need formatting — run Scripts/format-bash.sh:"
  printf '%s\n' "$UNFORMATTED" | sed "s#^$REPO/##; s/^/  ✗ /"
  exit 1
fi

"$FMT_BIN" -w "${FILES[@]}"
echo "format-bash ✅ reformatted ${#FILES[@]} script(s) in place (shfmt)"
