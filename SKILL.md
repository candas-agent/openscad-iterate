---
name: openscad-iterate
description: This skill should be used when the user is doing OpenSCAD or parametric 3D-print design work — starting a new OpenSCAD project, asking to "set up rendering", "render this part", "add a view selector", "write a render script", iterating on a .scad file, or reviewing/verifying a 3D-printable design's fit and dimensions.
version: 0.7.0
---

# OpenSCAD Iterative Design Workflow

Captures the render-and-verify workflow for OpenSCAD / 3D-print projects,
independent of what part is being designed. Distilled from two sibling
projects (a hub motor stator and a desk motor mount) built the same way.

## New project setup

When starting a new OpenSCAD project folder, create:

1. `SPECS.md` — measured dimensions and hardware specs. This is data, not
   derived from the code; keep it separate from the `.scad` file.
2. `CLAUDE.md` — this project's working conventions and hard-won design
   invariants. Start from `references/claude_md_template.md`.
3. A `view` variable plus an if/else dispatcher at the bottom of the `.scad`
   file, so any single part or cross-section can be rendered on its own
   instead of only ever rendering everything at once. For an assembly of
   more than one part, see "Multi-part assemblies" below before writing
   the dispatcher.
4. A `render_<project>.sh` script that renders every view in one command.
   Start from `references/render_script_template.sh`.
5. An `export_stl_<project>.sh` (or `export_stl.sh`) script that exports
   every printed part's STL in print orientation (STL only, no 3MF:
   see "Combined multi-part export" below) — see "STL export and print
   orientation". Start from `references/export_stl_template.sh`.

## Evaluate alternatives, don't just implement the first idea

This applies to the *initial* design of a mechanism, not only when
fixing something already broken. For any mechanical choice with more
than one plausible approach — how a screw is captured, which part gets
which mating feature, how a joint is fastened, how a hinge or a
sliding fit works — briefly weigh the realistic alternatives and say
which one wins and why, before modeling it. A sentence naming the
runner-up and why it lost is usually enough; this doesn't need a full
report unless the tradeoffs are genuinely close.

Weigh concrete criteria, not vague ones: part count, hardware sourcing
difficulty (buyable at a hardware store vs. needs machining or a
special order), print orientation/robustness, and — importantly —
whether an established real-world design already solves this exact
problem. A bench vise's screw-capture convention (screw spins in place
at the fixed jaw; only the moving jaw threads) exists for a reason;
reinventing it without checking how the real object works is how a
design ends up with a handle that slides back and forth as the jaws
open, discovered only after it's built. (Concrete case: exactly this —
the first version threaded the screw at the fixed jaw and captured a
sliding collar at the moving jaw, mechanically valid but backwards from
every real vise, causing the handle to travel with the mechanism. Once
named as "screw captured vs. screw threaded, which side does which,"
the fix was obvious and the file already had the exact hole-cutting
code needed — just applied to the other part.)

Retrofitting this reasoning after something's already built and wrong
is strictly more expensive than doing it once up front — one paragraph
of comparison at design time beats a rebuild plus an explanation of why
the rebuild was necessary.

## The iterate loop

Write `.scad` → render a PNG → look at the render → adjust. Never describe a
change as done without having looked at a render of the actual result.
Renders take a fraction of a second — there's no excuse to skip this step
and reason about geometry from the source alone.

```bash
xvfb-run openscad -o out.png -D 'view="<name>"' \
  --backend=Manifold \
  --camera=0,0,0,<rot_x>,0,<rot_z>,0 --viewall --autocenter \
  --imgsize=1200,1200 --colorscheme=Tomorrow <file>.scad
```

Always pass `--viewall --autocenter` and let OpenSCAD fit the model.
Hand-picked camera XYZ/distance wastes rounds — renders come out cropped to
a corner or empty. With those two flags, `--camera` only sets rotation; the
distance component is ignored.

Always pass `--backend=Manifold` too. It's much faster than the default CGAL
backend on CSG-heavy models (booleans, hulls, multi-part assemblies), which
matters since the iterate loop re-renders constantly. Drop it only if the
installed OpenSCAD build predates Manifold support and errors on the flag.

