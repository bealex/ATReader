#!/usr/bin/env bash
#
# check.sh — one-shot pre-commit gate: formatter + linter + localization linter + bash format/lint.
#
# Runs all project checks in sequence and prints one concise block per step, so verifying a commit is
# a single command. Every step runs even if an earlier one fails (you see all problems at once), and the
# script exits non-zero if any step failed — so it doubles as a CI / pre-commit gate.
#
# Usage:
#   Scripts/check.sh           # verify only: format --check, lint, loc-check, bash format/lint — modifies nothing
#   Scripts/check.sh --fix     # auto-fix first (format in place + lint --fix + shfmt), then the checkers
#   Scripts/check.sh -h
#
# In --fix mode the formatter/linter rewrite files, so (like the scripts they wrap) they refuse a tree with
# uncommitted target changes — that's the project flow: commit, then `check.sh --fix`, then amend.
#
# Copyright © 2026 Alexander Babaev. MIT licence — see LICENSE.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$REPO/Scripts"

FIX=0
while [ $# -gt 0 ]; do
  case "$1" in
    --fix) FIX=1 ;;
    -h | --help)
      sed -n '2,17p' "$0"
      exit 0
      ;;
    *)
      echo "check.sh: unknown option $1" >&2
      exit 2
      ;;
  esac
  shift
done

if [ -t 1 ]; then
  BOLD=$'\033[1m'
  DIM=$'\033[0;90m'
  GRN=$'\033[0;32m'
  RED=$'\033[0;31m'
  RST=$'\033[0m'
else
  BOLD=""
  DIM=""
  GRN=""
  RED=""
  RST=""
fi

FAILED=()

# step <label> <command...> — print a header, run the command capturing its output, echo that output
# indented/dimmed beneath the header, and record the label if it exited non-zero.
step() {
  local label="$1"
  shift
  printf '\n%s▸ %s%s\n' "$BOLD" "$label" "$RST"
  local out rc
  out="$("$@" 2>&1)"
  rc=$?
  # Drop blank lines and swiftlint --fix's per-file progress spam, then indent/dim the rest.
  printf '%s\n' "$out" |
    sed -e '/^[[:space:]]*$/d' -e "/^Correcting '/d" |
    sed -e "s/^/  ${DIM}/" -e "s/\$/${RST}/"
  [ "$rc" -eq 0 ] || FAILED+=("$label")
}

if [ "$FIX" = 1 ]; then
  step "Format (apply)" "$SCRIPTS/format.sh"
  step "Lint (apply)" "$SCRIPTS/lint.sh" --fix
  step "Bash format (apply)" "$SCRIPTS/format-bash.sh"
else
  step "Format" "$SCRIPTS/format.sh" --check
  step "Lint" "$SCRIPTS/lint.sh"
  step "Bash format" "$SCRIPTS/format-bash.sh" --check
fi
step "Bash lint" "$SCRIPTS/lint-bash.sh"
step "Localization" "$SCRIPTS/loc-check.sh"

echo
if [ ${#FAILED[@]} -eq 0 ]; then
  printf '%s✅ all checks passed%s\n' "$GRN" "$RST"
  exit 0
fi
printf '%s❌ %d check(s) failed: %s%s\n' "$RED" "${#FAILED[@]}" "${FAILED[*]}" "$RST"
exit 1
