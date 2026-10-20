"""Pack the mod's files (src/: scripts, the native module's file, the shield layout, the dropdown images,
the licence notices) into build/skill_preallocation.pack.

Usage (from the project folder):
  python generator/build_data.py --game-data "<game>/data" --out src         # after a game patch (the baked fallback data)
  python generator/build_ui.py --game-data "<game>/data" --out src           # after a patch that changes the skills panel
  python generator/build_dropdown_art.py --game-data "<game>/data" --out src  # needs Pillow
  python generator/build_native_schema.py                                     # after a patch that changes a skill table's layout
  python generator/build_native.py                                            # the native module (needs: pip install ziglang==0.13.0)
  python generator/build_pack.py [--install "<game>/data"] [--release]
--release: also refuse a build that isn't ready to publish (debug on, the repository link not set).
"""
import argparse
import hashlib
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tw_pack  # noqa: E402

PACK_NAME = "skill_preallocation.pack"
# The pack's header time: fixed, so the same source always gives the same pack, byte for byte (anyone can
# rebuild the published pack and compare its SHA-256 with SHA256SUMS.txt). SOURCE_DATE_EPOCH overrides it.
PACK_TIME = int(os.environ.get("SOURCE_DATE_EPOCH", "1792195200"))       # 2026-10-17 00:00 UTC


# what goes into the pack: the scripts, the layout, the images, and the licence notices
PACKED = (".lua", ".twui.xml", ".png", ".txt")


def collect(src):
    """{"path/in/pack": bytes} for every file of src/ that goes into the pack."""
    files = {}
    for dirpath, _, names in os.walk(src):
        for n in sorted(names):
            if n.endswith(PACKED):
                full = os.path.join(dirpath, n)
                files[os.path.relpath(full, src).replace(os.sep, "/")] = open(full, "rb").read()
    return files


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(here, "src"))
    ap.add_argument("--out", default=os.path.join(here, "build"))
    ap.add_argument("--install", help="game data folder to copy the pack into")
    ap.add_argument("--release", action="store_true", help="refuse a build that isn't ready to publish")
    a = ap.parse_args()
    files = collect(a.src)
    if not files:
        sys.exit("no scripts found under " + a.src)
    if any(p.startswith("ui/campaign ui/") for p in files):
        sys.exit("src/ has a copy of a game layout (ui/campaign ui/...): this variant replaces no game file")
    core = files.get("script/campaign/mod/skill_preallocation.lua", b"")
    live = files.get("script/campaign/mod/skill_preallocation_live.lua", b"")
    problems = []
    if b"\nSPA.debug = true" in core:
        problems.append("SPA.debug is on (clicks and the presets row are logged)")
    if b"github.com/OWNER/REPO" in live:
        problems.append("LIVE.INFO_URL in skill_preallocation_live.lua is still the placeholder (the link the mod writes next to the DLL)")
    if "script/skill_preallocation/native_bin.lua" not in files:
        problems.append("no native module (generator/build_native.py)")
    if b"Permission is hereby granted" not in files.get("script/skill_preallocation/LICENSES.txt", b""):
        problems.append("no licence notices (src/script/skill_preallocation/LICENSES.txt: the DLL carries zstd, whose licence must come with it)")
    for p in problems:
        print("NOTE: not ready to publish: " + p)
    if a.release and problems:
        sys.exit("--release: fix the notes above first")
    os.makedirs(a.out, exist_ok=True)
    out = os.path.join(a.out, PACK_NAME)
    tw_pack.write_mod_pack(out, files, timestamp=PACK_TIME)
    print(f"wrote {out} ({os.path.getsize(out) // 1024} KB) with {len(files)} files: {', '.join(sorted(files))}")
    print(f"SHA-256 of {PACK_NAME}: {hashlib.sha256(open(out, 'rb').read()).hexdigest()}")
    if a.install:
        shutil.copy2(out, os.path.join(a.install, PACK_NAME))
        print("installed into", a.install)


if __name__ == "__main__":
    main()