## Camera angles that work

- General three-quarter view: `rot_x=55, rot_z=25`.
- Cross-section, looking into a half-cut face: `rot_z=335` (cut plane along
  the Y axis).
- Cross-section, looking into a quarter-cut (two internal faces visible at
  once): `rot_x=60, rot_z=45`.

These are proven starting points, not laws — reuse them instead of
re-deriving good angles by trial and error on every new project, but adjust
if a specific part's proportions call for it.

## Cross-section technique

Define a small helper module that subtracts a cube covering the region to
remove, then wrap any module in it:

```scad
module half_cut() {
    difference() {
        children();
        translate([0, -200, -100]) cube([400, 200, 300]);
    }
}

module quarter_cut() {
    difference() {
        children();
        translate([-300, 0, -200]) cube([300, 300, 400]);
    }
}
```

Use `half_cut()` for a straight profile view. Use `quarter_cut()` when two
internal features (e.g. a pocket and a channel on different faces) both need
to be visible in a single shot — pair it with the `rot_x=60, rot_z=45`
camera above.

## Verifying renders honestly

Some features are genuinely hard to see:

- Small pockets or notches relative to the overall part size can read as
  faint lines, or disappear entirely, at typical render scale.
- In assembled/exploded views with semi-transparent parts, a part can hide
  behind another part of a similar color and translucency.

Say "present but not clearly visible at this scale" rather than "verified"
when a render doesn't clearly show a feature. If a dimension or a fit
matters, cross-section it, give the hard-to-see part a contrasting opaque
color, or check the numbers directly in the source — don't eyeball a
low-contrast render and call it confirmed.

## Multi-part assemblies

When a design has multiple printed parts that mate together (a base +
cover + fasteners, a housing + lid, etc.):

- **Hoist shared dimensions to top-level parameters**, not local variables
  re-declared inside each part's module. Anything one part's module needs
  (a bolt-hole position, a mating height) that another module — or the
  assembled-view placement math — also needs must live in exactly one
  place. Local copies of "the same" number drift out of sync the moment
  one gets edited and the other doesn't.
- **Build one `Assembled_Scene()` module**, parameterized with flags for
  optional layers (e.g. `show_bolts = false`), instead of duplicating the
  same per-part placement logic across more than one `if (view == ...)`
  branch. Every `assembled*` view then calls the same module, so parts
  can't silently drift apart between views.
- **Give each part a three-state visibility control, not just a boolean.**
  A plain `show_x = true/false` flag can't show how a part nests *inside*
  another opaque one — for that you need to see through the outer part
  without fully hiding it. A small `vis(mode, color, alpha)` helper
  wrapping each part's `color()` call covers all three states parts
  actually need in a combined view:

  ```scad
  module vis(mode, col, alpha = 0.35) {
      if (mode == "visible") color(col) children();
      else if (mode == "translucent") color(col, alpha) children();
      // anything else ("hidden"): draw nothing.
  }
  ```

  Declare one `vis_x` string per part under a Customizer group so they
  become live dropdowns in the OpenSCAD app's sidebar (Window >
  Customizer) — no command-line flags needed, and the preview updates the
  instant a dropdown changes:

  ```scad
  /* [Visibility] */
  vis_housing = "translucent"; // [visible, translucent, hidden]
  vis_insert  = "visible";     // [visible, translucent, hidden]
  ```

  Then in the assembled view: `vis(vis_housing, "royalblue", 0.3)
  Housing();`. Set each part's *default* mode to match whatever the view
  looked like before adding toggles, so turning this on doesn't change
  the default render.

  Two silent-failure gotchas confirmed hands-on — OpenSCAD's Customizer
  parser is stricter than it looks, and gives no error when it rejects a
  line, it just quietly produces no UI control for it:
  - **Group headers `/* [Name] */` must be plain ASCII.** An em-dash or
    embedded quotes in the name (`/* [Visibility — "x" only] */`) breaks
    parsing for the *entire group* — none of its variables get a UI
    control, checkbox, or dropdown.
  - **Nothing may trail after the closing `]`** on a dropdown line.
    `foo = "a"; // [a, b, c] some description` silently fails to render
    as a dropdown. Put the description on its own comment line above the
    variable instead of appending it after the bracket.
