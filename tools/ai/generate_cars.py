#!/usr/bin/env python3
"""Génère les sprites des voitures du catalogue avec FLUX.2 [klein] 4B (Cloudflare Workers AI).

Pour chaque modèle de scripts/catalog.gd :
  1. rend la carrosserie avec car_renderer.gd (guide pour l'angle et la couleur) ;
  2. demande à FLUX.2 [klein] 4B de la redessiner dans le style de tools/ai/style_ref.png ;
  3. nettoie le résultat en vrai pixel art (fond retiré, grille de pixels nette, palette
     réduite, contour d'1 px) et calcule une carte de reliefs pour l'éclairage dynamique.

Sorties dans assets/cars/ : <id>.png (grand, ~168 px), <id>_s.png (vignette, ~72 px),
<id>_n.png (reliefs du grand) et <id>.json (points d'ancrage). Brut dans tools/ai/out/ (ignoré).

Usage :
  CF_ACCOUNT_ID=... GODOT=/chemin/godot python3 tools/ai/generate_cars.py [ids...] [--force] [--only-process]
Le jeton Cloudflare est lu dans CF_API_TOKEN (dans le conteneur de Claude, le relais réseau
l'ajoute tout seul : mettre CF_API_TOKEN=proxy-injected). Coût : ≈ 37 Neurons par voiture
(10 000 gratuits par jour), voir docs/choix-modele-image.md.
"""
import base64
import colorsys
import json
import math
import os
import re
import subprocess
import sys
import urllib.request
import uuid

from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_RAW = os.path.join(ROOT, "tools", "ai", "out")
OUT = os.path.join(ROOT, "assets", "cars")
STYLE = os.path.join(ROOT, "tools", "ai", "style_sheet.png")
MODEL = "@cf/black-forest-labs/flux-2-klein-4b"
BIG_W = 168
SMALL_W = 72
OUTLINE = (13, 11, 18, 255)

ORIGIN = {
    "Renolt": "French", "Peujo": "French", "Citroan": "French", "Dacio": "Romanian",
    "Volkswagon": "German", "Audy": "German", "BMV": "German", "Mercedez": "German", "Porshe": "German",
    "Toyata": "Japanese", "Nisan": "Japanese", "Mazdo": "Japanese", "Skado": "Czech",
    "Fourd": "American", "Teslo": "American electric", "Land Rouver": "British",
    "Ferari": "Italian", "Lamborgino": "Italian", "Pagany": "Italian", "McLaran": "British",
    "Konigseg": "Swedish", "Mimi": "British",
}
BODY = {
    "citadine": "small city car hatchback", "compacte": "five-door compact hatchback",
    "berline": "four-door saloon sedan", "break": "estate wagon", "4x4": "boxy off-road 4x4 SUV",
    "suv": "crossover SUV", "monospace": "compact MPV people carrier", "combi": "retro passenger van",
    "fourgon": "large panel delivery van", "coupe": "two-door sports coupe",
    "fastback": "sleek four-door fastback sedan", "sportback": "sporty hot hatch",
    "cabriolet": "convertible with the roof down", "roadster": "two-seat roadster with the roof down",
    "pickup": "double-cab pickup truck", "supercar": "mid-engine supercar with sharp lines and side air intakes",
}
RARITY_HINT = ["everyday", "sporty", "high-performance", "exotic", "legendary classic", "hypercar"]
COLORS = {
    "red": (200, 32, 42), "dark red": (140, 25, 30), "orange": (242, 140, 28), "yellow": (227, 200, 74),
    "gold": (217, 180, 74), "lime green": (111, 191, 63), "dark green": (47, 93, 58), "olive green": (79, 90, 58),
    "blue": (47, 111, 209), "navy blue": (31, 58, 92), "steel blue": (63, 111, 143), "white": (244, 241, 234),
    "pearl white": (230, 230, 226), "silver": (168, 172, 178), "grey": (125, 122, 112), "dark grey": (74, 77, 82),
    "black": (43, 43, 46), "beige": (216, 210, 196), "brown": (154, 107, 79),
}


def catalog():
    src = open(os.path.join(ROOT, "scripts", "catalog.gd"), encoding="utf-8").read()
    cars = []
    for m in re.finditer(r'\{"id": "([^"]+)", "brand": "([^"]+)", "name": "([^"]+)", "rarity": (\d), "body": "([^"]+)", "color": "([0-9a-f]{6})"\}', src):
        cars.append({"id": m[1], "brand": m[2], "name": m[3], "rarity": int(m[4]), "body": m[5], "color": m[6]})
    return cars


def color_name(hexa):
    r, g, b = (int(hexa[i:i + 2], 16) for i in (0, 2, 4))
    return min(COLORS, key=lambda k: sum((a - c) ** 2 for a, c in zip(COLORS[k], (r, g, b))))


