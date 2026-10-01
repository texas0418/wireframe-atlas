#!/bin/bash
# Resolve a Geofabrik state slug to "<dated_url> <size_bytes>".
#
# Geofabrik's cache is unreliable about the "-latest" alias: it
# intermittently 301s to itself with a trailing slash and loops, for HEAD
# and sometimes for GET. So: try the alias, and when it fails, read the
# directory index and take the newest dated file. The dated files are
# immutable, which is also what makes resume safe.
set -uo pipefail
SLUG=${1:?usage: resolve-extract.sh <slug>}
BASE="https://download.geofabrik.de/north-america/us"

size_of() {  # url -> bytes on stdout, non-zero if unavailable
  local total
  total=$(curl -sL --max-time 30 -r 0-0 -D - -o /dev/null "$1" \
          | awk 'tolower($1)=="content-range:"{print $3}' | awk -F/ 'NF>1{print $2}' \
          | tr -cd '0-9' | tail -1)   # headers carry a trailing \r; strip it
  case "$total" in ''|*[!0-9]*) return 1;; esac
  printf '%s' "$total"
}

# Fast path: the -latest alias, if it actually redirects somewhere real.
EFF=$(curl -sL --max-time 30 -r 0-0 -o /dev/null -w '%{url_effective}' \
      "$BASE/$SLUG-latest.osm.pbf" 2>/dev/null | tr -d '\r' | sed 's:/*$::')
case "$EFF" in
  *"$SLUG-"[0-9][0-9][0-9][0-9][0-9][0-9]".osm.pbf")
    if SZ=$(size_of "$EFF"); then echo "$EFF $SZ"; exit 0; fi ;;
esac

# Fallback: newest dated file in the directory index.
DATED=$(curl -s --max-time 40 "$BASE/" \
        | grep -oE "$SLUG-[0-9]{6}\.osm\.pbf" | sort -u | tail -1)
[ -n "$DATED" ] || { echo "resolve failed: no dated file for $SLUG" >&2; exit 1; }
if SZ=$(size_of "$BASE/$DATED"); then echo "$BASE/$DATED $SZ"; exit 0; fi
echo "resolve failed: $DATED gave no size" >&2; exit 1
