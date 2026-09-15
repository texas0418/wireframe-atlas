#!/usr/bin/env python3
"""Read GeoJSONSeq on stdin, emit named label POINTS on stdout.

Points pass through; polygons become their (vertex-average) centroid, which is
plenty for placing a label; lines and unnamed features are dropped.
"""
import json, sys

def ring_centroid(ring):
    n = max(len(ring) - 1, 1)  # last vertex repeats the first
    return [sum(p[0] for p in ring[:n]) / n, sum(p[1] for p in ring[:n]) / n]

for line in sys.stdin:
    line = line.strip().lstrip("\x1e")
    if not line:
        continue
    try:
        f = json.loads(line)
    except json.JSONDecodeError:
        continue
    props = f.get("properties") or {}
    name = props.get("name")
    if not name:
        continue
    g = f.get("geometry") or {}
    t = g.get("type")
    if t == "Point":
        pt = g["coordinates"]
    elif t == "Polygon" and g["coordinates"]:
        pt = ring_centroid(g["coordinates"][0])
    elif t == "MultiPolygon" and g["coordinates"]:
        biggest = max(g["coordinates"], key=lambda poly: len(poly[0]))
        pt = ring_centroid(biggest[0])
    else:
        continue
    sys.stdout.write(json.dumps({
        "type": "Feature", "properties": props,
        "geometry": {"type": "Point", "coordinates": pt},
    }, separators=(",", ":")) + "\n")
