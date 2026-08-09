#!/usr/bin/env bash
#
# lint.sh — run SwiftLint over the Swift package sources with the project code-style rules.
#
# Usage:
#   Scripts/lint.sh              # lint Sources/ + Tests/ (warnings + errors), concise summary
#   Scripts/lint.sh --strict     # treat every finding as an error (exit 1 on any warning)
#   Scripts/lint.sh --fix        # auto-correct the correctable violations in place
#   Scripts/lint.sh --fix --allow-dirty   # auto-correct even with uncommitted target changes
#   Scripts/lint.sh PATH ...     # restrict to the given files/dirs
#
# The custom rules here are checkers only (they never modify code). `--fix` applies SwiftLint's built-in
# correctors, which DO rewrite files — so, like format.sh, it refuses to touch a tree with uncommitted target
# changes unless --allow-dirty is given.
#
# Config: .swiftlint.yml (repo root) — indented switch cases, 120-col lines, mandatory trailing commas,
# sorted imports, one-arg-per-line on wrapped calls, no blank lines hugging braces. Pure layout
# (indentation, brace placement) is owned by Scripts/format.sh; this catches the lint-only concerns.
#
# Override the binary with SWIFTLINT=/path/to/swiftlint if needed.
#
# Copyright © 2026 Alexander Babaev. MIT licence — see LICENSE.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$REPO/.swiftlint.yml"
LINT_BIN="${SWIFTLINT:-swiftlint}"

# SwiftLint loads sourcekitd from the selected Xcode; auto-select the newest Xcode.27 like build.sh does,
# unless the caller already picked one via DEVELOPER_DIR.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  candidate="$(ls -d /Applications/Xcode.27*.app 2>/dev/null | sort -V | tail -1 || true)"
  if [ -n "$candidate" ] && [ -d "$candidate/Contents/Developer" ]; then
    export DEVELOPER_DIR="$candidate/Contents/Developer"
  fi
fi

if ! command -v "$LINT_BIN" >/dev/null 2>&1; then
  echo "lint.sh: '$LINT_BIN' not found (install via \`brew install swiftlint\`)"
  exit 2
fi

MODE="lint"
ALLOW_DIRTY=0
STRICT=()
PATHS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --fix) MODE="fix" ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --strict) STRICT=(--strict) ;;
    -h | --help)
      sed -n '2,21p' "$0"
      exit 0
      ;;
    *) PATHS+=("$1") ;;
  esac
  shift
done

# Run from the repo root so the `included:`/`excluded:` globs in .swiftlint.yml resolve.
cd "$REPO"

if [ "$MODE" = "fix" ]; then
  # Safety guard: --fix rewrites files, so don't touch a tree with uncommitted target changes (recoverable).
  if [ "$ALLOW_DIRTY" = 0 ] && git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    TARGETS=(Code)
    [ -d "$REPO/Frameworks" ] && TARGETS=(Code Frameworks)
    [ ${#PATHS[@]} -gt 0 ] && TARGETS=("${PATHS[@]}")
    DIRTY="$(git -C "$REPO" status --porcelain -- "${TARGETS[@]}" 2>/dev/null)"
    if [ -n "$DIRTY" ]; then
      echo "lint.sh: refusing to --fix — these target paths have uncommitted changes:"
      printf '%s\n' "$DIRTY" | sed 's/^/  /'
      echo "Commit or stash them first, or pass --allow-dirty."
      exit 3
    fi
  fi

  "$LINT_BIN" --fix --config "$CONFIG" ${PATHS[@]+"${PATHS[@]}"}
  echo "lint ✅ applied auto-corrections (re-run Scripts/lint.sh to see what remains)"
  exit 0
fi

OUT="$("$LINT_BIN" lint --config "$CONFIG" --quiet ${STRICT[@]+"${STRICT[@]}"} ${PATHS[@]+"${PATHS[@]}"} 2>&1)"
RC=$?

if [ -n "$OUT" ]; then printf '%s\n' "$OUT"; fi

WARN=$(printf '%s\n' "$OUT" | grep -c ' warning: ' || true)
ERR=$(printf '%s\n' "$OUT" | grep -c ' error: ' || true)
echo "── lint summary: $WARN warning(s), $ERR error(s) ──"

if [ "$RC" = 0 ]; then exit 0; fi
exit 1
