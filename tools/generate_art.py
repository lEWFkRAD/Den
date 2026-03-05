#!/usr/bin/env python3
"""
DEN Art Pipeline — Procedural pixel art generator for terrain tiles,
enemy sprites, and character sprites.

Usage:
    python tools/generate_art.py          # Generate everything
    python tools/generate_art.py terrain  # Terrain tiles only
    python tools/generate_art.py enemies  # Enemy sprites only
    python tools/generate_art.py chars    # Missing characters only
"""

import os
import sys
import random
import math
from PIL import Image, ImageDraw

ASSETS = os.path.join(os.path.dirname(__file__), "..", "assets")

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITY
# ═══════════════════════════════════════════════════════════════════════════════

def lerp_color(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))

def noise2d(x, y, seed=0):
    """Simple value noise for texture generation."""
    n = x * 374761393 + y * 668265263 + seed * 1274126177
    n = (n ^ (n >> 13)) * 1274126177
    n = n ^ (n >> 16)
    return (n & 0x7fffffff) / 0x7fffffff

def fbm(x, y, octaves=4, seed=0):
    """Fractal Brownian Motion for natural-looking noise."""
    val = 0.0
    amp = 1.0
    freq = 1.0
    for i in range(octaves):
        val += noise2d(int(x * freq), int(y * freq), seed + i * 31) * amp
        amp *= 0.5
        freq *= 2.0
    return val / 1.93  # Normalize roughly to 0-1

def dither(val, x, y):
    """Bayer 4x4 dithering threshold."""
    bayer = [
        [0, 8, 2, 10],
        [12, 4, 14, 6],
        [3, 11, 1, 9],
        [15, 7, 13, 5],
    ]
    threshold = bayer[y % 4][x % 4] / 16.0
    return 1 if val > threshold else 0

def save_tile(img, name, folder="tiles"):
    path = os.path.join(ASSETS, folder)
    os.makedirs(path, exist_ok=True)
    filepath = os.path.join(path, f"{name}.png")
    img.save(filepath)
    print(f"  OK {folder}/{name}.png ({img.size[0]}x{img.size[1]})")
    return filepath

def save_sprite(img, name, folder, make_small=True):
    path = os.path.join(ASSETS, folder)
    os.makedirs(path, exist_ok=True)
    # Full size
    filepath = os.path.join(path, f"{name}.png")
    img.save(filepath)
    print(f"  OK {folder}/{name}.png ({img.size[0]}x{img.size[1]})")
    # Small (64x64) for grid display
    if make_small:
        small = img.resize((64, 64), Image.NEAREST)
        small_path = os.path.join(path, f"{name}_small.png")
        small.save(small_path)
        print(f"  OK {folder}/{name}_small.png (64x64)")


# ═══════════════════════════════════════════════════════════════════════════════
# TERRAIN TILE GENERATION (64x64 tileable textures)
# ═══════════════════════════════════════════════════════════════════════════════

TILE_SIZE = 64

def gen_grass():
    """Lush grass tile — dark greens with subtle blades."""
    img = Image.new("RGBA", (TILE_SIZE, TILE_SIZE))
    rng = random.Random(42)
    base_colors = [
        (34, 58, 28), (38, 65, 30), (42, 70, 34), (30, 52, 24),
        (36, 62, 32), (40, 68, 28), (32, 55, 26),
    ]
    for y in range(TILE_SIZE):
        for x in range(TILE_SIZE):
            n = fbm(x, y, 4, seed=100)
            idx = int(n * len(base_colors)) % len(base_colors)
            c = base_colors[idx]
            # Add subtle per-pixel variation
            v = rng.randint(-4, 4)
            img.putpixel((x, y), (max(0, c[0]+v), max(0, c[1]+v), max(0, c[2]+v), 255))
    # Draw grass blade highlights
    for _ in range(80):
        bx = rng.randint(0, TILE_SIZE-1)
        by = rng.randint(0, TILE_SIZE-1)
        length = rng.randint(2, 5)
        col = rng.choice([(52, 82, 40), (48, 78, 36), (58, 88, 44)])
        for dy in range(length):
            py = by - dy
            if 0 <= py < TILE_SIZE:
                img.putpixel((bx, py), (*col, 255))
    return img

