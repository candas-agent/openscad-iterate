#!/bin/bash
# Render script template — copy into a project as render_<project>.sh,
# then fill in F, the view list, and per-view camera choice.
cd "$(dirname "$0")"

F=<PROJECT>.scad
COMMON="--backend=Manifold --viewall --autocenter --imgsize=1200,1200 --colorscheme=Tomorrow"
ISO="--camera=0,0,0,55,0,25,0"        # general three-quarter view
CROSS="--camera=0,0,0,60,0,45,0"      # quarter-cut cross-section
# CROSS_HALF="--camera=0,0,0,55,0,335,0"  # alternative: half-cut cross-section

# One block per view. Number them "i/N" so a partial/failed run is obvious.

echo "=== 1/N: <view_name> ==="
xvfb-run openscad -o <prefix>_<view_name>.png -D 'view="<view_name>"' $ISO $COMMON $F 2>&1

echo "=== 2/N: <view_name>_cross ==="
xvfb-run openscad -o <prefix>_<view_name>_cross.png -D 'view="<view_name>_cross"' $CROSS $COMMON $F 2>&1

# ... repeat for every named view the .scad file's dispatcher supports ...

echo "=== Done ==="
ls -lh <prefix>_*.png
