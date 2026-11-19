#!/bin/sh
#
# Stages an official Reynard release's engine so the app layer (Reynard, GeckoView.framework,
# the Helper) builds against it without building Gecko. It fills GECKO_DIST the way
# tools/development/build-gecko.sh would, so browser/Scripts/AddGecko.sh and the Xcode project
# work unchanged:
#   dist/bin                      XUL, the engine dylibs, GeckoView.framework/Frameworks files
#   dist/include/GeckoView        IOSBootstrap.h and GeckoViewSwiftSupport.h with Reynard's patches
#   toolkit/.../default-theme     the release's default theme, which AddGecko.sh copies back
#
# Usage: tools/sitemode/stage-engine.sh [path to the .tipa]
# Without a path it downloads the asset named in engine.lock. Either way the sha256 must match.

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
. "$SCRIPT_DIR/engine.lock"

FIREFOX_DIR="$ROOT_DIR/engine/firefox"
GECKO_DIST="$FIREFOX_DIR/obj-aarch64-apple-ios/dist"
# Outside dist/, which tools/release/build-app.sh deletes; inside the Firefox submodule path,
# where build-gecko.sh writes its own output.
WORK_DIR="$FIREFOX_DIR/site-mode-engine"
TIPA="${1:-$WORK_DIR/$ENGINE_ASSET}"

if ! git -C "$ROOT_DIR" merge-base --is-ancestor "$APP_COMMIT" HEAD; then
	echo "HEAD does not contain $APP_COMMIT, the commit of Reynard $ENGINE_TAG." >&2
	exit 1
fi
if [ -n "$(git -C "$ROOT_DIR" diff --name-only "$APP_COMMIT" HEAD -- engine/release.txt patches)" ]; then
	echo "engine/release.txt or patches/ differ from Reynard $ENGINE_TAG: this engine does not match." >&2
	exit 1
fi

mkdir -p "$WORK_DIR"
if [ ! -f "$TIPA" ]; then
	curl --fail --location --output "$TIPA" \
		"https://github.com/minh-ton/reynard-browser/releases/download/$ENGINE_TAG/$ENGINE_ASSET"
fi
echo "$ENGINE_SHA256  $TIPA" | shasum -a 256 -c -

# 1. The engine from the release, as build-gecko.sh would leave it in dist/bin.
rm -rf "$WORK_DIR/unpacked" "$GECKO_DIST"
mkdir -p "$WORK_DIR/unpacked" "$GECKO_DIST/bin" "$GECKO_DIST/include/GeckoView"
unzip -q "$TIPA" 'Payload/Reynard.app/Frameworks/*' -d "$WORK_DIR/unpacked"
FRAMEWORKS="$WORK_DIR/unpacked/Payload/Reynard.app/Frameworks"
cp -p "$FRAMEWORKS/XUL" "$GECKO_DIST/bin/"
for dylib in "$FRAMEWORKS"/*.dylib; do
	case "$(basename "$dylib")" in
		libswift_*) ;; # Xcode embeds its own Swift runtime
		*) cp -p "$dylib" "$GECKO_DIST/bin/" ;;
	esac
done
cp -Rp "$FRAMEWORKS/GeckoView.framework/Frameworks/." "$GECKO_DIST/bin/"

# AddGecko.sh copies the default theme from the Firefox tree and registers it again.
THEME_DIR="$FIREFOX_DIR/toolkit/mozapps/extensions/default-theme"
rm -rf "$THEME_DIR"
mkdir -p "$(dirname "$THEME_DIR")"
mv "$GECKO_DIST/bin/default-theme" "$THEME_DIR"
grep -v '^resource default-theme ' "$GECKO_DIST/bin/chrome.manifest" > "$WORK_DIR/chrome.manifest"
mv "$WORK_DIR/chrome.manifest" "$GECKO_DIST/bin/chrome.manifest"

# 2. The two Gecko headers the app layer includes, from the pinned Firefox commit plus Reynard's patches.
for header in toolkit/xre/IOSBootstrap.h widget/uikit/GeckoViewSwiftSupport.h; do
	name="$(basename "$header")"
	curl --fail --silent --show-error --location --output "$GECKO_DIST/include/GeckoView/$name" \
		"https://raw.githubusercontent.com/mozilla-firefox/firefox/$FIREFOX_COMMIT/$header"
	patch --silent -p3 -d "$GECKO_DIST/include/GeckoView" "$name" < "$ROOT_DIR/patches/$header.patch"
done

rm -rf "$WORK_DIR/unpacked"
echo "Staged Reynard $ENGINE_TAG's engine in $GECKO_DIST"