def gen_dirt():
    """Earthy dirt tile — browns with pebbles."""
    img = Image.new("RGBA", (TILE_SIZE, TILE_SIZE))
    rng = random.Random(43)
    base_colors = [
        (72, 52, 34), (78, 56, 38), (68, 48, 32), (82, 60, 40),
        (74, 54, 36), (66, 46, 30),
    ]
    for y in range(TILE_SIZE):
        for x in range(TILE_SIZE):
            n = fbm(x, y, 3, seed=200)
            idx = int(n * len(base_colors)) % len(base_colors)
            c = base_colors[idx]
            v = rng.randint(-3, 3)
            img.putpixel((x, y), (max(0, c[0]+v), max(0, c[1]+v), max(0, c[2]+v), 255))
    # Pebbles
    for _ in range(25):
        px = rng.randint(1, TILE_SIZE-2)
        py = rng.randint(1, TILE_SIZE-2)
        col = rng.choice([(88, 68, 48), (62, 44, 28), (96, 74, 52)])
        img.putpixel((px, py), (*col, 255))
        img.putpixel((px+1, py), (*lerp_color(col, (100, 80, 56), 0.3), 255))
    return img

def gen_stone():
    """Stone/cobble tile — grays with cracks."""
    img = Image.new("RGBA", (TILE_SIZE, TILE_SIZE))
    rng = random.Random(44)
    for y in range(TILE_SIZE):
        for x in range(TILE_SIZE):
            n = fbm(x, y, 4, seed=300)
            base = int(55 + n * 35)
            v = rng.randint(-3, 3)
            g = max(0, min(255, base + v))
            # Slight warm tint
            img.putpixel((x, y), (g, g-2, g-4, 255))
    # Draw crack lines
    draw = ImageDraw.Draw(img)
    for _ in range(6):
        cx = rng.randint(0, TILE_SIZE-1)
        cy = rng.randint(0, TILE_SIZE-1)
        for step in range(rng.randint(4, 12)):
            nx = cx + rng.choice([-1, 0, 1])
            ny = cy + rng.choice([-1, 0, 1])
            if 0 <= nx < TILE_SIZE and 0 <= ny < TILE_SIZE:
                img.putpixel((nx, ny), (38, 35, 32, 255))
                cx, cy = nx, ny
    return img

def gen_sand():
    """Desert sand tile — warm yellows."""
    img = Image.new("RGBA", (TILE_SIZE, TILE_SIZE))
    rng = random.Random(45)
    base_colors = [
        (168, 142, 90), (175, 148, 95), (162, 136, 86), (180, 154, 100),
        (172, 144, 92), (158, 132, 82),
    ]
    for y in range(TILE_SIZE):
        for x in range(TILE_SIZE):
            n = fbm(x, y, 3, seed=400)
            idx = int(n * len(base_colors)) % len(base_colors)
            c = base_colors[idx]
            v = rng.randint(-3, 3)
            img.putpixel((x, y), (max(0, c[0]+v), max(0, c[1]+v), max(0, c[2]+v), 255))
    # Wind ripple lines
    for ry in range(0, TILE_SIZE, rng.randint(6, 10)):
        for x in range(TILE_SIZE):
            offset = int(math.sin(x * 0.2) * 1.5)
            py = (ry + offset) % TILE_SIZE
            if 0 <= py < TILE_SIZE:
                curr = img.getpixel((x, py))
                lighter = tuple(min(255, c + 8) for c in curr[:3]) + (255,)
                img.putpixel((x, py), lighter)
    return img

def gen_snow():
    """Snow tile — whites and pale blues."""
    img = Image.new("RGBA", (TILE_SIZE, TILE_SIZE))
    rng = random.Random(46)
    for y in range(TILE_SIZE):
        for x in range(TILE_SIZE):
            n = fbm(x, y, 3, seed=500)
            base = int(195 + n * 40)
            v = rng.randint(-3, 3)
            r = max(0, min(255, base + v - 2))
            g = max(0, min(255, base + v))
            b = max(0, min(255, base + v + 4))
            img.putpixel((x, y), (r, g, b, 255))
    # Sparkle highlights
    for _ in range(30):
        sx = rng.randint(0, TILE_SIZE-1)
        sy = rng.randint(0, TILE_SIZE-1)
        img.putpixel((sx, sy), (240, 242, 248, 255))
    return img

