"""Make the presets dropdown's images (src/ui/skins/default/spa_dropdown_<state>.png) from the game's
dropdown art (ui/skins/default/button_dropdown_<state>.png, 188x34).

The mod draws its dropdown with the game's text button template, which tiles its images with 26-unit
left and right margins. The game's dropdown art has its arrow box at x 160..183, so the 2 columns at
160..161 fall inside the tiled middle and show up as a thin line in the middle of a wide dropdown.
Here the arrow box moves 2 columns right (into the art's empty right edge) and the field is
extended, so the box lies entirely inside the 26-unit right margin.

Usage (needs Pillow):
  python generator/build_dropdown_art.py --images <folder with button_dropdown_*.png> --out src
  python generator/build_dropdown_art.py --game-data "<game>/data" --out src     # reads ui2.pack (zstd)
"""
import argparse
import io
import os
import sys

from PIL import Image

STATES = ("active", "hover", "pressed", "inactive", "underlay")
BOX_FROM, SHIFT, MARGIN = 160, 2, 26


def fix(img):
    img = img.convert("RGBA")
    w, h = img.size
    if (w, h) != (188, 34):
        raise ValueError(f"unexpected size {w}x{h}")
    out = img.copy()
    box = img.crop((BOX_FROM, 0, w - SHIFT, h))
    out.paste(Image.new("RGBA", (w - BOX_FROM, h), (0, 0, 0, 0)), (BOX_FROM, 0))
    out.paste(box, (BOX_FROM + SHIFT, 0))
    out.paste(img.crop((BOX_FROM - SHIFT, 0, BOX_FROM, h)), (BOX_FROM, 0))
    # the tiled middle must not contain any of the box any more
    px = out.load()
    for x in range(MARGIN, w - MARGIN):
        r, g, b, a = px[x, h // 2]
        if a and (0.3 * r + 0.59 * g + 0.11 * b) > 40:
            raise ValueError(f"bright column {x} left in the tiled part")
    return out


def load_from_pack(data_dir):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import tw_pack
    want = {f"ui\\skins\\default\\button_dropdown_{s}.png": s for s in STATES}
    found = {}
    for path, data in tw_pack.iter_files(os.path.join(data_dir, "ui2.pack"), lambda p: p.lower() in want):
        found[want[path.lower()]] = Image.open(io.BytesIO(data))
    return found


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap = argparse.ArgumentParser()
    ap.add_argument("--images")
    ap.add_argument("--game-data")
    ap.add_argument("--out", default=os.path.join(here, "src"))
    a = ap.parse_args()
    if a.images:
        imgs = {s: Image.open(os.path.join(a.images, f"button_dropdown_{s}.png")) for s in STATES}
    elif a.game_data:
        imgs = load_from_pack(a.game_data)
    else:
        sys.exit("give --images or --game-data")
    missing = [s for s in STATES if s not in imgs]
    if missing:
        sys.exit("missing images: " + ", ".join(missing))
    out_dir = os.path.join(a.out, "ui", "skins", "default")
    os.makedirs(out_dir, exist_ok=True)
    for s in STATES:
        path = os.path.join(out_dir, f"spa_dropdown_{s}.png")
        fix(imgs[s]).save(path, optimize=True)
        print("wrote", path, os.path.getsize(path), "bytes")


if __name__ == "__main__":
    main()