def is_light(car):
    r, g, b = (int(car["color"][i:i + 2], 16) / 255 for i in (0, 2, 4))
    return colorsys.rgb_to_hls(r, g, b)[1] > 0.75


def prompt_for(car):
    col = color_name(car["color"])
    # Voiture claire : fond vert uni (comme un fond vert de cinéma), sinon le
    # détourage confondrait la carrosserie blanche avec le fond blanc.
    bg = "plain solid bright green background (#00c000)" if is_light(car) else "plain white background"
    desc = "a %s %s %s %s" % (RARITY_HINT[car["rarity"]], col, ORIGIN.get(car["brand"], "European"), BODY[car["body"]])
    return (
        "Detailed modern pixel art sprite of %s. The car body paint MUST be %s, exactly like image 0. "
        "Use image 0 for the body type, the paint colour and the camera angle (three-quarter front view, "
        "front of the car on the LEFT side of the picture). Image 1 is a sheet of example sprites: use only its drawing style, never copy one of its cars or colours: "
        "high-detail pixel art like a premium mobile game, crisp dark outline, glossy paint with sharp highlights, "
        "tinted windows, detailed alloy wheels and headlights, %s, no ground shadow. "
        "Realistic proportions. No logos, no badges, no emblems, no text, no license plate." % (desc, col, bg)
    )


def render_subject(car, path):
    godot = os.environ.get("GODOT", "godot")
    subprocess.run([godot, "--headless", "--path", ROOT, "-s", "tools/ai/render_subject.gd", "--",
                    car["body"], car["color"], path], check=True, capture_output=True)
    im = Image.open(path)
    im.thumbnail((500, 500))
    im.save(path)


def call_api(prompt, files, seed):
    account = os.environ["CF_ACCOUNT_ID"]
    token = os.environ.get("CF_API_TOKEN", "proxy-injected")
    boundary = uuid.uuid4().hex
    body = b""
    fields = {"prompt": prompt, "width": "512", "height": "512", "seed": str(seed)}
    for k, v in fields.items():
        body += ("--%s\r\nContent-Disposition: form-data; name=\"%s\"\r\n\r\n%s\r\n" % (boundary, k, v)).encode()
    for k, path in files.items():
        body += ("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: image/png\r\n\r\n"
                 % (boundary, k, os.path.basename(path))).encode()
        body += open(path, "rb").read() + b"\r\n"
    body += ("--%s--\r\n" % boundary).encode()
    req = urllib.request.Request(
        "https://api.cloudflare.com/client/v4/accounts/%s/ai/run/%s" % (account, MODEL), data=body, method="POST",
        headers={"Authorization": "Bearer " + token, "Content-Type": "multipart/form-data; boundary=" + boundary})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            data = json.load(r)
    except urllib.error.HTTPError as e:
        data = json.load(e)
    if not data.get("success"):
        raise RuntimeError(json.dumps(data.get("errors")))
    return base64.b64decode(data["result"]["image"])


# --- Nettoyage en vrai pixel art -------------------------------------------------