def gen_water():
    """Water tile — dark blues with wave patterns."""
    img = Image.new("RGBA", (TILE_SIZE, TILE_SIZE))
    rng = random.Random(47)
    for y in range(TILE_SIZE):
        for x in range(TILE_SIZE):
            wave = math.sin(x * 0.25 + y * 0.15) * 0.5 + 0.5
            n = fbm(x, y, 3, seed=600)
            blend = wave * 0.6 + n * 0.4
            r = int(18 + blend * 20)
            g = int(42 + blend * 30)
            b = int(78 + blend * 40)
            img.putpixel((x, y), (r, g, b, 255))
    # Wave crests
    for wy in range(0, TILE_SIZE, 8):
        for x in range(TILE_SIZE):
            offset = int(math.sin(x * 0.3 + wy) * 2)
            py = (wy + offset) % TILE_SIZE
            if 0 <= py < TILE_SIZE:
                img.putpixel((x, py), (45, 72, 115, 255))
                if py + 1 < TILE_SIZE:
                    img.putpixel((x, py+1), (55, 82, 125, 255))
    return img

def gen_lava():
    """Lava tile — blacks and oranges with glowing cracks."""
    img = Image.new("RGBA", (TILE_SIZE, TILE_SIZE))
    rng = random.Random(48)
    # Dark volcanic base
    for y in range(TILE_SIZE):
        for x in range(TILE_SIZE):
            n = fbm(x, y, 3, seed=700)
            base = int(18 + n * 20)
            img.putpixel((x, y), (base + 4, base, base, 255))
    # Glowing lava cracks
    for _ in range(8):
        cx = rng.randint(0, TILE_SIZE-1)
        cy = rng.randint(0, TILE_SIZE-1)
        for step in range(rng.randint(6, 18)):
            nx = cx + rng.choice([-1, 0, 1])
            ny = cy + rng.choice([-1, 0, 1])
            if 0 <= nx < TILE_SIZE and 0 <= ny < TILE_SIZE:
                # Hot core
                img.putpixel((nx, ny), (220, 120, 20, 255))
                # Warm glow around
                for dx in [-1, 0, 1]:
                    for dy in [-1, 0, 1]:
                        gx, gy = nx + dx, ny + dy
                        if 0 <= gx < TILE_SIZE and 0 <= gy < TILE_SIZE:
                            curr = img.getpixel((gx, gy))
                            if curr[0] < 100:  # Don't overwrite existing glow
                                img.putpixel((gx, gy), (80, 30, 8, 255))
                cx, cy = nx, ny
    return img

def gen_void():
    """Dark void ground — deep purples and blacks."""
    img = Image.new("RGBA", (TILE_SIZE, TILE_SIZE))
    rng = random.Random(49)
    for y in range(TILE_SIZE):
        for x in range(TILE_SIZE):
            n = fbm(x, y, 4, seed=800)
            base = int(8 + n * 18)
            r = base + 6
            g = base - 2
            b = base + 12
            img.putpixel((x, y), (max(0, r), max(0, g), max(0, min(255, b)), 255))
    # Arcane glimmers
    for _ in range(15):
        sx = rng.randint(0, TILE_SIZE-1)
        sy = rng.randint(0, TILE_SIZE-1)
        col = rng.choice([(80, 20, 120), (60, 15, 90), (100, 30, 140)])
        img.putpixel((sx, sy), (*col, 255))
    return img

def gen_ice():
    """Ice tile — pale blues with crystalline patterns."""
    img = Image.new("RGBA", (TILE_SIZE, TILE_SIZE))
    rng = random.Random(50)
    for y in range(TILE_SIZE):
        for x in range(TILE_SIZE):
            n = fbm(x, y, 3, seed=850)
            base = int(155 + n * 50)
            r = max(0, min(255, base - 15))
            g = max(0, min(255, base - 5))
            b = max(0, min(255, base + 10))
            img.putpixel((x, y), (r, g, b, 255))
    # Crystal facet lines
    for _ in range(5):
        cx = rng.randint(0, TILE_SIZE-1)
        cy = rng.randint(0, TILE_SIZE-1)
        dx = rng.choice([-1, 0, 1])
        dy = rng.choice([-1, 0, 1])
        for step in range(rng.randint(5, 15)):
            if 0 <= cx < TILE_SIZE and 0 <= cy < TILE_SIZE:
                img.putpixel((cx, cy), (185, 210, 235, 255))
            cx += dx
            cy += dy
            if rng.random() < 0.2:
                dx = rng.choice([-1, 0, 1])
                dy = rng.choice([-1, 0, 1])
    return img

