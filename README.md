# Wireframe Atlas

Every street in the United States, drawn as light on black. All fifty states and
the District of Columbia: streets named, buildings extruded to their real heights
where OpenStreetMap knows them, parks, water, rails and runways, and the
businesses of whole cities. Rendered with MapLibre GL from static PMTiles. No
server code, no API keys, no per-view cost.

Live: https://atlas.simonbuilds.app

## Architecture

One tile file per state in `site/tiles/<slug>.pmtiles` (51 files, ~8.4GB), plus
`tiles/manifest.json` listing which states exist. The page reads the manifest and
clones its style layers onto each state source, so adding a state is a file drop
and a manifest bump — no page change.

Tiles are served from Cloudflare R2 at `tiles.simonbuilds.app`; the page, fonts and
search index stay on SiteGround. `index.html` only points at R2 when it is running
on the atlas hostname, so a local preview reads local files.

Search is a build-time name index (`site/search/<a-z|0>.bin`, gzipped JSON shards
by first letter) covering streets, places, parks and businesses. The browser
fetches one shard per query letter and ranks by prefix then distance from the
current view. Nothing server-side.

Below z5 only the Natural Earth boundary layer draws (`site/boundaries.pmtiles`,
coast/borders/state lines/lakes). Roads begin at z5, buildings and POIs at z13-14.

## Build A State

```
tools/build-guarded.sh <geofabrik-slug> [quote_MB]
```

Resolves the extract, measures it, builds, and updates the manifest and search
shards. Needs `osmium-tool` and `tippecanoe` (Homebrew). One state takes roughly
5-20 minutes depending on size.

Notes that cost real time to learn:

- **Never run two builds at once.** `build-state.sh` uses fixed `tmp-*.osm.pbf`
  names in `data/`, so parallel runs overwrite each other. Chain them.
- **Never edit these scripts while one is running.** Bash reads scripts
  incrementally; an edit shifts byte offsets and corrupts the running copy.
- Geofabrik's `-latest` alias intermittently 301s to itself with a trailing slash
  and loops. `tools/resolve-extract.sh` tries it, then falls back to the newest
  dated file in the directory index. Dated files are immutable, which is also what
  makes `curl -C -` resume safe.
- On a metered connection pass a quote; on a known-uncapped line set
  `ATLAS_UNMETERED=1`. The built-in time window describes a specific vessel's
  data plan, not where you are.

## Deploy

Tiles go straight to R2; the page fetches the manifest from R2 too, so adding a
state needs no SiteGround touch and no cache flush:

```
rclone copy site/tiles r2:wireframe-atlas/tiles --exclude manifest.json
rclone copy site/tiles/manifest.json r2:wireframe-atlas/tiles/
```

**Upload tiles first and the manifest last.** The manifest advertises every state
it lists, so the reverse order serves 404s for anything that has not landed yet.

Page changes (`index.html`, `vendor/`, `fonts/`, `search/`) rsync to the SiteGround
doc root and need a cache flush. Static assets carry `?v=N` busters; bump them when
vendor or fonts change.

Serving requirement either way: HTTP Range requests on the `.pmtiles` files.
Viewers stream only the tiles they look at, typically a few hundred KB per view.

## Layers

roads, buildings, parks, parklabels, pois, rails (+ runways), water, waterway,
places. Tiles z5-z14, overzoomed beyond.

Data © OpenStreetMap contributors (ODbL). Boundaries from Natural Earth (public
domain). Glyphs from openmaptiles/fonts (OFL).
