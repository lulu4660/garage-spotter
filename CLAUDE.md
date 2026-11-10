# Garage Spotter

Idle game mobile de car spotting : chaque vraie voiture photographiée dans la rue devient une source de revenus passive, améliorée pièce par pièce dans un garage en pixel art.
Le document de game design (GDD) fait foi : https://claude.ai/artifact/WgkvZZaTt9JrZg6hYERz9r

## Stack
- Appli : Godot 4 (GDScript), 2D uniquement. Dev sur PC Windows, test sur iPhone via l'export web, App Store plus tard depuis un Mac.
- Serveur : Supabase (Auth, Postgres + RLS, Storage, Edge Functions).
- IA : reconnaissance par Gemini 3.1 Flash-Lite (≈ 0,0006 $ la photo) ; pixel art par FLUX.2 [klein] 4B (gratuit/≈ 0,0004 $) avec trois images : la photo du joueur, la planche de style (`tools/ai/style_sheet.png`) et la silhouette de la carrosserie comme guide d'angle. Jamais de nom de marque ou de modèle dans la consigne quand une photo est jointe (le filtre de Cloudflare refuse tout) ; consigne « sans logo », plaque sans importance. Un sprite par modèle, mis en cache, recoloré (`generate_cars.recolor`). Voir `docs/choix-modele-image.md` et `tools/ai/spot_photo.py`.
- Pubs : AdMob. Achats : RevenueCat.

