#!/usr/bin/env bash
#
# check-modules.sh — enforce the module graph by checking what each package imports.
#
# The dependency edges are declared in the Package.swift files and the compiler enforces those. What
# it can't enforce is the absence of a framework nobody declared: any target may `import SwiftUI`. The
# three rules below are the ones the documents state and the compiler can't, so they're checked here.
#
# Usage (from anywhere):
#   Scripts/check-modules.sh
#
# Copyright © 2026 Alexander Babaev. MIT licence — see LICENSE.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

# forbid <import> <reason> <package...> — fail if any package's sources import the named module.
forbid() {
  local import="$1" reason="$2"
  shift 2
  local package hits
  for package in "$@"; do
    local sources="$REPO/Frameworks/$package/Sources"
    [ -d "$sources" ] || continue
    hits="$(grep -rn --include='*.swift' "^import ${import}\$" "$sources" 2>/dev/null)"
    [ -n "$hits" ] || continue
    echo "$package must not import $import: $reason"
    printf '%s\n' "$hits" | sed -e "s|^$REPO/||" -e 's/^/  /'
    FAILED=1
  done
}

forbid SwiftUI "nothing that models a book or talks to a service draws one" \
  AuthorToday Litres BookKit BookFormats BookStorage AuthorTodayBooks

forbid DesignSystem "the reader page is set by whoever is reading, not by the app's design system" \
  BookRenderer

forbid AuthorToday "only AuthorTodayBooks meets the service" \
  BookKit DesignSystem BookFormats BookStorage BookRenderer

forbid Litres "a service is met by the app, not by anything that models a book" \
  AuthorToday BookKit DesignSystem BookFormats BookStorage BookRenderer AuthorTodayBooks

forbid BookKit "a service package knows nothing about this app's books" \
  Litres

forbid BookKit "the design system knows nothing about books" \
  DesignSystem

if [ "$FAILED" -eq 0 ]; then
  echo "modules ✅ every package imports only what it may"
  exit 0
fi
exit 1
