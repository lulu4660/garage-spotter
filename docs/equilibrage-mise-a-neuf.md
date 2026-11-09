# Équilibrage de la mise à neuf : simulation d'une saison de 10 semaines

Script : `tools/sim/simulate_season.py` (Python 3, bibliothèque standard).
Relancer : `python3 tools/sim/simulate_season.py` (≈ 25 min, 20 tirages par profil). Plus rapide : `--runs 8 --no-variants`.
Autres options : `--profiles gratuit,rural`, `--stage-prices 2e5,2e8,2e10`, `--csv dossier/` (séries jour par jour).
Tous les chiffres ci-dessous sont des médianes sur 20 tirages (10 pour les variantes). Avec la même graine, les résultats sont reproductibles à l'identique.

## 1. Modèle simulé

**Règles reprises telles quelles** de `scripts/economy.gd` et `scripts/game_state.gd` :
- coût 20 × B × 1,10^niveau, revenu linéaire, ×2 aux paliers 25/50/100/150/200, pièces additives ;
- étapes Box/Atelier/Showroom/Hangar (0 / 20 000 / 2 M / 200 M, 3/6/8/10 pièces) ;
- places 100 × 5^(n−3) (de 3 à 20) ;
- bonus collection +1 % par modèle **mis à neuf** ;
- hors ligne 100 % pendant 2 h puis 50 % jusqu'à 8 h ;
- gain de spot 20/30/45/60/120/240 min du revenu actuel, chances 60/25/10/4/0,9/0,1 % ;
- tapes et rush (20 tapes, ×2 pendant 30 s).

**Mise à neuf** : une voiture spottée arrive grise. Elle ne rapporte que le gain immédiat du spot : pas de revenu, pas de pièces, pas de bonus de collection. Le tutoriel offre 2 communes et 1 peu commune déjà mises à neuf. Chaque jour, `jetons = max(jetons, 5)` : c'est la règle exacte du code. Les jetons gagnés en plus se gardent, mais le quota gratuit ne s'y ajoute pas. Une pub donne +1 jeton (5 par jour au plus). Comme dans `main.gd`, la pub n'est proposée que quand il ne reste plus de jeton et qu'une voiture grise attend. Le joueur met à neuf en priorité les voitures les plus rares.

**Joueur type** :
- 6 sessions de 3 min par jour (8 h, 10 h 30, 13 h, 16 h, 19 h, 22 h 30), un rush par session, hors ligne entre les sessions ;
- à chaque session, il achète l'action dont le score « temps de retour + temps d'attente » est le plus court : un niveau, un saut jusqu'au palier suivant, une place (seulement si une voiture mise à neuf attend) ou une étape (évaluée avec la montée des nouvelles pièces jusqu'au niveau 25) ;
- il expose ses voitures les plus rentables et échange une voiture exposée contre une plus rare quand c'est plus rentable sur 1 h de revenu.

**Rue** : catalogue réel de 600 modèles (240/180/110/50/15/5 par rareté). Dans chaque rareté, la fréquence en rue suit une loi de Zipf (1/k) : les modèles courants reviennent souvent, donc la nouveauté baisse. Le nombre de spots par jour baisse aussi (×0,35 en 10 semaines, lassitude).

| Profil | Spots/jour | Nouveaux modèles/jour, semaine 1 → semaine 10 | Modèles en fin de saison |
|---|---|---|---|
| Type (gratuit, pubs) | 7 → 2,5 | 4,7 → 0,7 | 148 |
| Rural | 2 (plafond) | 1,5 → 0,9 | 82 |
| Gros spotteur | 16 → 5,6 | 9,8 → 1,1 | 255 |

## 2. Résultats avec les règles actuelles

### 2.1 Tableau de synthèse