- **A dependent part's local origin isn't always where you'd assume.** If
  part B's rest position comes from contact with part A (pushed flush
  against a wall, resting on a ledge) rather than from being centered in
  the assembly, a feature centered in part B's own local frame (a socket,
  a hole) will *not* land on the same axis as a feature centered in part
  A's frame — even though both look centered in isolation. Work out where
  a part's local origin actually lands in the shared assembly frame
  *before* centering a mating feature on it. (Concrete case: a pad
  resting flush against a back wall had its center offset from the
  assembly's centerline by the wall's own thickness; a plain centered
  socket in the pad missed the mating bolt by that offset.)

## Library vitamins for standard hardware

Modeling a bearing, screw, or heat-set insert from primitive cylinders wastes
time and risks getting real-world dimensions wrong. Two libraries cover
almost everything these projects need — check for them before hand-rolling
a stand-in:

- **NopSCADlib** — accurate stand-ins for real hardware ("vitamins"):
  bearings, screws/bolts, nuts, heat-set inserts, motors. First place to
  look for any fastener or bearing stand-in.
- **BOSL2** — general-purpose CAD utilities: rounded/chamfered primitives,
  fillets, the attachment system. For geometry shortcuts, not hardware.

### One-time install

Install once per machine, not per project — both are large repos and don't
belong inside a project folder:

```bash
mkdir -p ~/.local/share/OpenSCAD/libraries
git clone https://github.com/nophead/NopSCADlib ~/.local/share/OpenSCAD/libraries/NopSCADlib
git clone https://github.com/BelfrySCAD/BOSL2 ~/.local/share/OpenSCAD/libraries/BOSL2
```

OpenSCAD searches `~/.local/share/OpenSCAD/libraries/` automatically, no
`OPENSCADPATH` needed for these two. Confirm before assuming a library is
present rather than guessing from a past project:

```bash
ls ~/.local/share/OpenSCAD/libraries/
```

### Reach for a vitamin instead of hand-rolling, when one exists

| Need | Library | Example |
|---|---|---|
| Bearing stand-in | NopSCADlib | `include <NopSCADlib/vitamins/bearing.scad>` → `bearing(BEARING_688)` |
| Screw/bolt stand-in | NopSCADlib | `include <NopSCADlib/vitamins/screws.scad>` → `screw(M4_cap_screw, 12)` |
| Heat-set insert | NopSCADlib | `include <NopSCADlib/vitamins/inserts.scad>` |
| Rounded box / filleted edges | BOSL2 | `include <BOSL2/std.scad>` → `cuboid([w,d,h], rounding=r, edges="Z")` |
| Generic fillet on a custom profile | BOSL2 | `include <BOSL2/rounding.scad>` |

Only hand-roll a stand-in (see "Test-fit hardware" below) when the hardware
is nonstandard enough that no vitamin model fits — a custom D-shaft, an odd
bracket, etc.

**A vitamin is still a stand-in, not the final part.** Apply the same
convention as a hand-rolled one: bright unmissable color, its own view(s)
(`assembled_bolts`), never exported. Pulling it from a library only saves
the time of getting the dimensions right — it doesn't change that
discipline.

## Test-fit hardware for interference checks

When no vitamin model fits (see "Library vitamins" above), model the
fasteners themselves as simple
stand-ins — head + shank cylinders, never exported or printed — so
reachability and clearance problems show up in a render before a real
print:

- Give them a bright, opaque, unmissable color (e.g. crimson) distinct
  from every printed part's palette.
- Put them behind their own view(s) (`assembled_bolts`,
  `assembled_bolts_cross`) so the plain `assembled` view stays
  uncluttered and hardware-free.
