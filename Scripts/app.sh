#!/usr/bin/env bash
#
# app.sh — build, deploy and test ATReader from one command.
#
# Each run writes its full log to a file under $TMPDIR and prints only a short summary: one line per
# phase, the first errors where a phase failed, and a final RESULT line meant to be parsed rather than
# read. The log path is on that line, so the detail is one `cat` away when the summary isn't enough.
#
# Usage:
#   Scripts/app.sh build  [target] [config] [selector]
#   Scripts/app.sh deploy [target] [config] [selector]
#   Scripts/app.sh test   [--unit | --ui] [config] [selector] [test options]
#   Scripts/app.sh clean
#
# Target:    -s, --simulator (default)      -d, --device
# Config:    --debug (default)              --release
# Selector:  --sim NAME, --sim-id UDID, --device-id UDID
# Also:      -O, --optimized (compile Debug with the optimiser on, which is how an optimised build gets
#            onto a device), -v, --verbose (stream the log too), -h, --help
#
# Test options, all of which are xcodebuild's and so imply the app UI tests:
#   --only SPEC     Run one target, suite or case, as ATReaderUITests/CatalogUITests. Repeatable.
#   --build-only    Build the tests without running them.
#   --no-build      Run tests already built by --build-only, reusing that build.
#
# Release carries no provisioning profile in the spec, on purpose, so it builds for a device but cannot
# install there. Use `--optimized` for a build that runs at speed on hardware.
#
# Copyright © 2026 Alexander Babaev. MIT licence — see LICENSE.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEME="ATReader"
PROJECT="$REPO/ATReader.xcodeproj"
PACKAGE="$REPO/Frameworks/AuthorToday"
DD="$REPO/build/dd"
MAX_ERRORS=12

COMMAND=""
TARGET="simulator"
CONFIG="Debug"
SIM_NAME="iPhone 17"
SIM_ID=""
DEVICE_ID=""
TESTS="all"
TEST_ACTION="test"
# Optimisation asked for on top of the configuration, which is how an optimised build reaches a device:
# Release is unsigned in the spec by design, and its signing cannot be supplied on the command line
# because xcodebuild would hand it to the package target as well, which rejects a profile outright.
SIGNING=()
ONLY=()
VERBOSE=0

usage() {
  sed -n '2,${/^[^#]/q;/^# Copyright/q;s/^# \{0,1\}//;p;}' "$0"
}

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

die() {
  printf '%s❌ %s%s\n' "$RED" "$1" "$RST" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    build | deploy | test | clean)
      [ -n "$COMMAND" ] && die "more than one command given: $COMMAND and $1"
      COMMAND="$1"
      ;;
    -d | --device) TARGET="device" ;;
    -s | --simulator) TARGET="simulator" ;;
    --debug) CONFIG="Debug" ;;
    --release) CONFIG="Release" ;;
    --unit) TESTS="unit" ;;
    --ui) TESTS="ui" ;;
    --build-only) TEST_ACTION="build-for-testing" ;;
    --no-build) TEST_ACTION="test-without-building" ;;
    --only)
      shift
      [ $# -gt 0 ] || die "--only needs a target, suite or case"
      ONLY+=("-only-testing:$1")
      ;;
    --sim)
      shift
      [ $# -gt 0 ] || die "--sim needs a simulator name"
      SIM_NAME="$1"
      ;;
    --sim-id)
      shift
      [ $# -gt 0 ] || die "--sim-id needs a UDID"
      SIM_ID="$1"
      ;;
    --device-id)
      shift
      [ $# -gt 0 ] || die "--device-id needs a UDID"
      DEVICE_ID="$1"
      ;;
    -O | --optimized)
      SIGNING=(
        "SWIFT_OPTIMIZATION_LEVEL=-O"
        "SWIFT_COMPILATION_MODE=wholemodule"
        "GCC_OPTIMIZATION_LEVEL=s"
      )
      ;;
    -v | --verbose) VERBOSE=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unknown option $1 (try --help)" ;;
  esac
  shift
done

[ -n "$COMMAND" ] || die "no command given (try --help)"