| Profil | Doublement j0-3 | j3-14 | j14-49 | j49-70 | Sessions avec achat | Revenu fin | P10 – P90 | vs gratuit | Pubs/j | Grises max | Grises j70 | Rattrapage S2 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Gratuit (5/j) | 5,7 h | 107 h | 348 h | 2 230 h | 89 % | 1,47e6/s | 1,10e6 – 2,16e6 | 1,00 | 0,0 | 2 | 0 | 12 j |
| Pubs (5 + 5/j) | 5,6 h | 111 h | 350 h | 2 230 h | 89 % | 1,46e6/s | 1,09e6 – 2,16e6 | 0,99 | 0,0 | 0 | 0 | 12 j |
| Rural | 6,5 h | 117 h | 337 h | 861 h | 80 % | 6,6e5/s | 3,7e5 – 1,24e6 | 0,45 | 0,0 | 0 | 0 | 18 j |
| Gros spotteur | 5,3 h | 91 h | 328 h | 2 090 h | 77 % | 3,37e6/s | 2,52e6 – 4,10e6 | 2,29 | 0,0 | **47** | 0 | 10 j |
| Gros spotteur + pubs | 5,1 h | 89 h | 408 h | 2 124 h | 74 % | 3,33e6/s | 2,54e6 – 4,01e6 | 2,26 | 0,7 | 6 | 0 | 12 j |
| Ancien modèle (type) | 5,6 h | 111 h | 350 h | 2 230 h | 89 % | 1,46e6/s | 1,09e6 – 2,16e6 | 0,99 | – | – | – | 12 j |
| Ancien modèle, rural | 6,5 h | 117 h | 337 h | 861 h | 80 % | 6,6e5/s | 3,7e5 – 1,24e6 | 0,45 | – | – | – | 18 j |
| Ancien modèle, gros spotteur | 5,1 h | 93 h | 418 h | 2 136 h | 74 % | 3,37e6/s | 2,54e6 – 4,01e6 | 2,29 | – | – | – | 12 j |

Notes de lecture :
- « Pubs/j » compte les pubs effectivement utiles. Le profil « pubs » n'en regarde que 3 sur toute la saison, car le bouton n'apparaît presque jamais.
- Rattrapage S2 : le règlement de saison n'est pas dans le code, j'ai donc fait une hypothèse. Niveaux, places, étape et pièces d'or sont remis à zéro, la collection est conservée. La valeur est le nombre de jours pour retrouver le revenu de fin de saison 1.

### 2.2 Voitures grises en attente (fin de journée)

| Jour | Gratuit | Pubs | Rural | Gros spotteur | Gros spotteur + pubs |
|---|---|---|---|---|---|
| 1 | 0 | 0 | 0 | 8 | 4 |
| 2 | 0 | 0 | 0 | 13 | 3 |
| 3 | 1 | 0 | 0 | 19 | 4 |
| 5 | 0 | 0 | 0 | 27 | 2 |
| 7 | 0 | 0 | 0 | 32 | 0 |
| 10 | 0 | 0 | 0 | 39 | 0 |
| 14 | 0 | 0 | 0 | 43 | 0 |
| 21 | 0 | 0 | 0 | 42 | 0 |
| 28 | 0 | 0 | 0 | 31 | 0 |
| 35 | 0 | 0 | 0 | 18 | 0 |
| 49 | 0 | 0 | 0 | 0 | 0 |
| 70 | 0 | 0 | 0 | 0 | 0 |

### 2.3 Nouveaux modèles / mises à neuf / quota gratuit perdu, par jour

| Jour | Gratuit | Rural | Gros spotteur | Gros spotteur + pubs |
|---|---|---|---|---|
| 1 | 5 / 5 / 0 | 2 / 2 / 3 | 14 / 5 / 0 | 14 / 10 / 0 |
| 3 | 6 / 5 / 0 | 2 / 2 / 3 | 11 / 5 / 0 | 11 / 10 / 0 |
| 7 | 4 / 4 / 1 | 2 / 2 / 3 | 6 / 5 / 0 | 6 / 10 / 0 |
| 14 | 3 / 3 / 2 | 1 / 1 / 4 | 5 / 5 / 0 | 5 / 5 / 0 |
| 28 | 2 / 2 / 3 | 2 / 2 / 3 | 3 / 5 / 0 | 3 / 3 / 2 |
| 49 | 1 / 1 / 4 | 1 / 1 / 4 | 2 / 2 / 3 | 2 / 2 / 3 |
| 70 | 0 / 0 / 5 | 1 / 1 / 4 | 1 / 1 / 4 | 1 / 1 / 4 |

### 2.4 Revenu par seconde (fin de journée)