- One generic module per head style covers most fasteners — bearing face
  of the head at local z=0, head extending +z, shank extending -z (i.e.
  modeled head-up/shank-down); `rotate([180,0,0])` flips it for a
  bottom-entry fastener.
- A cross-section view (`quarter_cut()`) of the full assembly plus
  hardware is far more informative than the solid view — most reach/
  overlap problems are internal and invisible from outside.

### This check is a hint, not a verdict

Two failure modes recurred in one project doing exactly this — both
looked like solid findings and both were wrong once checked against a
real print:

- **Sign/direction errors.** A shank spans from head to tip; whether a
  computed distance means "short of the target" or "past the target"
  depends on which end you're comparing and which way that axis runs.
  Restate the comparison in plain language ("the tip sits below the
  nut's bottom face — i.e. past it, not short of it") before concluding
  short vs. long. Don't trust a signed number's sign at a glance.
- **"Too long" does not mean "punches through."** A fastener longer than
  the stack it's clamping can't thread through solid material just
  because the arithmetic says it reaches further — it stops advancing
  once it meets resistance. The real consequence is usually the head
  sitting unseated/proud with extra shank exposed, not a structural
  failure at the tip. Don't report a bolt-too-long finding as "will
  damage/penetrate the part being clamped" without checking that claim.

Treat this check's output as "worth confirming on the real print," not as
a verdict — especially before telling the user something is broken.

## Check interference across the full range of motion, not one demo position

For any mechanism parameterized by a "current position" — a slide's
travel distance, a hinge's opening angle, anything with a min and a
max — manifold checks, slicer checks, and renders only ever exercise
whatever single value happens to be hardcoded for the demo/assembled
view (`jaw_gap = 20`, `angle = 45`, whatever). None of them prove the
mechanism actually works across its whole intended range; a part can be
manifold-clean, print-support-clean, and still physically collide with
itself at an opening you never happened to render.

Write a small interference-check module: `intersection()` the two parts
that move relative to each other, parameterized by the same position
variable the assembly uses, and check it at both extremes (and any
point in between where the motion isn't simple/monotonic). It should
come back empty at every valid position; non-empty means a real
collision, not a rendering curiosity — confirm with actual vertex
coordinates (extent and location of the overlap), not just "empty vs.
not empty," so you can tell a genuine interference from a coincidental
touch.

Exclude deliberate small overlaps from the check first, or a real fudge
factor will show up as a false "collision" at *every* position, not
just the ones actually worth catching — e.g. a small deliberate overlap
(a fraction of a mm) used elsewhere in the design to avoid a CGAL
coincident-face non-manifold warning when unioning two touching parts.
Cut away a thin band around the exact touching plane before judging the
result, so the real check isn't drowned out by a known, harmless
artifact.

**Keep these as permanent, named views, not one-off debug scripts
deleted after use.** A length/reach formula that's correct today can
silently go wrong the next time any dimension feeding into it changes —
particularly after a coordinate-frame change: a part positioned
directly in assembly coordinates today, refactored tomorrow into a
feature cut inside a sub-part that itself gets shifted, keeps the same
formula that was correct for the old frame and silently wrong for the
new one. (Concrete case: a dovetail slide's required channel length was
computed correctly for the tenon's own travel span, but never
re-derived after the channel moved from "positioned directly in
assembly coordinates" to "cut inside a housing part that itself gets
shifted 10mm" — the channel came up exactly that 10mm short at full
extension. It survived an entire redesign's worth of manifold checks,
slicer checks, and renders, because none of them check a *specific*
travel position — only checking the assembly at the actual min/max
opening found it.) Re-run these checks after any change to a dimension
feeding the mechanism's travel, the same way a slicer check gets re-run
after any geometry change.

### Rotating parts: check the swept envelope, not the built orientation

Only relevant when a part **continuously rotates** relative to a
neighbor during normal use (a knob driving a screw, a dial, a wheel)
**and** that neighbor's geometry isn't already rotationally symmetric
about the same axis. Most projects have neither condition — don't add
this as a rote step everywhere; reach for it only when a specific part
actually meets both.

When it does apply, a part built from discrete features (grip bumps,
ribs, an asymmetric flange), checked only in its as-modeled orientation,
can pass by pure luck — none of the features happen to line up with
whatever's nearby *in that one snapshot*. But if the part rotates during
use, every feature eventually sweeps through every angular position,
including whichever one is closest to the neighbor. The as-modeled
check answers "does this specific build orientation collide," not the
question that actually matters: "does this part collide at any point
during normal operation."

Check the true worst case instead of the faceted part: intersect the
neighbor against a solid matching the rotating part's own outer swept
envelope — usually just a cylinder at its maximum radius, spanning its
full axial extent — rather than the actual faceted geometry. Empty
means safe at every angle, not just the one that happened to render.
(Concrete case: an 8-bump grip knob checked in its as-modeled
orientation showed a real overlap with a neighboring wall. Re-checking
against a solid swept cylinder confirmed the *same* collision region —
proving it wasn't a lucky/unlucky coincidence of where the bumps
happened to land, but a structural conflict that would recur on every
single rotation regardless of bump placement.)

## Nut traps: capturing hardware without glue

A hex nut (or any part) that just sits in an open-faced pocket relies on
glue, friction, or gravity to stay put before the mating fastener is
even inserted — a reliability gap worth designing out, not documenting
around. The fix depends on one question: **does this part need to
rotate with the fastener, or stay fixed?**

**Fixed (never rotates) — the common case, e.g. a nut a bolt threads
through:**
1. Cut the pocket to the part's actual shape (hex, for a hex nut),
   snug — its own walls block rotation, no extra geometry needed for that.
2. Don't let the pocket open flush onto an exterior face. Stop it short
   by a thin wall, pierced only by the through-hole for the fastener's
   shaft (too small for the part itself to fit through). That wall,
   plus the natural shoulder at the pocket's other end (where it
   narrows back to the through-hole), traps the part axially on both
   sides using the surrounding geometry alone.
3. Load the part through a slot in a *different* face (perpendicular to
   the fastener axis) before the fastener is inserted. Size the slot
   generously — across-corners for a hex, not across-flats — no locking
   geometry is needed here: once the fastener passes through the part's
   bore, the shaft itself physically blocks the part from ever exiting
   sideways again. Sideways-and-out is only possible pre-assembly.

**Free-spinning (must rotate with the fastener) — e.g. a nut captured
behind a bolt head so the bolt can spin in place without sliding:**
Same two axial walls as above, but the pocket stays round and oversized
so the part can spin freely — its own shape can't block rotation here,
that's the point. The loading slot instead needs a *locking* width:
size it to the part's narrow dimension (across-flats for a hex, not
across-corners). Inserted flat-first, it fits through; once installed
and rotated even slightly by the fastener, its wider dimension
(across-corners) can no longer pass back through the same opening —
captured rotationally-free but unable to escape, the moment it turns.

