#!/usr/bin/env python3
"""Build the client-side search index from the exported geojsonseq layers.

Reads places/parklabels/poipoints/roads geojsonseq in data/, writes gzipped
JSON shards to site/search/<a-z|0>.bin, sharded by first character of the
normalized name so the page only fetches the shard it needs.

Entry: [name, kind, lon, lat]
kind: c city/town, s suburb/village, r road, k park, p poi
"""
import gzip, json, os, sys, unicodedata

DATA = os.path.join(os.path.dirname(__file__), "..", "data")
OUT = os.path.join(os.path.dirname(__file__), "..", "site", "search")


def norm(s):
    s = unicodedata.normalize("NFD", s.lower())
    return "".join(c for c in s if not unicodedata.combining(c))


def lines(fn):
    path = os.path.join(DATA, fn)
    if not os.path.exists(path):
        return
    with open(path) as f:
        for line in f:
            line = line.strip().lstrip("\x1e")
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                continue


def line_mid(geom):
    if geom["type"] == "LineString":
        cs = geom["coordinates"]
    elif geom["type"] == "MultiLineString" and geom["coordinates"]:
        cs = max(geom["coordinates"], key=len)
    else:
        return None
    return cs[len(cs) // 2]


shards = {}
seen_roads = set()
counts = {}


def add(name, kind, lon, lat):
    n = norm(name)
    if not n:
        return
    ch = n[0] if "a" <= n[0] <= "z" else "0"
    shards.setdefault(ch, []).append([name, kind, round(lon, 5), round(lat, 5)])
    counts[kind] = counts.get(kind, 0) + 1


for f in lines("places.geojsonseq"):
    p = f.get("properties") or {}
    if p.get("name") and f["geometry"]["type"] == "Point":
        lon, lat = f["geometry"]["coordinates"]
        kind = "c" if p.get("place") in ("city", "town") else "s"
        add(p["name"], kind, lon, lat)

for f in lines("parklabels.geojsonseq"):
    p = f.get("properties") or {}
    if p.get("name"):
        lon, lat = f["geometry"]["coordinates"]
        add(p["name"], "k", lon, lat)

for f in lines("poipoints.geojsonseq"):
    p = f.get("properties") or {}
    if p.get("name"):
        lon, lat = f["geometry"]["coordinates"]
        add(p["name"], "p", lon, lat)

# Roads: one entry per name per ~0.1 degree cell, so a long street yields a
# few entries across town rather than one per OSM segment. The cell dedupe is
# global, so border roads appearing in two state extracts collapse to one.
def add_roads(fn):
    for f in lines(fn):
        p = f.get("properties") or {}
        name = p.get("name")
        if not name:
            continue
        mid = line_mid(f.get("geometry") or {})
        if not mid:
            continue
        lon, lat = mid[0], mid[1]
        key = (norm(name), round(lon * 10), round(lat * 10))
        if key in seen_roads:
            continue
        seen_roads.add(key)
        add(name, "r", lon, lat)

def add_places(fn):
    for f in lines(fn):
        p = f.get("properties") or {}
        if p.get("name") and f["geometry"]["type"] == "Point":
            lon, lat = f["geometry"]["coordinates"]
            add(p["name"], "c" if p.get("place") in ("city", "town") else "s", lon, lat)

add_roads("roads.geojsonseq")

# Per-state skeleton exports (see build-state.sh)
SRCDIR = os.path.join(DATA, "search-src")
if os.path.isdir(SRCDIR):
    for fn in sorted(os.listdir(SRCDIR)):
        rel = os.path.join("search-src", fn)
        if fn.endswith("-roads.geojsonseq"):
            add_roads(rel)
        elif fn.endswith("-places.geojsonseq"):
            add_places(rel)

os.makedirs(OUT, exist_ok=True)
for old in os.listdir(OUT):
    if old.endswith(".bin"):
        os.remove(os.path.join(OUT, old))
total = 0
for ch, entries in sorted(shards.items()):
    entries.sort(key=lambda e: e[0])
    blob = gzip.compress(json.dumps(entries, separators=(",", ":")).encode(), 9)
    with open(os.path.join(OUT, ch + ".bin"), "wb") as f:
        f.write(blob)
    total += len(blob)
    print(f"{ch}: {len(entries)} entries, {len(blob)//1024}KB")
print("kinds:", counts, "| shards total:", total // 1024, "KB gz")
