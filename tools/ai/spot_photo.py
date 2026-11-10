#!/usr/bin/env python3
"""Prototype de la chaîne de la phase 1 : d'une photo de rue au sprite de la voiture.

  1. Détection de la voiture (DETR, Workers AI) et recadrage.
  2. Reconnaissance sur le recadrage (modèle de vision, Workers AI) : marque, modèle,
     génération, carrosserie, couleur, modifications visibles, plaque(s), score « vraie voiture ».
  3. Floutage des plaques avant tout envoi à la génération (vie privée, GDD).
  4. Génération du sprite (FLUX.2 [klein] 4B) : image 0 = la photo recadrée et floutée,
     image 1 = la planche de style, consigne = le modèle reconnu + ses modifications.
  5. Nettoyage en pixel art (mêmes étapes que generate_cars.py).

Usage :
  CF_ACCOUNT_ID=... python3 tools/ai/spot_photo.py photo.jpg sortie/ [--identity "Honda Civic 11th gen hatchback"]
Les photos et résultats restent hors du dépôt. En production, cette chaîne tournera dans un
Worker Cloudflare (clé côté serveur), jamais dans l'appli.
"""
import base64
import io
import json
import os
import sys
import urllib.error
import urllib.request

from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_cars as gc  # noqa: E402

VISION = "@cf/meta/llama-4-scout-17b-16e-instruct"
DETECT = "@cf/facebook/detr-resnet-50"
BODY_TYPES = ["citadine", "compacte", "berline", "break", "4x4", "suv", "monospace", "combi", "fourgon",
              "coupe", "fastback", "sportback", "cabriolet", "roadster", "pickup", "supercar"]

RECOGNIZE = """You are the car recognition engine of a car-spotting game. Look at the photo and answer with ONE JSON object only, no other text:
{"is_real_car": 0..1 (1 = real car photographed in the street, 0 = screen, poster or toy),
 "make": "...", "model": "...", "generation": "...", "variant": "... or null", "year_range": "...",
 "body_type": one of %s,
 "color_name": "...", "color_hex": "#rrggbb",
 "visible_modifications": ["..."] (aftermarket or notable visible parts: spoiler, wheels, tinted windows, tow hitch, body kit, exhaust...),
 "view": "front" | "rear" | "side" | "front three-quarter" | "rear three-quarter",
 "plate_boxes": [[x0, y0, x1, y1], ...] (fractions 0..1, every readable license plate),
 "confidence": 0..1}
Be precise: read badges, light shapes and body lines to identify the exact model and generation. If unsure, lower the confidence.""" % json.dumps(BODY_TYPES)


def _post(model, body, content_type):
    req = urllib.request.Request(
        "https://api.cloudflare.com/client/v4/accounts/%s/ai/run/%s" % (os.environ["CF_ACCOUNT_ID"], model),
        data=body, method="POST",
        headers={"Authorization": "Bearer " + os.environ.get("CF_API_TOKEN", "proxy-injected"), "Content-Type": content_type})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        return json.load(e)


def detect_car(photo):
    """Cadre de la voiture dans la photo. DETR renvoie ses cadres dans une image étirée
    à 1333 × 800 : on lui envoie un carré et on reconvertit."""
    small = photo.copy()
    small.thumbnail((1024, 1024))
    sq = Image.new("RGB", (1024, 1024))
    sq.paste(small, (0, 0))
    buf = io.BytesIO()
    sq.save(buf, "JPEG", quality=90)
    res = _post(DETECT, buf.getvalue(), "application/octet-stream")["result"]
    cars = [x for x in res if x["label"] in ("car", "truck", "bus") and x["score"] > 0.5]
    if not cars:
        return None
    b = max(cars, key=lambda x: (x["box"]["xmax"] - x["box"]["xmin"]) * (x["box"]["ymax"] - x["box"]["ymin"]))["box"]
    k = photo.width / small.width
    x0, x1 = b["xmin"] * 1024 / 1333 * k, b["xmax"] * 1024 / 1333 * k
    y0, y1 = b["ymin"] * 1024 / 800 * k, b["ymax"] * 1024 / 800 * k
    m = 0.08
    w, h = x1 - x0, y1 - y0
    return [max(0, x0 - w * m), max(0, y0 - h * m), min(photo.width, x1 + w * m), min(photo.height, y1 + h * m)]


