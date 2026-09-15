#!/usr/bin/env bash
#
# shots.sh — take a picture of one page on each of several simulators.
#
# The reader's whole job is setting a page, and a page is set against the screen it's on. Reading the
# geometry off the code says nothing about how it looks at a size nobody has run, so this puts the
# same page on every screen and leaves the pictures side by side.
#
# It photographs PageProof, not the app: the same packages set the same page with no account, no
# library and no book to read in first. It installs through app.sh and then drives simulators that are
# already running, which is what simctl is for here.
#
# Usage (from anywhere):
#   Scripts/shots.sh                         # every screen below, at the system's own type size
#   Scripts/shots.sh "iPhone 17 Pro"         # just these screens
#   Scripts/shots.sh --type "iPhone 17 Pro"  # that screen at every system type size
#
# Anything after `--` is passed to the app, so the page can be set as the reader would set it:
#   Scripts/shots.sh "iPhone 17 Pro" -- -proof.fontSize 30 -proof.margins 0
#
# Copyright © 2026 Alexander Babaev. MIT licence — see LICENSE.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="com.lonelybytes.atreader.proof"
OUT="$REPO/Fixtures/Reports/Shots"

SCREENS=("iPhone 17e" "iPhone 17" "iPhone Air" "iPhone 17 Pro" "iPhone 17 Pro Max" "iPad mini (A17 Pro)" "iPad Pro 13-inch (M5)")
# The size the system sets its own text at. The page is set from the book's own size, so this should
# leave it alone; that is the thing worth looking at.
SIZES=("large")

if [ "${1:-}" = "--type" ]; then
  shift
  SIZES=("extra-small" "large" "extra-extra-extra-large" "accessibility-extra-large" "accessibility-extra-extra-extra-large")
fi

ASKED=()
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--" ]; then
    shift
    ASKED=("$@")
    break
  fi
  [ "${#SCREENS[@]}" -eq 7 ] && SCREENS=()
  SCREENS+=("$1")
  shift
done

mkdir -p "$OUT"

for screen in "${SCREENS[@]}"; do
  echo "▸ $screen"
  # The UDID comes out of app.sh's own report: two runtimes can offer the same name, and the one it
  # installed on is the only one with the app.
  id="$("$REPO/Scripts/app.sh" deploy --sim "$screen" --scheme PageProof 2>&1 |
    sed -n 's/.*install · simulator \([0-9A-F-]\{36\}\).*/\1/p' | head -1)"
  [ -n "$id" ] || {
    echo "  ✗ could not install"
    continue
  }

  for size in "${SIZES[@]}"; do
    xcrun simctl ui "$id" content_size "$size" >/dev/null 2>&1
    xcrun simctl terminate "$id" "$BUNDLE" >/dev/null 2>&1
    xcrun simctl launch "$id" "$BUNDLE" ${ASKED[@]+"${ASKED[@]}"} >/dev/null 2>&1 || {
      echo "  ✗ would not launch"
      continue
    }

    # One chapter has to be read and set before there is a page to photograph.
    sleep 6
    file="$OUT/$(echo "$screen" | tr ' ()' '-')"
    [ "${#SIZES[@]}" -eq 1 ] || file="$file--$size"
    xcrun simctl io "$id" screenshot "$file.png" >/dev/null 2>&1 &&
      echo "  ✅ $file.png" ||
      echo "  ✗ no picture"
  done

  xcrun simctl ui "$id" content_size large >/dev/null 2>&1
done