def gen_ruins():
    """Ruined stone — cracked cobbles with moss."""
    img = gen_stone()  # Start from stone base
    rng = random.Random(51)
    # More cracks
    for _ in range(10):
        cx = rng.randint(0, TILE_SIZE-1)
        cy = rng.randint(0, TILE_SIZE-1)
        for step in range(rng.randint(3, 10)):
            nx = cx + rng.choice([-1, 0, 1])
            ny = cy + rng.choice([-1, 0, 1])
            if 0 <= nx < TILE_SIZE and 0 <= ny < TILE_SIZE:
                img.putpixel((nx, ny), (32, 28, 24, 255))
                cx, cy = nx, ny
    # Moss patches
    for _ in range(12):
        mx = rng.randint(2, TILE_SIZE-3)
        my = rng.randint(2, TILE_SIZE-3)
        for dx in range(-1, 2):
            for dy in range(-1, 2):
                if rng.random() < 0.6:
                    px, py = mx + dx, my + dy
                    if 0 <= px < TILE_SIZE and 0 <= py < TILE_SIZE:
                        img.putpixel((px, py), (
                            rng.randint(32, 48),
                            rng.randint(55, 72),
                            rng.randint(28, 40),
                            255
                        ))
    return img

def gen_road():
    """Packed road — worn brown-gray path."""
    img = Image.new("RGBA", (TILE_SIZE, TILE_SIZE))
    rng = random.Random(52)
    for y in range(TILE_SIZE):
        for x in range(TILE_SIZE):
            n = fbm(x, y, 3, seed=900)
            base = int(62 + n * 22)
            r = base + 8
            g = base + 4
            b = base - 4
            img.putpixel((x, y), (max(0, r), max(0, g), max(0, b), 255))
    # Wheel rut lines
    for rx in [20, 44]:
        for y in range(TILE_SIZE):
            v = rng.randint(-2, 2)
            px = (rx + v) % TILE_SIZE
            curr = img.getpixel((px, y))
            darker = tuple(max(0, c - 12) for c in curr[:3]) + (255,)
            img.putpixel((px, y), darker)
    return img

def gen_forest_floor():
    """Forest floor — dark greens with leaf litter."""
    img = gen_grass()
    rng = random.Random(53)
    # Darken overall
    for y in range(TILE_SIZE):
        for x in range(TILE_SIZE):
            c = img.getpixel((x, y))
            darker = (max(0, c[0]-12), max(0, c[1]-8), max(0, c[2]-10), 255)
            img.putpixel((x, y), darker)
    # Leaf scatter
    leaf_colors = [(64, 42, 18), (58, 38, 14), (48, 34, 16), (72, 48, 22)]
    for _ in range(40):
        lx = rng.randint(0, TILE_SIZE-1)
        ly = rng.randint(0, TILE_SIZE-1)
        col = rng.choice(leaf_colors)
        img.putpixel((lx, ly), (*col, 255))
        if lx + 1 < TILE_SIZE:
            img.putpixel((lx+1, ly), (*col, 255))
    # Tree root shadows
    for _ in range(4):
        rx = rng.randint(0, TILE_SIZE-1)
        ry = rng.randint(0, TILE_SIZE-1)
        for step in range(rng.randint(3, 8)):
            if 0 <= rx < TILE_SIZE and 0 <= ry < TILE_SIZE:
                c = img.getpixel((rx, ry))
                img.putpixel((rx, ry), (max(0, c[0]-15), max(0, c[1]-10), max(0, c[2]-12), 255))
            rx += rng.choice([-1, 0, 1])
            ry += rng.choice([0, 1])
    return img

def generate_terrain():
    print("\n=== TERRAIN TILES ===")
    tiles = {
        "grass": gen_grass,
        "dirt": gen_dirt,
        "stone": gen_stone,
        "sand": gen_sand,
        "snow": gen_snow,
        "water": gen_water,
        "lava": gen_lava,
        "void": gen_void,
        "ice": gen_ice,
        "ruins": gen_ruins,
        "road": gen_road,
        "forest": gen_forest_floor,
    }
    for name, gen_fn in tiles.items():
        img = gen_fn()
        save_tile(img, name)
    print(f"  Generated {len(tiles)} terrain tiles")


# ═══════════════════════════════════════════════════════════════════════════════
# CHARACTER / UNIT SPRITE GENERATION
# ═══════════════════════════════════════════════════════════════════════════════

SPRITE_SIZE = 64  # Grid sprite size

# Palette: dark fantasy tactical RPG
SKIN_TONES = [(182, 148, 118), (165, 130, 100), (140, 105, 75), (200, 165, 135)]

