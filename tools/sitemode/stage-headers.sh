#!/bin/sh
#
# Stages the Gecko headers the app layer includes in GECKO_DIST/include, where Gecko's export tier
# puts them, from the Firefox commit in engine.lock and Reynard's patches:
#   GeckoView/IOSBootstrap.h            Firefox's, with Reynard's patch (Reynard-Bridging-Header.h)
#   GeckoView/GeckoViewSwiftSupport.h   Firefox's, with Reynard's patch (Reynard-Bridging-Header.h)
#   GeckoView/GeckoViewRuntimeSupport.h added by Reynard's patch (IOSBootstrap.h includes it)
#   nsError.h, mozilla/Likely.h         Firefox's (WebRequestErrorBridge.mm)
#   ErrorList.h                         generated from Firefox's ErrorList.py (nsError.h includes it)
#   mozilla-config.h                    generated from Firefox's template, version defines only
#                                       (GeckoRuntimeBridge.mm reads MOZILLA_VERSION)
# It only downloads text files and runs nothing from Firefox: errorlist_h.py reads ErrorList.py
# as data.
#
# Usage: tools/sitemode/stage-headers.sh <GECKO_DIST>
# stage-engine.sh runs it after staging the engine.

set -eu

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
	echo "Usage: $0 <GECKO_DIST>" >&2
	exit 2
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
. "$SCRIPT_DIR/engine.lock"

INCLUDE="$1/include"
RAW="https://raw.githubusercontent.com/mozilla-firefox/firefox/$FIREFOX_COMMIT"
GEN="$(mktemp -d)"
trap 'rm -rf "$GEN"' EXIT

fetch() { # <path in Firefox> <output file>
	curl --fail --silent --show-error --location --retry 3 --output "$2" "$RAW/$1"
}

# The files below are staged or read as Firefox has them: stop if a Reynard patch ever changes one.
for file in xpcom/base/nsError.h mfbt/Likely.h xpcom/base/ErrorList.py mozilla-config.h.in config/milestone.txt; do
	if grep -rqxF -e "+++ b/$file" -e "--- a/$file" "$ROOT_DIR/patches"; then
		echo "A Reynard patch changes $file: stage it with the patch." >&2
		exit 1
	fi
done

rm -rf "$INCLUDE"
mkdir -p "$INCLUDE/GeckoView" "$INCLUDE/mozilla"

# 1. GeckoView/: two Firefox headers with Reynard's patches, and the header Reynard's patch adds.
for header in toolkit/xre/IOSBootstrap.h widget/uikit/GeckoViewSwiftSupport.h; do
	name="$(basename "$header")"
	fetch "$header" "$INCLUDE/GeckoView/$name"
	patch --silent -p3 -d "$INCLUDE/GeckoView" "$name" < "$ROOT_DIR/patches/$header.patch"
done
patch --silent -p3 -d "$INCLUDE/GeckoView" < "$ROOT_DIR/patches/widget/uikit/GeckoViewRuntimeSupport.h.patch"

# 2. nsError.h and the source header it includes (EXPORTS and EXPORTS.mozilla in Firefox).
fetch xpcom/base/nsError.h "$INCLUDE/nsError.h"
fetch mfbt/Likely.h "$INCLUDE/mozilla/Likely.h"

# 3. ErrorList.h, which nsError.h includes. Firefox generates it in the export tier
#    (xpcom/base/moz.build: GeneratedFile, entry point error_list_h, no extra error files on iOS).
fetch xpcom/base/ErrorList.py "$GEN/ErrorList.py"
python3 -I "$SCRIPT_DIR/errorlist_h.py" "$GEN/ErrorList.py" "$INCLUDE/ErrorList.h"

# 4. mozilla-config.h. Firefox's configure fills mozilla-config.h.in with every define it sets
#    (process_define_files.py: "#undef ALLDEFINES" becomes the sorted defines, other "#undef NAME"
#    lines are commented out). Only the version defines are written here, from the last line of
#    config/milestone.txt as configure takes it (build/moz.configure/init.configure: milestone).
fetch mozilla-config.h.in "$GEN/mozilla-config.h.in"
fetch config/milestone.txt "$GEN/milestone.txt"
version="$(tail -n 1 "$GEN/milestone.txt" | tr -d '\r')"
if ! printf '%s\n' "$version" | grep -qxE '[0-9]+\.[0-9]+[.0-9ab]*'; then
	echo "Unexpected Firefox milestone '$version' in config/milestone.txt." >&2
	exit 1
fi
awk -v version="\"$version\"" -v uaversion="\"${version%%.*}.0\"" '
/^[[:space:]]*#[[:space:]]*undef[[:space:]]+ALLDEFINES/ {
	print "#define MOZILLA_UAVERSION " uaversion
	print "#define MOZILLA_VERSION " version
	next
}
/^[[:space:]]*#[[:space:]]*undef[[:space:]]+[A-Za-z_]/ {
	match($0, /undef[[:space:]]+[A-Za-z_0-9]+/)
	print "/* " substr($0, 1, RSTART + RLENGTH - 1) " */" substr($0, RSTART + RLENGTH)
	next
}
{ print }
' "$GEN/mozilla-config.h.in" > "$INCLUDE/mozilla-config.h"
if [ "$(grep -cE '^#define MOZILLA_(UA)?VERSION "' "$INCLUDE/mozilla-config.h")" -ne 2 ]; then
	echo "mozilla-config.h.in has no single '#undef ALLDEFINES' line any more." >&2
	exit 1
fi

# That mozilla-config.h has only the version defines: stop if an app layer file that includes it
# reads any other configure define.
grep -rlF --include='*.c' --include='*.h' --include='*.m' --include='*.mm' 'mozilla-config.h' "$ROOT_DIR/browser" |
	while IFS= read -r file; do
		other="$(grep -owE '(MOZ|MOZILLA|XP|NIGHTLY|RELEASE|EARLY|HAVE|ENABLE)_[A-Za-z0-9_]+' "$file" |
			grep -vx -e MOZILLA_VERSION -e MOZILLA_UAVERSION | sort -u | paste -s -d ' ' -)"
		if [ -n "$other" ]; then
			echo "${file#"$ROOT_DIR"/} reads $other, which the staged mozilla-config.h does not define." >&2
			exit 1
		fi
	done

echo "Staged the Gecko headers from Firefox $FIREFOX_COMMIT in $INCLUDE"
