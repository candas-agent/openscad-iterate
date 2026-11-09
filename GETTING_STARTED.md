# Getting started (no 3D design experience needed)

This lets Claude Code design and render 3D-printable parts for you. You
don't need to know OpenSCAD, CAD, or how 3D printing works — you describe
the physical thing you want, provide a photo or measurements when asked,
and look at pictures Claude shows you to say "yes" / "no, make X bigger."

## One-time setup

1. **Install Claude Code**, if not already installed.
2. **Install OpenSCAD** (the tool that turns code into 3D geometry —
   Claude writes it, you never see it unless you want to):
   - macOS: `brew install openscad`
   - Linux/WSL: `sudo apt install openscad xvfb`
     (`xvfb` lets it render without a display, which is how Claude runs it)
   - Windows: download from https://openscad.org/downloads.html
3. **Copy this skill folder** into your own `~/.claude/skills/` directory,
   so it sits at `~/.claude/skills/openscad-iterate/`.
4. **Add permissions** so Claude doesn't stop to ask before every render.
   Open (or create) `~/.claude/settings.local.json` and merge in the
   contents of `references/permissions_snippet.json` (see that file for
   how to merge if you already have a `permissions` block).

That's it — no other install or config needed.

## How to actually use it

Start Claude Code in an empty project folder and just describe the part in
plain language, e.g.:

> "I need a small hook that clips onto a 15mm-thick shelf edge to hold my
> headphones."

Claude will:
- Ask for a photo and/or measurements if the part needs to fit something
  real (a shelf, a motor, a phone) — take a photo with a ruler or known
  object next to it if you can, it helps a lot.
- Write the design, then show you rendered pictures of it from a few
  angles as it goes — you don't need to read any code, just look at the
  pictures.
- Ask you to confirm dimensions or react to a render ("does this look
  right?", "is this hole too small?").
- Export a 3D-printable file (`.stl`) at the end, ready to send to a
  printer or print shop.

## What you should expect to do

- Answer questions about how the part is used and what it touches.
- Take/send a reference photo when asked — this is the single biggest
  thing that avoids wasted back-and-forth.
- Look at renders and give feedback in plain language ("too thick",
  "the hole needs to be higher up") — no measurements or CAD terms
  required, though exact numbers (in mm) help when you have them.
- Have a real object or caliper/ruler on hand if precise fit matters
  (e.g. it needs to clip onto something specific) — a render can look
  right and still be a few mm off in real life.

## Where this can go wrong for a beginner

Claude can show you a picture and reason about clearances, but it can't
physically test-fit the part. For anything load-bearing or with a tight
mechanical fit (snap clips, screw threads, press fits), treat the first
print as a test print, not the final one — check the real fit before
printing a second copy or a full batch.
