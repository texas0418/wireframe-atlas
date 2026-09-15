# Atlanta Wireframe

A 3D wireframe of metro Atlanta — every street and building drawn as light on black.
Built from OpenStreetMap data, rendered with MapLibre GL, served as a single static
PMTiles file. No server code, no API keys, no per-view cost.

## Rebuild The Tiles

```
cd data
curl -L -O https://download.geofabrik.de/north-america/us/georgia-latest.osm.pbf
../tools/build-tiles.sh
```

Needs `osmium-tool` and `tippecanoe` (both via Homebrew). Output is `site/atl.pmtiles`.
To widen the coverage area, change `BBOX` in `tools/build-tiles.sh` — or swap the
Geofabrik extract for a bigger one and re-run; nothing else changes.

## Deploy

The `site/` folder is the whole deployable. rsync it to the subdomain doc root,
flush the SuperCacher, done. Static assets carry `?v=N` cache busters — bump them
in `index.html` when vendor/ or fonts/ change.

Serving requirement: the host must honor HTTP Range requests on `atl.pmtiles`
(plain nginx static serving does). Viewers stream only the tiles they look at.

## Layers

roads, buildings (extruded, real heights where OSM has them), rails (+ runways),
water, waterway, places. Tiles z8–z14, overzoomed beyond.

Data © OpenStreetMap contributors (ODbL). Glyphs from openmaptiles/fonts (OFL).