Both variants are pure "no glue" wins — the second is worth the sharper
mental model, but the first is more common and simpler to get right.
Verify the same way as any other geometry (see "Real slicer verification"
above): a side-loading slot is usually just curves and thin rings, but
confirm nothing new got flagged rather than assuming a hardware-capture
pattern is automatically overhang-free.

## Design invariants

Record *why*, not just *what*, whenever a design decision took iteration to
reach, or reverses an earlier wrong attempt — e.g. "bearings go inside the
shell, not exterior-facing — an earlier version put them on the wrong face."
Put these in the project's `CLAUDE.md`, not in code comments, so a future
edit trips over the reasoning before undoing the decision.

## Reference photos for real-world fit

When a part needs to mate with a real, physical object — an existing motor,
a shaft, a desk edge, another manufactured part — ask for a reference photo
and/or measurements before modeling the mating geometry. Guessing at how
physical pieces fit together from a spec sheet alone is a common source of
wasted iteration; a photo settles it in one round instead of several.

## Housekeeping

Renders overwrite in place, so stale PNGs from an older geometry can linger
if a view is renamed or dropped and the script isn't re-run. After any
design change, re-run the full render script rather than a subset of views.

## STL export and print orientation

No camera flags are needed for STL/3MF output — geometry only. Still pass
`--backend=Manifold`, since export runs the full CSG resolve:

