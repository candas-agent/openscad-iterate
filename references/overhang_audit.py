#!/usr/bin/env python3
"""
Independent geometric overhang audit for an STL — a supplement to, not a
replacement for, slice_check.sh.

Why this exists: a slicer's automatic support/overhang detection can miss
a real, confirmed overhang — e.g. a narrow post suddenly flaring into a
wider flat flange — even at an extreme threshold angle (verify any
override actually took effect via --export-settings before trusting a
"0 support" result). Slicer heuristics tend to be tuned for gradually-
sloping surfaces (the continuous per-layer angle check) and large
isolated masses (a separate "critical region"/cantilever detector) —
not small, abrupt, single-step overhangs. Real printers often bridge
these fine in practice, so a slicer's tolerance may be a deliberate
design choice on its part, but that's a different confidence level than
"this is verified safe" — don't rely on the slicer's silence alone when
auditing a design for print-readiness (see SKILL.md "Real slicer
verification").

This script instead reads every triangle's face normal directly and
flags any that face downward (into open air, not bed contact) beyond a
given angle from horizontal, independent of any slicer's judgment call.
Run it alongside a real slicer check, not instead of it: the slicer
check still matters for realistic support/adhesion judgment (a flagged
surface here might bridge just fine), and this catches shape classes a
slicer's own heuristics may silently tolerate that a designer still
wants to know about.

Usage: overhang_audit.py file.stl [min_overhang_deg] [bed_epsilon_mm]
  min_overhang_deg: flag surfaces facing more than this many degrees
                     below horizontal (default 1 -- catches everything
                     except perfectly vertical walls)
  bed_epsilon_mm:    triangles within this of the model's global z-min
                     are bed contact, not overhangs (default 0.05)
"""
import sys
import struct
import math


def read_stl(path):
    with open(path, 'rb') as f:
        data = f.read()
    if data[:5] == b'solid':
        text = data.decode(errors='ignore')
        tris = []
        normal = None
        verts = []
        for line in text.splitlines():
            line = line.strip()
            if line.startswith('facet normal'):
                normal = tuple(float(x) for x in line.split()[2:5])
                verts = []
            elif line.startswith('vertex'):
                verts.append(tuple(float(x) for x in line.split()[1:4]))
            elif line.startswith('endfacet'):
                tris.append((normal, verts))
        return tris
    n = struct.unpack('<I', data[80:84])[0]
    tris = []
    off = 84
    for _ in range(n):
        floats = struct.unpack('<12f', data[off:off + 48])
        normal = floats[0:3]
        verts = [floats[3:6], floats[6:9], floats[9:12]]
        tris.append((normal, verts))
        off += 50
    return tris


def tri_area(v):
    ax, ay, az = v[1][0] - v[0][0], v[1][1] - v[0][1], v[1][2] - v[0][2]
    bx, by, bz = v[2][0] - v[0][0], v[2][1] - v[0][1], v[2][2] - v[0][2]
    cx = ay * bz - az * by
    cy = az * bx - ax * bz
    cz = ax * by - ay * bx
    return 0.5 * math.sqrt(cx * cx + cy * cy + cz * cz)


def audit(path, min_overhang_deg=1.0, bed_epsilon=0.05):
    tris = read_stl(path)
    z_min = min(v[2] for _, verts in tris for v in verts)
    flagged = []
    for normal, verts in tris:
        nx, ny, nz = normal
        norm = math.sqrt(nx * nx + ny * ny + nz * nz)
        if norm == 0:
            continue
        nz_n = nz / norm
        if nz_n < -math.sin(math.radians(min_overhang_deg)):
            z_avg = sum(v[2] for v in verts) / 3
            if z_avg <= z_min + bed_epsilon:
                continue  # bed contact, not a real overhang
            angle = math.degrees(math.asin(-nz_n))
            flagged.append((angle, z_avg, tri_area(verts)))
    return tris, z_min, flagged


if __name__ == '__main__':
    path = sys.argv[1]
    min_deg = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
    bed_eps = float(sys.argv[3]) if len(sys.argv) > 3 else 0.05
    tris, z_min, flagged = audit(path, min_deg, bed_eps)
    flagged.sort(key=lambda t: -t[2])
    total_area = sum(f[2] for f in flagged)
    print(f"{path}: z_min={z_min:.2f}, {len(tris)} triangles, "
          f"{len(flagged)} elevated downward-facing triangles, "
          f"total overhang area={total_area:.1f}mm^2")
    for angle, z, area in flagged[:15]:
        print(f"  angle_from_horizontal={angle:5.1f} deg  z~{z:6.2f}  area={area:6.2f}mm^2")
    if flagged:
        sys.exit(1)
