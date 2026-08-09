#!/usr/bin/env bash
# loc-check.sh — report untranslated / needs-review strings in the app's String Catalogs.
#
# Usage:
#   Scripts/loc-check.sh [locale ...]          # check these locales (default: every non-source locale)
#   Scripts/loc-check.sh --catalog <path> ...  # check a specific .xcstrings (repeatable)
#   Scripts/loc-check.sh --missing-only        # list only fully-missing strings (hide needs-review)
#
# Default catalogs: Code/Resources/Localizable.xcstrings and the AuthorToday package catalog.
# A string counts as translated when it has a non-empty value whose state isn't "new"/"needs_review"
# (machine-translated counts as translated). Stale (out-of-code) and don't-translate keys are skipped.
# Exit status is non-zero when anything is missing or needs review, so it doubles as a CI gate. Wraps a
# single python3 pass — no jq dependency.
# Copyright © 2026 Alexander Babaev. MIT licence — see LICENSE.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOGS=()
LOCALES=()
MISSING_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --catalog)
      CATALOGS+=("$2")
      shift 2
      ;;
    --missing-only)
      MISSING_ONLY=1
      shift
      ;;
    -h | --help)
      sed -n '2,17p' "$0"
      exit 0
      ;;
    -*)
      echo "loc-check.sh: unknown option $1" >&2
      exit 2
      ;;
    *)
      LOCALES+=("$1")
      shift
      ;;
  esac
done

if [[ ${#CATALOGS[@]} -eq 0 ]]; then
  CATALOGS=(
    "$REPO/Code/Resources/Localizable.xcstrings"
    "$REPO/Frameworks/AuthorToday/Sources/AuthorToday/Resources/Localizable.xcstrings"

  )
fi

LOC_CSV="$(
  IFS=,
  echo "${LOCALES[*]:-}"
)"
LOC="$LOC_CSV" MISSING_ONLY="$MISSING_ONLY" python3 - "${CATALOGS[@]}" <<'PY'
import json, os, sys

locales = [loc for loc in os.environ.get("LOC", "").split(",") if loc]
missing_only = os.environ.get("MISSING_ONLY") == "1"
catalogs = sys.argv[1:]
failed = False


def string_units(localization):
    """Every stringUnit under one locale's entry — directly, or nested through plural / device /
    width `variations` (a plural string has no top-level stringUnit)."""
    units = []
    if "stringUnit" in localization:
        units.append(localization["stringUnit"])
    variations = localization.get("variations")
    if isinstance(variations, dict):
        for axis in variations.values():
            for case in axis.values():
                units.extend(string_units(case))
    return units

for path in catalogs:
    if not os.path.exists(path):
        continue

    data = json.load(open(path))
    source = data.get("sourceLanguage", "en")
    strings = data.get("strings", {})

    present = set()
    for info in strings.values():
        present.update(info.get("localizations", {}).keys())
    targets = locales or sorted(loc for loc in present if loc != source)

    print(f"== {os.path.basename(path)} (source={source}) ==")
    for loc in targets:
        missing, review, total = [], [], 0
        for key, info in strings.items():
            if key == "" or info.get("extractionState") == "stale":
                continue
            if info.get("shouldTranslate") is False:
                continue
            total += 1
            localization = info.get("localizations", {}).get(loc)
            units = string_units(localization) if localization else []
            if not units or any(not unit.get("value") for unit in units):
                missing.append(key)
            elif any(unit.get("state") in ("new", "needs_review") for unit in units):
                review.append(key)

        ok = total - len(missing) - len(review)
        flag = "" if not missing and not review else "  ⚠️"
        print(f"  {loc}: {ok}/{total} translated, {len(missing)} missing, {len(review)} need review{flag}")
        for key in missing:
            print(f"      missing: {key!r}")
        if not missing_only:
            for key in review:
                print(f"      review:  {key!r}")
        if missing or (review and not missing_only):
            failed = True

sys.exit(1 if failed else 0)
PY
