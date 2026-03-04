#!/usr/bin/env python3
"""
DEN Sprite Slicer — crops a sprite grid into individual files.

Usage:
  python tools/sprite_slicer.py <image> --cols 3 --rows 5 --names "a,b,c,d,e" --dest portraits
  python tools/sprite_slicer.py <image> --cols 3 --rows 3 --names "scar,thorn,bolt" --dest kips
  python tools/sprite_slicer.py <image> --cols 3 --rows 5 --row-heights "345,345,282,282,282" --names "..." --dest portraits

Options:
  --cols         Number of columns in the grid
  --rows         Number of rows in the grid
  --names        Comma-separated names for each cell (left-to-right, top-to-bottom)
  --dest         Destination folder inside assets/ (portraits, kips, enemies)
  --row-heights  Comma-separated pixel heights for each row (if rows differ in size)
  --col-widths   Comma-separated pixel widths for each column
  --skip         Comma-separated indices to skip (0-based)
  --small        Also generate _small.png resized to this size (default: 64)
  --preview      Just show crop boundaries, don't save

Requires: pip install Pillow
"""

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow is required. Install with: pip install Pillow")
    sys.exit(1)

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ASSETS_DIR = PROJECT_ROOT / "assets"


def main():
    parser = argparse.ArgumentParser(description="Slice a sprite grid into individual files")
    parser.add_argument("image", help="Path to the sprite grid image")
    parser.add_argument("--cols", type=int, required=True, help="Number of columns")
    parser.add_argument("--rows", type=int, required=True, help="Number of rows")
    parser.add_argument("--names", required=True, help="Comma-separated names for each cell")
    parser.add_argument("--dest", required=True, help="Subfolder in assets/ (portraits, kips, enemies)")
    parser.add_argument("--row-heights", default="", help="Comma-separated row heights in pixels")
    parser.add_argument("--col-widths", default="", help="Comma-separated column widths in pixels")
    parser.add_argument("--skip", default="", help="Comma-separated cell indices to skip")
    parser.add_argument("--small", type=int, default=64, help="Size for _small thumbnail (default: 64)")
    parser.add_argument("--preview", action="store_true", help="Preview mode — show boundaries only")
    args = parser.parse_args()

    img = Image.open(args.image)
    w, h = img.size
    print(f"Image: {args.image} ({w}x{h})")

    names = [n.strip() for n in args.names.split(",") if n.strip()]
    skip = set(int(s) for s in args.skip.split(",") if s.strip()) if args.skip else set()

    # Calculate cell boundaries
    if args.row_heights:
        row_heights = [int(x) for x in args.row_heights.split(",")]
    else:
        row_heights = [h // args.rows] * args.rows

    if args.col_widths:
        col_widths = [int(x) for x in args.col_widths.split(",")]
    else:
        col_widths = [w // args.cols] * args.cols

    dest_path = ASSETS_DIR / args.dest
    dest_path.mkdir(parents=True, exist_ok=True)

    idx = 0
    y = 0
    saved = 0
    for row in range(args.rows):
        x = 0
        rh = row_heights[row] if row < len(row_heights) else row_heights[-1]
        for col in range(args.cols):
            cw = col_widths[col] if col < len(col_widths) else col_widths[-1]
            cell_idx = row * args.cols + col

            if cell_idx in skip:
                print(f"  [{cell_idx}] ({col},{row}) SKIPPED")
                x += cw
                continue

            if idx >= len(names):
                x += cw
                continue

            name = names[idx]
            box = (x, y, x + cw, y + rh)

            if args.preview:
                print(f"  [{cell_idx}] ({col},{row}) -> {name}.png  crop={box}")
            else:
                cell_img = img.crop(box)

                # Full size
                full_path = dest_path / f"{name}.png"
                cell_img.save(full_path)

                # Small version
                small_img = cell_img.copy()
                small_img.thumbnail((args.small, args.small), Image.LANCZOS)
                small_path = dest_path / f"{name}_small.png"
                small_img.save(small_path)

                print(f"  [{cell_idx}] ({col},{row}) -> {name}.png ({cw}x{rh}) + {name}_small.png ({args.small}x{args.small})")
                saved += 1

            idx += 1
            x += cw
        y += rh

    if not args.preview:
        print(f"\nSaved {saved} sprites to {dest_path}")
    else:
        print(f"\nPreview mode — {idx} cells mapped, {len(skip)} skipped")


if __name__ == "__main__":
    main()
