#!/usr/bin/env python3
"""Generate the iOS app-icon sets (primary + alternates) and in-app previews.

Source PNGs are the 4K design exports (not committed). Re-running is only
needed when icons are added or redesigned:

    python3 scripts/generate_app_icons.py --src "~/Desktop/IOS Lumi Icons"

For each icon the script center-crops to a square, flattens any alpha onto
white (App Store requires opaque icons), then writes:
  * the default icon into every slot of AppIcon.appiconset (per Contents.json)
  * one single-size 1024px .appiconset per alternate icon (Xcode 14+ format,
    consumed via ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES)
  * a 256px preview per icon into assets/app_icons/ for the in-app picker

The 1024px catalog PNGs are lossless crops of the sources, so if the Desktop
folder is ever lost they can serve as regeneration input themselves.
"""
import argparse
import json
import os
import sys

from PIL import Image

# source filename -> (id, alternate iconset name or None for the primary icon)
ICONS = {
    "red face (default).png": ("red_face", None),
    "blue face.png": ("blue_face", "AppIconBlueFace"),
    "green face.png": ("green_face", "AppIconGreenFace"),
    "yellow face.png": ("yellow_face", "AppIconYellowFace"),
    "red lumi.png": ("red_lumi", "AppIconRedLumi"),
    "blue lumi.png": ("blue_lumi", "AppIconBlueLumi"),
    "lblue lumi.png": ("light_blue_lumi", "AppIconLightBlueLumi"),
    "green lumi.png": ("green_lumi", "AppIconGreenLumi"),
    "orange lumi.png": ("orange_lumi", "AppIconOrangeLumi"),
    "pink lumi.png": ("pink_lumi", "AppIconPinkLumi"),
    "purple lumi.png": ("purple_lumi", "AppIconPurpleLumi"),
    "yellow lumi.png": ("yellow_lumi", "AppIconYellowLumi"),
}

PREVIEW_SIZE = 256

ALTERNATE_CONTENTS = {
    "images": [
        {
            "filename": "icon_1024.png",
            "idiom": "universal",
            "platform": "ios",
            "size": "1024x1024",
        }
    ],
    "info": {"author": "xcode", "version": 1},
}


def load_flat_square(path):
    """Center-crop to square and flatten alpha onto white."""
    im = Image.open(path)
    im = im.convert("RGBA")
    w, h = im.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    im = im.crop((left, top, left + side, top + side))
    opaque = Image.new("RGB", im.size, (255, 255, 255))
    opaque.paste(im, mask=im.split()[3])
    return opaque


def save_png(im, size, dest):
    im.resize((size, size), Image.LANCZOS).save(dest, format="PNG", optimize=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--src", required=True, help="folder with the 4K source PNGs")
    ap.add_argument("--repo", default=".", help="repo root (default: cwd)")
    args = ap.parse_args()

    src = os.path.expanduser(args.src)
    repo = os.path.abspath(os.path.expanduser(args.repo))
    xcassets = os.path.join(repo, "ios", "Runner", "Assets.xcassets")
    primary_set = os.path.join(xcassets, "AppIcon.appiconset")
    previews = os.path.join(repo, "assets", "app_icons")
    os.makedirs(previews, exist_ok=True)

    missing = [f for f in ICONS if not os.path.exists(os.path.join(src, f))]
    if missing:
        sys.exit(f"missing source files in {src}: {missing}")

    for src_name, (icon_id, iconset) in sorted(ICONS.items()):
        im = load_flat_square(os.path.join(src, src_name))
        save_png(im, PREVIEW_SIZE, os.path.join(previews, f"{icon_id}.png"))

        if iconset is None:
            # Primary icon: fill every slot declared in the existing Contents.json.
            with open(os.path.join(primary_set, "Contents.json")) as f:
                slots = json.load(f)["images"]
            for slot in slots:
                pts = float(slot["size"].split("x")[0])
                scale = int(slot["scale"].rstrip("x"))
                px = round(pts * scale)
                save_png(im, px, os.path.join(primary_set, slot["filename"]))
            print(f"{icon_id}: primary AppIcon ({len(slots)} slots) + preview")
        else:
            set_dir = os.path.join(xcassets, f"{iconset}.appiconset")
            os.makedirs(set_dir, exist_ok=True)
            with open(os.path.join(set_dir, "Contents.json"), "w") as f:
                json.dump(ALTERNATE_CONTENTS, f, indent=2)
                f.write("\n")
            save_png(im, 1024, os.path.join(set_dir, "icon_1024.png"))
            print(f"{icon_id}: {iconset}.appiconset + preview")


if __name__ == "__main__":
    main()
