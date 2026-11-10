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

## Réduire le coût : générer une fois par modèle, pas une fois par mise à neuf (10 novembre 2026)

Un modèle d'image qui dessine la voiture exacte coûte ≈ 0,03 à 0,04 $ l'image (Nano Banana, Qwen Image
Edit Plus, Seedream, FLUX Kontext pro). Payé à chaque mise à neuf, cela fait ≈ 6 $ par mois pour un joueur
qui utilise ses 5 mises à neuf par jour : beaucoup trop cher. La solution n'est pas un modèle moins cher,
c'est de **ne plus générer à chaque mise à neuf**.

**Principe : un sprite par modèle de voiture, partagé par tous les joueurs, recoloré.**
1. Photo → reconnaissance (marque, modèle, génération, carrosserie, couleur, modifications).
2. On cherche dans le cache `make/model/generation` (Supabase Storage). Trouvé : on reprend ce sprite,
   **recoloré** à la couleur de la photo (déjà prévu par les règles : sprites fixes recolorés). Coût : 0.
3. Pas trouvé : on le génère **une seule fois**, en texte seul (« Honda Civic 11e génération hayon, vue 3/4
   avant, sans logo ni plaque », + planche de style), en gris neutre pour pouvoir le recolorer, puis on le
   stocke. Tous les joueurs suivants qui spottent ce modèle le reçoivent gratuitement.
4. Les modifications visibles (aileron, jantes, vitres teintées, attelage…) sont des **calques** dessinés
   une fois et posés sur le sprite, pas une nouvelle génération.

Avantages en plus du prix : la voiture n'est plus inventée depuis une photo de dos (on part du nom, plus
la photo), le rendu est relu une fois par modèle (aucun logo ni plaque qui passe), et la photo du joueur
n'est plus envoyée à un générateur d'images.

**Coûts estimés**

| Poste | Combien | Coût |
|---|---|---|
| Reconnaissance, Gemini 3.1 Flash-Lite (0,25 $ / 1,50 $ par M jetons), **mesuré** | 1 402 jetons entrée + ≈ 180 sortie | **≈ 0,0006 $** (gratuit au début) |
| Reconnaissance, Gemini 3.5 Flash-Lite (0,30 $ / 2,50 $), mesuré | idem | ≈ 0,0009 $ |
| Génération d'un nouveau modèle, modèle haut de gamme (≈ 0,04 $) | une fois par modèle | 2 000 modèles ≈ **80 $ en tout, une seule fois** |
| Génération d'un nouveau modèle, FLUX.2 [klein] 4B | une fois par modèle | ≈ 0 (gratuit) |
| Mise à neuf d'un modèle déjà en cache | recoloration + calques | **0** |

Un joueur très actif (10 photos par jour) coûte donc ≈ 300 × 0,0006 ≈ **0,18 $ par mois**, au lieu
de ≈ 6 $ (et ≈ 0,09 $ pour 5 mises à neuf par jour). On peut aussi **pré-générer avant la sortie** les ≈ 300 modèles les plus vendus en Europe :
la plupart des spots tombent alors dans le cache dès le premier jour.

Prix relevés sur des comparateurs (août 2026) et à confirmer sur les pages officielles avant de
s'engager : Gemini 3.1 Flash-Lite est le seul prix confirmé par une annonce officielle.

**Plan de test**
1. Reconnaissance : comparer Gemini 2.5 Flash-Lite / 3.1 Flash-Lite sur une vingtaine de photos (dont
   la Civic) avec Llama 4 Scout gratuit ; garder le moins cher qui trouve la bonne génération. En cas
   de doute (confiance basse), le joueur choisit parmi 3 propositions.
2. Génération en texte seul + planche de style : klein 4B d'abord (gratuit) ; si la voiture n'est pas
   reconnaissable, un modèle haut de gamme, payé une seule fois par modèle.