```bash
xvfb-run openscad -o part.stl -D 'view="<name>"' --backend=Manifold <file>.scad
```

**Never export the design/assembly-frame view directly if that orientation
would print badly.** The coordinate frame that keeps assembly math
consistent (part positions, mating features, cross-part references) is
frequently *not* a good print orientation — the two concerns are
independent and should not be forced to share one frame. For every
printed part, add a `<Part>_Print()` module (and a matching `<name>_print`
view) that wraps the part with whatever `rotate()`/`translate()` makes it
sit flat with minimal overhangs, leaving the plain view and all assembly
placement math untouched:

```scad
module Widget_Print() {
    translate([0, 0, <lift>]) rotate([<rx>, <ry>, <rz>]) Widget();
}
```

If a part is already flat-bottomed as modeled, its `_Print()` module can be
a no-op (or just a Z-shift) — say so explicitly rather than silently
skipping it, so it's clear the part was considered, not forgotten.

**Verify a rotation empirically before trusting it — this is not optional.**
The same kind of sign/axis reasoning that goes wrong in cross-part distance
math (see "This check is a hint, not a verdict" above) goes wrong here too,
and the cost of being wrong is a failed print, not just a bad answer. Before
calling a print orientation good:
1. Render the rotated part's **footprint** (camera looking straight down the
   new vertical axis) — it should be a clean outline with no stray
   disconnected geometry.
2. Render a **bed-level side view** (`rot_x≈85-88`) — it should read as a
   simple, mostly-flat silhouette. A cantilevered mass hanging off to one
   side is visible here as a distinct floating shape.
3. For internal features (pockets, nut traps, blind holes) a cross-section
   slice can help, but is genuinely harder to get a clean read from than
   (1) and (2) — if a slice render comes out confusing or ambiguous, say so
   plainly rather than forcing a confident conclusion from an inconclusive
   picture. Small enclosed pockets (roughly ≤10mm span) rarely fail either
   way, so this is a lower-stakes gap than getting the *overall* orientation
   wrong — flag it as unverified and point at the slicer's own
   overhang/support preview as the authoritative check, rather than
   asserting an unconfirmed conclusion.

## Combined multi-part export

**Currently disabled by user preference (2026-11-09):** the user builds
3MF files in Bambu Studio. Do not generate, overwrite or modify `.3mf`
files. Export STLs only and drop the 3MF step from the template. The notes
below are kept in case the user asks for it again.

Alongside individual per-part STLs, also export one combined 3MF with all
printed parts laid out (print-oriented, non-overlapping) on a shared
virtual bed — convenient for loading a whole kit into a slicer at once:

- Measure each `_Print()` part's actual bounding box (don't guess it) —
  render to STL and check vertex extents, or render a footprint view and
  read dimensions off it — then place parts on a grid with a consistent
  gap (10mm is a reasonable default) so nothing overlaps.
- OpenSCAD exports 3MF the same way as STL, just by changing the `-o`
  extension (`-D 'view="all_print"'`-style). Confirm it actually worked by
  unzipping the output and checking `3D/3dmodel.model` contains real
  geometry — don't just trust a zero exit code.
- Know the limitation: OpenSCAD writes the whole scene as **one 3MF object
  with N disconnected shells**, not N separately-named objects. Most
  slicers can still split it into independently-movable parts, but tell
  the user it's usually a manual "split to objects" step on import, not
  automatic — don't imply it drops in pre-separated.
- This is additive, not a replacement — keep exporting individual STLs
  too; some workflows (single-part reprints, non-3MF-aware tools) need them.

`references/export_stl_template.sh` covers both the individual STLs and the
combined 3MF in one script.

## Real slicer verification (OrcaSlicer)

