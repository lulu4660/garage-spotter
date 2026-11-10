#!/usr/bin/env python3
"""Prototype de la chaîne de la phase 1 : d'une photo de rue au sprite de la voiture.

  1. Détection de la voiture (DETR, Workers AI) et recadrage.
  2. Reconnaissance sur le recadrage (modèle de vision, Workers AI) : marque, modèle,
     génération, carrosserie, couleur, modifications visibles, plaque(s), score « vraie voiture ».
  3. Photo de référence du modèle exact, cherchée sur Wikipédia (photo de 3/4 avant de l'article
     du modèle ou de sa génération ; gratuit, à mettre en cache côté serveur, une par modèle).
  4. Génération du sprite (FLUX.2 [klein] 4B, gratuit) : image 0 = la référence (forme exacte du
     modèle), image 1 = la planche de style, image 2 = la photo du joueur (couleur, modifications).
     Consigne : ne pas dessiner le logo. Une plaque en pixel art est illisible : sans importance.
  5. Retouche (facultative, --cleanup ; FLUX.2 [klein] 4B en mode édition) : on renvoie l'image générée et on fait effacer
     tout logo, badge, texte ou plaque restant, sans rien changer d'autre.
  6. Nettoyage en pixel art (mêmes étapes que generate_cars.py).
La copie de la photo gardée pour l'album, elle, est floutée (plaques) : la photo intacte ne sert
qu'au traitement et n'est jamais stockée.

Usage :
  CF_ACCOUNT_ID=... [GEMINI_API_KEY=...] python3 tools/ai/spot_photo.py photo.jpg sortie/ [--identity "Honda Civic 11th gen hatchback"] [--no-reference] [--cleanup]
Les photos et résultats restent hors du dépôt. En production, cette chaîne tournera dans un
Worker Cloudflare (clé côté serveur), jamais dans l'appli.
"""
import base64
import io
import json
import os
import sys
import random
import time
import urllib.error
import urllib.parse
import urllib.request

from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_cars as gc  # noqa: E402

VISION = "@cf/meta/llama-4-scout-17b-16e-instruct"  # gratuit, mais se trompe de génération
# Reconnaissance retenue : Gemini 3.1 Flash-Lite (≈ 0,0006 $ la photo), clé côté serveur.
GEMINI = "gemini-3.1-flash-lite"
GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
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
    """Reconnaissance par Gemini si une clé est disponible (GEMINI_API_KEY), sinon Workers AI."""
    if os.environ.get("GEMINI_API_KEY"):
        for attempt in range(4):
            try:
                return recognize_gemini(crop)
            except (urllib.error.HTTPError, OSError, ValueError) as e:  # 503 « surchargé » fréquent
                print("  Gemini indisponible (%s), nouvel essai" % str(e)[:40])
                time.sleep(3 * (attempt + 1))
        print("  Gemini indisponible : repli sur Workers AI")
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


