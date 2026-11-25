#!/bin/sh
# Runs swift test with an Xcode toolchain. swift-testing ships with Xcode, not the Command Line Tools.
set -eu
cd "$(dirname "$0")/.."
if [ -z "${DEVELOPER_DIR:-}" ]; then
  case "$(xcode-select -p 2>/dev/null)" in
    *.app/Contents/Developer) ;;
    *)
      xcode=$(find /Applications -maxdepth 1 -name 'Xcode*.app' | sort -V | tail -1)
      [ -n "$xcode" ] || { echo "test: no Xcode in /Applications; install Xcode to run swift-testing" >&2; exit 1; }
      export DEVELOPER_DIR="$xcode/Contents/Developer"
      ;;
  esac
fi
exec swift test "$@"
