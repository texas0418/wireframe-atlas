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
# ATLAS_UNMETERED=1 for a known-uncapped line (shore leave at home, a
# friend's wifi). The time window below only describes the VESSEL's plan.
WIFI_IP=$(ipconfig getifaddr en0 2>/dev/null)
H=$(date +%H)
if [ "${ATLAS_UNMETERED:-0}" = 1 ]; then CARRIER=${WIFI_IP:+wifi}; CARRIER=${CARRIER:-wired}; METERED=no
elif [ -z "$WIFI_IP" ]; then CARRIER=wired; METERED=no
elif [ "$H" -ge 23 ] || [ "$H" -lt 11 ]; then CARRIER=wifi; METERED=no
else CARRIER=wifi; METERED=yes; fi
echo "carrier=$CARRIER metered=$METERED time=$(date +%H:%M)"

# Resolve + measure via the shared resolver (handles Geofabrik's flaky
# -latest alias by falling back to the directory index).
RES=$(bash tools/resolve-extract.sh "$SLUG") || { echo "ABORT: could not resolve $SLUG"; exit 1; }
PINNED=${RES%% *}
BYTES=${RES##* }
MB=$(awk -v b="$BYTES" 'BEGIN{printf "%.0f", b/1048576}')
case "$MB" in ''|*[!0-9]*) echo "ABORT: measurement failed for $SLUG (got '${MB}')"; exit 1;; esac
echo "$SLUG measured ${MB}MB"

# --- on metered wifi a quote is mandatory and must cover the download
if [ "$METERED" = yes ]; then
  if [ "$QUOTE" -eq 0 ]; then echo "ABORT: metered - pass a quote in MB"; exit 1; fi
  if [ "$MB" -ge "$QUOTE" ]; then
    echo "ABORT: ${MB}MB download does not fit a ${QUOTE}MB quote (leave room for chat)"; exit 1
  fi
  # netbudget was retired 2026-10-04 (no-op stub). capwatch.sh is the real
  # enforcement; jobreg registers this transfer so it can cut Wi-Fi at +20%.
  ~/Documents/data-usage/jobreg.sh "atlas-$SLUG" "$QUOTE" 2>&1 | tail -1
fi

bash tools/build-state.sh "$SLUG" >"/tmp/atlas-$SLUG.log" 2>&1
if grep -q STATE-DONE "/tmp/atlas-$SLUG.log"; then
  echo "$SLUG OK $(ls -lh "site/tiles/$SLUG.pmtiles" | awk '{print $5}')"
else
  echo "$SLUG FAILED: $(tail -2 "/tmp/atlas-$SLUG.log" | tr '\n' ' ')"
fi
echo "files: $(ls site/tiles/*.pmtiles | wc -l | tr -d ' ')  total: $(du -sh site/tiles | cut -f1)"
[ "$METERED" = yes ] && ~/Documents/data-usage/jobreg.sh --end "atlas-$SLUG" 2>&1 | tail -1
exit 0
