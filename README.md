# Garage Spotter

Idle game mobile de car spotting en pixel art (Godot 4 + Supabase).
Voir `CLAUDE.md` pour la stack et les règles du projet.

## Phase 0 : le garage idle, sans photo

Le but : savoir si la boucle est amusante avant de payer le moindre appel d'IA.

Ce qui est jouable :
- une épave offerte, des revenus par seconde, des gains hors ligne (100 % pendant 2 h, 50 % jusqu'à 8 h) ;
- 10 pièces par voiture, 200 niveaux, coût ×1,10, revenus ×2 aux niveaux 25 / 50 / 100 / 150 / 200 ;
- les étapes Box → Atelier → Showroom → Hangar, qui débloquent des pièces et changent le décor ;
- les places du garage, l'album, le bonus de collection (+1 % par modèle) ;
- toucher la voiture (gain + jauge de rush ×2 pendant 30 s) ;
- un **spot simulé** toutes les 3 minutes, en attendant la caméra de la phase 1 ;
- le tutoriel avec le doigt pixel, le mode test « argent illimité » dans le Menu, la sauvegarde automatique.

Rendu : vrai pixel art en 320 × 568 agrandi sans flou, polices pixel, cadres et icônes dessinés en code. Les voitures sont modélisées en volume puis rendues en pixel art (vue 3/4 avant fixe), en attendant les sprites générés de la phase 1. Pas encore de sons.

## Lancer le jeu

1. Installe [Godot 4.3](https://godotengine.org/download) (version standard, pas .NET).
2. Ouvre Godot, « Importer », choisis le fichier `project.godot` de ce dossier.
3. Appuie sur F5.

## Tests

```bash
godot --headless --path . --editor --quit          # première fois : importe le projet
godot --headless --path . -s tests/run_tests.gd    # économie et sauvegarde
godot --headless --path . -s tests/test_playthrough.gd -- --fresh   # parcours d'un nouveau joueur
```

Les mêmes tests tournent sur GitHub à chaque envoi (onglet Actions).

## Captures d'écran

```bash
GODOT=godot tools/screenshots.sh                                        # écrans du jeu
godot --headless --path . -s tools/car_sheet.gd -- planche.png 2.5      # toutes les carrosseries
```

## Crédits

Polices Jersey 10 (modifiée) et Micro 5 : The Soft Type Project, licence SIL OFL 1.1 (voir `assets/fonts/`).