def recognize_gemini(crop):
    img = crop.copy()
    img.thumbnail((768, 768))
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=90)
    uri = "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
    body = {"model": GEMINI, "temperature": 0.1, "response_format": {"type": "json_object"},
            "messages": [{"role": "user", "content": [{"type": "text", "text": RECOGNIZE}, {"type": "image_url", "image_url": {"url": uri}}]}]}
    req = urllib.request.Request(GEMINI_URL, data=json.dumps(body).encode(), method="POST",
                                 headers={"Authorization": "Bearer " + os.environ["GEMINI_API_KEY"], "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        out = json.loads(json.load(r)["choices"][0]["message"]["content"].strip().strip("`").removeprefix("json"))
    return out[0] if isinstance(out, list) else out


def blur_plates(crop, boxes):
    """Floute chaque plaque (avec de la marge) : la photo ne part jamais avec une plaque lisible."""
    img = crop.copy()
    for b in boxes or []:
        if len(b) != 4:
            continue
        if max(b) > 1:  # Gemini donne ses cadres sur une échelle de 0 à 1000
            b = [v / 1000 for v in b]
        x0, y0, x1, y1 = b
        w, h = x1 - x0, y1 - y0
        box = [int(max(0, (x0 - w * 0.25) * img.width)), int(max(0, (y0 - h * 0.6) * img.height)),
               int(min(img.width, (x1 + w * 0.25) * img.width)), int(min(img.height, (y1 + h * 0.6) * img.height))]
        if box[2] > box[0] and box[3] > box[1]:
            region = img.crop(box).filter(ImageFilter.GaussianBlur(radius=max(6, (box[3] - box[1]) // 2)))
            img.paste(region, box)
    return img


WIKI_UA = {"User-Agent": "GarageSpotterPrototype/0.1 (https://github.com/lulu4660/garage-spotter)"}


def _wiki_get(url):
    """Wikimedia limite le débit des adresses partagées : on respecte son délai d'attente."""
    for _ in range(8):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=WIKI_UA), timeout=30) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code != 429:
                raise
            time.sleep(int(e.headers.get("retry-after") or 30) + 2)
    raise RuntimeError("Wikimedia : trop de requêtes")


def reference_photo(query, path):
    """Photo de référence du modèle : l'image principale de l'article Wikipédia (en anglais) le plus
    proche, en général une vue de 3/4 avant de la bonne génération. Renvoie le titre de l'article."""
    url = "https://en.wikipedia.org/w/api.php?" + urllib.parse.urlencode({
        "action": "query", "format": "json", "generator": "search", "gsrsearch": query, "gsrlimit": 3,
        "prop": "pageimages", "piprop": "thumbnail", "pithumbsize": 500})
    pages = sorted(json.loads(_wiki_get(url)).get("query", {}).get("pages", {}).values(), key=lambda p: p["index"])
    page = next((p for p in pages if "thumbnail" in p), None)
    if page is None:
        return None
    open(path, "wb").write(_wiki_get(page["thumbnail"]["source"]))
    small = Image.open(path).convert("RGB")
    small.thumbnail((500, 500))
    small.save(path, "PNG")
    return page["title"]


BODY_EN = {"citadine": "small hatchback", "compacte": "hatchback", "berline": "sedan", "break": "estate", "4x4": "off-roader",
           "suv": "SUV", "monospace": "MPV", "combi": "van", "fourgon": "van", "coupe": "coupe", "fastback": "fastback",
           "sportback": "sportback", "cabriolet": "convertible", "roadster": "roadster", "pickup": "pickup truck", "supercar": "supercar"}


def car_name(car, identity=None):
    """Nom pour la consigne : marque, modèle, génération et carrosserie, sans la motorisation
    (« e:HEV », « TDI »…), qui n'aide pas le dessin et déclenche plus souvent le filtre."""
    if identity:
        return " ".join(identity.split())
    gen = str(car.get("generation") or "")
    if gen and "gen" not in gen.lower():
        gen += " generation"
    name = "%s %s %s %s" % (car.get("make", ""), car.get("model", ""), gen, BODY_EN.get(car.get("body_type"), ""))
    return " ".join(name.split())


def is_light_hex(hexa):
    try:
        r, g, b = [int(hexa[i:i + 2], 16) for i in (1, 3, 5)]
    except (TypeError, ValueError):
        return False
    return (max(r, g, b) + min(r, g, b)) / 510 > 0.6 and max(r, g, b) - min(r, g, b) < 60


def reference_prompt(car, identity=None):
    """Pas de code couleur hexadécimal dans la consigne : il déclenche souvent le filtre de Cloudflare.
    Consigne avec référence : image 0 = photo du modèle exact, 1 = planche de style, 2 = photo du joueur."""
    mods = [m for m in car.get("visible_modifications") or [] if m]
    bg = "Plain solid bright green background (#00c000)" if is_light_hex(car.get("color_hex")) else "Plain white background"
    return (
        "Image 0 is a reference photo of the exact car model to draw: a %s. Redraw THIS exact car as a detailed modern pixel art sprite: "
        "same body shape, headlights, grille, bumpers, windows, mirrors and proportions, so that a car fan recognises the model at once. "
        "Image 2 is the player's photo of the very same car: copy its paint colour (%s)%s. "
        "Three-quarter FRONT view, front of the car on the LEFT side of the picture. "
        "IMPORTANT: do NOT draw the brand logo or emblem anywhere: where the logo sits on the grille, the bonnet, the boot or the wheel centres, "
        "draw plain grille mesh or plain body paint instead, with no symbol and no lettering. "
        "Image 1 is a sheet of example sprites: use only its drawing style, never copy one of its cars: high-detail pixel art like a premium mobile game, "
        "crisp dark outline, glossy paint with sharp highlights, tinted windows, detailed alloy wheels. %s, no ground shadow, no scenery."
        % (car_name(car, identity), car.get("color_name", ""),
           (" and its visible modifications: %s" % ", ".join(mods)) if mods else "", bg))


def generation_prompt(car, identity=None):
    name = identity or "%s %s %s %s" % (car.get("make", ""), car.get("model", ""), car.get("generation", "") or "", car.get("variant") or "")
    mods = [m for m in car.get("visible_modifications") or [] if m]
    mods_txt = ("Keep its visible modifications: %s. " % ", ".join(mods)) if mods else ""
    return (
        "Detailed modern pixel art sprite of this exact car: a %s %s (%s). Image 0 is a real street photo of this very car "
        "(seen from the %s): reproduce its exact model, generation, body shape, paint colour and wheels. %s"
        "Do NOT draw the real brand logo: replace every logo or emblem with a small plain blank badge, and draw no license plate. "
        "Draw the whole car in a three-quarter FRONT view, front of the car on the LEFT side of the picture, even if the photo shows another side. "
        "Image 1 is a sheet of example sprites: use only its drawing style, never copy one of its cars or colours: high-detail pixel art like a premium "
        "mobile game, crisp dark outline, glossy paint with sharp highlights, tinted windows, detailed alloy wheels and headlights, plain white background, "
        "no ground shadow, no scenery. No logos, no badges, no emblems, no text, no license plate."
        % (car.get("color_name", ""), " ".join(name.split()), car.get("body_type", ""), car.get("view", "photo"), mods_txt)
    )


CLEANUP = ("Edit this pixel art car sprite: remove every brand logo, emblem, badge, lettering and license plate "
           "(paint those areas with the surrounding grille or body colour, a plate holder becomes plain body colour). "
           "Keep everything else exactly identical: same car, same colours, same pixel art style, same angle, same white background.")


def cleanup(raw_path, out_path):
    """Deuxième passe : efface logos, textes et plaques de l'image générée."""
    small = Image.open(raw_path).convert("RGB")
    small.thumbnail((500, 500))
    tmp = out_path + ".in.png"
    small.save(tmp)
    for attempt in range(5):
        try:
            data = gc.call_api(CLEANUP, {"input_image_0": tmp}, 700 + attempt * 13)
            open(out_path, "wb").write(data)
            return True
        except RuntimeError as e:
            print("  retouche, nouvel essai :", str(e)[:80])
    return False


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
    # Copie pour l'album : plaques floutées. La photo intacte part seulement au traitement.
    blur_plates(crop, car.get("plate_boxes")).save(os.path.join(out_dir, "photo_album.jpg"), quality=92)
    ref = crop.copy()
    ref.thumbnail((500, 500))
    ref_path = os.path.join(out_dir, "photo_ref.png")
    ref.save(ref_path)
    model_ref = os.path.join(out_dir, "model_ref.png")
    title = None if "--no-reference" in sys.argv else reference_photo(car_name(car, identity), model_ref)
    print("Référence :", title)
    if title:
        prompt = reference_prompt(car, identity)
        files = {"input_image_0": model_ref, "input_image_1": gc.STYLE, "input_image_2": ref_path}
    else:
        prompt = generation_prompt(car, identity)
        files = {"input_image_0": ref_path, "input_image_1": gc.STYLE}
    for attempt in range(16):
        if attempt == 10 and "input_image_2" in files:
            # Le filtre de Cloudflare bloque souvent à tort quand la photo du joueur est jointe :
            # on garde la référence et la planche, la couleur passe par le texte seul.
            files.pop("input_image_2")
            prompt = prompt.replace("Image 2 is the player's photo of the very same car: copy its paint colour", "Paint colour")
        try:
            data = gc.call_api(prompt, files, random.randrange(1, 1 << 30))
            break
        except (RuntimeError, OSError, ValueError) as e:
            print("  nouvel essai :", str(e)[:80])
    else:
        print("Échec de la génération.")
        return
    raw = os.path.join(out_dir, "raw.jpg")
    open(raw, "wb").write(data)
    edited = os.path.join(out_dir, "raw_clean.jpg")
    source = edited if "--cleanup" in sys.argv and cleanup(raw, edited) else raw
    clean = gc.remove_background(Image.open(source))
    big = gc.to_pixel_art(clean, gc.BIG_W)
    print("Logos / plaques effacés :", gc.scrub_badges(big))
    big.save(os.path.join(out_dir, "sprite.png"))
    gc.normal_map(big).save(os.path.join(out_dir, "sprite_n.png"))
    json.dump({"recognition": car, "identity": identity, "reference": title, "prompt": prompt, "meta": gc.meta(big)}, open(os.path.join(out_dir, "result.json"), "w"), ensure_ascii=False, indent=1)
    print("Sprite :", os.path.join(out_dir, "sprite.png"))


if __name__ == "__main__":
    main()
