#!/usr/bin/env bash
# build_release.sh — builds the pilot APKs and names them with the app version.
#
# Flutter always names the APKs app-<abi>-release.apk, so a new build overwrites
# the previous one under the same name. This script copies each split APK to
# dist/ as layerflow-capture-<version>-<abi>.apk (version from pubspec.yaml,
# e.g. 0.2.2) plus a .sha256 next to it. It reads Gradle's own output
# (build/app/outputs/apk/release/), which manual renames in flutter-apk/ never
# touch.
#
# Usage:
#   scripts/build_release.sh              # build arm64 + armeabi-v7a, then copy
#   scripts/build_release.sh --skip-build # copy the last build only
set -euo pipefail

cd "$(dirname "$0")/.."

full=$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -1)
version=${full%%+*}
[ -n "$version" ] || { echo "No version in pubspec.yaml" >&2; exit 1; }

if [ "${1:-}" != "--skip-build" ]; then
  flutter build apk --release --split-per-abi \
    --target-platform android-arm,android-arm64
fi

src=build/app/outputs/apk/release
mkdir -p dist
for abi in arm64-v8a armeabi-v7a; do
  in="$src/app-$abi-release.apk"
  [ -f "$in" ] || { echo "Missing $in — build first" >&2; exit 1; }
  out="dist/layerflow-capture-$version-$abi.apk"
  cp "$in" "$out"
  (cd dist && sha256sum "$(basename "$out")" > "$(basename "$out").sha256")
  echo "$out  ($(du -h "$out" | cut -f1))"
done
echo "Version $full — check Ajustes shows \"Versión $full\" after installing."
