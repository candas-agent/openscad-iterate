#!/bin/bash
# Export script template — copy into a project as export_stl.sh, then fill
# in F, the per-part list, and the combined-layout view.
#
# Exports each printed part as an individual STL using its `_print` view
# (print-oriented — see SKILL.md "STL export and print orientation"), plus
# one combined 3MF with all parts laid out non-overlapping on a shared
# virtual bed via an `all_print` view. No camera flags needed for STL/3MF
# output — geometry only.
cd "$(dirname "$0")"
F=<PROJECT>.scad

echo "=== 1/N: <part_name> ==="
xvfb-run openscad -o <part_name>.stl -D 'view="<part_name>_print"' --backend=Manifold $F 2>&1

# ... repeat per printed part ...

echo "=== N/N: combined 3MF (all parts, one file) ==="
xvfb-run openscad -o <project>_all.3mf -D 'view="all_print"' --backend=Manifold $F 2>&1

echo "=== Done ==="
ls -lh *.stl *.3mf