# Element colors for enemy tinting
ELEMENT_COLORS = {
    "blood":    (180, 30, 30),
    "void":     (100, 30, 160),
    "dark":     (60, 40, 80),
    "light":    (210, 195, 140),
    "electric": (60, 140, 200),
    "ice":      (140, 190, 220),
    "plant":    (50, 120, 50),
    "fire":     (200, 90, 20),
    "":         (120, 115, 110),   # neutral
}

def draw_humanoid(img, palette, features=None):
    """Draw a pixel art humanoid character on a 64x64 canvas.

    palette: dict with keys: skin, armor_primary, armor_secondary, accent, hair, weapon_color
    features: dict with optional keys: helmet, cape, shield, weapon_type, bulky, hooded
    """
    if features is None:
        features = {}
    draw = ImageDraw.Draw(img)
    skin = palette["skin"]
    p1 = palette["armor_primary"]
    p2 = palette["armor_secondary"]
    accent = palette["accent"]
    hair = palette["hair"]
    w_col = palette.get("weapon_color", (160, 160, 170))

    cx = 32  # Center x

    # Cape (behind body)
    if features.get("cape"):
        cape_col = palette.get("cape_color", lerp_color(p1, (20, 20, 20), 0.3))
        draw.rectangle([cx-8, 18, cx+7, 50], fill=cape_col)
        draw.rectangle([cx-9, 22, cx-8, 48], fill=lerp_color(cape_col, (0,0,0), 0.2))
        draw.rectangle([cx+8, 22, cx+8, 48], fill=lerp_color(cape_col, (0,0,0), 0.2))

    # Legs
    leg_col = lerp_color(p2, (40, 40, 40), 0.2)
    draw.rectangle([cx-5, 42, cx-2, 54], fill=leg_col)
    draw.rectangle([cx+1, 42, cx+4, 54], fill=leg_col)
    # Boots
    boot_col = lerp_color(p2, (30, 25, 20), 0.4)
    draw.rectangle([cx-6, 52, cx-1, 56], fill=boot_col)
    draw.rectangle([cx, 52, cx+5, 56], fill=boot_col)

    # Body / torso
    body_w = 7 if features.get("bulky") else 6
    draw.rectangle([cx-body_w, 24, cx+body_w-1, 42], fill=p1)
    # Armor detail lines
    draw.rectangle([cx-1, 26, cx, 40], fill=p2)
    # Belt
    draw.rectangle([cx-body_w, 40, cx+body_w-1, 42], fill=lerp_color(p2, (60, 50, 30), 0.5))
    draw.point((cx, 41), fill=accent)

    # Shoulder pads
    if features.get("bulky") or features.get("helmet"):
        draw.rectangle([cx-body_w-2, 24, cx-body_w, 28], fill=p2)
        draw.rectangle([cx+body_w, 24, cx+body_w+2, 28], fill=p2)

    # Arms
    draw.rectangle([cx-body_w-1, 26, cx-body_w, 40], fill=p1)
    draw.rectangle([cx+body_w, 26, cx+body_w+1, 40], fill=p1)
    # Hands
    draw.rectangle([cx-body_w-1, 38, cx-body_w, 40], fill=skin)
    draw.rectangle([cx+body_w, 38, cx+body_w+1, 40], fill=skin)

    # Head
    head_top = 10
    head_w = 5
    draw.rectangle([cx-head_w, head_top, cx+head_w-1, head_top+12], fill=skin)

    # Hair / helmet
    if features.get("helmet"):
        helm_col = p2
        draw.rectangle([cx-head_w-1, head_top-2, cx+head_w, head_top+4], fill=helm_col)
        # Visor slit
        draw.rectangle([cx-3, head_top+4, cx+2, head_top+5], fill=(20, 20, 25))
        # Crest
        draw.rectangle([cx-1, head_top-4, cx, head_top-1], fill=accent)
    elif features.get("hooded"):
        hood_col = lerp_color(p1, (30, 30, 35), 0.3)
        draw.rectangle([cx-head_w-1, head_top-2, cx+head_w, head_top+6], fill=hood_col)
        draw.rectangle([cx-head_w-2, head_top+2, cx+head_w+1, head_top+6], fill=hood_col)
        # Shadow face
        draw.rectangle([cx-3, head_top+4, cx+2, head_top+6], fill=(25, 22, 20))
        # Eyes glowing in shadow
        draw.point((cx-2, head_top+5), fill=accent)
        draw.point((cx+1, head_top+5), fill=accent)
    else:
        draw.rectangle([cx-head_w, head_top-2, cx+head_w-1, head_top+2], fill=hair)
        if features.get("long_hair"):
            draw.rectangle([cx-head_w-1, head_top, cx-head_w, head_top+14], fill=hair)
            draw.rectangle([cx+head_w, head_top, cx+head_w+1, head_top+14], fill=hair)

    # Eyes (if no helmet/hood)
    if not features.get("helmet") and not features.get("hooded"):
        eye_y = head_top + 6
        draw.point((cx-2, eye_y), fill=(30, 30, 35))
        draw.point((cx+1, eye_y), fill=(30, 30, 35))

    # Weapon
    wt = features.get("weapon_type", "sword")
    if wt == "sword":
        draw.rectangle([cx+body_w+2, 14, cx+body_w+3, 42], fill=w_col)
        draw.rectangle([cx+body_w+1, 34, cx+body_w+4, 36], fill=lerp_color(w_col, (80, 60, 30), 0.5))
        draw.point((cx+body_w+2, 14), fill=(220, 220, 230))  # Tip glint
    elif wt == "bow":
        # Bow arc
        for i in range(14):
            bx = cx + body_w + 3 + int(math.sin(i * 0.45) * 3)
            by = 16 + i * 2
            if 0 <= bx < 64 and 0 <= by < 64:
                draw.point((bx, by), fill=(90, 60, 30))
        # String
        draw.line([(cx+body_w+3, 16), (cx+body_w+3, 42)], fill=(180, 170, 150))
    elif wt == "staff":
        draw.rectangle([cx+body_w+2, 6, cx+body_w+3, 44], fill=(80, 55, 30))
        # Orb on top
        draw.ellipse([cx+body_w, 4, cx+body_w+5, 9], fill=accent)
        draw.point((cx+body_w+2, 5), fill=(255, 255, 240))
    elif wt == "axe":
        draw.rectangle([cx+body_w+2, 12, cx+body_w+3, 42], fill=(100, 70, 40))
        # Axe head
        draw.rectangle([cx+body_w+3, 12, cx+body_w+7, 20], fill=w_col)
        draw.point((cx+body_w+7, 16), fill=(200, 200, 210))
    elif wt == "spear":
        draw.rectangle([cx+body_w+2, 4, cx+body_w+3, 44], fill=(100, 75, 40))
        # Spear tip
        draw.polygon([(cx+body_w+1, 8), (cx+body_w+4, 8), (cx+body_w+2, 2)], fill=w_col)
    elif wt == "dagger":
        draw.rectangle([cx+body_w+2, 28, cx+body_w+3, 40], fill=w_col)
        draw.point((cx+body_w+2, 28), fill=(220, 220, 230))
    elif wt == "shield":
        # Shield on left arm
        draw.rectangle([cx-body_w-4, 26, cx-body_w-1, 38], fill=p2)
        draw.rectangle([cx-body_w-3, 28, cx-body_w-2, 36], fill=accent)
    elif wt == "greatsword":
        draw.rectangle([cx+body_w+2, 8, cx+body_w+4, 44], fill=w_col)
        draw.rectangle([cx+body_w, 32, cx+body_w+6, 34], fill=lerp_color(w_col, (80, 60, 30), 0.5))
        draw.point((cx+body_w+3, 8), fill=(240, 240, 250))

    # Shield (separate from weapon)
    if features.get("shield"):
        draw.rectangle([cx-body_w-4, 26, cx-body_w-1, 38], fill=p2)
        draw.rectangle([cx-body_w-3, 30, cx-body_w-2, 34], fill=accent)


