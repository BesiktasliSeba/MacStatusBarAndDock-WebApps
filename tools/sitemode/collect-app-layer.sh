#!/bin/sh
#
# Collects the site mode app layer from the built TrollStore package: the app without its
# engine (Frameworks) and without OpenIn.appex, plus GeckoView.framework's binary and
# Info.plist, which replace the official ones in the shared engine. Writes
# dist/site-mode/site-mode-app-layer-<tag>.zip with a sha256 manifest and the engine pin.

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
. "$SCRIPT_DIR/engine.lock"

APP="$ROOT_DIR/dist/Reynard/Payload/Reynard.app"
OUT="$ROOT_DIR/dist/site-mode"
LAYER="$OUT/layer"

rm -rf "$OUT"
mkdir -p "$LAYER/Reynard.app/Frameworks/GeckoView.framework"
rsync -a --exclude '/Frameworks' --exclude '/PlugIns/OpenIn.appex' "$APP/" "$LAYER/Reynard.app/"
cp -p "$APP/Frameworks/GeckoView.framework/GeckoView" "$APP/Frameworks/GeckoView.framework/Info.plist" \
	"$LAYER/Reynard.app/Frameworks/GeckoView.framework/"
cp "$SCRIPT_DIR/engine.lock" "$LAYER/"
git -C "$ROOT_DIR" rev-parse HEAD > "$LAYER/BUILT_COMMIT"
(
	cd "$LAYER"
	find Reynard.app -type f | LC_ALL=C sort | while IFS= read -r file; do
		shasum -a 256 "$file"
	done > MANIFEST.sha256
	zip -qry "$OUT/site-mode-app-layer-$ENGINE_TAG.zip" Reynard.app MANIFEST.sha256 engine.lock BUILT_COMMIT
)
du -sh "$LAYER/Reynard.app" "$OUT/site-mode-app-layer-$ENGINE_TAG.zip"
