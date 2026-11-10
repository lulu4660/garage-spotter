# Équilibrage de la progression longue : prestige, arbre, mécaniciens, séries, missions, succès

Script : `tools/sim/simulate_progression.py` (Python 3, bibliothèque standard). Il réutilise `tools/sim/simulate_season.py` sans le modifier : rue, catalogue de 600 modèles, mise à neuf, joueur type et profils sont les mêmes.
Relancer le rapport : `python3 tools/sim/simulate_progression.py --runs 12 --quick`. Cela prend environ 35 min sur 4 cœurs ; ajouter `--jobs N` pour régler le nombre de processus.
Par section : `--only base,profils,sensib,variantes,proposition,s2`. Séries jour par jour : `--csv dossier/`.
Au lancement, le script compare ses constantes à `progression.gd` et `game_state.gd` et affiche un avertissement en cas d'écart.

Les chiffres sont des médianes sur 12 tirages, et sur 6 tirages pour les variantes (sections D et E). Les tirages sont appariés : à graine égale, la rue est la même.

## 1. Modèle simulé

**Repris du code** (`progression.gd`, `game_state.gd`) :
- **Prestige** : `floor(√(gains de la partie / 1e7))` points. Chaque point gagné donne +1 % de revenus. Le prestige remet à zéro les pièces, les niveaux, l'étape et les places. Il garde la collection, les mises à neuf, la réputation, l'arbre et les succès. Il applique `start_coins`, `start_stage` et `start_slots`.
- **Multiplicateur global** : `(1 + collection) × (1 + réputation + séries) × income_mult de l'arbre`, comme dans `income_multiplier()`.
- **Arbre** : les 24 compétences, avec leurs coûts et effets. Les réductions des améliorations, des étapes et des places sont appliquées. Le hors ligne de 4 h / 12 h, le rush de 45 s ×2,5, le gain de spot ×1,5 / ×3, les mises à neuf en plus, le bonus de collection, les places, l'étape et les pièces de départ aussi.
- **Mécaniciens** : 0/1/1/2 selon l'étape, plus l'arbre. Chacun achète 1 niveau toutes les 8 s (4 s avec « Chef d'atelier »), sur la pièce la moins chère, si son prix est ≤ 30 % des pièces. Ils ne travaillent que lorsque l'appli est ouverte (`tick`), pas hors ligne.
- **Séries** : 7 séries, paliers +5 / +10 / +25 %.
- **Missions** : 3 missions par jour, tirées parmi 6, avec un objectif au hasard parmi 3.
- **Succès** : les 18 succès, avec leurs récompenses. Le joueur réclame tout à chaque session.
- **Jetons** : `jetons = max(jetons, quota)` chaque jour. Les jetons gagnés en récompense s'ajoutent.

**Joueur type** : celui du rapport précédent, soit 6 sessions de 3 min par jour, l'achat le plus rentable et 20 touches (1 rush) par session. S'y ajoutent :
- **Prestige** : le joueur prestige dès que le gain atteint 50 % de sa réputation à vie (1 point suffit s'il n'en a aucune), au plus tôt 24 h après le début ou après le prestige précédent. La sensibilité à cette règle est en section D.
- **Arbre** : il achète tout de suite après chaque prestige la compétence disponible la moins chère. À coût égal, l'ordre est Revenus > Atelier > Spot > Garage.

**Hypothèses à connaître** :
- *Séries* : le catalogue de saison n'a pas de marques. On reprend, rareté par rareté, les proportions du catalogue de phase 0 (`catalog.gd`) : 60 % des communes sont françaises, tous les Épiques sont des supercars, etc.
- *Radar (s3, délai de spot −30 %)* : sans effet ici. Les spots viennent de la rue (profils), pas d'un minuteur.
- *Joueur optimal* : il fait des centaines d'achats par session sans coût de clic. La part des mécaniciens est donc un minimum.
- *Saison 2* : la règle n'existe pas encore. Deux hypothèses sont simulées : on garde la réputation et l'arbre, ou on les remet à zéro.
- *Pass et gros payeur* : aucune offre payante n'est définie. Le profil « Payeur » a des mises à neuf illimitées.

## 2. Résultats avec les valeurs actuelles

### 2.1 Q1 : calendrier du prestige et de l'arbre (joueur type)

| Indicateur | Médiane | P10 – P90 |
|---|---|---|
| 1er point de réputation disponible | j1 13 h | j1 11 h – j1 13 h |
| 1er prestige (bloqué par le délai de 24 h) | j2 8 h, 6 points | j2 8 h |
| Prestiges sur 70 j | 22 | 21 – 22 |
| Réputation à vie à j70 | **123 178** | 97 644 – 207 309 |
| 12e compétence | jour 4,3 | 4,3 – 5,3 |
| Arbre complet (24/24) | **j8 9 h** | j7 8 h – j8 13 h |

| Prestige | Heure de jeu | Points gagnés | Réputation à vie | Revenu avant (/s) | Rattrapage (h réelles) |
|---|---|---|---|---|---|
| 1 | j2 8 h | 6 | 6 | 13 639 | 12,8 |
| 2 | j3 8 h | 10 | 17 | 32 594 | 11,0 |
| 3 | j4 8 h | 18 | 35 | 97 118 | 11,0 |
| 5 | j6 8 h | 35,5 | 99 | 239 282 | 8,0 |
| 7 | j8 11 h | 114 | 253 | 2,21e6 | 9,5 |
| 10 | j11 23 h | 338 | 990 | 9,04e6 | 9,5 |
| 12 | j15 18 h | 800 | 2 296 | 3,54e7 | 14,5 |

Le joueur prestige une fois par jour pendant 12 jours : chaque prestige rapporte au moins 50 % de réputation en plus. L'arbre de 170 points est complet au **jour 8**. Il n'y a plus rien à y acheter pendant les 62 jours suivants.

### 2.2 Q2 : le prestige est-il rentable dès le premier ?

**Oui, beaucoup trop.**
- Le 1er prestige (6 points) est rattrapé en **12,8 h réelles**, soit 3 sessions. Le joueur dépasse ensuite tout de suite la courbe sans prestige : 218 k contre 137 k au j5, ×1,6.
- Tous les prestiges suivants sont rattrapés en 6 à 15 h, avant le suivant (12/12 parties).
- Il n'y a aucun coût réel à prestiger : la décision est triviale.

### 2.3 Q3 : emballement ou mur ?

**Emballement massif.** Revenu record du joueur type, en /s :

| Jour | Tout (actuel) | Sans prestige | Sans nouveaux systèmes | Tout ÷ sans systèmes | Réputation | Multiplicateur global | Collection | Réputation + séries | Arbre |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 8 865 | 8 865 | 5 256 | 1,67 | 0 | ×1,36 | +8 % | +25 % (séries +25 %) | ×1,00 |
| 3 | 62 485 | 57 879 | 28 906 | 2,47 | 17 | ×3,13 | +19 % | +110 % (séries +92 %) | ×1,24 |
| 7 | 1,05e6 | 205 976 | 73 519 | 11,6 | 150 | ×13,5 | +69 % | +290 % | ×2,06 |
| 14 | 2,05e7 | 698 978 | 152 690 | 138 | 1 654 | ×113 | +117 % | +1 854 % | ×2,75 |
| 28 | 1,14e9 | 2,32e6 | 568 783 | 2 013 | 13 298 | ×1 075 | +186 % | +13 518 % | ×2,75 |
| 49 | 9,54e9 | 4,56e6 | 1,18e6 | 9 562 | 62 486 | ×6 129 | +247 % | +62 742 % | ×2,75 |
| 70 | **2,45e10** | 6,36e6 | 1,62e6 | **15 647** | 123 178 | **×13 407** | +296 % | +123 434 % (séries +255 %) | ×2,75 |

| Variante | Doublement j0-3 | j3-14 | j14-49 | j49-70 | Sessions avec un achat du joueur |
|---|---|---|---|---|---|
| Tout (actuel) | 5 h | 30 h | 102 h | 336 h | 38 % |
| Sans prestige | 5 h | 71 h | 325 h | 1 726 h | 54 % |
| Sans nouveaux systèmes | 6 h | 107 h | 306 h | 1 919 h | 88 % |

- **Boucle qui se compose** :
  - plus de revenu donne plus de points (√ des gains) ;
  - chaque point donne +1 % de revenu ;
  - ce bonus se multiplie avec la collection (×) et l'arbre (×2,75).

  La réputation pèse ×1 235 à j70 : le revenu ×15 600 par rapport au jeu sans ces systèmes vient d'elle. Un délai de 24 h ne change rien (sensibilité ci-dessous).
- **Mur de contenu** : au jour 70, **100 % des pièces exposées sont au niveau 200**. Dès que le revenu dépasse ~1e9/s, un niveau ne coûte plus rien. Le joueur n'achète quelque chose que dans **38 % des sessions** (88 % sans ces systèmes) : il n'a plus que prestige et spots à faire.
- **Les étapes ne comptent plus** :
  - après le 1er prestige, Atelier, Showroom et Hangar sont rachetés en 2,5 / 3 / 3,5 h ;
  - avec « Atelier / Showroom de départ » (g5, g6), la plupart des parties démarrent au Showroom.
- **Séries trop fortes** : +25 % dès le jour 1 et +255 % à j70, soit plus que la collection elle-même (+296 %) pour 7 séries faciles à compléter.

**Classement décidé par la règle de prestige** (section D, 6 tirages) :

| Règle du joueur | Prestiges | Réputation j70 | Revenu j70 |
|---|---|---|---|
| Ratio 50 %, délai 24 h (référence) | 22 | 166 818 | 4,23e10 |
| Délai 6 h | 27 | 151 744 | 3,81e10 |
| Délai 72 h | 14 | 153 160 | 4,26e10 |
| Ratio 100 % (prestiges rares) | 14 | 74 855 | 1,92e10 |
| Ratio 25 % (prestiges fréquents) | 34 | 349 344 | **9,54e10** |

Prestiger souvent rapporte **×5** par rapport à prestiger rarement. Avec la boucle composée, les écarts entre profils explosent aussi :

| Profil | Revenu j70 | ÷ gratuit | Avant ces systèmes (rapport précédent) |
|---|---|---|---|
| Gratuit / pubs / payeur | 2,45e10 | 1,00 | 1,00 |
| Rural | 2,27e9 | **0,09** | 0,45 |
| Gros spotteur | 2,89e11 | **11,8** | 2,29 |

Le nombre de spots (×11,8) et la fréquence des prestiges (×5) décident du classement. Ce n'est pas le cas d'un achat : « payeur » = gratuit (1,00), car le quota de mises à neuf ne bloque pas le joueur type.

### 2.4 Q4 : les mécaniciens rendent-ils le jeu passif ?

**Non, ils sont presque inutiles.**

| Variante | Revenu j7 | j14 | j28 | j70 | ÷ joueur actif | Part des niveaux achetés par mécano |
|---|---|---|---|---|---|---|
| Joueur actif + mécaniciens (actuel) | 1,05e6 | 2,05e7 | 1,14e9 | 2,45e10 | 1,00 | 2 % |
| Joueur actif sans mécaniciens | 1,10e6 | 2,06e7 | 1,16e9 | 2,44e10 | 1,00 | 0 % |
| Mécaniciens seuls (le joueur n'achète aucun niveau) | 411 | 1 902 | 15 249 | 4,64e6 | 0,0002 | 100 % |

- Avec 4 mécaniciens dès le jour 7, ils font **2 à 3 % des niveaux** (12 436 contre 562 766 sur la saison) et 2,2 % des pièces dépensées.
- Les retirer ne change rien (1,00). Les passer à 4 s et 50 % de budget non plus : 4,23e10 contre 4,23e10.
- La raison : ils ne travaillent que lorsque l'appli est ouverte (3 min par session) et n'achètent qu'un niveau à la fois sur la pièce la moins chère. Le joueur, lui, dépense tout à l'ouverture.
- Le risque de jeu passif viendrait seulement de mécaniciens qui travailleraient hors ligne. Ce n'est pas le cas, et il ne faut pas le faire.

### 2.5 Q5 : missions et succès, trop de mises à neuf ?

| Profil | Mises à neuf faites/j | Gagnées en missions/j | Gagnées en succès (saison) | Jetons perdus au changement de jour/j | Grises max avec / sans récompenses | Revenu j14 avec ÷ sans | j70 avec ÷ sans |
|---|---|---|---|---|---|---|---|
| Gratuit | 2,07 | 0,56 | 41 | 3,70 | 0 / 1 | 1,00 | 1,00 |
| Rural | 1,13 | 0,20 | 39 | 2,24 | 0 / 0 | 1,00 | 1,00 |
| Gros spotteur | 3,64 | 0,83 | 41 | 3,69 | **5 / 24** | **1,50** | 0,96 |

- **Joueur type et rural** : aucun effet. Le quota ne les bloque déjà pas : ils perdent 2,2 à 3,7 jetons par jour à cause de `max(jetons, quota)`. Les compétences « Carnet d'adresses » (+1/j) et « Réseau de spotters » (+2/j) ne leur servent à rien non plus.
- **Gros spotteur** : les récompenses sont utiles, pas excessives. Le jour 1, les succès donnent 13 jetons (« Spotter du dimanche », « Petite collection », « Ça brille », etc.) et 12 le jour 2. Elles ramènent le pic de voitures grises de 24 à 5 et le revenu au j14 de ×0,67 à ×1. Elles jouent donc le rôle de la « semaine de bienvenue » recommandée dans le rapport précédent.
- **Missions mal calibrées** pour le joueur type (20 touches et environ 1 à 7 spots par jour) :

| Mission | Réussies / proposées |
|---|---|
| Rush (2/4/6) | 100 % |
| Niveaux (25/60/150) | 47 % (actuel, pièces au niveau 200) ; 99 % (proposition) |
| Mises à neuf (1/2/3) | 65 % |
| Paliers ×2 (2/4/8) | 48 % (actuel) ; 68 % (proposition) |
| Spots (3/5/8) | 48 % |
| Touches (100/250/500) | **31 %** (250 et 500 jamais atteints avec 120 touches/jour) |

## 3. Variantes testées (joueur type, 6 tirages)

| Variante | 1er prestige | Prestiges | Réputation j70 | Arbre complet | Rattrapage 1er prestige | Doubl. j3-14 | j14-49 | j49-70 | Sessions avec achat | Revenu j70 | ÷ sans systèmes |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Actuel | j2 8 h | 22 | 166 818 | j8 12 h | 12,8 h | 27 h | 102 h | 339 h | 37 % | 4,23e10 | 21 588 |
| Diviseur 1e8 | j2 8 h | 20 | 16 010 | j15 | 14,5 h | 40 h | 103 h | 328 h | 55 % | 4,48e9 | 2 239 |
| Diviseur 1e9 | j2 19 h | 18 | 1 647 | j28 | 21 h | 55 h | 124 h | 309 h | 83 % | 5,38e8 | 270 |
| Diviseur 1e10 | j4 21 h | 12 | 140 | 2/6 | 22 h | 70 h | 220 h | 359 h | 82 % | 3,35e7 | 17 |
| Bonus 0,5 %/point | j2 8 h | 21 | 75 010 | j8 | 12,8 h | 31 h | 112 h | 339 h | 46 % | 9,48e9 | 4 745 |
| Bonus globaux additionnés | j2 8 h | 17 | 13 670 | j9 | 12,8 h | 43 h | 171 h | 376 h | 85 % | 3,35e8 | 174 |
| Séries +2/+4/+8 % | j2 8 h | 23 | 159 208 | j9 | 14,5 h | 26 h | 96 h | 332 h | 38 % | 4,35e10 | 21 422 |
| Coûts de l'arbre ×2 | j2 8 h | 22 | 177 798 | j11 | 12,8 h | 27 h | 102 h | 334 h | 37 % | 4,83e10 | 23 769 |
| Mécaniciens 4 s, 50 % | j2 8 h | 22 | 166 825 | j8 12 h | 12,8 h | 27 h | 102 h | 339 h | 37 % | 4,23e10 | 21 589 |
| Additionnés + diviseur 1e9 | j2 19 h | 14 | 315 | j44 | 21 h | 63 h | 240 h | 924 h | 79 % | 1,07e7 | 5,6 |
| Additionnés + 1e9 + séries 2/4/8 + étapes 1e5/5e7/5e9 | j3 3 h | 14 | 262 | j54 | 24 h | 71 h | 225 h | 717 h | 85 % | 7,81e6 | 3,9 |
| Additionnés + bonus 10 % × √réputation | j2 8 h | 14 | 4 128 | j9 | 11 h | 51 h | 366 h | 930 h | 75 % | 1,69e7 | 8,8 |
| Additionnés + points calculés hors bonus de réputation | j2 8 h | 14 | 4 198 | j9 | 12,8 h | 46 h | 227 h | 399 h | 86 % | 9,42e7 | 47 |
| **PROPOSITION** | j2 8 h | 15 | 2 982 | j43 | 14,5 h | 60 h | 215 h | 1 042 h | 80 % | 1,08e7 | **5,7** |
| Proposition, bonus 5 % × √réputation | j2 8 h | 14 | 2 851 | j50 | 14,5 h | 63 h | 232 h | 1 026 h | 85 % | 7,34e6 | 3,9 |
| Proposition, coûts de l'arbre ×5 | j2 8 h | 15 | 3 163 | j27 | 14,5 h | 61 h | 222 h | 1 093 h | 77 % | 1,13e7 | 5,9 |
| Proposition, coûts de l'arbre ×15 | j2 8 h | 14 | 2 778 | j60 | 14,5 h | 59 h | 217 h | 746 h | 82 % | 1,04e7 | 5,2 |
| Proposition, étapes actuelles | j2 8 h | 15 | 3 438 | j47 | 14,5 h | 61 h | 235 h | 967 h | 80 % | 1,07e7 | 5,6 |
| Proposition, séries actuelles (5/10/25) | j2 8 h | 15 | 3 696 | j43 | 14,5 h | 63 h | 238 h | 992 h | 80 % | 1,33e7 | 7,0 |
| Proposition, sans mises à neuf en récompense | j2 8 h | 15 | 2 982 | j43 | 14,5 h | 60 h | 214 h | 1 042 h | 80 % | 1,08e7 | 5,7 |
| Proposition, ratio 25 % | j2 8 h | 24 | 4 575 | j36 | 14,5 h | 63 h | 215 h | 955 h | 88 % | 1,15e7 | 5,9 |
| Proposition, ratio 100 % | j2 8 h | 9 | 1 819 | 3/6 | 14,5 h | 61 h | 235 h | 688 h | 72 % | 9,16e6 | 4,7 |
| Proposition, délai 6 h | j1 13 h | 18 | 3 256 | j44 | 9,5 h | 49 h | 213 h | 969 h | 81 % | 1,08e7 | 5,6 |

Lecture :
- **Le diviseur seul ne guérit rien.** Avec 1e9, on a encore ×270. Avec 1e10, la boucle est cassée mais le 1er prestige n'est plus rentable : voir la remarque ci-dessous.
- **Additionner les bonus ne suffit pas non plus** (×174), car la réputation reste linéaire en points.
- **La boucle est cassée par un bonus de réputation concave** : 10 % × √(réputation à vie). Les doublements ralentissent alors normalement (51 → 366 → 930 h).
- **Le diviseur 1e9 additionné** (×3,9 à ×5,6) a un défaut : les premiers prestiges ne valent que 1 point. Dans une version antérieure de ces variantes, avec 12 tirages et les étapes 1e5/5e7/5e9, le 1er prestige était au j2 23 h. Ses 4 premiers prestiges rapportaient 1, 1, 1 et 2 points. Le joueur restait sous la courbe sans prestige jusqu'au **jour 35** (j7 : 68 k contre 93 k). C'est un piège pour le joueur.
- **Avec la proposition, la règle de prestige du joueur ne décide plus du classement** : de ×4,7 (ratio 100 %) à ×5,9 (ratio 25 %), soit ±15 %, contre ×5 aujourd'hui.

## 4. Proposition retenue

Les valeurs sont détaillées en section 5. Le diviseur reste à 1e7.

### 4.1 Joueur type, proposition (12 tirages)

| Indicateur | Médiane | P10 – P90 |
|---|---|---|
| 1er prestige | j2 8 h, 4 points | j2 8 h |
| Prestiges sur 70 j | 14 | 14 – 15 |
| Réputation à vie j70 | 2 590 | 1 957 – 3 375 |
| 12e compétence | jour 18,9 | 13,8 – 22,3 |
| Arbre complet | **j53** | j39 – j64 |

| Prestige | Heure de jeu | Points | Réputation à vie | Revenu avant (/s) | Rattrapage (h réelles) |
|---|---|---|---|---|---|
| 1 | j2 8 h | 4 | 4 | 8 241 | 14,5 |
| 2 | j3 8 h | 6,5 | 11 | 19 437 | 14,5 |
| 4 | j5 8 h | 12 | 32,5 | 52 465 | 14,5 |
| 6 | j7 19 h | 26,5 | 76 | 104 993 | 22,8 |
| 8 | j12 9 h | 58,5 | 174 | 218 986 | 38,5 |
| 10 | j20 15 h | 133 | 394 | 971 860 | 72 |
| 12 | j33 19 h | 302 | 892 | 2,90e6 | 78,5 |

Les prestiges s'espacent naturellement : un par jour au début, un par semaine à la fin. Leur rattrapage passe de 14 h à 3 jours.

| Jour | Proposition | Sans prestige | Sans nouveaux systèmes | ÷ sans systèmes | Multiplicateur global | Collection | Réputation | Séries | Arbre |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 5 035 | 5 035 | 5 256 | 0,99 | ×1,19 | +8 % | 0 | +10 % | 0 |
| 2 | 10 726 | 19 088 | 16 228 | 0,64 | ×1,55 | +13 % | +20 % | +20 % | 0 |
| 3 | 19 927 | 33 002 | 28 906 | 0,76 | ×1,94 | +19 % | +33 % | +34 % | +10 % |
| 5 | 68 486 | 67 705 | 56 474 | 1,13 | ×2,41 | +26 % | +57 % | +49 % | +10 % |
| 7 | 99 095 | 92 706 | 73 519 | 1,36 | ×2,76 | +34 % | +79 % | +50 % | +10 % |
| 14 | 276 407 | 218 208 | 152 690 | 1,82 | ×3,88 | +58 % | +137 % | +71 % | +23 % |
| 28 | 1,81e6 | 938 558 | 568 783 | 3,18 | ×5,54 | +95 % | +254 % | +78 % | +35 % |
| 49 | 4,57e6 | 1,53e6 | 1,18e6 | 4,39 | ×8,46 | +185 % | +381 % | +90 % | +85 % |
| 70 | **8,65e6** | 2,18e6 | 1,62e6 | **5,41** | ×10,4 | +222 % | +509 % | +90 % | +135 % |

| Doublement | j0-3 | j3-14 | j14-49 | j49-70 | Sessions avec un achat du joueur |
|---|---|---|---|---|---|
| Proposition | 6 h | 70 h | 216 h | 1 021 h | 82 % |
| Sans nouveaux systèmes | 6 h | 107 h | 306 h | 1 919 h | 88 % |

- **Rentabilité du prestige** : le 1er prestige (+20 % de réputation) fait baisser le revenu pendant environ 2 jours (×0,64 au j2, ×0,76 au j3 face au jeu sans systèmes). Le joueur repasse devant la courbe sans prestige au **jour 5** (68 k contre 68 k), puis l'écart grandit : ×1,27 au j14, ×4,0 au j70. Le prestige reste donc intéressant, sans être gratuit.
- **Pas d'emballement** : les doublements ralentissent (6 → 70 → 216 → 1 021 h), seules 11 % des pièces sont au niveau 200 à j70, et 82 % des sessions ont un achat.
- **Plateau de fin de saison** : il est réduit (1 021 h contre 1 919 h) mais toujours là. Avec des coûts de l'arbre ×15, on descend à 746 h (arbre complet au j60).
- **Étapes** (1e5 / 5e7 / 5e9) : après un prestige, l'Atelier arrive en 2,5 h, le Showroom en 12 h et le **Hangar en 48 h**. Le Hangar n'est atteint que dans 69 parties sur 173 : il redevient un objectif de fin de partie. Le revenu final ne bouge pas (5,66 contre 5,59 avec les étapes actuelles).
- **Mécaniciens** : 6 % des niveaux, effet nul sur le revenu (1,08e7 contre 1,08e7 à 4 s et 50 % de budget).

### 4.2 Écart entre profils, proposition (12 tirages)

| Profil | 1er prestige | Prestiges | Réputation j70 | Compétences | Doubl. j0-3 | j3-14 | j14-49 | j49-70 | Sessions avec achat | Revenu j70 | P10 – P90 | ÷ gratuit | Grises max |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Gratuit | j2 8 h | 14 | 2 590 | 24 | 6 h | 70 h | 216 h | 1 021 h | 82 % | 8,65e6 | 5,51e6 – 1,30e7 | 1,00 | 0 |
| Pubs 5/j | j2 8 h | 14 | 2 590 | 24 | 6 h | 70 h | 216 h | 1 021 h | 82 % | 8,65e6 | idem | 1,00 | 0 |
| Payeur (mises à neuf illimitées) | j2 8 h | 14 | 2 590 | 24 | 6 h | 70 h | 216 h | 1 021 h | 82 % | 8,65e6 | idem | 1,00 | 0 |
| Rural | j2 8 h | 14 | 1 215 | 22 | 7 h | 70 h | 220 h | 544 h | 95 % | 2,52e6 | 1,39e6 – 7,13e6 | **0,29** | 0 |
| Gros spotteur | j2 8 h | 14 | 5 814 | 24 | 5 h | 71 h | 293 h | 835 h | 82 % | 2,05e7 | 1,27e7 – 2,85e7 | **2,36** | 9 |
| Gros spotteur + pubs | j2 8 h | 14 | 5 921 | 24 | 5 h | 72 h | 300 h | 806 h | 82 % | 2,04e7 | 1,30e7 – 2,86e7 | 2,36 | 0 |

- **Gros spotteur** : il revient à ×2,36, contre ×11,8 aujourd'hui et ×2,29 avant ces systèmes.
- **Rural** : il remonte à ×0,29, contre ×0,09 aujourd'hui, mais reste sous le ×0,45 d'avant. Cela vient de séries et d'une collection plus maigres, et de 22 compétences sur 24. Son P90 atteint pourtant 0,82 du gratuit médian. C'est le **point faible restant** de la proposition.
- **Payeur** : aucun achat ne décide du classement. Pubs et payeur sont égaux au gratuit, puisque le quota de mises à neuf ne bloque pas.

### 4.3 Rattrapage en saison 2 (jours pour retrouver le revenu record de fin de S1)

| Réglage | Profil | S2 garde réputation + arbre | S2 remet réputation + arbre à zéro |
|---|---|---|---|
| Actuel | Gratuit | 1 j | 20,5 j |
| Actuel | Rural | 1 j | 21,5 j |
| Actuel | Gros spotteur | 1 j | 32 j |
| Proposition | Gratuit | **7 j** | 27,5 j |
| Proposition | Rural | **5,5 j** | 24,5 j |
| Proposition | Gros spotteur | **7 j** | 32,5 j |

(4 tirages par case.) Avec la proposition, **une S2 qui garde réputation et arbre tombe sur la cible d'environ 8 jours**. Aujourd'hui, une S2 de ce type est rattrapée en 1 jour : la saison n'aurait aucun sens. Remettre la réputation à zéro donne 20 à 33 jours dans les deux cas, ce qui est trop long.

## 5. Recommandations (par ordre de priorité)

1. **Rendre le bonus de réputation concave (10 % × √réputation à vie), en gardant `PRESTIGE_DIVISOR := 1.0e7`.**
   - Dans `progression.gd`, `REP_INCOME_BONUS := 0.10`, et ajouter `static func rep_bonus(rep_total: int) -> float: return REP_INCOME_BONUS * sqrt(float(rep_total))`.
   - Dans `game_state.income_multiplier()`, l'utiliser à la place de `REP_INCOME_BONUS * rep_total`.
   - C'est la seule mesure qui casse la boucle (×15 600 → ×5,4 à j70, réputation 123 178 → 2 590) tout en gardant un 1er prestige utile : +20 % dès 4 points, rattrapé en 14,5 h.
   - Les variantes « diviseur 1e9 / 1e10 » cassent la boucle mais rendent les premiers prestiges perdants pendant des semaines.
   - Le texte d'aide devient « +10 % × √(points gagnés) ».
2. **Additionner tous les bonus globaux** (règle « les échelles s'additionnent »).
   - `income_multiplier()` devient `1.0 + (COLLECTION_BONUS + fx.collection_bonus) * unique_models() + Progression.rep_bonus(rep_total) + fx.income_bonus`.
   - Les compétences de revenus passent en bonus additif : r1 `{"income_bonus": 0.10}`, r3 `{"income_bonus": 0.25}`, r6 `{"income_bonus": 1.0}` (texte : « +100 % de revenus »).
   - Les réductions de coût (a1/a3/a6) peuvent rester multiplicatives : elles équivalent à un décalage de 6,5 niveaux.
3. **Coûts de l'arbre ×10** (170 → 1 700 points ; arbre complet au j53 au lieu du j8) :
   - **Revenus** : r1 10, r2 20, r3 40, r4 60, r5 100, r6 200 ;
   - **Atelier** : a1 10, a2 20, a3 40, a4 60, a5 100, a6 180 ;
   - **Spot** : s1 10, s2 30, s3 40, s4 70, s5 100, s6 160 ;
   - **Garage** : g1 10, g2 30, g3 40, g4 70, g5 100, g6 200.

   Si l'on veut atténuer le plateau de fin de saison, passer à ×15 : arbre au j60, doublement j49-70 de 746 h au lieu de 1 042 h.
4. **Calmer les séries et « Collectionneur ».**
   - `SERIES_BONUS = [0.02, 0.04, 0.08]` au lieu de `[0.05, 0.10, 0.25]`. Les 7 séries pèsent alors +90 % au maximum au lieu de +280 %. Aujourd'hui, elles dépassent la collection dès le jour 3.
   - s5 : `{"collection_bonus": 0.005}`, texte « +1,5 % par modèle au lieu de +1 % ».
5. **Prix des étapes dans `economy.gd` : Atelier 1.0e5, Showroom 5.0e7, Hangar 5.0e9.**
   - Avec la proposition, le Hangar arrive 48 h après un prestige, contre 3,5 h aujourd'hui, et seulement dans 40 % des parties. L'arc Box → Hangar rejoue à chaque prestige.
   - Coût sur le revenu final : nul (5,66 contre 5,59).
   - Garder g5/g6 (départ Atelier/Showroom) à 100 et 200 points pour qu'ils restent tardifs.
6. **Mécaniciens et récompenses : garder les valeurs, corriger les missions.**
   - Laisser `STAFF_INTERVAL := 8.0`, `STAFF_BUDGET := 0.3`, `STAFF_BY_STAGE = [0, 1, 1, 2]` : 2 à 6 % des niveaux, effet nul sur le revenu, aucun risque de jeu passif tant qu'ils ne travaillent pas hors ligne.
   - Garder les mises à neuf des missions et succès. Elles n'ont d'effet que pour le gros spotteur, positif : pic de grises 24 → 5.
   - Mission « touches » : passer les objectifs à `[60, 100, 120]` (31 % de réussite aujourd'hui).
   - Mission « spots » : passer à `[2, 3, 5]` (48 %).
   - Ces deux objectifs viennent du modèle de joueur (120 touches et 2,5 à 7 spots par jour). Ils n'ont pas été simulés à part ; leur effet sur le revenu est négligeable, car les récompenses ne pèsent que 2,5 % des gains.

Les autres points relevés ne sont pas chiffrés dans les recommandations :
- « Radar » (s3) n'a aucun effet quand les spots sont de vraies photos.
- « Carnet d'adresses » et « Réseau de spotters » ne servent pas au joueur type, qui perd déjà 3 jetons par jour.
- Le rural reste à ×0,29 avec la proposition. Il faut une étude dédiée, par exemple des paliers de séries plus bas ou un bonus de rattrapage.

Aucun fichier du jeu n'a été modifié. Une fois ces valeurs codées, il faut relancer `godot --headless --path . -s tests/run_tests.gd`, puis `python3 tools/sim/simulate_progression.py --runs 12 --quick` en mettant `DEFAULT` = `PROPOSAL` dans le script pour retrouver ces chiffres.