if [ "$TEST_ACTION" != test ] || [ ${#ONLY[@]} -gt 0 ]; then
  [ "$COMMAND" = test ] || die "--only, --build-only and --no-build belong to the test command"
  [ "$TESTS" = unit ] && die "--only, --build-only and --no-build do not apply to the package tests"
  TESTS="ui"
fi

LOG_DIR="${TMPDIR:-/tmp}"
LOG_DIR="${LOG_DIR%/}/atreader-logs"
mkdir -p "$LOG_DIR" || die "cannot create $LOG_DIR"
LOG="$LOG_DIR/$COMMAND-$(date +%Y%m%d-%H%M%S).log"
: >"$LOG"

# The first distinct errors in the log, made repo-relative so each fits on one line.
show_errors() {
  local lines
  # The compiler renders each diagnostic twice: once as a path:line: error, then again in a source
  # excerpt whose lines carry a `|` gutter. Only the first says where the error is.
  lines="$(grep -aE "(error|fatal error):|^\*\* [A-Z ]+ FAILED \*\*|^✘ |Testing failed:|^ERROR:|NSLocalizedFailureReason" "$LOG" |
    grep -avE "^[[:space:]]*[|~^]" |
    sed -e "s|$REPO/||g" -e 's/^[[:space:]]*//' | awk 'NF && !seen[$0]++')"
  if [ -z "$lines" ]; then
    return 0
  fi
  printf '%s\n' "$lines" | head -"$MAX_ERRORS" | sed -e 's/^/    /'
  local total
  total="$(printf '%s\n' "$lines" | wc -l | tr -d ' ')"
  if [ "$total" -gt "$MAX_ERRORS" ]; then
    printf '    %s… %d more, see the log%s\n' "$DIM" "$((total - MAX_ERRORS))" "$RST"
  fi
  return 0
}

# Runs one phase quietly, timing it and reporting a single line for it.
run_phase() {
  local label="$1"
  shift
  local start=$SECONDS
  printf '%s▸ %s%s\n' "$BOLD" "$label" "$RST"
  {
    printf '\n===== %s =====\n' "$label"
    printf '$ %s\n' "$*"
  } >>"$LOG"

  local rc
  if [ "$VERBOSE" = 1 ]; then
    "$@" 2>&1 | tee -a "$LOG"
    rc=${PIPESTATUS[0]}
  else
    "$@" >>"$LOG" 2>&1
    rc=$?
  fi

  local secs=$((SECONDS - start))
  if [ "$rc" -eq 0 ]; then
    printf '  %s✅ ok%s · %ds\n' "$GRN" "$RST" "$secs"
  else
    printf '  %s❌ failed, exit %d%s · %ds\n' "$RED" "$rc" "$RST" "$secs"
    show_errors
  fi
  return "$rc"
}

# Newest available simulator of that name; the runtimes list oldest first, so the last match wins.
resolve_simulator() {
  if [ -n "$SIM_ID" ]; then
    return 0
  fi
  SIM_ID="$(xcrun simctl list devices available |
    sed -n "s/^[[:space:]]*$SIM_NAME (\([0-9A-Fa-f-]\{36\}\)).*/\1/p" | tail -1)"
  if [ -z "$SIM_ID" ]; then
    printf '%s❌ no available simulator named "%s"%s\n' "$RED" "$SIM_NAME" "$RST" >&2
    return 1
  fi
  return 0
}

# Guessing between several devices installs onto the wrong one, so this only picks when there is no
# choice to make. "unavailable" is excluded by name because it contains "available".
resolve_device() {
  if [ -n "$DEVICE_ID" ]; then
    return 0
  fi

  local rows
  rows="$(xcrun devicectl list devices 2>/dev/null | grep -a physical | grep -av unavailable)"
  local count
  count="$(printf '%s' "$rows" | grep -ac .)"

  if [ "$count" -eq 0 ]; then
    printf '%s❌ no device available; connect and unlock one, or pass --device-id%s\n' "$RED" "$RST" >&2
    return 1
  fi
  if [ "$count" -gt 1 ]; then
    printf '%s❌ %d devices available; choose one with --device-id%s\n' "$RED" "$count" "$RST" >&2
    printf '%s\n' "$rows" | sed -e 's/^/    /' >&2
    return 1
  fi

  DEVICE_ID="$(printf '%s\n' "$rows" | sed -n 's/.*[[:space:]]\([A-Za-z0-9-]\{8,\}\) (UDID).*/\1/p')"
  if [ -z "$DEVICE_ID" ]; then
    printf '%s❌ cannot read the device UDID; pass --device-id%s\n' "$RED" "$RST" >&2
    return 1
  fi
  return 0
}

# project.yml is the source of truth and ATReader.xcodeproj is its output, so a spec newer than the
# project means the project is stale.
#
# So does a file having been added or removed: the spec globs Code/ and Tests/, and the glob is expanded
# when the project is generated, so a new test sits outside the project and silently never runs. A
# directory's own timestamp moves when an entry is added or removed and not when one is merely edited,
# which is the difference this looks for. Editing a file must not regenerate: that rewrites the project
# and costs a full rebuild.
ensure_project() {
  local changed=""

  if [ -d "$PROJECT" ]; then
    changed="$(find "$REPO/Code" "$REPO/Tests" -type d -newer "$PROJECT" -print -quit 2>/dev/null)"
  fi

  if [ -d "$PROJECT" ] && [ -z "$changed" ] && [ "$REPO/project.yml" -ot "$PROJECT" ]; then
    return 0
  fi
  if ! command -v xcodegen >/dev/null 2>&1; then
    printf '%s❌ xcodegen is not installed; brew install xcodegen%s\n' "$RED" "$RST" >&2
    return 1
  fi
  run_phase "generate · xcodegen" xcodegen generate --spec "$REPO/project.yml" --project "$REPO"
}

