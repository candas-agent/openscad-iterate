#!/bin/bash
# Slice-check template — copy into a project's tools/ as slice_check.sh,
# fill in ORCA/MACH/PROC/FIL paths for the project's actual OrcaSlicer
# install (see references/orca_slicer_setup.md if it isn't set up yet).
#
# Slices each given STL individually and reports three signals together
# — see SKILL.md "Real slicer verification": no single one is reliable
# alone.
#   1. actual support scaffolding generated (TYPE:Support gcode lines)
#   2. bridging used instead (FEATURE: Bridge / FEATURE: Internal Bridge)
#      -- a short-span gap the slicer decided to print via speed/pattern
#      changes rather than scaffolding; usually fine, but a check that
#      only greps for TYPE:Support can't tell "handled via bridging"
#      apart from "never even considered" -- both show up as "0 support".
#   3. an independent geometric overhang audit (overhang_audit.py) that
#      doesn't depend on this slicer's judgment calls at all -- catches
#      shape classes a slicer's own auto-support/auto-bridge heuristics
#      tolerate without any gcode marker. This one WILL over-flag small
#      round/hex hole ceilings and already-verified gradual tapers -- it
#      needs human judgment, it's a completeness net, not a pass/fail
#      gate.
#
# Different slicers (and different versions/forks of the "same" slicer)
# can disagree on borderline calls -- treat a clean result across all
# three signals as strong evidence, not proof. For a shape sitting near
# a threshold, prefer redesigning the overhang away over trusting any
# one tool's silence.
#
# Usage: ./slice_check.sh file1.stl [file2.stl ...]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ORCA="$HERE/OrcaSlicer/squashfs-root/bin/orca-slicer"                    # <-- adjust path
export LD_LIBRARY_PATH="$HERE/OrcaSlicer/squashfs-root/lib/orca-runtime:$HERE/OrcaSlicer/squashfs-root/bin:/tmp/apt-user/extracted/usr/lib/x86_64-linux-gnu"  # <-- adjust path
DATADIR=/tmp/orca_data_<PROJECT>                                         # <-- pick a stable per-project datadir
MACH="$HERE/OrcaSlicer/squashfs-root/resources/profiles/BBL/machine/Bambu Lab X1 Carbon 0.4 nozzle.json"   # <-- pick the actual printer
PROC="$HERE/OrcaSlicer/squashfs-root/resources/profiles/BBL/process/0.20mm Standard @BBL X1C.json"          # <-- pick the actual process profile
FIL="$HERE/OrcaSlicer/squashfs-root/resources/profiles/BBL/filament/Bambu PLA Basic @BBL X1C.json"          # <-- pick the actual filament

for stl in "$@"; do
    name=$(basename "$stl" .stl)
    outdir=$(mktemp -d /tmp/orca_check_XXXX)
    timeout 60 xvfb-run "$ORCA" \
        --datadir "$DATADIR" \
        --load-settings "$PROC;$MACH" \
        --load-filaments "$FIL" \
        --orient 0 --ensure-on-bed \
        --enable-support=1 "--support-type=normal(auto)" --support-critical-regions-only=0 \
        --outputdir "$outdir" \
        --slice 0 \
        "$stl" > "$outdir/run.log" 2>&1
    rc=$?
    warn=$(python3 -c "import json,sys
try:
    d=json.load(open('$outdir/result.json'))
    print(d['sliced_plates'][0].get('warning_message',''))
except Exception as e:
    print('PARSE_ERROR:', e)
" 2>/dev/null)
    if [ -f "$outdir/plate_1.gcode" ]; then
        supcount=$(grep -c "TYPE:Support" "$outdir/plate_1.gcode")
        bridgecount=$(grep -c "FEATURE: Bridge\|FEATURE: Internal Bridge" "$outdir/plate_1.gcode")
    else
        supcount="N/A"
        bridgecount="N/A"
    fi
    echo "=== $name ==="
    echo "  slicer: exit=$rc  support_lines=$supcount  bridge_features=$bridgecount  warning=[$warn]"
    echo "  geometric audit (independent of slicer judgment):"
    python3 "$HERE/overhang_audit.py" "$stl" 1 | sed 's/^/    /'
    rm -rf "$outdir"
done
