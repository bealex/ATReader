#!/usr/bin/env bash
#
# lint-bash.sh — run shellcheck over the project shell scripts.
#
# The bash analogue of lint.sh. Don't call shellcheck directly — go through this script (or
# Scripts/check.sh, which runs it as one of its steps). Config: the repo-root .shellcheckrc.
#
# Usage (from anywhere; defaults to every *.sh under Scripts/ and FeediqPusher/):
#   Scripts/lint-bash.sh                  # report findings; non-zero only on error-severity findings
#   Scripts/lint-bash.sh --strict         # treat any finding (warnings/notes too) as failure
#   Scripts/lint-bash.sh PATH ...         # restrict to the given files/dirs
#
# Copyright © 2026 Alexander Babaev. MIT licence — see LICENSE.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LINT_BIN="${SHELLCHECK:-shellcheck}"
if ! command -v "$LINT_BIN" >/dev/null 2>&1; then
  echo "lint-bash.sh: '$LINT_BIN' not found (install via \`brew install shellcheck\`)" >&2
  exit 2
fi

STRICT=0
PATHS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1 ;;
    -h | --help)
      sed -n '2,14p' "$0"
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
  echo "lint-bash.sh: no *.sh files found"
  exit 0
fi

# -x follows `source`d files; shellcheck finds the repo-root .shellcheckrc from each file's own directory upward
# (so no cd — a cd would break relative path args). gcc format = one line per finding.
OUT="$("$LINT_BIN" -x -f gcc "${FILES[@]}" 2>&1)"
if [ -n "$OUT" ]; then printf '%s\n' "$OUT" | sed "s#^$REPO/##"; fi

WARN=$(printf '%s\n' "$OUT" | grep -c ' warning: ' || true)
ERR=$(printf '%s\n' "$OUT" | grep -c ' error: ' || true)
NOTE=$(printf '%s\n' "$OUT" | grep -c ' note: ' || true)
echo "── shellcheck summary: $ERR error(s), $WARN warning(s), $NOTE note(s) ──"

if [ "$ERR" -gt 0 ]; then exit 1; fi
if [ "$STRICT" = 1 ] && [ "$((WARN + NOTE))" -gt 0 ]; then exit 1; fi
exit 0