def remove_background(im):
    """Retire le fond (et l'ombre grise claire) relié aux bords : la couleur du fond est
    mesurée dans les coins, car l'image n'est jamais d'un blanc parfait (compression)."""
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    corners = [px[x, y] for x in (2, w - 3) for y in (2, h - 3)]
    bg = tuple(sorted(c[i] for c in corners)[len(corners) // 2] for i in range(3))
    bh, bl, bs = colorsys.rgb_to_hls(*(v / 255 for v in bg))
    green = bs > 0.4 and bl < 0.85  # un quasi-blanc a une « saturation » trompeuse

    def is_bg(c):
        if sum((c[i] - bg[i]) ** 2 for i in range(3)) < (70 if green else 45) ** 2:
            return True
        r, g, b = (v / 255 for v in c[:3])
        h, l, s = colorsys.rgb_to_hls(r, g, b)
        if green:
            # Vert plus ou moins sombre ou clair : toujours le fond.
            return abs(h - bh) < 0.08 and s > 0.35
        return l > bl - 0.30 and s < 0.10

    seen = bytearray(w * h)
    stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    while stack:
        x, y = stack.pop()
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        if not is_bg(px[x, y]):
            continue
        px[x, y] = (0, 0, 0, 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx]:
                stack.append((nx, ny))
    # Petites îles isolées (bruit) : on ne garde que le plus grand morceau.
    alpha = [[px[x, y][3] > 0 for x in range(w)] for y in range(h)]
    label = [[0] * w for _ in range(h)]
    sizes = {}
    cur = 0
    for y in range(h):
        for x in range(w):
            if alpha[y][x] and not label[y][x]:
                cur += 1
                n = 0
                st = [(x, y)]
                label[y][x] = cur
                while st:
                    cx, cy = st.pop()
                    n += 1
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h and alpha[ny][nx] and not label[ny][nx]:
                            label[ny][nx] = cur
                            st.append((nx, ny))
                sizes[cur] = n
    if sizes:
        keep = max(sizes, key=sizes.get)
        for y in range(h):
            for x in range(w):
                if label[y][x] and label[y][x] != keep:
                    px[x, y] = (0, 0, 0, 0)
    return im


def to_pixel_art(im, width):
    """Recadre, réduit sur une vraie grille de pixels, palette réduite, contour net."""
    bbox = im.getbbox()
    im = im.crop(bbox)
    height = max(1, round(im.height * width / im.width))
    small = im.resize((width, height), Image.BOX)
    rgb = Image.new("RGB", small.size, (0, 0, 0))
    rgb.paste(small, mask=small.split()[3])
    pal = rgb.quantize(colors=48, method=Image.MEDIANCUT, dither=Image.NONE).convert("RGB")
    out = Image.new("RGBA", (width + 4, height + 4), (0, 0, 0, 0))
    a = small.split()[3]
    pp, ap, op = pal.load(), a.load(), out.load()
    for y in range(height):
        for x in range(width):
            if ap[x, y] >= 128:
                r, g, b = pp[x, y]
                op[x + 2, y + 2] = (r, g, b, 255)
    # Contour sombre d'1 px.
    w2, h2 = out.size
    solid = [[op[x, y][3] > 0 for x in range(w2)] for y in range(h2)]
    for y in range(h2):
        for x in range(w2):
            if solid[y][x]:
                continue
            if any(0 <= x + dx < w2 and 0 <= y + dy < h2 and solid[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                op[x, y] = OUTLINE
    return out


def scrub_badges(sprite):
    """Efface logos et plaques dans le sprite final (vue 3/4 avant, avant à gauche).
    On cherche sur la face avant (moitié gauche, bas de l'image) des amas de pixels clairs
    et peu saturés (chrome, blanc) :
      - logo  : petit amas posé sur une zone sombre (la calandre) ;
      - plaque : rectangle clair, plein et allongé, dans le bas du pare-chocs.
    Chaque amas est repeint avec la couleur médiane qui l'entoure. Renvoie le nombre d'amas effacés."""
    w, h = sprite.size
    px = sprite.load()

    def lum(c):
        return (0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]) / 255

    def badge_like(c):
        if c[3] == 0:
            return False
        _, l, s_ = colorsys.rgb_to_hls(c[0] / 255, c[1] / 255, c[2] / 255)
        return l > 0.55 and s_ < 0.30

    seen = set()
    removed = 0
    for y in range(int(h * 0.40), int(h * 0.97)):
        for x in range(0, int(w * 0.52)):
            if (x, y) in seen or not badge_like(px[x, y]):
                continue
            cluster, stack = [], [(x, y)]
            seen.add((x, y))
            while stack:
                cx, cy = stack.pop()
                cluster.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and badge_like(px[nx, ny]):
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            cxs = [p[0] for p in cluster]
            cys = [p[1] for p in cluster]
            bw, bh = max(cxs) - min(cxs) + 1, max(cys) - min(cys) + 1
            my = sum(cys) / len(cluster)
            cs = set(cluster)
            ring = []
            for (cx, cy) in cluster:
                for dx in range(-2, 3):
                    for dy in range(-2, 3):
                        q = (cx + dx, cy + dy)
                        if q not in cs and 0 <= q[0] < w and 0 <= q[1] < h and px[q][3] and not badge_like(px[q]):
                            ring.append(px[q])
            if len(ring) < 4:
                continue
            ring.sort(key=lum)
            fill = ring[len(ring) // 2]
            on_dark = lum(fill) < 0.35
            fill_ratio = len(cluster) / float(bw * bh)
            # Logo : petit amas sur la calandre sombre (règle stricte, pour ne pas abîmer phares et jantes).
            logo = len(cluster) <= 14 and bw <= 7 and bh <= 6 and on_dark and my < h * 0.75
            # Plaque : rectangle clair allongé dans le bas ; ses caractères sombres laissent des trous.
            plate = len(cluster) >= 10 and bw >= 1.3 * bh and fill_ratio > 0.5 and my > h * 0.6
            if not (logo or plate):
                continue
            for q in cluster:
                px[q] = fill
            removed += 1
    return removed


def recolor(sprite, target_hex, hue_band=(0.52, 0.75), min_sat=0.35):
    """Recolore un sprite généré en peinture « bleu roi » (couleur témoin) vers la couleur de la
    photo, en gardant les ombres et reflets : un seul sprite par modèle sert à toutes les couleurs."""
    tr, tg, tb = [int(target_hex[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    th, tl, ts = colorsys.rgb_to_hls(tr, tg, tb)
    px = sprite.load()
    paint = []
    for y in range(sprite.height):
        for x in range(sprite.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            if hue_band[0] < h < hue_band[1] and s > min_sat and l > 0.08:
                paint.append((x, y, l))
    if not paint:
        return sprite.copy()
    mean = sum(p[2] for p in paint) / len(paint)
    out = sprite.copy()
    po = out.load()
    for x, y, l in paint:
        r, g, b = colorsys.hls_to_rgb(th, min(0.95, max(0.03, tl + (l - mean))), ts)
        po[x, y] = (int(r * 255), int(g * 255), int(b * 255), 255)
    return out


def normal_map(sprite):
    """Reliefs approchés depuis la luminosité (clair = en avant), format Godot (y vers le haut)."""
    w, h = sprite.size
    src = sprite.load()
    lum = Image.new("L", (w, h))
    lp = lum.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = src[x, y]
            lp[x, y] = int((0.299 * r + 0.587 * g + 0.114 * b) * (a / 255))
    lum = lum.filter(ImageFilter.GaussianBlur(1.2))
    lp = lum.load()
    out = Image.new("RGBA", (w, h), (128, 128, 255, 255))
    op = out.load()
    k = 2.2
    for y in range(h):
        for x in range(w):
            if src[x, y][3] == 0:
                continue
            dx = (lp[min(x + 1, w - 1), y] - lp[max(x - 1, 0), y]) / 255.0
            dy = (lp[x, min(y + 1, h - 1)] - lp[x, max(y - 1, 0)]) / 255.0
            nx, ny, nz = -dx * k, dy * k, 1.0
            n = math.sqrt(nx * nx + ny * ny + nz * nz)
            op[x, y] = (int((nx / n * 0.5 + 0.5) * 255), int((ny / n * 0.5 + 0.5) * 255), int((nz / n * 0.5 + 0.5) * 255), 255)
    return out


def meta(sprite):
    """Points utiles au jeu : contact au sol, phares (pixels très clairs à l'avant), échappement."""
    w, h = sprite.size
    px = sprite.load()
    rows = [y for y in range(h) if any(px[x, y][3] for x in range(w))]
    bottom = rows[-1] if rows else h - 1
    lamps = []
    for x in range(int(w * 0.45)):
        for y in range(int(h * 0.35), bottom):
            r, g, b, a = px[x, y]
            if a and min(r, g, b) > 215:
                lamps.append((x, y))
    out = {"anchor": [w * 0.5, bottom - h * 0.12], "ground": bottom, "exhaust": [w - 10, bottom - 6], "lamps": []}
    if lamps:
        lamps.sort()
        half = len(lamps) // 2
        for part in (lamps[:half] or lamps, lamps[half:] or lamps):
            out["lamps"].append([sum(p[0] for p in part) / len(part), sum(p[1] for p in part) / len(part)])
    return out


def process(car_id):
    raw = Image.open(os.path.join(OUT_RAW, car_id + ".jpg"))
    clean = remove_background(raw)
    big = to_pixel_art(clean, BIG_W)
    scrub_badges(big)
    small = to_pixel_art(clean, SMALL_W)
    scrub_badges(small)
    big.save(os.path.join(OUT, car_id + ".png"))
    small.save(os.path.join(OUT, car_id + "_s.png"))
    normal_map(big).save(os.path.join(OUT, car_id + "_n.png"))
    json.dump(meta(big), open(os.path.join(OUT, car_id + ".json"), "w"), indent=1)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    force = "--force" in sys.argv
    only_process = "--only-process" in sys.argv
    os.makedirs(OUT_RAW, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    for car in catalog():
        if args and car["id"] not in args:
            continue
        raw = os.path.join(OUT_RAW, car["id"] + ".jpg")
        if not only_process and (force or not os.path.exists(raw)):
            subj = os.path.join(OUT_RAW, car["id"] + "_subject.png")
            render_subject(car, subj)
            for attempt in range(5):
                try:
                    data = call_api(prompt_for(car), {"input_image_0": subj, "input_image_1": STYLE}, 100 + attempt * 17 + len(car["id"]))
                    open(raw, "wb").write(data)
                    break
                except RuntimeError as e:
                    print("  %s : nouvel essai (%s)" % (car["id"], str(e)[:90]))
            else:
                print("ÉCHEC", car["id"])
                continue
        if os.path.exists(raw):
            process(car["id"])
            print("ok", car["id"])


if __name__ == "__main__":
    main()