Render-based overhang checking (footprint/bed-level renders, "STL
export and print orientation" above) is a *model* of what a slicer will
do — reasoning about angles and taper direction from the geometry. It's
necessary but not sufficient: it has repeatedly disagreed with what a
real slicer actually decides, in both directions (missed real
cantilevers; also, separately, a real slicer can silently tolerate a
shape that reasoning-from-angles would flag). **The goal is to prevent
support through design — reorientation first, geometry changes second —
not to tune settings until a checker stops complaining.** Use an actual
slicer to find what still needs it, then change the design, not the
slicer settings, to make that need go away.

**Check every printed part individually, not just the combined
assembly.** A small part's overhang is invisible as a rounding error in
a whole-model check — this is the single most common way this check
gets skipped in practice, not lack of tooling.

### Setup

Install OrcaSlicer normally if you have a browser and `sudo`. In a
sandboxed/agent environment with no root and no outbound HTTPS, see
`references/orca_slicer_setup.md` for the full recipe (AppImage
`--appimage-extract`, `ldd`-driven discovery of the handful of actually-
missing shared libraries, downloading just those via a user-writable
`apt-get` cache, `dpkg-deb -x` — all no-root, HTTP-only, no browser
needed after the initial AppImage download). Keep the extracted install
in the project's `tools/` for reuse across sessions.

### Usage

`references/slice_check_template.sh` (fill in the Orca/profile paths
for the actual setup) slices each given STL and reports three signals
together — trust the combination, not any one alone:

1. **`TYPE:Support` gcode lines** — real scaffolding was generated.
2. **`FEATURE: Bridge` / `FEATURE: Internal Bridge` gcode lines** — a
   short-span gap the slicer chose to print via speed/pattern changes
   instead of scaffolding. Normal and usually fine, but a check that
   only looks for `TYPE:Support` can't distinguish "handled via
   bridging" from "never even considered" — both read as "0 support."
3. **`references/overhang_audit.py`** — reads every triangle's face
   normal directly and flags downward-facing surfaces regardless of
   what the slicer's heuristics decide to do about them. This is a
   completeness net, not a pass/fail gate: it will also flag small
   round/hex hole ceilings and already-verified gradual tapers that
   print fine. Every real part has *some* flagged triangles; only
   human judgment (does this look like an abrupt single-step overhang,
   or a small bridgeable hole/gradual taper already accounted for)
   separates "known fine" from "worth a second look."

Before trusting any CLI override (a threshold angle, an enabled-support
flag), confirm it actually applied with `--export-settings out.json`
and grep the key back out — a bad enum string can be silently accepted
as a token without ever taking effect, producing a false "0 support"
result. See `references/orca_slicer_setup.md`'s CLI gotchas for the
specific flag-syntax traps already hit (space vs. `=`, exact enum
strings, `--arrange 0` crashing on off-origin parts).

**Different slicers — and different forks of the "same" slicer — can
disagree on borderline calls, and no CLI flag closes that gap.** A
short, abrupt overhang bridged fine under every setting tried in one
slicer, yet needed real support in another (a proprietary fork of the
same lineage). Treat a clean result across all three signals as strong
evidence, not proof. For anything sitting near a threshold — especially
a narrow post suddenly flaring wider, or any other abrupt single-step
shape rather than a gradual taper — prefer eliminating the overhang
through reorientation or a geometry change over trusting either slicer's
silence.

## Additional resources

- **`references/claude_md_template.md`** — starting point for a new
  project's `CLAUDE.md`.
- **`references/render_script_template.sh`** — starting point for a new
  project's render script.
- **`references/export_stl_template.sh`** — starting point for a new
  project's STL + combined-3MF export script.
- **`references/orca_slicer_setup.md`** — recipe for a headless,
  no-root OrcaSlicer CLI install, for real slicer verification.
- **`references/slice_check_template.sh`** — starting point for a
  per-part slicer verification script (support + bridge + geometric
  audit, see "Real slicer verification" above).
- **`references/overhang_audit.py`** — standalone, project-agnostic
  geometric overhang auditor; copy as-is, no editing needed.