Sources : [tarifs Gemini API](https://ai.google.dev/pricing), [comparatif des prix d'image (invideo,
août 2026)](https://invideo.io/blog/ai-image-model-pricing/), [Qwen Image Edit Plus (pricepertoken)](https://pricepertoken.com/image/model/qwen-qwen-image-edit-plus),
[Gemini 2.5 Flash-Lite (anotherwrapper)](https://anotherwrapper.com/llm-pricing/gemini-2.5-flash-lite).

## Résultats des deux tests (10 novembre 2026)

**1. Reconnaissance (photo recadrée de la Civic rouge, vue de dos)**

| Modèle | Réponse | Juste ? | Temps | Coût |
|---|---|---|---|---|
| Llama 4 Scout (Workers AI, gratuit) | Honda Civic 10e génération break | génération fausse | — | 0 |
| Mistral Small 3.1 (Workers AI) | Honda Jazz | non | — | 0 |
| **Gemini 3.1 Flash-Lite** | Honda Civic **11e génération**, e:HEV, compacte, rouge, attelage, vue arrière, confiance 0,98 | **oui** | 3,2 s | ≈ 0,0006 $ |
| Gemini 3.5 Flash-Lite | Honda Civic 11e (FE/FL), e:HEV, attelage | oui | 3,4 s | ≈ 0,0009 $ (souvent « surchargé », 503) |
| Gemini 2.5 Flash-Lite / 2.5 Flash | fermés aux nouveaux comptes | — | — | — |

Retenu : **Gemini 3.1 Flash-Lite** (`spot_photo.py` l'utilise si `GEMINI_API_KEY` est défini). Attention RGPD :
avec l'offre gratuite, Google peut utiliser les données envoyées ; en production (photos des joueurs), passer
à l'offre payante. Un seul essai sur une seule photo : à confirmer sur une vingtaine de photos variées.

**2. Génération à partir du nom seul (FLUX.2 [klein] 4B, gratuit), peinture bleu roi puis recoloration**
6 modèles (Civic 11, Clio V, Golf 8, 208 II, Model 3, Mini F56), 2 graines chacun.
- Style, angle 3/4 avant et fond : bons. **Recoloration** (`generate_cars.recolor`) : très bonne en rouge et
  en blanc, ombres et reflets gardés ; le bleu des vitres est épargné (saturation minimale 0,35).
- **Fidélité au modèle : insuffisante.** klein dessine une citadine générique ; seule la Mini est
  reconnaissable. Il dessine aussi parfois le vrai logo (losange Renault, lion Peugeot) malgré la consigne.
- Le filtre de Cloudflare bloque souvent le nom de marque (« output flagged ») : jusqu'à 8 graines.
- Gemini Flash Image (génération) : pas inclus dans l'offre gratuite de l'API (quota 0).

**Conclusion** : reconnaissance avec Gemini 3.1 Flash-Lite ; génération avec un modèle haut de gamme
(Gemini Flash Image, ≈ 0,04 $) **une seule fois par modèle**, relu à la main (logos), puis recoloré pour
tous les joueurs. klein 4B reste le secours gratuit pour les modèles rares.

## Chaîne retenue, 100 % bon marché : photo de référence + FLUX.2 [klein] 4B (10 novembre 2026)

Pas de modèle d'image payant. La fidélité au modèle vient d'une **vraie photo du modèle exact**,
cherchée sur internet et jointe à la consigne :

1. Reconnaissance : Gemini 3.1 Flash-Lite (≈ 0,0006 $), repli sur Workers AI si Gemini est saturé (503 fréquents).
2. Référence : image principale de l'article Wikipédia du modèle (API Wikipédia, gratuite, sans clé ;
   en général une vue de 3/4 avant de la bonne génération). À mettre en cache, une par modèle.
3. Génération klein 4B : image 0 = la référence (forme exacte), image 1 = la planche de style,
   image 2 = la photo du joueur (couleur, modifications). Consigne explicite : **ne pas dessiner le logo**
   (calandre, capot, coffre, centres de roues lisses). La plaque n'est pas un problème : illisible en pixel art.
4. Pixel art, `scrub_badges` (efface les petits logos restants), normales.

**Résultats** (Civic 11 du joueur + 6 modèles de test) :
- **Bien plus fidèle** que le nom seul : Clio V, 208 II et Model 3 sont reconnaissables au premier coup d'œil ;
  la Civic a la face et les phares de la 11e génération.
- Logo : souvent supprimé ; il reste parfois un logo de quelques pixels (losange, H), jugé acceptable.
- Limites :
  - Wikipédia donne parfois une autre génération (« Mini Hatch F56 » → photo d'une Mini R50) ou une autre
    carrosserie (la photo de l'article Civic 11 est la berline) : chercher l'article de la génération,
    puis vérifier la photo (Gemini, ≈ 0,0006 $, une fois par modèle).
  - Les voitures argentées sur fond vert dérivent parfois (Clio rendue mauve).
  - **Filtre de Cloudflare** : refuse beaucoup d'images de vraies marques (Civic ≈ 5 sur 6, Golf et Mini
    8 sur 8). Un code couleur hexadécimal dans la consigne et la motorisation (« e:HEV ») aggravent le
    problème : ils sont retirés. Le script fait jusqu'à 16 essais avec des graines au hasard et retire la
    photo du joueur après 10 refus. Pour la Golf et la Mini, il faudra un plan B (autre hébergeur de klein 4B,
    le modèle étant sous licence Apache 2.0, ou un GPU à la demande).
- Coût : ≈ 0,0006 $ (reconnaissance) + ≈ 0,0004 $ par essai de génération, une fois par modèle si l'on met en cache.

Commande : `GEMINI_API_KEY=... CF_ACCOUNT_ID=... python3 tools/ai/spot_photo.py photo.jpg sortie/`
(`--no-reference` pour l'ancienne consigne, `--cleanup` pour la passe de retouche).

## Nouvel angle et abandon de Wikipédia (10 novembre 2026, soir)

- **Angle unique** : toutes les voitures du jeu suivent l'angle des silhouettes grises fournies (3/4 avant, caméra basse,
  avant à gauche), plus de vue de dessus. La silhouette de la carrosserie est envoyée à l'IA comme guide d'angle, de
  taille et de position ; la planche de voitures en couleur sert de référence de style. Les 32 voitures du catalogue
  ont été régénérées ainsi : silhouette et voiture mise à neuf se superposent.
- **Wikipédia retiré** : trop de refus du filtre et de mauvaises photos (autre génération, autre carrosserie).
- **Cause des refus trouvée** : le **nom de marque ou de modèle dans la consigne**, dès qu'une photo est jointe.
  Sur la photo de la Civic : 0 image acceptée sur 6 avec « Honda Civic », 0 sur 3 avec « Civic » seul, **6 sur 6 sans
  nom**, plaque lisible ou floutée (la plaque n'y change rien). La consigne ne décrit donc plus que la couleur et la
  carrosserie : c'est la photo qui porte l'identité.
- **Fidélité sans le nom** : photo de 3/4 avant → voiture proche du modèle (calandre, phares, proportions) ; photo de
  dos → voiture générique de la bonne couleur et de la bonne carrosserie (l'avant est inventé). À décider côté jeu :
  demander une photo de l'avant, ou accepter une voiture générique pour les photos de dos.
- **Quota** : régénérer le catalogue et faire les essais a consommé les 10 000 Neurons gratuits du jour (remise à
  zéro à minuit UTC). `amg_c36` est sortie dans un mauvais angle et reste à refaire (`--seed=N`).