def make_character_sprite(name, palette, features=None):
    """Generate and save a character sprite."""
    img = Image.new("RGBA", (SPRITE_SIZE, SPRITE_SIZE), (0, 0, 0, 0))
    draw_humanoid(img, palette, features)
    return img


# ─── MISSING PLAYER CHARACTERS ──────────────────────────────────────────────

def generate_characters():
    print("\n=== MISSING CHARACTERS ===")

    # Corvin — Rogue class
    corvin = make_character_sprite("corvin", {
        "skin": (175, 140, 110),
        "armor_primary": (42, 38, 48),
        "armor_secondary": (55, 50, 62),
        "accent": (140, 60, 180),
        "hair": (35, 30, 40),
        "weapon_color": (150, 148, 155),
    }, {
        "hooded": True,
        "weapon_type": "dagger",
        "cape": True,
        "cape_color": (38, 32, 48),
    })
    # Full portrait (upscale to ~341x345 to match others)
    corvin_full = corvin.resize((341, 345), Image.NEAREST)
    save_sprite(corvin_full, "corvin", "portraits", make_small=False)
    # Save the 64x64 as _small
    small_path = os.path.join(ASSETS, "portraits", "corvin_small.png")
    corvin.save(small_path)
    print(f"  OK portraits/corvin_small.png (64x64)")

    # Lorn — Warden class
    lorn = make_character_sprite("lorn", {
        "skin": (160, 120, 85),
        "armor_primary": (65, 72, 78),
        "armor_secondary": (82, 90, 95),
        "accent": (170, 140, 60),
        "hair": (45, 40, 35),
        "weapon_color": (140, 140, 150),
    }, {
        "helmet": True,
        "bulky": True,
        "shield": True,
        "weapon_type": "spear",
    })
    lorn_full = lorn.resize((341, 345), Image.NEAREST)
    save_sprite(lorn_full, "lorn", "portraits", make_small=False)
    small_path = os.path.join(ASSETS, "portraits", "lorn_small.png")
    lorn.save(small_path)
    print(f"  OK portraits/lorn_small.png (64x64)")


