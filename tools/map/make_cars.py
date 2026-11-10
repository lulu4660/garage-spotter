#!/usr/bin/env python3
"""Petites voitures des clients sur la map, à partir des deux planches d'angles :

  tools/map/src/cars_hatch.jpg  citadine rouge, 24 angles (fond blanc)
  tools/map/src/cars_sedan.jpg  berline bleue, 27 angles (fond vert)

On garde, pour chaque voiture, les quatre directions des rues de la map (avant vers le haut-droite,
le bas-droite, le bas-gauche, le haut-gauche), réduites en pixel art (≈ 26 px de long), et on
remplace la peinture par du gris : le jeu la recolore à la couleur voulue (shader de city_map.gd).

Produit assets/map/cars.png (atlas : une rangée par voiture, une colonne par direction),
assets/map/cars_paint.png (masque de la peinture) et assets/map/cars.json (cases et points de contact).
Usage : python3 tools/map/make_cars.py   (numpy, scipy, Pillow)
"""
import colorsys
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "tools", "map", "src")
OUT = os.path.join(ROOT, "assets", "map")
DIRS = ["ne", "se", "sw", "nw"]
# Case de la planche (ordre de lecture) pour chaque direction.
SHEETS = [
    {"file": "cars_hatch.jpg", "cells": {"ne": 18, "se": 0, "sw": 2, "nw": 12}, "paint": "red"},
    {"file": "cars_sedan.jpg", "cells": {"ne": 14, "se": 7, "sw": 0, "nw": 22}, "paint": "blue"},
]
LENGTH = 26
CELL = (32, 26)
OUTLINE = (13, 11, 18, 255)


def cells(path):
    im = np.asarray(Image.open(path).convert("RGB")).astype(int)
    bg = np.median(im[5:30, 5:30].reshape(-1, 3), axis=0)
    m = np.abs(im - bg).max(axis=2) > 40
    lab, _ = ndi.label(ndi.binary_closing(m, iterations=3))
    boxes = []
    for sl in ndi.find_objects(lab):
        if sl[1].stop - sl[1].start > 120 and sl[0].stop - sl[0].start > 80:
            boxes.append((sl[0].start, sl[1].start, sl[0].stop, sl[1].stop))
    boxes.sort(key=lambda b: (round(b[0] / 200), b[1]))
    return im, bg, boxes


def cut(im, bg, box):
    """La voiture seule (RGBA) : fond et ombre portée retirés par remplissage depuis les bords."""
    y0, x0, y1, x1 = box
    sub = im[max(0, y0 - 4):y1 + 4, max(0, x0 - 4):x1 + 4]
    bh, bl, bs = colorsys.rgb_to_hls(*(bg / 255))
    flat = sub.reshape(-1, 3) / 255
    hls = np.array([colorsys.rgb_to_hls(*p) for p in flat]).reshape(sub.shape[0], sub.shape[1], 3)
    dist = np.abs(sub - bg).max(axis=2)
    if bs < 0.1:  # fond blanc : le blanc et l'ombre grise peu saturée
        bgish = (dist < 40) | ((hls[..., 2] < 0.12) & (hls[..., 1] > 0.55))
    else:  # fond vert : le vert et son ombre (même teinte, plus sombre)
        bgish = (dist < 40) | ((np.abs(hls[..., 0] - bh) < 0.06) & (hls[..., 2] > 0.15))
    lab, _ = ndi.label(bgish)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    out = np.isin(lab, list(border))
    car = ~out
    lab2, n = ndi.label(car)
    if n > 1:
        sizes = ndi.sum(car, lab2, range(1, n + 1))
        car = lab2 == (1 + int(np.argmax(sizes)))
    car = ndi.binary_fill_holes(car)
    rgba = np.dstack([sub, car * 255]).astype(np.uint8)
    img = Image.fromarray(rgba, "RGBA")
    return img.crop(img.getbbox())


def is_paint(rgb, kind):
    h, l, s = colorsys.rgb_to_hls(*(np.array(rgb[:3]) / 255))
    if kind == "red":
        return (h < 0.05 or h > 0.94) and s > 0.28 and 0.06 < l < 0.8
    return 0.54 < h < 0.70 and s > 0.18 and 0.08 < l < 0.8


def pixelize(img, scale, kind):
    w = max(1, round(img.width * scale))
    h = max(1, round(img.height * scale))
    small = img.resize((w, h), Image.BOX)
    px = small.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 255) if a >= 128 else (0, 0, 0, 0)
    q = small.convert("RGB").quantize(colors=24, method=Image.Quantize.MEDIANCUT).convert("RGB")
    alpha = small.getchannel("A")
    small = q.convert("RGBA")
    small.putalpha(alpha)
    # Contour sombre d'1 px.
    pad = Image.new("RGBA", (w + 2, h + 2), (0, 0, 0, 0))
    pad.paste(small, (1, 1))
    p = pad.load()
    a = np.array(pad.getchannel("A")) > 0
    ring = ndi.binary_dilation(a) & ~a
    for y, x in zip(*np.nonzero(ring)):
        p[int(x), int(y)] = OUTLINE
    # Peinture : remplacée par du gris (moyenne 0,5) et marquée dans le masque.
    mask = Image.new("L", pad.size, 0)
    mk = mask.load()
    paint = [(x, y) for y in range(pad.height) for x in range(pad.width) if p[x, y][3] and p[x, y] != OUTLINE and is_paint(p[x, y], kind)]
    if paint:
        lums = [sum(p[x, y][:3]) / 765 for x, y in paint]
        mean = sum(lums) / len(lums)
        for (x, y), lv in zip(paint, lums):
            g = int(max(0, min(255, lv / mean * 0.5 * 255)))
            p[x, y] = (g, g, g, 255)
            mk[x, y] = 255
    return pad, mask


def main():
    atlas = Image.new("RGBA", (CELL[0] * len(DIRS), CELL[1] * len(SHEETS)), (0, 0, 0, 0))
    paint = Image.new("L", atlas.size, 0)
    meta = {"cell": list(CELL), "dirs": DIRS, "cars": []}
    for row, sheet in enumerate(SHEETS):
        im, bg, boxes = cells(os.path.join(SRC, sheet["file"]))
        cars = {d: cut(im, bg, boxes[i]) for d, i in sheet["cells"].items()}
        # Même échelle pour les quatre directions : la vue de côté la plus longue fait LENGTH px.
        scale = LENGTH / max(c.width for c in cars.values())
        entry = {}
        for col, d in enumerate(DIRS):
            spr, mask = pixelize(cars[d], scale, sheet["paint"])
            ox = col * CELL[0] + (CELL[0] - spr.width) // 2
            oy = row * CELL[1] + (CELL[1] - spr.height)
            atlas.alpha_composite(spr, (ox, oy))
            paint.paste(mask, (ox, oy), mask)
            # Point de contact au sol : centre de la case, 3 px au-dessus du bas.
            entry[d] = [col * CELL[0], row * CELL[1], CELL[0] // 2, CELL[1] - 3]
        meta["cars"].append(entry)
    atlas.save(os.path.join(OUT, "cars.png"))
    paint.save(os.path.join(OUT, "cars_paint.png"))
    json.dump(meta, open(os.path.join(OUT, "cars.json"), "w"), indent=1)
    print("atlas", atlas.size)


if __name__ == "__main__":
    main()
