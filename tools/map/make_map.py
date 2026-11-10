#!/usr/bin/env python3
"""Prépare la map de la ville à partir des deux images de référence (générées par IA) :

  tools/map/src/day.jpg    la ville de jour (la base affichée)
  tools/map/src/night.jpg  la même ville de nuit (sert seulement à savoir où sont les lumières)

Produit, à la taille du jeu (moitié de l'image source, 1 pixel de map = 1 pixel du jeu) :
  assets/map/day.png    la ville de jour
  assets/map/light.png  la lumière ajoutée la nuit (fenêtres, vitrines, lampadaires, néons) :
                        nuit = jour × AMBIENT + light, ce qui redonne l'image de nuit de référence
  assets/map/lamps.json les sources les plus fortes (halos doux dessinés à la résolution de l'écran)
  assets/map/front.png  masque des bâtiments qui passent devant les voitures (redessinés par-dessus)

Usage : python3 tools/map/make_map.py   (numpy, scipy, Pillow)
"""
import json
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "tools", "map", "src")
OUT = os.path.join(ROOT, "assets", "map")


# Bâtiments qui cachent les voitures passant derrière eux (polygones en coordonnées de la map).
FRONT = [
    [(352, 727), (427, 687), (511, 730), (512, 786), (434, 822), (350, 781)],  # showroom
]


def main():
    os.makedirs(OUT, exist_ok=True)
    day_src = Image.open(os.path.join(SRC, "day.jpg")).convert("RGB")
    size = (day_src.width // 2, day_src.height // 2)
    day = day_src.resize(size, Image.BOX)
    night = Image.open(os.path.join(SRC, "night.jpg")).convert("RGB").resize(size, Image.BOX)
    d = np.asarray(day).astype(float) / 255
    n = np.asarray(night).astype(float) / 255
    lum = lambda a: a @ np.array([0.299, 0.587, 0.114])
    # Teinte de nuit (lumière ambiante) : ajustée sur les zones non éclairées de l'image de nuit.
    dark = lum(n) < np.percentile(lum(n), 60)
    k = [(n[..., c][dark] * d[..., c][dark]).sum() / (d[..., c][dark] ** 2).sum() for c in range(3)]
    light = np.clip(n - d * np.array(k), 0, 1)
    # Le léger bruit de compression ne doit pas s'allumer : seuil doux.
    light *= np.clip((lum(light) - 0.03) / 0.05, 0, 1)[..., None]
    day.save(os.path.join(OUT, "day.png"))
    Image.fromarray((light * 255).round().astype(np.uint8)).save(os.path.join(OUT, "light.png"))
    # Sources fortes : centres des taches les plus lumineuses.
    strong = lum(light) > 0.42
    lab, count = ndi.label(ndi.binary_dilation(strong, iterations=2))
    lamps = []
    for i, sl in enumerate(ndi.find_objects(lab)):
        area = int((lab[sl] == i + 1).sum())
        if area < 6:
            continue
        ys, xs = np.nonzero(lab[sl] == i + 1)
        cy, cx = ys.mean() + sl[0].start, xs.mean() + sl[1].start
        col = light[sl][lab[sl] == i + 1].mean(axis=0)
        col = col / max(col.max(), 1e-3)
        lamps.append([int(cx), int(cy), min(area, 400), [round(float(c), 2) for c in col]])
    mask = Image.new("L", size, 0)
    for poly in FRONT:
        ImageDraw.Draw(mask).polygon(poly, fill=255)
    mask.save(os.path.join(OUT, "front.png"))
    json.dump({"ambient": [round(float(v), 3) for v in k], "size": list(size), "lamps": lamps},
              open(os.path.join(OUT, "lamps.json"), "w"))
    print("map", size, "ambiance", np.round(k, 3), "sources", len(lamps))


if __name__ == "__main__":
    main()