# ─── ENEMY SPRITES ──────────────────────────────────────────────────────────

ENEMY_DEFS = {
    "grunt": {
        "class": "soldier", "element": "",
        "palette": {"skin": (165, 130, 100), "armor_primary": (85, 55, 40), "armor_secondary": (100, 70, 50), "accent": (140, 40, 40), "hair": (50, 40, 30), "weapon_color": (145, 140, 135)},
        "features": {"weapon_type": "sword"},
    },
    "archer": {
        "class": "archer", "element": "",
        "palette": {"skin": (180, 145, 115), "armor_primary": (70, 65, 50), "armor_secondary": (85, 78, 60), "accent": (130, 100, 50), "hair": (60, 45, 30), "weapon_color": (120, 115, 100)},
        "features": {"weapon_type": "bow"},
    },
    "heavy": {
        "class": "heavy", "element": "",
        "palette": {"skin": (155, 120, 90), "armor_primary": (72, 68, 72), "armor_secondary": (90, 85, 90), "accent": (120, 50, 40), "hair": (40, 35, 30), "weapon_color": (155, 150, 145)},
        "features": {"weapon_type": "axe", "bulky": True, "helmet": True},
    },
    "mage": {
        "class": "mage", "element": "dark",
        "palette": {"skin": (170, 135, 105), "armor_primary": (45, 35, 55), "armor_secondary": (60, 48, 70), "accent": (130, 60, 160), "hair": (55, 40, 60), "weapon_color": (130, 60, 160)},
        "features": {"weapon_type": "staff", "hooded": True},
    },
    "rogue": {
        "class": "rogue", "element": "",
        "palette": {"skin": (175, 140, 110), "armor_primary": (50, 48, 45), "armor_secondary": (65, 62, 58), "accent": (100, 90, 70), "hair": (40, 35, 30), "weapon_color": (160, 155, 150)},
        "features": {"weapon_type": "dagger", "hooded": True, "cape": True, "cape_color": (40, 38, 35)},
    },
    "blood_knight": {
        "class": "knight", "element": "blood",
        "palette": {"skin": (150, 115, 85), "armor_primary": (100, 22, 22), "armor_secondary": (130, 35, 35), "accent": (200, 50, 50), "hair": (45, 30, 30), "weapon_color": (160, 40, 40)},
        "features": {"weapon_type": "greatsword", "helmet": True, "bulky": True, "cape": True, "cape_color": (80, 15, 15)},
    },
    "void_warden": {
        "class": "warden", "element": "void",
        "palette": {"skin": (140, 105, 80), "armor_primary": (50, 28, 70), "armor_secondary": (68, 38, 90), "accent": (160, 80, 220), "hair": (35, 20, 50), "weapon_color": (130, 70, 180)},
        "features": {"weapon_type": "spear", "helmet": True, "shield": True, "bulky": True},
    },
    "commander": {
        "class": "commander", "element": "",
        "palette": {"skin": (165, 130, 100), "armor_primary": (78, 60, 48), "armor_secondary": (95, 75, 58), "accent": (180, 150, 60), "hair": (55, 45, 35), "weapon_color": (170, 165, 155)},
        "features": {"weapon_type": "sword", "cape": True, "cape_color": (65, 50, 38), "helmet": True},
    },
    "priest": {
        "class": "priest", "element": "light",
        "palette": {"skin": (185, 150, 120), "armor_primary": (180, 170, 140), "armor_secondary": (160, 148, 120), "accent": (220, 200, 100), "hair": (190, 175, 140), "weapon_color": (210, 195, 100)},
        "features": {"weapon_type": "staff", "hooded": True},
    },
    "paladin": {
        "class": "paladin", "element": "light",
        "palette": {"skin": (180, 145, 115), "armor_primary": (170, 160, 130), "armor_secondary": (145, 135, 108), "accent": (220, 200, 80), "hair": (180, 165, 130), "weapon_color": (195, 185, 150)},
        "features": {"weapon_type": "sword", "helmet": True, "shield": True, "bulky": True, "cape": True, "cape_color": (150, 140, 110)},
    },
    "assassin": {
        "class": "assassin", "element": "void",
        "palette": {"skin": (160, 125, 95), "armor_primary": (25, 20, 30), "armor_secondary": (38, 32, 45), "accent": (120, 50, 180), "hair": (20, 15, 25), "weapon_color": (110, 60, 160)},
        "features": {"weapon_type": "dagger", "hooded": True, "cape": True, "cape_color": (22, 18, 28)},
    },
    "golem": {
        "class": "golem", "element": "",
        "palette": {"skin": (95, 90, 85), "armor_primary": (80, 75, 72), "armor_secondary": (100, 95, 90), "accent": (140, 80, 40), "hair": (80, 75, 72), "weapon_color": (110, 105, 100)},
        "features": {"weapon_type": "axe", "bulky": True, "helmet": True},
    },
    "siege_mage": {
        "class": "siege_mage", "element": "electric",
        "palette": {"skin": (175, 140, 110), "armor_primary": (35, 55, 75), "armor_secondary": (48, 68, 90), "accent": (80, 180, 240), "hair": (40, 55, 70), "weapon_color": (80, 180, 240)},
        "features": {"weapon_type": "staff", "hooded": True, "cape": True, "cape_color": (30, 48, 65)},
    },
    "covenant_captain": {
        "class": "captain", "element": "light",
        "palette": {"skin": (180, 145, 115), "armor_primary": (160, 150, 120), "armor_secondary": (140, 130, 100), "accent": (230, 210, 90), "hair": (170, 155, 120), "weapon_color": (200, 190, 150)},
        "features": {"weapon_type": "sword", "helmet": True, "shield": True, "cape": True, "cape_color": (140, 130, 100)},
    },
    "warden_corrupted": {
        "class": "warden_corrupt", "element": "blood",
        "palette": {"skin": (130, 95, 75), "armor_primary": (80, 30, 30), "armor_secondary": (100, 40, 40), "accent": (180, 40, 40), "hair": (50, 25, 25), "weapon_color": (140, 35, 35)},
        "features": {"weapon_type": "spear", "helmet": True, "shield": True, "bulky": True, "cape": True, "cape_color": (65, 20, 20)},
    },
    "varek_final": {
        "class": "boss", "element": "blood",
        "palette": {"skin": (140, 100, 72), "armor_primary": (60, 15, 15), "armor_secondary": (90, 25, 25), "accent": (220, 40, 30), "hair": (40, 15, 15), "weapon_color": (180, 30, 25)},
        "features": {"weapon_type": "greatsword", "helmet": True, "bulky": True, "cape": True, "cape_color": (50, 10, 10)},
    },
}

def generate_enemies():
    print("\n=== ENEMY SPRITES ===")
    for eid, edef in ENEMY_DEFS.items():
        img = make_character_sprite(eid, edef["palette"], edef["features"])
        # Full size (upscale to reasonable portrait size)
        full = img.resize((128, 128), Image.NEAREST)
        save_sprite(full, eid, "enemies", make_small=True)


# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════

def main():
    target = sys.argv[1] if len(sys.argv) > 1 else "all"

    print("======================================")
    print("     DEN Art Pipeline Generator       ")
    print("======================================")

    if target in ("all", "terrain"):
        generate_terrain()
    if target in ("all", "enemies"):
        generate_enemies()
    if target in ("all", "chars"):
        generate_characters()

    print("\nArt generation complete!")
    print("  Run the game in Godot to see the new assets.")

if __name__ == "__main__":
    main()
