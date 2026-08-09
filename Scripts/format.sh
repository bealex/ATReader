#!/usr/bin/env bash
#
# format.sh — reformat (or check) the app sources (Code/) to the project code style.
#
# Two passes per file:
#   1. swift-format   — layout (4-space indent, 120 cols, indented switch cases, spaced ranges `0 ..< n`,
#                       one-arg-per-line on wrapped calls, no blank lines hugging type braces).
#   2. style-respace  — a SwiftSyntax post-pass (Scripts/StyleRespace) for the rules swift-format can't
#                       express: interior spaces on single-line collection literals (`[.foo]` → `[ .foo ]`),
#                       guard / ternary / if-condition layout, dropping `;` statement separators, and
#                       collapsing single-argument calls (`foo(\n .bar{…}\n)` → `foo(.bar{…})`).
#                       Parser-aware: never touches array types, subscripts, strings, or comments.
#
# Usage:
#   Scripts/format.sh              # rewrite Sources/ + Tests/ in place
#   Scripts/format.sh --check      # report files that are NOT formatted; modify nothing (exit 1 if any)
#   Scripts/format.sh --allow-dirty  # rewrite even when target files have uncommitted changes
#   Scripts/format.sh PATH ...     # restrict to the given files/dirs (instead of the whole Sources/+Tests/ tree)
#
# Safety: the style-respace pass does structural rewrites (guard / expression-form surgery) that could, in a
# rare unhandled edge case, lose content. So an in-place run refuses to touch any target file that has
# uncommitted git changes — commit or stash first, so a bad transform is a `git diff` / `git checkout` away
# (override with --allow-dirty). `--check` never modifies and skips this guard.
#
# Config: .swift-format (repo root; also auto-discovered by editors/IDEs).
# Override the binary with SWIFT_FORMAT=/path/to/swift-format if needed.
#
# Copyright © 2026 Alexander Babaev. MIT licence — see LICENSE.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$REPO/.swift-format"
RESPACE_PKG="$REPO/Scripts/StyleRespace"
FORMAT_BIN="${SWIFT_FORMAT:-swift-format}"

# StyleRespace needs the Swift 6.3 toolchain (its swift-tools-version); auto-select the newest Xcode.27
# like build.sh/uitest.sh do, unless the caller already picked one via DEVELOPER_DIR.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  candidate="$(ls -d /Applications/Xcode.27*.app 2>/dev/null | sort -V | tail -1 || true)"
  if [ -n "$candidate" ] && [ -d "$candidate/Contents/Developer" ]; then
    export DEVELOPER_DIR="$candidate/Contents/Developer"
  fi
fi

if ! command -v "$FORMAT_BIN" >/dev/null 2>&1; then
  echo "format.sh: '$FORMAT_BIN' not found (install via the Swift toolchain or \`brew install swift-format\`)"
  exit 2
fi

CHECK=0
ALLOW_DIRTY=0
PATHS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK=1 ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    -h | --help)
      sed -n '2,31p' "$0"
      exit 0
      ;;
    *) PATHS+=("$1") ;;
  esac
  shift
done

if [ ${#PATHS[@]} -eq 0 ]; then
  PATHS=("$REPO/Code")
  [ -d "$REPO/Frameworks" ] && PATHS+=("$REPO/Frameworks")
fi

# Build the collection-literal re-spacer once and resolve its binary (first build fetches swift-syntax).
# Build in release: the first compile is slower, but the binary runs on every file (it re-parses to a
# fixpoint per edit), so the faster optimized binary more than pays for itself across a run.
echo "format.sh: building style-respace…" >&2
RESPACE_TMP="$RESPACE_PKG/.build/tmp"
mkdir -p "$RESPACE_TMP"
if ! TMPDIR="$RESPACE_TMP" xcrun swift build -c release --package-path "$RESPACE_PKG" --disable-sandbox >/dev/null 2>&1; then
  echo "format.sh: failed to build style-respace (Scripts/StyleRespace) — run its build manually to see why"
  exit 2
fi
RESPACE="$(TMPDIR="$RESPACE_TMP" xcrun swift build -c release --package-path "$RESPACE_PKG" --disable-sandbox --show-bin-path 2>/dev/null)/style-respace"

# Collect .swift files (defensively skip any .build tree under the given paths).
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(
  find "${PATHS[@]}" -name '*.swift' -not -path '*/.build/*' 2>/dev/null | sort
)

if [ ${#FILES[@]} -eq 0 ]; then
  echo "format.sh: no .swift files found"
  exit 0
fi

if [ "$CHECK" = 1 ]; then
  bad=0
  for f in "${FILES[@]}"; do
    if ! "$FORMAT_BIN" format --configuration "$CONFIG" "$f" 2>/dev/null | "$RESPACE" - 2>/dev/null | diff -q "$f" - >/dev/null 2>&1; then
      echo "✗ ${f#"$REPO/"}"
      bad=$((bad + 1))
    fi
  done
  if [ "$bad" = 0 ]; then
    echo "format ✅ all ${#FILES[@]} files already formatted"
    exit 0
  fi
  echo "format ❌ $bad of ${#FILES[@]} file(s) need formatting — run Scripts/format.sh"
  exit 1
fi

# Safety guard: don't rewrite files that have uncommitted changes, so any destructive transform stays
# recoverable. Checks only the files about to be modified; untracked non-target files don't block.
if [ "$ALLOW_DIRTY" = 0 ] && git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  DIRTY="$(git -C "$REPO" status --porcelain -- "${FILES[@]}" 2>/dev/null)"
  if [ -n "$DIRTY" ]; then
    echo "format.sh: refusing to rewrite — these target files have uncommitted changes:"
    printf '%s\n' "$DIRTY" | sed 's/^/  /'
    echo "Commit or stash them first (so a bad structural transform is recoverable), or pass --allow-dirty."
    exit 3
  fi
fi

"$FORMAT_BIN" format --in-place --parallel --configuration "$CONFIG" "${FILES[@]}"
"$RESPACE" "${FILES[@]}" >/dev/null
echo "format ✅ reformatted ${#FILES[@]} files in place (swift-format + style-respace)"
