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
- Pas de 3D, pas de rotation : sprites fixes vue 3/4 avant (~240 px), recolorés par masque.
- Le nom réel d'une voiture n'est jamais affiché : on passe par la base de noms modifiés.
- Économie : coût ×1,10 par niveau, revenu linéaire, ×2 aux paliers 25/50/100/150/200 ; les échelles s'additionnent, jamais ne se multiplient. Tout changement d'équilibrage passe par une simulation (agent economy-balancer).
- DA : pixel art sombre, rue de nuit, noir charbon + orange/rouge/or, pas de bleu dominant.

## Priorité actuelle
Phase 0 : un garage idle jouable sans photo, pour savoir si la boucle est amusante avant de payer le moindre appel d'IA.

## Agents (.claude/agents/)
godot-dev, economy-balancer, supabase-backend, ai-pipeline, art-director (relecture), playtester-qa (tests), store-compliance (conformité).
