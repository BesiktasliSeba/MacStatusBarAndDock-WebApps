#!/bin/sh
#
# Compares the built TrollStore package with the official one of the same release, after
# tools/release/create-ipa.sh --trollstore:
#   - the app and GeckoView load the same engine libraries;
#   - nothing they import from the engine is missing from the official engine;
#   - the app and the Helper carry the same entitlements;
#   - the version is the release's.

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
. "$SCRIPT_DIR/engine.lock"

WORK="$ROOT_DIR/dist/site-mode-check"
OURS="$ROOT_DIR/dist/Reynard/Payload/Reynard.app"
OFFICIAL="$WORK/Payload/Reynard.app"
status=0
fail() {
	echo "FAIL: $*"
	status=1
}

rm -rf "$WORK"
mkdir -p "$WORK"
unzip -q "$ROOT_DIR/engine/firefox/site-mode-engine/$ENGINE_ASSET" -d "$WORK" \
	'Payload/Reynard.app/Reynard' \
	'Payload/Reynard.app/Info.plist' \
	'Payload/Reynard.app/Frameworks/XUL' \
	'Payload/Reynard.app/Frameworks/libmozglue.dylib' \
	'Payload/Reynard.app/Frameworks/libnss3.dylib' \
	'Payload/Reynard.app/Frameworks/GeckoView.framework/GeckoView' \
	'Payload/Reynard.app/PlugIns/Reynard Helper.appex/Reynard Helper'

for binary in "Reynard" "Frameworks/GeckoView.framework/GeckoView" "PlugIns/Reynard Helper.appex/Reynard Helper"; do
	otool -L "$OFFICIAL/$binary" | awk 'NR > 1 && $1 ~ /^@rpath\// { print $1 }' | sort > "$WORK/official.libs"
	otool -L "$OURS/$binary" | awk 'NR > 1 && $1 ~ /^@rpath\// { print $1 }' | sort > "$WORK/ours.libs"
	diff -u "$WORK/official.libs" "$WORK/ours.libs" || fail "$binary links other @rpath libraries than the official build"
done

for library in XUL libmozglue libnss3; do
	file="$library"
	[ "$library" = XUL ] || file="$library.dylib"
	nm -gU "$OFFICIAL/Frameworks/$file" | awk '{ print $NF }' | sort -u > "$WORK/$library.exports"
	for binary in "Reynard" "Frameworks/GeckoView.framework/GeckoView"; do
		nm -m -u "$OURS/$binary" | sed -nE "s/.* external ([^ ]*) \(from (@rpath\/)?$library\)\$/\1/p" | sort -u > "$WORK/imports"
		missing="$(comm -23 "$WORK/imports" "$WORK/$library.exports")"
		[ -z "$missing" ] || fail "$binary imports from $library what the official engine lacks: $missing"
		echo "$binary imports $(wc -l < "$WORK/imports" | tr -d ' ') symbols from $library"
	done
done

for binary in "Reynard" "PlugIns/Reynard Helper.appex/Reynard Helper"; do
	ldid -e "$OFFICIAL/$binary" > "$WORK/official.entitlements"
	ldid -e "$OURS/$binary" > "$WORK/ours.entitlements"
	diff -u "$WORK/official.entitlements" "$WORK/ours.entitlements" || fail "$binary has other entitlements than the official build"
done

version="$(plutil -extract CFBundleShortVersionString raw "$OURS/Info.plist")"
[ "$version" = "$ENGINE_TAG" ] || fail "version $version, expected $ENGINE_TAG"

[ "$status" -eq 0 ] && echo "The app layer matches Reynard $ENGINE_TAG's official engine."
exit "$status"
