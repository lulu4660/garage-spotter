# Choix du modèle de génération pour la mise à neuf

Étude du 9 novembre 2026. Prix relevés sur la page officielle de Cloudflare Workers AI.

## Le besoin

Chaque mise à neuf transforme la photo d'une voiture en sprite pixel art, vue 3/4 avant,
fond uni, dans le style du jeu. Il faut donc un modèle qui **part de la photo** (image de
référence), pas seulement d'un texte. Le sprite final fait environ 240 px de large :
une sortie en 512 × 512 suffit.

Cloudflare Workers AI donne **10 000 « Neurons » gratuits par jour** (remis à zéro à
minuit UTC), puis facture **0,011 $ les 1 000 Neurons**.

## Comparatif (une image 512 × 512)

| Modèle (Workers AI) | Part de la photo ? | Neurons / image | Prix payant | Gratuites / jour | Licence |
|---|---|---|---|---|---|
| **FLUX.2 [klein] 4B** | **Oui** (jusqu'à 4 images < 512 px) | 26,05 + 5,37 par image de référence = **31,4** (1 réf.) | **0,00035 $** | **≈ 318** | Apache 2.0, commercial OK |
| FLUX.1 Schnell | Non (texte seul) | 4,80 + 4 étapes × 9,60 = 43,2 | 0,00048 $ | ≈ 231 | Apache 2.0 |
| FLUX.2 [klein] 9B | Oui | ≈ 1 364 (1er mégapixel) | ≈ 0,015 $ | ≈ 7 | Non commerciale (API seulement) |
| FLUX.2 [dev] | Oui | ≈ 225 par étape | > 0,01 $ | < 50 | Non commerciale |
| Gemini 2.5 Flash Image (« Nano Banana ») | Oui | — | ≈ 0,039 $ | pas d'offre gratuite fiable par API | — |

## Recommandation : FLUX.2 [klein] 4B sur Workers AI

- **Le moins cher, et le seul pas cher qui part de la photo.** Il coûte même moins que
  FLUX.1 Schnell prévu au départ, qui ne sait pas utiliser la photo.
- **Gratuit au début** : ≈ 318 mises à neuf par jour sans rien payer, de quoi couvrir
  ≈ 60 joueurs qui utilisent leurs 5 mises à neuf chaque jour.
- **Ensuite presque rien** : un joueur qui utilise ses 5 mises à neuf tous les jours coûte
  5 × 0,00035 $ ≈ **0,05 $ par mois**, contre ≈ 6 $ avec un modèle à 0,04 $ l'image.
  Il faut l'offre Workers Paid de Cloudflare (5 $ par mois) pour dépasser le gratuit.
- **Cohérence du style** : on peut lui donner deux images, la photo du joueur (la voiture)
  et un sprite de référence du jeu (le style), pour ≈ 36,8 Neurons (0,0004 $).
- **Licence Apache 2.0** : utilisable commercialement.

## À vérifier avant de s'engager (début de la phase 1)

1. **La qualité** : 4 étapes fixes, modèle « rapide ». Tester sur une dizaine de vraies
   photos (voitures variées, de jour et de nuit) que le résultat ressemble à la voiture,
   est en vue 3/4 avant sur fond uni et tient le style. Si ce n'est pas assez bon : même
   test avec un post-traitement plus fort (palette réduite, contour), puis en dernier
   recours un modèle plus cher.
2. **La modération** : la fiche du modèle conseille un filtre ou une relecture ; le GDD
   prévoit déjà de flouter plaques et visages avant l'envoi.
3. **Les limites** : images d'entrée de moins de 512 px de côté (la photo est réduite
   avant l'envoi, ce qui la rend aussi plus légère).

Le test demande un compte Cloudflare et une clé d'API Workers AI, gardée côté serveur
(le Worker), jamais dans l'appli.

## Sources

- Tarifs Workers AI : https://developers.cloudflare.com/workers-ai/platform/pricing/
- FLUX.2 [klein] 4B sur Workers AI : https://developers.cloudflare.com/changelog/post/2026-01-15-flux-2-klein-4b-workers-ai/
- Licence de FLUX.2 [klein] : https://help.bfl.ai/articles/8642316687-flux-2-klein-fast-generation-guide

## Essai de la chaîne complète sur une vraie photo (10 novembre 2026)

Script : `tools/ai/spot_photo.py` (détection → recadrage → reconnaissance → floutage des plaques →
génération → pixel art). Photo de test : une Honda Civic 11e génération (hayon, 2022+), rouge, vue
de l'arrière, avec attelage.

| Étape | Résultat |
|---|---|
| Détection (DETR, Workers AI) | Voiture trouvée (99,9 %). Attention : les cadres sont exprimés dans une image étirée à 1333 × 800 ; le script envoie un carré et reconvertit. |
| Reconnaissance, photo entière (Llama 4 Scout) | **Faux** : « Tesla Model 3 », confiance 0,95. |
| Reconnaissance, voiture recadrée (Llama 4 Scout) | Marque et modèle justes (Honda Civic), **génération et carrosserie fausses** (10e génération break), attelage repéré. |
| Reconnaissance, voiture recadrée (Mistral Small 3.1) | **Faux** : « Honda Jazz ». |
| Moondream 3.1 | Réponses vides par l'API, inutilisable pour l'instant. |
| Floutage de la plaque | Plaque illisible avant envoi. |
| Génération FLUX.2 [klein] 4B | Bon style ; voiture plausible mais **pas le modèle exact**, avant inventé (photo de dos), **logo de marque dessiné** malgré la consigne. |
| Génération FLUX.2 [klein] 9B | Bloquée 3 fois sur 3 par le filtre de Cloudflare avec la photo. |

**Conclusions**
- La chaîne fonctionne de bout en bout et coûte presque rien, mais les modèles gratuits de Workers AI ne
  suffisent pas pour reconnaître **la génération exacte** ni pour dessiner **le modèle exact**.
- Reconnaissance : passer à un modèle de vision plus fort (Gemini Flash, Claude Haiku/Sonnet) — de l'ordre de
  0,001 à 0,005 $ par photo — ou demander au joueur de confirmer le modèle proposé (choix parmi 3).
- Génération : tester un modèle qui connaît mieux les voitures et suit mieux « sans logo » (Nano Banana /
  Gemini Flash Image, ≈ 0,04 $ l'image ; FLUX.2 [pro] via l'API de Black Forest Labs) ; garder klein 4B pour
  le style si besoin, en deux passes.
- Photo de dos : l'avant est forcément inventé. Option de jeu : demander une photo de face ou de 3/4, ou
  générer la vue dans l'angle de la photo.
- Le filtre de Cloudflare bloque souvent à tort (« output flagged »), surtout avec une vraie photo : prévoir
  plusieurs essais et un plan B chez un autre fournisseur.
