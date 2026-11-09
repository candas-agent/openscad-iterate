# Setting up a headless OrcaSlicer CLI for support verification

On a normal machine with a browser and `sudo`, just install OrcaSlicer or
Bambu Studio normally and skip this file. This procedure is specifically
for a sandboxed/agent Linux environment with **no root and no outbound
HTTPS** (only plain HTTP works) — the situation that forced this recipe
out in the first place. Ask the user to download the AppImage on a
machine that has a real browser (HTTPS works there) and hand you the
file; everything after that is HTTP + local, no root needed.

## 1. Get the AppImage onto the machine

Ask the user to download the Linux AppImage from OrcaSlicer's GitHub
releases (`https://github.com/SoftFever/OrcaSlicer/releases`, look for
`OrcaSlicer_Linux_AppImage_*.AppImage` under the latest release's
Assets) and place it somewhere you can read it (the project folder, or
their Downloads folder if you have filesystem access to it, e.g.
`/mnt/c/Users/<name>/Downloads/` under WSL).

## 2. Extract it — don't rely on FUSE

Sandboxed containers usually lack FUSE, which AppImages normally need to
mount themselves:

```bash
chmod +x OrcaSlicer.AppImage
./OrcaSlicer.AppImage --appimage-extract   # unpacks to squashfs-root/
```

The real binary is `squashfs-root/bin/orca-slicer`. Don't delete the
`.AppImage` or the extracted `squashfs-root/` afterward — keep both in
the project's `tools/` directory for reuse across sessions.

## 3. Find exactly which shared libraries are missing

Don't guess — `ldd` the binary with its bundled private lib dir on
`LD_LIBRARY_PATH` and read off which names come back `not found`:

```bash
cd squashfs-root
LD_LIBRARY_PATH="lib/orca-runtime:bin" ldd bin/orca-slicer 2>&1 | grep "not found"
```

Typically only ~5 top-level libraries are missing (WebKitGTK,
GStreamer video, libsoup, libsecret — GUI/webview dependencies the CLI
slicing path never actually exercises, but the dynamic linker still
refuses to start the binary without them).

## 4. Download just those libraries as a normal user

`apt-get` needs root only because its *default* state/cache directories
(`/var/lib/apt/lists`, `/var/cache/apt`) are root-owned. Point it at a
writable directory instead and it works fine unprivileged:

```bash
mkdir -p /tmp/apt-user/lists/partial /tmp/apt-user/archives/partial
apt-get -o Dir::State::Lists=/tmp/apt-user/lists \
        -o Dir::Cache::Archives=/tmp/apt-user/archives update

apt-get -o Dir::State::Lists=/tmp/apt-user/lists \
        -o Dir::Cache::Archives=/tmp/apt-user/archives \
        install --download-only --reinstall --yes --no-install-recommends \
        --print-uris <missing-package-names> \
    | grep -oP "^'\K[^']+" > /tmp/deb_urls.txt
```

Package names for the common WebKitGTK/GStreamer/libsoup/libsecret set:
`libgstreamer-plugins-base1.0-0 libsoup-3.0-0 libwebkit2gtk-4.1-0
libjavascriptcoregtk-4.1-0 libsecret-1-0` — adjust based on what step 3
actually reported. `--no-install-recommends` matters: without it, apt
pulls in ~65 packages (spell-checkers, codec extras); with it, ~50, all
genuinely small.

Then fetch the URLs directly (plain HTTP — Ubuntu's own package mirrors
serve over HTTP, matching what `/etc/apt/sources.list.d/*.sources`
already points at) and unpack each with `dpkg-deb -x`, which — like
`apt-get download` — needs no root:

```bash
mkdir -p /tmp/apt-user/extracted
cd /tmp/apt-user/archives
while read -r url; do wget -q "$url"; done < /tmp/deb_urls.txt
for f in *.deb; do dpkg-deb -x "$f" /tmp/apt-user/extracted; done
```

## 5. Run it

```bash
export LD_LIBRARY_PATH="squashfs-root/lib/orca-runtime:squashfs-root/bin:/tmp/apt-user/extracted/usr/lib/x86_64-linux-gnu"
xvfb-run squashfs-root/bin/orca-slicer --help
```

`xvfb-run` is required even for pure CLI slicing — the binary still
initializes a GTK context on startup regardless of whether anything is
displayed (same reason OpenSCAD renders need it in this environment).

`/tmp` doesn't survive a machine reboot; if `LD_LIBRARY_PATH`'s
`/tmp/apt-user/extracted` component goes missing later, redo step 4
(fast — the `.deb` URLs can be cached in the repo instead of `/tmp` if
persistence across reboots matters).

## Bundled printer/filament/process profiles

Real Bambu machine/process/filament profiles ship inside the AppImage —
no need to author your own for common printers:

```
squashfs-root/resources/profiles/BBL/machine/Bambu Lab X1 Carbon 0.4 nozzle.json
squashfs-root/resources/profiles/BBL/process/0.20mm Standard @BBL X1C.json
squashfs-root/resources/profiles/BBL/filament/Bambu PLA Basic @BBL X1C.json
```

`--load-settings` takes process+machine JSON paths semicolon-separated;
`--load-filaments` takes the filament JSON. Full absolute paths only —
bare filenames aren't found relative to any search path.

## CLI gotchas worth knowing before debugging them yourself

- Config overrides need `=`, not a separate token:
  `--enable-support=1`, not `--enable-support 1` (the latter fails with
  a confusing "No such file: 1", as if `1` were parsed as another input
  file).
- `support_type`'s valid values are exactly `normal(auto)`,
  `normal(manual)`, `tree(auto)`, `tree(manual)` — quote the whole
  thing (`"--support-type=normal(auto)"`) since it contains parens.
  A bare `normal` is silently accepted as a token but doesn't match any
  real enum value and the profile's own default wins instead — verify
  any override actually took effect with `--export-settings out.json`
  and grep the key back out, rather than assuming a flag worked because
  the command didn't error.
- `--arrange 0` (disable auto-arrange) reliably crashed with an opaque
  `return -50` in testing, apparently because this project's parts
  aren't centered on the origin (negative X/Y in their own STL frame)
  and skipping arrange leaves them somewhere plate validation rejects.
  Leave `arrange` at its default (translate-only for a single part,
  doesn't rotate) and pass `--orient 0` instead — that's the flag that
  actually matters for preserving a chosen print orientation. Verify
  orientation was preserved by checking `; max_z_height` in the output
  gcode against the `_Print()` module's own height.
- A stale lock file in `--datadir` from an earlier crashed/backgrounded
  run can cause an unrelated-looking failure on the next invocation; if
  a command that worked a moment ago suddenly fails opaquely, try a
  fresh `--datadir`.
