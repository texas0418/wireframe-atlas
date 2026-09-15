#!/bin/bash
# Build atl.pmtiles from georgia-latest.osm.pbf
# Bbox covers the full metro: Newnan/Cartersville/Gainesville/Covington corners.
set -euo pipefail
cd "$(dirname "$0")/../data"

BBOX="-84.97,33.30,-83.75,34.36"

echo "== 1/4 clip metro =="
osmium extract -O -b "$BBOX" georgia-latest.osm.pbf -o metro.osm.pbf
osmium fileinfo -e metro.osm.pbf | grep -E "Number of|Bounding"

echo "== 2/4 filter + export layers =="
osmium tags-filter -O metro.osm.pbf w/highway -o roads.osm.pbf
osmium tags-filter -O metro.osm.pbf a/building -o buildings.osm.pbf
osmium tags-filter -O metro.osm.pbf w/railway=rail,light_rail,subway,tram w/aeroway=runway,taxiway -o rails.osm.pbf
osmium tags-filter -O metro.osm.pbf a/natural=water a/landuse=reservoir,basin -o water.osm.pbf
osmium tags-filter -O metro.osm.pbf w/waterway=river,canal,stream -o waterway.osm.pbf
osmium tags-filter -O metro.osm.pbf n/place=city,town,village,suburb -o places.osm.pbf
osmium tags-filter -O metro.osm.pbf \
  a/leisure=park,golf_course,nature_reserve,garden,recreation_ground,stadium \
  a/landuse=cemetery a/boundary=national_park -o parks.osm.pbf
osmium tags-filter -O metro.osm.pbf \
  nwr/shop \
  nwr/amenity=restaurant,cafe,bar,pub,fast_food,food_court,ice_cream,cinema,theatre,nightclub,library,pharmacy,hospital,clinic,dentist,veterinary,bank,fuel,charging_station,post_office,school,college,university,place_of_worship,police,fire_station,townhall,courthouse,marketplace \
  nwr/tourism=hotel,motel,museum,gallery,attraction,zoo,theme_park \
  nwr/leisure=fitness_centre -o pois.osm.pbf

for f in roads buildings rails water waterway places parks pois; do
  osmium export -O "$f.osm.pbf" -f geojsonseq -o "$f.geojsonseq"
  echo "$f: $(du -h "$f.geojsonseq" | cut -f1)"
done

echo "== 3/4 tippecanoe =="
# Roads: majors appear early, everything by z13. $zoom filters thin low zooms.
tippecanoe -f -o roads.pmtiles -l roads -Z8 -z14 \
  -y highway -y name -y ref \
  --simplification=4 --coalesce --reorder \
  --drop-densest-as-needed --extend-zooms-if-still-dropping \
  -j '{ "roads": [ "any",
        [ "all", [ "<=", "$zoom", 9 ], [ "in", "highway", "motorway", "motorway_link", "trunk", "trunk_link" ] ],
        [ "all", [ ">=", "$zoom", 10 ], [ "<=", "$zoom", 11 ], [ "in", "highway", "motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link" ] ],
        [ "all", [ ">=", "$zoom", 12 ], [ "<=", "$zoom", 12 ], [ "!in", "highway", "service", "track", "path", "footway", "cycleway", "steps", "pedestrian", "bridleway", "corridor" ] ],
        [ ">=", "$zoom", 13 ] ] }' \
  roads.geojsonseq

tippecanoe -f -o buildings.pmtiles -l buildings -Z13 -z14 \
  -y building -y height -y building:levels -y name \
  --drop-smallest-as-needed --coalesce-smallest-as-needed \
  --maximum-tile-bytes=750000 \
  buildings.geojsonseq

tippecanoe -f -o rails.pmtiles -l rails -Z9 -z14 -y railway -y aeroway --simplification=4 rails.geojsonseq
tippecanoe -f -o water.pmtiles -l water -Z8 -z14 --simplification=4 --drop-smallest-as-needed -X water.geojsonseq
tippecanoe -f -o waterway.pmtiles -l waterway -Z9 -z14 -y waterway -y name --simplification=4 waterway.geojsonseq
tippecanoe -f -o places.pmtiles -l places -Z8 -z14 -y place -y name -B0 places.geojsonseq

python3 ../tools/labelpoints.py < parks.geojsonseq > parklabels.geojsonseq
python3 ../tools/labelpoints.py < pois.geojsonseq > poipoints.geojsonseq
tippecanoe -f -o parks-poly.pmtiles -l parks -Z10 -z14 -y leisure -y landuse \
  --simplification=4 --drop-smallest-as-needed parks.geojsonseq
tippecanoe -f -o parklabels.pmtiles -l parklabels -Z10 -z14 -y name -y leisure -y landuse -r1 parklabels.geojsonseq
tippecanoe -f -o poipoints.pmtiles -l pois -Z14 -z14 -y name -y shop -y amenity -y tourism -y leisure -r1 \
  --drop-densest-as-needed poipoints.geojsonseq

echo "== 4/4 tile-join =="
tile-join -f -o atl.pmtiles roads.pmtiles buildings.pmtiles rails.pmtiles water.pmtiles waterway.pmtiles places.pmtiles parks-poly.pmtiles parklabels.pmtiles poipoints.pmtiles
ls -lh atl.pmtiles
cp -f atl.pmtiles ../site/atl.pmtiles
echo DONE
