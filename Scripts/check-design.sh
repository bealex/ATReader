#!/usr/bin/env bash
#
# check-design.sh — keep the app drawing from the design system rather than from literals.
#
# Every length outside the reader page is a multiple of three and has a name in `Design`, and every
# text style is one of the seven roles. A number written straight into a view is how a design system
# stops being one, so they are checked here. The reader page is exempt: its type and margins belong to
# whoever is reading.
#
# Usage (from anywhere):
#   Scripts/check-design.sh
#
# Copyright © 2026 Alexander Babaev. MIT licence — see LICENSE.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

# report <label> <pattern> — fail on any match under Code/, minus the reader and the catalogue.
report() {
  local label="$1" pattern="$2" hits
  hits="$(grep -rnE --include='*.swift' "$pattern" "$REPO/Code" 2>/dev/null |
    grep -v '/Screens/Reader/' |
    grep -v '/Screens/DesignSystem/' |
    grep -v '/Services/ReaderSettings.swift')"
  [ -n "$hits" ] || return 0
  echo "$label"
  printf '%s\n' "$hits" | sed -e "s|^$REPO/||" -e 's/^/  /'
  FAILED=1
}

report "a length with no name (use Design.Space, Radius or Size):" \
  '\.padding\([0-9]|(spacing|cornerRadius|minHeight|lineWidth|width|height): [1-9][0-9]*'

report "a text style with no role (use Design.Style):" \
  '\.font\(\.(largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2)'

report "a colour off the palette (use Design.Palette or Design.Surface):" \
  'Color\(\.(system|secondarySystem|tertiarySystem|quaternarySystem)[A-Za-z]+\)'

if [ "$FAILED" -eq 0 ]; then
  echo "design ✅ every length and style in the app has a name"
  exit 0
fi
exit 1
