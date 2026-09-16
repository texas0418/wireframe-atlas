#!/bin/bash
# National skeleton: roads/rails/water/waterway/places for the whole USA from
# us-latest.osm.pbf, tile-joined with Georgia's detail layers (buildings,
# parks, POIs stay GA-only until each state gets its detail pass).
# NOTE: national waterway keeps river+canal only; per-state detail passes can
# add streams back regionally if wanted.
set -euo pipefail
cd "$(dirname "$0")/../data"

echo "== 1/5 skeleton prefilter (one pass over the 10GB file) =="
osmium tags-filter -O us-latest.osm.pbf \
  w/highway \
  w/railway=rail,light_rail,subway,tram w/aeroway=runway,taxiway \
  a/natural=water a/landuse=reservoir,basin \
  w/waterway=river,canal \
  n/place=city,town,village,suburb \
  -o us-skel.osm.pbf
ls -lh us-skel.osm.pbf

echo "== 2/5 per-layer filter =="
osmium tags-filter -O us-skel.osm.pbf w/highway -o us-roads.osm.pbf
osmium tags-filter -O us-skel.osm.pbf w/railway=rail,light_rail,subway,tram w/aeroway=runway,taxiway -o us-rails.osm.pbf
osmium tags-filter -O us-skel.osm.pbf a/natural=water a/landuse=reservoir,basin -o us-water.osm.pbf
osmium tags-filter -O us-skel.osm.pbf w/waterway=river,canal -o us-waterway.osm.pbf
osmium tags-filter -O us-skel.osm.pbf n/place=city,town,village,suburb -o us-places.osm.pbf

echo "== 3/5 export =="
for f in us-roads us-rails us-water us-waterway us-places; do
  osmium export -O "$f.osm.pbf" -f geojsonseq -o "$f.geojsonseq"
  echo "$f: $(du -h "$f.geojsonseq" | cut -f1)"
done

echo "== 4/5 tippecanoe =="
tippecanoe -f -q -o us-roads.pmtiles -l roads -Z5 -z14 \
  -y highway -y name -y ref \
  --simplification=4 --coalesce --reorder \
  --drop-densest-as-needed --extend-zooms-if-still-dropping \
  -j '{ "roads": [ "any",
        [ "all", [ "<=", "$zoom", 7 ], [ "in", "highway", "motorway", "motorway_link" ] ],
        [ "all", [ ">=", "$zoom", 8 ], [ "<=", "$zoom", 9 ], [ "in", "highway", "motorway", "motorway_link", "trunk", "trunk_link" ] ],
        [ "all", [ ">=", "$zoom", 10 ], [ "<=", "$zoom", 11 ], [ "in", "highway", "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link" ] ],
        [ "all", [ ">=", "$zoom", 12 ], [ "<=", "$zoom", 12 ], [ "!in", "highway", "service", "track", "path", "footway", "cycleway", "steps", "pedestrian", "bridleway", "corridor" ] ],
        [ ">=", "$zoom", 13 ] ] }' \
  us-roads.geojsonseq

tippecanoe -f -q -o us-rails.pmtiles -l rails -Z9 -z14 -y railway -y aeroway --simplification=4 \
  --drop-densest-as-needed us-rails.geojsonseq
tippecanoe -f -q -o us-water.pmtiles -l water -Z6 -z14 --simplification=4 --drop-smallest-as-needed -X us-water.geojsonseq
tippecanoe -f -q -o us-waterway.pmtiles -l waterway -Z9 -z14 -y waterway -y name --simplification=4 \
  --drop-densest-as-needed us-waterway.geojsonseq
tippecanoe -f -q -o us-places.pmtiles -l places -Z5 -z14 -y place -y name -r1 \
  -j '{ "places": [ "any", [ "all", [ "<=", "$zoom", 7 ], [ "==", "place", "city" ] ], [ ">=", "$zoom", 8 ] ] }' \
  us-places.geojsonseq

echo "== 5/5 tile-join with Georgia detail =="
for f in buildings.pmtiles parks-poly.pmtiles parklabels.pmtiles poipoints.pmtiles; do
  [ -f "$f" ] || { echo "MISSING GA LAYER $f - aborting"; exit 1; }
done
tile-join -f -q -o atl.pmtiles \
  us-roads.pmtiles us-rails.pmtiles us-water.pmtiles us-waterway.pmtiles us-places.pmtiles \
  buildings.pmtiles parks-poly.pmtiles parklabels.pmtiles poipoints.pmtiles
ls -lh atl.pmtiles
cp -f atl.pmtiles ../site/atl.pmtiles

echo "== search index (national places + GA detail) =="
cp -f us-places.geojsonseq places.geojsonseq
python3 ../tools/build-search.py | tail -3
echo USA-BUILD-DONE