| Jour | Gratuit | Ancien (type) | Rural | Gros spotteur | Ancien (gros spotteur) |
|---|---|---|---|---|---|
| 1 | 5 256 | 5 256 | 2 420 | 7 784 | 13 219 |
| 2 | 16 599 | 19 903 | 7 581 | 29 647 | 55 431 |
| 3 | 30 424 | 34 120 | 10 423 | 54 254 | 76 133 |
| 7 | 78 464 | 81 567 | 30 151 | 159 399 | 234 325 |
| 14 | 185 323 | 186 666 | 63 001 | 419 708 | 625 385 |
| 21 | 369 891 | 367 904 | 95 604 | 917 796 | 1,29e6 |
| 28 | 615 944 | 616 320 | 139 481 | 1,50e6 | 1,74e6 |
| 49 | 1,13e6 | 1,13e6 | 409 521 | 2,69e6 | 2,69e6 |
| 70 | 1,47e6 | 1,46e6 | 658 493 | 3,37e6 | 3,37e6 |

## 3. Diagnostic

### Pas de mur pour 4 profils sur 5, mais une fonction presque inerte (ennui)
- **Joueur type** : il trouve 4,7 nouveaux modèles par jour en semaine 1, sous le quota de 5. Il a au plus 2 voitures grises (jour 3), et son revenu est égal à celui de l'ancien modèle dès le jour 5 (rapport 1,00 aux jours 7, 14, 28 et 70). Le seul effet est un creux de −17 % au jour 2 et de −11 % au jour 3.
- **Rural** : il n'est jamais bloqué. Avec 2 spots par jour, il perd 3 à 4 jetons tous les jours. Il reste à 0,45 du joueur type, exactement comme dans l'ancien modèle : la mise à neuf ne creuse pas l'écart rural.
- **Pubs** : la pub n'est proposée que si le joueur n'a plus de jeton. Le joueur type n'en manque presque jamais, et le profil « pubs » regarde **3 pubs sur 70 jours**. En l'état, la mise à neuf ne génère ni friction ni revenu publicitaire.
- Dès la semaine 2, le joueur type perd 2 à 5 mises à neuf gratuites par jour. Le quota n'est pas une décision pour lui, juste un compteur.
- **Coût IA** : avec ≈ 0,00035 $ l'image (CLAUDE.md) et un cache par modèle, le quota ne protège aucun budget. Toute la saison d'un gros spotteur coûte 255 images, soit ≈ 0,09 $. Le quota est donc un pur levier de design.

### Le mur touche le joueur le plus engagé : le gros spotteur
- Les voitures grises s'empilent de 5 par jour en semaine 1 : 8 au jour 1, 32 au jour 7, **47 au pic** (jours 14 à 21). Il en reste au moins 10 en attente pendant **37 jours**, et la pile ne se vide qu'au jour 49.
- Son revenu est inférieur à celui de l'ancien modèle : **−31 % au jour 7, −32 % au jour 14, −15 % au jour 28**. Il rattrape au jour 49, à cause de la nouveauté qui baisse.
- Le coût économique vient surtout du bonus de collection retardé, à 1 % par voiture grise. Les rares sont mises à neuf en premier, donc les places ne manquent pas de bonnes voitures.
- Avec 5 pubs par jour, il n'y a plus de pénalité (rapport 1,00 partout, 6 voitures grises au plus), pour 3,1 pubs par jour en semaines 1-2 et 50 pubs sur la saison.
- Le jeu punit donc le verbe principal (spotter beaucoup) et seul ce profil est poussé vers la pub. C'est la seule frustration nette trouvée.

### Emballements et achats décisifs
- **La mise à neuf ne crée aucun emballement.** Le bonus de collection est linéaire (+1 % par modèle) et multiplie la somme des pièces sans se composer.
- **Il n'existe aucun achat payant qui décide du classement** : pass, Carats et gros payeur ne sont pas encore définis. Un joueur qui paierait toutes ses mises à neuf rejoint au mieux l'ancien modèle, rapport 1,00. La mise à neuf payante plafonne donc l'avantage à « ne pas être retardé ».
- **Ce qui décide le classement, c'est le nombre de spots et la chance**, pas la mise à neuf :
  - à profil identique, l'écart P10 – P90 est d'un facteur 2 ;
  - un mythique (0,1 %) tombe dans 26 % des saisons du joueur type, 13 % du rural et 50 % du gros spotteur ; un légendaire dans 94 %, 72 % et 100 % ;
  - le gros spotteur finit à ×2,3 du joueur type, le rural à ×0,45.