## Règles non négociables
- L'appli affiche, le serveur décide : tout calcul d'argent faisant foi est côté serveur.
- Revenus idle calculés depuis l'heure de la dernière récolte, jamais en continu.
- Aucune clé d'API dans l'appli.
- Pas de 3D affichée, pas de rotation : sprites fixes, tous dans le même angle que les silhouettes (3/4 avant, caméra basse à hauteur de phare, avant à gauche ; pas de vue de dessus ni d'isométrie), recolorés. Seule exception : la map de la ville est en isométrique, avec ses petites voitures de clients en quatre directions (`assets/map/cars.png`).
- Le nom réel d'une voiture n'est jamais affiché : on passe par la base de noms modifiés.
- Économie : coût ×1,10 par niveau, revenu linéaire, ×2 aux paliers 25/50/100/150/200 ; les échelles s'additionnent, jamais ne se multiplient. Tout changement d'équilibrage passe par une simulation (agent economy-balancer).
- DA : pixel art sombre, rue de nuit, noir charbon + orange/rouge/or, pas de bleu dominant.

## Priorité actuelle
Phase 0 : un garage idle jouable sans photo, pour savoir si la boucle est amusante avant de payer le moindre appel d'IA.
Le spot est simulé (un toutes les 3 min) ; tout est local, sans serveur.
Mise à neuf : chaque voiture spottée arrive grise (silhouette de sa carrosserie) et ne sert à rien tant qu'elle n'est pas mise à neuf (seul le gain immédiat du spot compte). Mettre à neuf = générer son pixel art (phase 1 ; en phase 0, rendu de `car_renderer.gd`). 5 par jour gratuites, + pubs (5/jour), Carats plus tard. Le tuto offre 3 voitures (2 communes, 1 peu commune) mises à neuf gratuitement.

## Code
- `scripts/economy.gd` : formules de base (pièces, étapes, places, hors ligne, spot), fonctions pures (à porter dans les Edge Functions en phase 1).
- `scripts/progression.gd` : progression longue, données et fonctions pures : réputation (prestige), arbre de compétences (4 branches × 6), collections, missions du jour, succès. Ne mets aucune règle d'économie ailleurs que dans ces deux fichiers.
- `scripts/game_state.gd` : état de la partie, actions du joueur, sauvegarde `user://save.json`.
- `scripts/main.gd` : interface construite en code, fenêtres, tutoriel. L'écran principal montre la ville ; le bouton SERVIR fait sortir des clients (gain = toucher, `state.tap()`), de plus en plus si l'on enchaîne ; toucher son bâtiment ouvre la scène du garage (`_show_showcase`).
- `scripts/city_map.gd` : la ville (`assets/map/`) : heure réelle (nuit 20 h 30 → 5 h 30, aube et crépuscule dorés), météo tirée au hasard par demi-heure (clair, nuages, pluie, brouillard), lumières de nuit qui s'allument par petits blocs, halos des lampadaires, voitures des clients qui suivent les routes peintes (`ROUTES` puis `SPINE` : rue entre showroom et atelier, bretelle, autoroute), circulation de fond (`TRAFFIC` : autoroute dans les deux sens, deux rues), étiquettes des bâtiments (Box, Atelier, Showroom, Hangar), caméra qu'on fait glisser et qui se recentre sur l'étape, deux niveaux de zoom (1 et 0,5 : bouton, pincement, molette). Les trajets sont en coordonnées de la map : à relever sur `assets/map/day.png` si la map change. Les ombres des bâtiments sont celles peintes dans l'image ; les nuages, la pluie et le brouillard sont dynamiques.
- `tools/map/make_cars.py` : petites voitures des clients, découpées dans deux planches d'angles (`tools/map/src/cars_*.jpg`) : quatre directions par modèle, réduites en pixel art, peinture grise recolorée en jeu (`assets/map/cars.png`, `cars_paint.png`, `cars.json`).
- `tools/map/make_map.py` : prépare la map à partir de `tools/map/src/day.jpg` (affichée) et `night.jpg` (sert seulement à repérer les lumières) : `day.png`, `light.png` (nuit = jour × ambiance + light), `lamps.json`, `front.png` (bâtiments redessinés devant les voitures).
- `scripts/pixel_ui.gd` : kit d'interface « course de rue » : couleurs, polices, cadres en aplats (`frame` : `StyleBoxFlat` sans lissage, boutons et bandeaux inclinés, coins coupés, tranche sombre sous les boutons), texte sombre sur les aplats vifs (`ink_label`), pastilles rondes d'icônes (`badge`), icônes pixel 16×16. Tout nouveau bouton passe par `style_button` (éclair au clic, reflet sur les boutons d'action).
- `scripts/seg_bar.gd` : jauge à segments animée (`PixelUI.bar`).
- `scripts/car_renderer.gd` : voitures modélisées en volume puis rendues en pixel art, vue 3/4 avant fixe, mises en cache.
- `scripts/garage_scene.gd` : scène du garage en couches (décor pixel, ville en parallaxe, voiture, brouillard/pluie, lumières additives, post-traitement).
- `scripts/fx.gd` : shaders « HD-2D » (bloom + étalonnage + vignettage, liseré et reflet de carrosserie, reflet au sol) et textures douces.
- `assets/env/` : fonds de ville Warped City 2 (CC0, ansimuz).
- `scripts/reveal_view.gd` : voiture sur plateau, bloquée ou révélée ; animation de mise à neuf (shader).
- Carrosseries (16) : citadine, compacte, berline, break, 4x4, suv, monospace, combi, fourgon, coupe, fastback, sportback, cabriolet, roadster, pickup, supercar.
- Les nombres sont des `float` (double) : le plus gros revenu possible reste très loin de 1e308.
- Pas de `class_name` : les scripts se chargent avec `preload`.

## Pixel art (règles de rendu)
- Style « HD-2D » : le jeu est mis en page en 320 × 568 et agrandi d'un facteur entier (stretch « canvas_items », « integer »). Les objets (sprites, icônes, texte, cadres) restent en pixels nets ; la lumière, le brouillard, les halos et les particules sont dessinés à la résolution de l'écran, doux.
- Pour un objet pixel : positions et tailles en pixels entiers, filtre « nearest », jamais d'agrandissement non entier. Les effets doux passent par `fx.gd` (shaders, `soft_dot`, couche additive).
- Polices : Garage Jersey en 19 (texte) ou 38 (gros chiffres), Micro 5 en 11 (petits textes). Aucune autre taille.
- Couleurs depuis `pixel_ui.gd` ; contour sombre d'1 px sur les sprites ; lumière venant du haut.
- Images générées par IA : les sprites de voitures (`assets/cars/`, produits par `tools/ai/generate_cars.py`, FLUX.2 [klein] 4B sur Cloudflare Workers AI, licence Apache 2.0) et la map de la ville (`tools/map/src/`, fournie par l'auteur). Aucune marque réelle (logo, badge, texte, plaque) : relire chaque nouvelle image.
- `tools/car_sheet.gd` produit une planche de toutes les carrosseries pour relire le rendu des voitures.

## Sprites de voitures générés (mise à neuf)
- Une voiture mise à neuf s'affiche avec son sprite généré `assets/cars/<id>.png` (~168 px, + `_s` vignette, `_n` reliefs pour l'éclairage, `.json` points d'ancrage). Une voiture pas encore mise à neuf s'affiche avec la silhouette grise de sa carrosserie, `assets/silhouettes/<carrosserie>.png` (même format). Sans image, on retombe sur `car_renderer.gd`.
- `tools/ai/make_references.py` découpe les deux planches de `tools/ai/src/` (silhouettes grises, voitures en couleur) : silhouettes du jeu, guides d'angle `tools/ai/guides/`, planche de style.
- Générer : `CF_ACCOUNT_ID=... python3 tools/ai/generate_cars.py [ids] [--force] [--only-process] [--seed=N]`. Le script envoie la silhouette de la carrosserie (guide d'angle, de taille et de position) et la planche de style, puis nettoie en vrai pixel art (détourage, grille nette, palette 48 couleurs, contour 1 px). Les voitures claires sont générées sur fond vert pour un détourage propre. `--seed=N` refait une voiture ratée avec un autre tirage.
- Le jeton Cloudflare n'est jamais dans le dépôt ; ≈ 37 Neurons par voiture (10 000 gratuits par jour). Le filtre de Cloudflare bloque parfois une image à tort : le script réessaie avec une autre graine.
- Phase 1 : la même chaîne part de la photo du joueur (`tools/ai/spot_photo.py`) via un Worker. Une photo de face ou de 3/4 avant donne une voiture ressemblante ; une photo de dos donne une voiture générique (l'avant est inventé).

## Version web
- `export_presets.cfg` : préréglage « Web » sans threads (Safari iPhone, hébergement simple). Export : `godot --headless --path . --export-release "Web" build/web/index.html`.
- `.github/workflows/web.yml` : export à chaque mise à jour de `main` (archive dans Actions) et mise en ligne sur GitHub Pages (https://lulu4660.github.io/garage-spotter/).
- `main.gd` élargit la zone de jeu pour remplir l'écran en gardant un agrandissement entier.

## Vérifier un changement
- `godot --headless --path . -s tests/run_tests.gd` et `godot --headless --path . -s tests/test_playthrough.gd -- --fresh` doivent passer.
- Pour un changement visible : `tools/screenshots.sh` (via `xvfb-run` sous Linux), puis relire les captures. Options de capture : `--demo`, `--fresh`, `--stage=0..3`, `--hour=0..24`, `--weather=clear|clouds|rain|fog`, `--popup=showcase|serve|serve_far|atelier|garage|album|spot|reveal|offline|menu|tree|staff|collections|missions|succes` (`serve` : dix appuis sur SERVIR avant la capture ; `serve_far` : idem, dézoomé).

## Agents (.claude/agents/)
godot-dev, economy-balancer, supabase-backend, ai-pipeline, art-director (relecture), playtester-qa (tests), store-compliance (conformité).
