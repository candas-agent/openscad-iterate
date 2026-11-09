# Working conventions for this project

## What this is
<One paragraph: what the part is, what it's for, what printer/material it
targets. State what `SPECS.md` holds (dimensions) versus what this file
holds (how we work).>

## The iterate loop
Write `.scad` → render PNG → look at the render → adjust. Do not describe a
change as done until a render has been looked at. Renders are cheap.

```bash
cd <project-path>
bash render_<project>.sh                      # all <N> views
```

Single view:
```bash
xvfb-run openscad -o out.png -D 'view="<name>"' \
  --camera=0,0,0,55,0,25,0 --viewall --autocenter \
  --imgsize=1200,1200 --colorscheme=Tomorrow <file>.scad
```

Views: `<list every view name the .scad dispatcher supports>`

STL/3MF export — use the `_print` views, NOT the plain design/assembly
views, if those differ (see "Print orientation" below):
```bash
bash export_stl.sh                              # every part + combined 3MF
# or individually:
xvfb-run openscad -o <part>.stl -D 'view="<name>_print"' <file>.scad
```

## Camera framing
Always pass `--viewall --autocenter` and let OpenSCAD fit the model. The
`--camera` argument then only sets rotation (`0,0,0,<rot_x>,0,<rot_z>,0`);
distance is ignored.

- General three-quarter view: `rot_x=55, rot_z=25`.
- Cross-section views: `rot_x=<>, rot_z=<>` — <note what cut plane this looks
  into, and which helper module produces it>.

## Design invariants
These were each arrived at deliberately — check before changing:
- **<Invariant>.** <Why — what it prevents, or what earlier wrong attempt it
  replaced. Reference a photo/spec file if one settled it.>
- **<Invariant>.**
- **<Invariant>.**

## Verifying renders honestly
<List any features specific to this part that are hard to see at render
scale — small pockets, thin walls, overlapping transparent parts in an
assembled view — and name the view or check that actually confirms them.
Say "present but not clearly visible at this scale" rather than "verified"
for anything not actually confirmed this way.>

## Housekeeping
Renders overwrite in place, so stale PNGs from an older geometry can linger
if a view gets renamed or dropped. After a design change, re-run the full
script rather than a subset.

## Print orientation
<For each printed part, state whether its `_Print()` module is a no-op
(already flat-bottomed as modeled) or an actual rotation, and why. For any
real rotation, record what was independently verified (footprint render +
bed-level render) vs. what's inferred/unverified (e.g. small internal
pocket behavior) — be explicit about the difference rather than presenting
both with equal confidence. Combined 3MF layout (if multiple parts) and
its approximate footprint dimensions go here too.>

## Combined 3MF
<Note the `all_print` view / export command, the combined footprint size,
and the caveat that it exports as one object with N disconnected shells —
most slicers need an explicit "split to objects" step, it's not automatic.>

## Test-fit hardware (if this is a multi-part assembly with fasteners)
<If fasteners connect the parts, note the stand-in hardware module(s), which
views include them (e.g. `assembled_bolts`, `assembled_bolts_cross`), and
that they are for interference checks only — never exported or printed.
Record any reach/interference findings here, but verify against a real
print before treating a computed finding as confirmed — see the skill's
"Interference/reachability checks are a hint, not a verdict" section.>

## Open items
<Anything still pending before this is print-ready — e.g. "no reference
photo of the real part yet", "dimensions not yet verified against the
physical part", "STL not yet exported".>
