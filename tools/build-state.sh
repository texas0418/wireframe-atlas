#!/bin/bash
# Add one COMPLETE state (roads/rails/water/waterway/places + buildings,
# parks, POIs) as its own tile file: site/tiles/<slug>.pmtiles + manifest +
# search update. Usage: tools/build-state.sh alabama  (slug = Geofabrik us/ name)
# Nightly cadence: one or two states, ~150-250MB upload each. Georgia's
# detail lives in the main atl.pmtiles and is untouched by this.
set -euo pipefail
SLUG=$1
cd "$(dirname "$0")/../data"
mkdir -p states-src search-src ../site/tiles

# Geofabrik transfers stall on a weak link. Retry transient failures and
# count a <10KB/s crawl for 30s as one, so --retry resumes instead of the
# whole build dying at 80% (cost us PA, MA and HI before this existed).
CURL_HARDEN="--retry 6 --retry-delay 5 --retry-all-errors --speed-limit 10240 --speed-time 30"
echo "== $SLUG: download =="
# A valid existing file is used as-is. Never resume-append: Geofabrik files
# change daily, so -C - onto an older copy corrupts it (learned the hard way).
if ! osmium fileinfo "states-src/$SLUG.osm.pbf" >/dev/null 2>&1; then
  # Resolve -latest to its DATED url. That file never changes, so resuming
  # against it is safe; resuming against -latest is what corrupts a download
  # when the daily rebuild lands mid-transfer.
  PINNED=$(curl -sI "https://download.geofabrik.de/north-america/us/$SLUG-latest.osm.pbf" \
           | awk '/^[Ll]ocation:/{print $2}' | tr -d '\r' | sed 's:/*$::')
  [ -n "$PINNED" ] || PINNED="https://download.geofabrik.de/north-america/us/$SLUG-latest.osm.pbf"
  STAMP="states-src/$SLUG.url"
  if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$PINNED" ] && [ -f "states-src/$SLUG.osm.pbf.part" ]; then
    echo "resuming $(du -h "states-src/$SLUG.osm.pbf.part" | cut -f1) of $PINNED"
    curl -sL -C - $CURL_HARDEN -o "states-src/$SLUG.osm.pbf.part" "$PINNED"
  else
    rm -f "states-src/$SLUG.osm.pbf.part"
    echo "$PINNED" > "$STAMP"
    curl -sL $CURL_HARDEN -o "states-src/$SLUG.osm.pbf.part" "$PINNED"
  fi
  mv -f "states-src/$SLUG.osm.pbf.part" "states-src/$SLUG.osm.pbf"
fi
osmium fileinfo "states-src/$SLUG.osm.pbf" >/dev/null  # fails loudly on a bad file
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
osmium tags-filter -O "states-src/$SLUG.osm.pbf" a/building -o tmp-bldg.osm.pbf
osmium tags-filter -O "states-src/$SLUG.osm.pbf" \
  a/leisure=park,golf_course,nature_reserve,garden,recreation_ground,stadium \
  a/landuse=cemetery a/boundary=national_park -o tmp-parks.osm.pbf
osmium tags-filter -O "states-src/$SLUG.osm.pbf" \
  nwr/shop \
  nwr/amenity=restaurant,cafe,bar,pub,fast_food,food_court,ice_cream,cinema,theatre,nightclub,library,pharmacy,hospital,clinic,dentist,veterinary,bank,fuel,charging_station,post_office,school,college,university,place_of_worship,police,fire_station,townhall,courthouse,marketplace \
  nwr/tourism=hotel,motel,museum,gallery,attraction,zoo,theme_park \
  nwr/leisure=fitness_centre -o tmp-pois.osm.pbf

echo "== $SLUG: export =="
for f in tmp-roads tmp-rails tmp-water tmp-waterway tmp-places tmp-bldg tmp-parks tmp-pois; do
  osmium export -O "$f.osm.pbf" -f geojsonseq -o "$f.geojsonseq"
done
python3 ../tools/labelpoints.py < tmp-parks.geojsonseq > tmp-parklabels.geojsonseq
python3 ../tools/labelpoints.py < tmp-pois.geojsonseq > tmp-poipoints.geojsonseq

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
tippecanoe -f -q -o tmp-bldg.pmtiles -l buildings -Z13 -z14 \
  -y building -y height -y building:levels -y name \
  --drop-smallest-as-needed --coalesce-smallest-as-needed \
  --maximum-tile-bytes=750000 tmp-bldg.geojsonseq
tippecanoe -f -q -o tmp-parks.pmtiles -l parks -Z10 -z14 -y leisure -y landuse \
  --simplification=4 --drop-smallest-as-needed tmp-parks.geojsonseq
tippecanoe -f -q -o tmp-parklabels.pmtiles -l parklabels -Z10 -z14 -y name -y leisure -y landuse -r1 tmp-parklabels.geojsonseq
tippecanoe -f -q -o tmp-poipoints.pmtiles -l pois -Z14 -z14 -y name -y shop -y amenity -y tourism -y leisure -r1 \
  --drop-densest-as-needed tmp-poipoints.geojsonseq

echo "== $SLUG: join + manifest + search =="
tile-join -f -q -o "../site/tiles/$SLUG.pmtiles" \
  tmp-roads.pmtiles tmp-rails.pmtiles tmp-water.pmtiles tmp-waterway.pmtiles tmp-places.pmtiles \
  tmp-bldg.pmtiles tmp-parks.pmtiles tmp-parklabels.pmtiles tmp-poipoints.pmtiles
ls -lh "../site/tiles/$SLUG.pmtiles"
cp -f tmp-roads.geojsonseq "search-src/$SLUG-roads.geojsonseq"
cp -f tmp-places.geojsonseq "search-src/$SLUG-places.geojsonseq"
cp -f tmp-parklabels.geojsonseq "search-src/$SLUG-parks.geojsonseq"
cp -f tmp-poipoints.geojsonseq "search-src/$SLUG-pois.geojsonseq"
python3 - <<'EOF'
import json, os, time
tiles = sorted(f[:-8] for f in os.listdir("../site/tiles") if f.endswith(".pmtiles"))
with open("../site/tiles/manifest.json", "w") as f:
    json.dump({"v": int(time.time()), "states": tiles}, f)
print("manifest:", tiles)
EOF
python3 ../tools/build-search.py | tail -2
echo "STATE-DONE $SLUG"