### Constats hors mise à neuf (économie de base, à traiter à part)
- **Plateau de fin de saison** : le temps de doublement passe à **≈ 2 200 h (≈ 90 jours) sur j49-70** (861 h pour le rural). Le revenu ne gagne que +30 % en 3 semaines. 89 % des sessions ont encore un achat, mais ce sont de petits niveaux à long retour (pièces vers le niveau 166).
- **Les étapes sont consommées en 48 h** : Atelier et Showroom au jour 1, Hangar au jour 2 ou 3. Au jour 1, le revenu atteint déjà ~10 000/s, et 2 M représentent 3 minutes de revenu. L'arc Box → Hangar ne joue aucun rôle dans la saison.
- **Rattrapage en saison 2** (hypothèse ci-dessus) : 12 jours pour le joueur type, 18 pour le rural, 10 pour le gros spotteur. La cible est d'environ 8 jours.
- Test rapide d'étapes à 2e5 / 2e8 / 2e10 (`--stage-prices 2e5,2e8,2e10`, 12 tirages) :
  - le Showroom arrive au jour 3 et le Hangar aux jours 32 (type), 47 (rural) et 23 (gros spotteur) : l'arc couvre la saison ;
  - en revanche, l'écart rural se creuse (0,40 → 0,35 du type) et le rattrapage en S2 s'allonge (type 12 → 14 j, rural 18 → 20 j) ;
  - ce réglage n'est donc pas mûr et demande sa propre étude.

## 4. Variantes testées (comparaison appariée avec l'ancien modèle, mêmes spots)

Chaque valeur est le revenu de la variante divisé par celui de l'ancien modèle, sur les mêmes tirages ; 1,00 signifie aucun retard.

| Variante | Profil | j7 | j14 | j28 | j70 | Grises max | Jours avec ≥ 10 grises | Pubs/j (j1-14) | Mises à neuf par pub, saison |
|---|---|---|---|---|---|---|---|---|---|
| Actuel (5/j, `max`) | Gratuit | 1,00 | 1,00 | 1,00 | 1,00 | 2 | 0 | 0,0 | 0 |
| Actuel | Pubs | 1,00 | 1,00 | 1,00 | 1,00 | 0 | 0 | 0,2 | 3 |
| Actuel | Gros spotteur | **0,69** | **0,68** | 0,85 | 0,99 | **46** | **37** | 0,0 | 0 |
| Actuel | Gros spotteur + pubs | 1,00 | 1,00 | 1,00 | 1,00 | 6 | 0 | 3,1 | 50 |
| A : jetons cumulables (+5/j, plafond 15) | Gros spotteur | 0,73 | 0,72 | 0,86 | 0,99 | 41 | 34 | 0,0 | 0 |
| B : 8/j | Gros spotteur | 0,82 | 0,94 | 1,00 | 1,00 | 14 | 4 | 0,0 | 0 |
| B : 8/j | Gros spotteur + pubs | 1,00 | 1,00 | 1,00 | 1,00 | 1 | 0 | 1,1 | 16 |
| C : grise = 0,5 % de bonus collection | Gros spotteur | 0,78 | 0,82 | 0,92 | 1,00 | 46 | 37 | 0,0 | 0 |
| D : 3/j | Gratuit | 0,85 | 0,87 | 0,93 | 1,00 | 16 | 13 | 0,0 | 0 |
| D : 3/j | Pubs | 1,00 | 1,00 | 1,00 | 1,00 | 0 | 0 | 1,1 | 19 |
| D : 3/j | Gros spotteur | **0,61** | **0,54** | **0,65** | **0,86** | **92** | **70** | 0,0 | 0 |
| D : 3/j | Gros spotteur + pubs | 0,82 | 0,94 | 1,00 | 1,00 | 14 | 4 | 4,9 | 99 |
| E : bienvenue 10/j pendant 7 j, puis 5/j | Gros spotteur | 1,00 | 0,92 | 0,96 | 0,99 | 14 | 10 | 0,0 | 0 |
| E | Gros spotteur + pubs | 1,00 | 1,00 | 1,00 | 1,00 | 0 | 0 | 1,3 | 24 |
| F : Rare et plus mises à neuf d'office, 5/j | Gros spotteur | 0,88 | 0,83 | 0,96 | 0,99 | 24 | 18 | 0,0 | 0 |
| F | Gros spotteur + pubs | 1,00 | 1,00 | 1,00 | 1,00 | 2 | 0 | 1,9 | 27 |
| G : E + F + cumulables | Gros spotteur | 1,00 | 1,00 | 1,00 | 1,00 | 0 | 0 | 0,0 | 0 |
| H : 3/j + E + F + cumulables (plafond 9) | Gratuit | 1,00 | 1,00 | 1,00 | 1,00 | 0 | 0 | 0,0 | 0 |
| H | Gros spotteur | 1,00 | 0,96 | 0,95 | 1,00 | 14 | 12 | 0,0 | 0 |
| H | Gros spotteur + pubs | 1,00 | 1,00 | 1,00 | 1,00 | 0 | 0 | 0,6 | 16 |

