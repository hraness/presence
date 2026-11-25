#!/bin/sh
# Builds a universal (arm64 + x86_64) release binary and a tarball with its sha256.
# Writes to dist/. Publishes nothing.
set -eu

cd "$(dirname "$0")/.."
version=$(sed -n 's/^public let version = "\(.*\)"$/\1/p' Sources/PresenceCore/CLI.swift)
[ -n "$version" ] || { echo "release: cannot read version from Sources/PresenceCore/CLI.swift" >&2; exit 1; }

# Multi-architecture builds need Xcode, not only the Command Line Tools.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  case "$(xcode-select -p 2>/dev/null)" in
    *.app/Contents/Developer) ;;
    *)
      xcode=$(find /Applications -maxdepth 1 -name 'Xcode*.app' | sort -V | tail -1)
      if [ -n "$xcode" ]; then export DEVELOPER_DIR="$xcode/Contents/Developer"; fi
      ;;
  esac
fi

swift build -c release --arch arm64 --arch x86_64
bin_dir=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
binary="$bin_dir/presence"

archs=$(lipo -archs "$binary")
case "$archs" in
  *arm64*x86_64*|*x86_64*arm64*) ;;
  *) echo "release: expected arm64 and x86_64, got: $archs" >&2; exit 1 ;;
esac

name="presence-$version-macos-universal"
stage="dist/$name"
rm -rf "$stage" "dist/$name.tar.gz" "dist/$name.tar.gz.sha256"
mkdir -p "$stage"
cp "$binary" "$stage/presence"
strip -x "$stage/presence"
cp LICENSE README.md CHANGELOG.md "$stage/"
"$stage/presence" --version

# Fixed owner and group so the archive does not carry the builder's account.
tar -C dist --uid 0 --gid 0 --uname root --gname wheel -czf "dist/$name.tar.gz" "$name"
(cd dist && shasum -a 256 "$name.tar.gz" > "$name.tar.gz.sha256")

echo "binary:  $stage/presence ($archs)"
echo "tarball: dist/$name.tar.gz"
cat "dist/$name.tar.gz.sha256"
