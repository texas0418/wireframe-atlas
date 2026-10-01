#!/bin/bash
# Guarded state build: measure -> verify against budget -> meter -> build.
# Usage: tools/build-guarded.sh <slug> [quote_MB]
#
# Fails CLOSED. A measurement that comes back empty or non-numeric aborts,
# because a silently-skipped guard on a metered night is the whole problem
# this exists to prevent (bit us on utah 09-30: empty measurement, guard
# passed anyway, build ran unchecked).
set -uo pipefail
SLUG=${1:?usage: build-guarded.sh <slug> [quote_MB]}
QUOTE=${2:-0}
cd "$(dirname "$0")/.."

# --- carrier: wired and the free window are both unmetered
WIFI_IP=$(ipconfig getifaddr en0 2>/dev/null)
H=$(date +%H)
if [ -z "$WIFI_IP" ]; then CARRIER=wired; METERED=no
elif [ "$H" -ge 23 ] || [ "$H" -lt 11 ]; then CARRIER=wifi; METERED=no
else CARRIER=wifi; METERED=yes; fi
echo "carrier=$CARRIER metered=$METERED time=$(date +%H:%M)"

if [ -f "$HOME/.claude/netbudget/STOP_NETWORK" ]; then
  echo "ABORT: data gate is armed; Simon clears it"; exit 1
fi

# --- measure, and insist on a real number
# Resolve AND measure with a 1-byte range GET. HEAD is unusable here:
# Geofabrik's cache intermittently 301s -latest to itself with a trailing
# slash, looping forever, while GET follows to the dated file correctly.
HDR=$(curl -sL --max-time 30 -r 0-0 -D - -o /dev/null \
      -w 'EFFECTIVE %{url_effective}\n' \
      "https://download.geofabrik.de/north-america/us/$SLUG-latest.osm.pbf")
PINNED=$(printf '%s\n' "$HDR" | awk '/^EFFECTIVE /{print $2}' | tr -d '\r' | sed 's:/*$::')
if [ -z "$PINNED" ]; then echo "ABORT: could not resolve $SLUG to a dated url"; exit 1; fi
MB=$(printf '%s\n' "$HDR" | awk 'tolower($1)=="content-range:"{print $2}' \
     | awk -F/ '{print $2}' | tr -cd '0-9' | tail -1 | awk '{printf "%.0f", $1/1048576}')
case "$MB" in ''|*[!0-9]*) echo "ABORT: measurement failed for $SLUG (got '${MB}')"; exit 1;; esac
echo "$SLUG measured ${MB}MB"

# --- on metered wifi a quote is mandatory and must cover the download
if [ "$METERED" = yes ]; then
  if [ "$QUOTE" -eq 0 ]; then echo "ABORT: metered - pass a quote in MB"; exit 1; fi
  if [ "$MB" -ge "$QUOTE" ]; then
    echo "ABORT: ${MB}MB download does not fit a ${QUOTE}MB quote (leave room for chat)"; exit 1
  fi
  ~/Documents/scripts/netbudget.sh start "$QUOTE" "atlas-$SLUG" 2>&1 | tail -1
fi

bash tools/build-state.sh "$SLUG" >"/tmp/atlas-$SLUG.log" 2>&1
if grep -q STATE-DONE "/tmp/atlas-$SLUG.log"; then
  echo "$SLUG OK $(ls -lh "site/tiles/$SLUG.pmtiles" | awk '{print $5}')"
else
  echo "$SLUG FAILED: $(tail -2 "/tmp/atlas-$SLUG.log" | tr '\n' ' ')"
fi
echo "files: $(ls site/tiles/*.pmtiles | wc -l | tr -d ' ')  total: $(du -sh site/tiles | cut -f1)"
[ "$METERED" = yes ] && ~/Documents/scripts/netbudget.sh stop 2>&1 | tail -1
exit 0