Variantes A, B, C, E, F et G pour les profils gratuit et pubs : 1,00 partout, au plus 2 voitures grises. Le tableau complet est dans la sortie du script.

Lecture :
- **E (semaine de bienvenue)** supprime le retard de la semaine 1 (j7 : 0,69 → 1,00) et divise le pic de voitures grises par plus de 3 (46 → 14), sans rien changer pour les autres profils.
- **F (Rare et plus d'office)** protège les moments « wow », qui représentent 15 % des spots, et divise la pile par 2 (46 → 24).
- **G** fait disparaître toute attente. La mise à neuf devient alors purement cosmétique : à ne retenir que si c'est voulu.
- **D (3/j)** est le seul réglage qui fasse regarder des pubs au joueur type (1,1/j en semaines 1-2, 19 sur la saison). Seul, c'est un mur pour le gros spotteur : 92 voitures grises, il en reste 42 au jour 70, et il finit à 0,86.
- **A (cumul)** et **C (bonus partiel des grises)** changent peu de chose seuls.

## 5. Recommandations (par ordre de priorité)

1. **Semaine de bienvenue : 10 mises à neuf gratuites par jour du jour 1 au jour 7, puis 5 par jour** (variante E). Le gros spotteur n'est plus retardé en semaine 1 (j7 : 0,69 → 1,00 ; j14 : 0,68 → 0,92). Son pic passe de 46 à 14 voitures grises et ses jours avec au moins 10 grises de 37 à 10. Effet nul sur les joueurs type, pubs et rural. Coût IA : au plus 35 images de plus par nouveau joueur, soit ≈ 0,01 $.
2. **Mettre à neuf d'office toute voiture Rare ou plus rare** (variante F, 15 % des spots). Le spot rare ne doit jamais finir en silhouette grise : c'est le moment de révélation. Pic du gros spotteur ramené à 24 seul. Avec E, il ne reste que 14 voitures grises au plus quand le quota est de 3 (variante H).
3. **Choisir explicitement le rôle du quota, puis le régler.**
   - *Si la mise à neuf doit rester un simple rituel* : garder 5 par jour avec E + F. La pub reste réservée aux gros spotteurs (1,3 pub/j en semaines 1-2 avec E).
   - *Si elle doit porter les pubs et les Carats* : passer à **3 par jour, avec E + F et des jetons cumulables plafonnés à 3 jours** (variante H). Avec ce plafond, le joueur type ne voit plus aucun retard (1,00 partout, 0 voiture grise) et le gros spotteur reste à 0,95 au pire. Il n'y a en revanche presque pas de pubs (0,6/j pour le gros spotteur).
   - **Ne pas passer à 3 par jour sans E et F** (variante D) : le mur est de 92 voitures grises, 42 encore au jour 70.
4. **Remplacer `jetons = max(jetons, 5)` par un cumul plafonné (`min(jetons + quota, 3 × quota)`)**, une fois le quota choisi. Seul, l'effet économique est faible (pic 46 → 41). Mais la règle devient lisible (« tes mises à neuf non utilisées se gardent 3 jours ») et le rural, qui perd 3 à 4 jetons par jour, peut faire des réserves pour ses sorties. À simuler de nouveau avec le quota retenu : avec 5 par jour, ce plafond de 15 efface l'effet du quota.
5. **Hors mise à neuf, à confier à une étude séparée** :
   - les étapes sont achetées dès les jours 1 à 3 ;
   - plateau j49-70 (doublement ≈ 2 200 h) ;
   - rattrapage en S2 à 12 jours au lieu d'environ 8.
   Des étapes à 2e5 / 2e8 / 2e10 étalent l'arc Box → Hangar sur la saison (Hangar au jour 32 pour le joueur type), mais creusent l'écart rural (0,40 → 0,35) et allongent le rattrapage (12 → 14 j). Ne pas l'appliquer sans compenser, par exemple avec un bonus de rattrapage en S2.

Aucun fichier du jeu n'a été modifié. Les réglages E et F se coderaient dans `scripts/economy.gd` (constantes) et `scripts/game_state.gd` (`daily_refresh`, `spot_simulated`), puis passeraient par les tests et une nouvelle simulation.