def recognize(crop):
    img = crop.copy()
    img.thumbnail((768, 768))
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=90)
    uri = "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
    body = {"messages": [{"role": "user", "content": [{"type": "text", "text": RECOGNIZE}, {"type": "image_url", "image_url": {"url": uri}}]}],
            "max_tokens": 600, "temperature": 0.1}
    res = _post(VISION, json.dumps(body).encode(), "application/json")["result"]
    out = res.get("response")
    if isinstance(out, str):
        out = json.loads(out.strip().strip("`").removeprefix("json"))
    return out


def blur_plates(crop, boxes):
    """Floute chaque plaque (avec de la marge) : la photo ne part jamais avec une plaque lisible."""
    img = crop.copy()
    for b in boxes or []:
        x0, y0, x1, y1 = b
        w, h = x1 - x0, y1 - y0
        box = [int(max(0, (x0 - w * 0.25) * img.width)), int(max(0, (y0 - h * 0.6) * img.height)),
               int(min(img.width, (x1 + w * 0.25) * img.width)), int(min(img.height, (y1 + h * 0.6) * img.height))]
        if box[2] > box[0] and box[3] > box[1]:
            region = img.crop(box).filter(ImageFilter.GaussianBlur(radius=max(6, (box[3] - box[1]) // 2)))
            img.paste(region, box)
    return img


def generation_prompt(car, identity=None):
    name = identity or "%s %s %s %s" % (car.get("make", ""), car.get("model", ""), car.get("generation", "") or "", car.get("variant") or "")
    mods = [m for m in car.get("visible_modifications") or [] if m]
    mods_txt = ("Keep its visible modifications: %s. " % ", ".join(mods)) if mods else ""
    return (
        "Detailed modern pixel art sprite of this exact car: a %s %s (%s). Image 0 is a real street photo of this very car "
        "(seen from the %s): reproduce its exact model, generation, body shape, paint colour %s and wheels. %s"
        "Draw the whole car in a three-quarter FRONT view, front of the car on the LEFT side of the picture, even if the photo shows another side. "
        "Image 1 is a sheet of example sprites: use only its drawing style, never copy one of its cars or colours: high-detail pixel art like a premium "
        "mobile game, crisp dark outline, glossy paint with sharp highlights, tinted windows, detailed alloy wheels and headlights, plain white background, "
        "no ground shadow, no scenery. No logos, no badges, no emblems, no text, no license plate."
        % (car.get("color_name", ""), " ".join(name.split()), car.get("body_type", ""), car.get("view", "photo"), car.get("color_hex", ""), mods_txt)
    )


def main():
    photo_path, out_dir = sys.argv[1], sys.argv[2]
    identity = sys.argv[sys.argv.index("--identity") + 1] if "--identity" in sys.argv else None
    os.makedirs(out_dir, exist_ok=True)
    photo = Image.open(photo_path).convert("RGB")
    box = detect_car(photo)
    if box is None:
        print("Aucune voiture détectée.")
        return
    crop = photo.crop([int(v) for v in box])
    car = recognize(crop)
    print("Reconnaissance :", json.dumps(car, ensure_ascii=False))
    if float(car.get("is_real_car", 1)) < 0.5:
        print("Refusé : écran, affiche ou jouet.")
        return
    safe = blur_plates(crop, car.get("plate_boxes"))
    safe.save(os.path.join(out_dir, "photo_safe.jpg"), quality=92)
    ref = safe.copy()
    ref.thumbnail((500, 500))
    ref_path = os.path.join(out_dir, "photo_ref.png")
    ref.save(ref_path)
    prompt = generation_prompt(car, identity)
    for attempt in range(5):
        try:
            data = gc.call_api(prompt, {"input_image_0": ref_path, "input_image_1": gc.STYLE}, 300 + attempt * 31)
            break
        except RuntimeError as e:
            print("  nouvel essai :", str(e)[:80])
    else:
        print("Échec de la génération.")
        return
    raw = os.path.join(out_dir, "raw.jpg")
    open(raw, "wb").write(data)
    clean = gc.remove_background(Image.open(raw))
    big = gc.to_pixel_art(clean, gc.BIG_W)
    big.save(os.path.join(out_dir, "sprite.png"))
    gc.normal_map(big).save(os.path.join(out_dir, "sprite_n.png"))
    json.dump({"recognition": car, "identity": identity, "prompt": prompt, "meta": gc.meta(big)}, open(os.path.join(out_dir, "result.json"), "w"), ensure_ascii=False, indent=1)
    print("Sprite :", os.path.join(out_dir, "sprite.png"))


if __name__ == "__main__":
    main()
