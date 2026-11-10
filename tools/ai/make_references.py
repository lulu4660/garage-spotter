#!/usr/bin/env python3
"""Prépare les images de référence à partir des deux planches du projet (fond sombre uni) :

  tools/ai/src/silhouettes.jpg  15 voitures grises, une par carrosserie
  tools/ai/src/style.jpg        15 voitures en couleur (style et angle voulus)
  tools/ai/src/supercar.png     silhouette de supercar (absente de la planche grise)

Produit :
  assets/silhouettes/<carrosserie>.png, _s.png, .json   silhouettes du jeu (voiture pas encore mise à neuf)
  tools/ai/guides/<carrosserie>.png                     guide d'angle envoyé à l'IA (silhouette sur fond blanc)
  tools/ai/style_sheet.png                              planche de style envoyée à l'IA (12 voitures sur fond blanc)

Usage : python3 tools/ai/make_references.py   (demande numpy, scipy, Pillow)
"""
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_cars as gc  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SIL_OUT = os.path.join(gc.ROOT, "assets", "silhouettes")
GUIDES = os.path.join(HERE, "guides")
# Ordre des voitures sur la planche grise, rangée par rangée.
BODIES = ["citadine", "compacte", "berline", "break", "4x4",
          "suv", "monospace", "combi", "coupe", "fastback",
          "cabriolet", "roadster", "sportback", "pickup", "fourgon"]


def cut(path, thr=7):
    """Découpe chaque voiture d'une planche à fond uni : liste d'images RGBA, dans l'ordre de lecture."""
    im = np.asarray(Image.open(path).convert("RGB")).astype(int)
    bg = np.median(im[:100].reshape(-1, 3), axis=0)
    m = np.abs(im - bg).max(axis=2) > thr
    lab, _ = ndi.label(ndi.binary_closing(m, iterations=6))
    out = []
    for i, sl in enumerate(ndi.find_objects(lab)):
        if sl[1].stop - sl[1].start < 120 or sl[0].stop - sl[0].start < 50:
            continue
        pad = 6
        y0, y1 = max(0, sl[0].start - pad), sl[0].stop + pad
        x0, x1 = max(0, sl[1].start - pad), sl[1].stop + pad
        mm = m[y0:y1, x0:x1] & ndi.binary_dilation(lab[y0:y1, x0:x1] == i + 1, iterations=2)
        # Contours et pneus ont presque la couleur du fond : on comble les trous, on épaissit d'1 px.
        mm = ndi.binary_dilation(ndi.binary_fill_holes(ndi.binary_closing(mm, iterations=3)), iterations=1)
        rgba = np.dstack([im[y0:y1, x0:x1], mm * 255]).astype(np.uint8)
        out.append(((sl[0].start, sl[1].start), Image.fromarray(rgba, "RGBA")))
    out.sort(key=lambda t: (round(t[0][0] / 300), t[0][1]))
    return [o[1] for o in out]


def on_white(car, size):
    canvas = Image.new("RGB", size, (255, 255, 255))
    canvas.paste(car, ((size[0] - car.width) // 2, (size[1] - car.height) // 2), car)
    return canvas


def save_silhouette(body, car):
    """Silhouette du jeu (grande, vignette, points d'ancrage) et guide d'angle pour l'IA."""
    big = gc.to_pixel_art(car, gc.BIG_W)
    big.save(os.path.join(SIL_OUT, body + ".png"))
    gc.to_pixel_art(car, gc.SMALL_W).save(os.path.join(SIL_OUT, body + "_s.png"))
    json.dump(gc.meta(big), open(os.path.join(SIL_OUT, body + ".json"), "w"), indent=1)
    on_white(car, (400, 280)).save(os.path.join(GUIDES, body + ".png"))


def main():
    os.makedirs(SIL_OUT, exist_ok=True)
    os.makedirs(GUIDES, exist_ok=True)
    grey = cut(os.path.join(HERE, "src", "silhouettes.jpg"))
    assert len(grey) == len(BODIES), len(grey)
    for body, car in zip(BODIES, grey):
        save_silhouette(body, car)
    # La planche n'a pas de supercar : silhouette générée à part dans le même style.
    save_silhouette("supercar", Image.open(os.path.join(HERE, "src", "supercar.png")).convert("RGBA"))
    # Planche de style : 12 voitures en couleur, 3 par rangée, sur fond blanc (moins de 512 px de côté).
    colour = cut(os.path.join(HERE, "src", "style.jpg"))[:12]
    sheet = Image.new("RGB", (498, 400), (255, 255, 255))
    for i, car in enumerate(colour):
        car = car.resize((160, round(car.height * 160 / car.width)), Image.LANCZOS)
        sheet.paste(car, (4 + (i % 3) * 166, 4 + (i // 3) * 100 + (92 - car.height) // 2), car)
    sheet.save(gc.STYLE)
    print("ok :", len(grey), "silhouettes,", len(colour), "voitures de style")


if __name__ == "__main__":
    main()
