#!/bin/bash
# Add one state's skeleton (roads/rails/water/waterway/places, no buildings)
# as its own tile file: site/tiles/<slug>.pmtiles + manifest + search update.
# Usage: tools/build-state.sh alabama   (slug = Geofabrik us/ name)
# Nightly cadence: one or two states, ~60-150MB upload each. Georgia's full
# detail lives in the main atl.pmtiles and is untouched by this.
set -euo pipefail
SLUG=$1
cd "$(dirname "$0")/../data"
mkdir -p states-src search-src ../site/tiles

echo "== $SLUG: download =="
curl -sL -C - -o "states-src/$SLUG.osm.pbf" \
  "https://download.geofabrik.de/north-america/us/$SLUG-latest.osm.pbf" || true
osmium fileinfo "states-src/$SLUG.osm.pbf" >/dev/null  # fails loudly on a bad/partial file
ls -lh "states-src/$SLUG.osm.pbf"

echo "== $SLUG: filter =="
osmium tags-filter -O "states-src/$SLUG.osm.pbf" \
  w/highway \
  w/railway=rail,light_rail,subway,tram w/aeroway=runway,taxiway \
  a/natural=water a/landuse=reservoir,basin \
  w/waterway=river,canal \
  n/place=city,town,village,suburb \
  -o tmp-skel.osm.pbf
osmium tags-filter -O tmp-skel.osm.pbf w/highway -o tmp-roads.osm.pbf
osmium tags-filter -O tmp-skel.osm.pbf w/railway=rail,light_rail,subway,tram w/aeroway=runway,taxiway -o tmp-rails.osm.pbf
osmium tags-filter -O tmp-skel.osm.pbf a/natural=water a/landuse=reservoir,basin -o tmp-water.osm.pbf
osmium tags-filter -O tmp-skel.osm.pbf w/waterway=river,canal -o tmp-waterway.osm.pbf
osmium tags-filter -O tmp-skel.osm.pbf n/place=city,town,village,suburb -o tmp-places.osm.pbf

echo "== $SLUG: export =="
for f in tmp-roads tmp-rails tmp-water tmp-waterway tmp-places; do
  osmium export -O "$f.osm.pbf" -f geojsonseq -o "$f.geojsonseq"
done

echo "== $SLUG: tippecanoe =="
tippecanoe -f -q -o tmp-roads.pmtiles -l roads -Z5 -z14 \
  -y highway -y name -y ref \
  --simplification=4 --coalesce --reorder \
  --drop-densest-as-needed --extend-zooms-if-still-dropping \
  -j '{ "roads": [ "any",
        [ "all", [ "<=", "$zoom", 7 ], [ "in", "highway", "motorway", "motorway_link" ] ],
        [ "all", [ ">=", "$zoom", 8 ], [ "<=", "$zoom", 9 ], [ "in", "highway", "motorway", "motorway_link", "trunk", "trunk_link" ] ],
        [ "all", [ ">=", "$zoom", 10 ], [ "<=", "$zoom", 11 ], [ "in", "highway", "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link" ] ],
        [ "all", [ ">=", "$zoom", 12 ], [ "<=", "$zoom", 12 ], [ "!in", "highway", "service", "track", "path", "footway", "cycleway", "steps", "pedestrian", "bridleway", "corridor" ] ],
        [ ">=", "$zoom", 13 ] ] }' \
  tmp-roads.geojsonseq
tippecanoe -f -q -o tmp-rails.pmtiles -l rails -Z9 -z14 -y railway -y aeroway --simplification=4 \
  --drop-densest-as-needed tmp-rails.geojsonseq
tippecanoe -f -q -o tmp-water.pmtiles -l water -Z6 -z14 --simplification=4 --drop-smallest-as-needed -X tmp-water.geojsonseq
tippecanoe -f -q -o tmp-waterway.pmtiles -l waterway -Z9 -z14 -y waterway -y name --simplification=4 \
  --drop-densest-as-needed tmp-waterway.geojsonseq
tippecanoe -f -q -o tmp-places.pmtiles -l places -Z5 -z14 -y place -y name -r1 \
  -j '{ "places": [ "any", [ "all", [ "<=", "$zoom", 7 ], [ "==", "place", "city" ] ], [ ">=", "$zoom", 8 ] ] }' \
  tmp-places.geojsonseq

echo "== $SLUG: join + manifest + search =="
tile-join -f -q -o "../site/tiles/$SLUG.pmtiles" \
  tmp-roads.pmtiles tmp-rails.pmtiles tmp-water.pmtiles tmp-waterway.pmtiles tmp-places.pmtiles
ls -lh "../site/tiles/$SLUG.pmtiles"
cp -f tmp-roads.geojsonseq "search-src/$SLUG-roads.geojsonseq"
cp -f tmp-places.geojsonseq "search-src/$SLUG-places.geojsonseq"
python3 - <<'EOF'
import json, os, time
tiles = sorted(f[:-8] for f in os.listdir("../site/tiles") if f.endswith(".pmtiles"))
with open("../site/tiles/manifest.json", "w") as f:
    json.dump({"v": int(time.time()), "states": tiles}, f)
print("manifest:", tiles)
EOF
python3 ../tools/build-search.py | tail -2
echo "STATE-DONE $SLUG"