app_path() {
  local sdk="iphonesimulator"
  [ "$TARGET" = device ] && sdk="iphoneos"
  printf '%s/Build/Products/%s-%s/%s.app' "$DD" "$CONFIG" "$sdk" "$SCHEME"
}

xcode_build() {
  local dest="$1"
  local label="$2"
  local action="$3"
  shift 3
  run_phase "$label" \
    xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
    -destination "$dest" -derivedDataPath "$DD" "$action" "$@"
}

cmd_build() {
  ensure_project || return 1

  local dest
  if [ "$TARGET" = device ]; then
    dest="generic/platform=iOS"
    [ -n "$DEVICE_ID" ] && dest="id=$DEVICE_ID"
  else
    resolve_simulator || return 1
    dest="id=$SIM_ID"
  fi

  xcode_build "$dest" "build · $CONFIG · $TARGET" build ${SIGNING[@]+"${SIGNING[@]}"}
}

# simctl's bootstatus boots the device when it is off and returns at once when it is already up.
boot_simulator() {
  xcrun simctl bootstatus "$SIM_ID" -b >>"$LOG" 2>&1
  open -a Simulator >>"$LOG" 2>&1
  return 0
}

cmd_deploy() {
  cmd_build || return 1

  local app
  app="$(app_path)"
  [ -d "$app" ] || {
    printf '%s❌ no app at %s%s\n' "$RED" "${app#"$REPO"/}" "$RST" >&2
    return 1
  }

  local bundle
  bundle="$(plutil -extract CFBundleIdentifier raw "$app/Info.plist" 2>/dev/null)"
  [ -n "$bundle" ] || {
    printf '%s❌ cannot read the bundle id from the built app%s\n' "$RED" "$RST" >&2
    return 1
  }

  if [ "$TARGET" = device ]; then
    resolve_device || return 1
    run_phase "install · device $DEVICE_ID" \
      xcrun devicectl device install app --device "$DEVICE_ID" "$app" || return 1
    run_phase "launch · $bundle" \
      xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$bundle"
  else
    resolve_simulator || return 1
    boot_simulator
    run_phase "install · simulator $SIM_ID" xcrun simctl install "$SIM_ID" "$app" || return 1
    run_phase "launch · $bundle" xcrun simctl launch "$SIM_ID" "$bundle"
  fi
}

# The counts each framework prints at the end of a run.
test_totals() {
  local swift_testing
  local xctest
  swift_testing="$(grep -aoE "Test run with .*" "$LOG" | awk '!seen[$0]++' | tail -2)"
  xctest="$(grep -aoE "Executed [0-9]+ tests?, with [^)]*\)" "$LOG" | tail -1)"

  # XCTest reports a run of zero whenever the target is swift-testing only; that is noise beside the real count.
  if [ -n "$swift_testing" ]; then
    xctest="$(printf '%s\n' "$xctest" | grep -v "^Executed 0 test")"
  fi

  local totals
  totals="$(printf '%s\n%s\n' "$swift_testing" "$xctest" | awk 'NF')"
  [ -n "$totals" ] && printf '%s\n' "$totals" | sed -e 's/^/    /'
  return 0
}

cmd_test() {
  local rc=0
  if [ "$TESTS" != ui ]; then
    run_phase "test · package unit" swift test --package-path "$PACKAGE" || rc=1
  fi
  if [ "$TESTS" != unit ]; then
    ensure_project || return 1
    resolve_simulator || return 1
    # Pages reported as badly set. xcodebuild strips the prefix on the way to the test process.
    export TEST_RUNNER_AT_REPORTS="$REPO/Fixtures/Reports"
    local label="test · app UI · $CONFIG"
    [ "$TEST_ACTION" = test ] || label="$label · $TEST_ACTION"
    xcode_build "id=$SIM_ID" "$label" "$TEST_ACTION" ${ONLY[@]+"${ONLY[@]}"} || rc=1
  fi
  test_totals
  return "$rc"
}

cmd_clean() {
  run_phase "clean · build output" rm -rf "$REPO/build"
}

case "$COMMAND" in
  build) cmd_build ;;
  deploy) cmd_deploy ;;
  test) cmd_test ;;
  clean) cmd_clean ;;
esac
RC=$?

STATUS="ok"
[ "$RC" -eq 0 ] || STATUS="failed"

FIELDS="status=$STATUS command=$COMMAND"
[ "$COMMAND" = test ] && FIELDS="$FIELDS tests=$TESTS action=$TEST_ACTION"
[ "$COMMAND" = clean ] || FIELDS="$FIELDS config=$CONFIG"
# A unit-only run never picks a destination, so naming one would claim more than the run did.
if [ "$COMMAND" = build ] || [ "$COMMAND" = deploy ] || { [ "$COMMAND" = test ] && [ "$TESTS" != unit ]; }; then
  FIELDS="$FIELDS target=$TARGET"
fi

printf '\n%sRESULT%s %s duration=%ds log=%s\n' "$BOLD" "$RST" "$FIELDS" "$SECONDS" "$LOG"
exit "$RC"
