# Garage Spotter

Idle game mobile de car spotting : chaque vraie voiture photographiée dans la rue devient une source de revenus passive, améliorée pièce par pièce dans un garage en pixel art.
Le document de game design (GDD) fait foi : https://claude.ai/artifact/WgkvZZaTt9JrZg6hYERz9r

## Stack
- Appli : Godot 4 (GDScript), 2D uniquement. Dev sur PC Windows, test sur iPhone via l'export web, App Store plus tard depuis un Mac.
- Serveur : Supabase (Auth, Postgres + RLS, Storage, Edge Functions).
- IA : reconnaissance par Gemini 3.1 Flash-Lite (≈ 0,0006 $ la photo) ; photo de référence du modèle exact prise sur Wikipédia (gratuit) ; pixel art par FLUX.2 [klein] 4B (gratuit/≈ 0,0004 $) avec référence + planche de style + photo du joueur, consigne « sans logo » (plaque sans importance). Un sprite par modèle, mis en cache, recoloré (`generate_cars.recolor`). Voir `docs/choix-modele-image.md` et `tools/ai/spot_photo.py`.
- Pubs : AdMob. Achats : RevenueCat.

## Règles non négociables
- L'appli affiche, le serveur décide : tout calcul d'argent faisant foi est côté serveur.
- Revenus idle calculés depuis l'heure de la dernière récolte, jamais en continu.
- Aucune clé d'API dans l'appli.
- Pas de 3D affichée, pas de rotation : sprites fixes vue 3/4 avant, recolorés.
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
- `scripts/main.gd` : interface construite en code, fenêtres, tutoriel.
- `scripts/pixel_ui.gd` : kit d'interface : couleurs, polices, cadres et boutons en relief (9 tranches générées ; un bouton a une tranche visible et descend de 2 px quand on l'enfonce), pastilles rondes d'icônes (`badge`), icônes pixel 16×16. Tout nouveau bouton passe par `style_button` (éclair au clic, reflet sur les boutons d'action).
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
- Images générées par IA : seulement les sprites de voitures (`assets/cars/`), produits par `tools/ai/generate_cars.py` (FLUX.2 [klein] 4B sur Cloudflare Workers AI, licence Apache 2.0). Aucune marque réelle (logo, badge, texte, plaque) : relire chaque nouveau sprite.
- `tools/car_sheet.gd` produit une planche de toutes les carrosseries pour relire le rendu des voitures.

## Sprites de voitures générés (mise à neuf)
- Une voiture mise à neuf s'affiche avec son sprite généré `assets/cars/<id>.png` (~168 px, + `_s` vignette, `_n` reliefs pour l'éclairage, `.json` points d'ancrage) ; sans sprite, on retombe sur `car_renderer.gd`. Les silhouettes grises (voitures bloquées) restent celles de `car_renderer.gd`.
- Générer : `CF_ACCOUNT_ID=... GODOT=... python3 tools/ai/generate_cars.py [ids] [--force] [--only-process]`. Le script rend la carrosserie (guide d'angle et de couleur), envoie aussi `tools/ai/style_sheet.png` comme référence de style, puis nettoie en vrai pixel art (détourage, grille nette, palette 48 couleurs, contour 1 px). Les voitures claires sont générées sur fond vert pour un détourage propre.
- Le jeton Cloudflare n'est jamais dans le dépôt ; ≈ 37 Neurons par voiture (10 000 gratuits par jour). Le filtre de Cloudflare bloque parfois une image à tort : le script réessaie avec une autre graine.
- Phase 1 : la même consigne partira de la photo du joueur (image 0) via un Worker.

## Version web
- `export_presets.cfg` : préréglage « Web » sans threads (Safari iPhone, hébergement simple). Export : `godot --headless --path . --export-release "Web" build/web/index.html`.
- `.github/workflows/web.yml` : export à chaque mise à jour de `main` (archive dans Actions) et mise en ligne sur GitHub Pages (https://lulu4660.github.io/garage-spotter/).
- `main.gd` élargit la zone de jeu pour remplir l'écran en gardant un agrandissement entier.

## Vérifier un changement
- `godot --headless --path . -s tests/run_tests.gd` et `godot --headless --path . -s tests/test_playthrough.gd -- --fresh` doivent passer.
- Pour un changement visible : `tools/screenshots.sh` (via `xvfb-run` sous Linux), puis relire les captures. Options de capture : `--demo`, `--fresh`, `--stage=0..3`, `--popup=atelier|garage|album|spot|reveal|offline|menu|tree|staff|collections|missions|succes`.

## Agents (.claude/agents/)
godot-dev, economy-balancer, supabase-backend, ai-pipeline, art-director (relecture), playtester-qa (tests), store-compliance (conformité).
