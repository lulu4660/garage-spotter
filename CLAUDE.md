# Garage Spotter

Idle game mobile de car spotting : chaque vraie voiture photographiée dans la rue devient une source de revenus passive, améliorée pièce par pièce dans un garage en pixel art.
Le document de game design (GDD) fait foi : https://claude.ai/artifact/WgkvZZaTt9JrZg6hYERz9r

## Stack
- Appli : Godot 4 (GDScript), 2D uniquement. Dev sur PC Windows, test sur iPhone via l'export web, App Store plus tard depuis un Mac.
- Serveur : Supabase (Auth, Postgres + RLS, Storage, Edge Functions).
- IA : API de vision pour la reconnaissance ; FLUX.1 Schnell via un Worker Cloudflare pour le pixel art (cache par modèle).
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
- `scripts/economy.gd` : toutes les formules, fonctions pures (à porter dans les Edge Functions en phase 1). Ne mets aucune règle d'économie ailleurs.
- `scripts/game_state.gd` : état de la partie, actions du joueur, sauvegarde `user://save.json`.
- `scripts/main.gd` : interface construite en code, fenêtres, tutoriel.
- `scripts/pixel_ui.gd` : couleurs, polices, cadres biseautés (9-slice générés), icônes pixel 16×16.
- `scripts/car_renderer.gd` : voitures modélisées en volume puis rendues en pixel art, vue 3/4 avant fixe, mises en cache.
- `scripts/garage_scene.gd` : décor du garage par étape, néons, sol mouillé, plateau, effets au toucher.
- `scripts/reveal_view.gd` : voiture sur plateau, bloquée ou révélée ; animation de mise à neuf (shader).
- Carrosseries (16) : citadine, compacte, berline, break, 4x4, suv, monospace, combi, fourgon, coupe, fastback, sportback, cabriolet, roadster, pickup, supercar.
- Les nombres sont des `float` (double) : le plus gros revenu possible reste très loin de 1e308.
- Pas de `class_name` : les scripts se chargent avec `preload`.

## Pixel art (règles de rendu)
- Le jeu est dessiné en 320 × 568 et agrandi d'un facteur entier (stretch « viewport », « integer ») : pas de flou, pas de pixels de tailles différentes.
- Positions et tailles en pixels entiers ; ne jamais agrandir une image ou une icône par un facteur non entier.
- Polices : Garage Jersey en 19 (texte) ou 38 (gros chiffres), Micro 5 en 11 (petits textes). Aucune autre taille.
- Couleurs depuis `pixel_ui.gd` ; contour sombre d'1 px sur les sprites ; lumière venant du haut.
- Aucune image générée par IA dans le dépôt pour l'instant ; aucune marque réelle (logo, calandre reconnaissable).
- `tools/car_sheet.gd` produit une planche de toutes les carrosseries pour relire le rendu des voitures.

## Vérifier un changement
- `godot --headless --path . -s tests/run_tests.gd` et `godot --headless --path . -s tests/test_playthrough.gd -- --fresh` doivent passer.
- Pour un changement visible : `tools/screenshots.sh` (via `xvfb-run` sous Linux), puis relire les captures.

## Agents (.claude/agents/)
godot-dev, economy-balancer, supabase-backend, ai-pipeline, art-director (relecture), playtester-qa (tests), store-compliance (conformité).
