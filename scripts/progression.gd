## Règles de la progression longue : réputation (prestige), arbre de
## compétences, collections, missions du jour et succès.
## Données et fonctions pures, comme economy.gd : à porter côté serveur en phase 1.
## Les valeurs sont un premier jet, à valider par simulation (agent economy-balancer).
extends RefCounted

# --- Réputation (prestige) ---------------------------------------------------
## Repartir à zéro rapporte floor(√(gains de la partie / DIVISEUR)) points.
## Les points gagnés (à vie) donnent +10 % × √(points) de revenus : un bonus qui
## ralentit avec le temps, pour que les prestiges ne s'emballent pas
## (voir docs/equilibrage-progression.md). Les points non dépensés achètent l'arbre.

const PRESTIGE_DIVISOR := 1.0e7
const REP_INCOME_BONUS := 0.10


static func rep_bonus(rep_total: int) -> float:
	return REP_INCOME_BONUS * sqrt(float(maxi(rep_total, 0)))


static func prestige_points(run_earnings: float) -> int:
	if run_earnings <= 0.0:
		return 0
	return int(floor(sqrt(run_earnings / PRESTIGE_DIVISOR)))


## Gains de la partie nécessaires pour atteindre `points` points.
static func earnings_for_points(points: int) -> float:
	return float(points * points) * PRESTIGE_DIVISOR


# --- Arbre de compétences ------------------------------------------------------
## 4 branches de 6 nœuds ; un nœud demande le précédent de sa branche.
## Effets possibles (cumulés par addition, sauf les « _mult » qui se multiplient) :
##   income_mult, upgrade_cost_mult, stage_cost_mult, slot_cost_mult, spot_gain_mult,
##   spot_cooldown_mult, rush_mult, rush_duration, offline_full_h, offline_max_h,
##   extra_restores, collection_bonus, start_slots, start_stage, start_coins,
##   staff_slots, staff_speed_mult.

const BRANCHES: Array[Dictionary] = [
	{"id": "revenus", "name": "Revenus", "icon": "coin"},
	{"id": "atelier", "name": "Atelier", "icon": "wrench"},
	{"id": "spot", "name": "Spot", "icon": "camera"},
	{"id": "garage", "name": "Garage", "icon": "garage"},
]

const SKILLS: Array[Dictionary] = [
	{"id": "r1", "branch": "revenus", "name": "Huile de coude", "desc": "+10 % de revenus.", "cost": 10, "fx": {"income_bonus": 0.10}},
	{"id": "r2", "branch": "revenus", "name": "Clients fidèles", "desc": "Hors ligne : 100 % pendant 4 h au lieu de 2 h.", "cost": 20, "fx": {"offline_full_h": 2.0}},
	{"id": "r3", "branch": "revenus", "name": "Néons tape-à-l'œil", "desc": "+25 % de revenus.", "cost": 40, "fx": {"income_bonus": 0.25}},
	{"id": "r4", "branch": "revenus", "name": "Rush prolongé", "desc": "Le rush dure 45 s et rapporte x2,5.", "cost": 60, "fx": {"rush_duration": 15.0, "rush_mult": 1.25}},
	{"id": "r5", "branch": "revenus", "name": "Nuit blanche", "desc": "Hors ligne : jusqu'à 12 h au lieu de 8 h.", "cost": 100, "fx": {"offline_max_h": 4.0}},
	{"id": "r6", "branch": "revenus", "name": "Empire de la nuit", "desc": "+100 % de revenus.", "cost": 200, "fx": {"income_bonus": 1.0}},
	{"id": "a1", "branch": "atelier", "name": "Clé à choc", "desc": "Améliorations -10 %.", "cost": 10, "fx": {"upgrade_cost_mult": 0.90}},
	{"id": "a2", "branch": "atelier", "name": "Mécano", "desc": "+1 mécanicien : il achète les améliorations tout seul.", "cost": 20, "fx": {"staff_slots": 1}},
	{"id": "a3", "branch": "atelier", "name": "Fournisseur attitré", "desc": "Améliorations -15 %.", "cost": 40, "fx": {"upgrade_cost_mult": 0.85}},
	{"id": "a4", "branch": "atelier", "name": "Chef d'atelier", "desc": "Les mécaniciens travaillent 2 fois plus vite.", "cost": 60, "fx": {"staff_speed_mult": 2.0}},
	{"id": "a5", "branch": "atelier", "name": "Équipe de nuit", "desc": "+1 mécanicien.", "cost": 100, "fx": {"staff_slots": 1}},
	{"id": "a6", "branch": "atelier", "name": "Usine", "desc": "Améliorations -30 %.", "cost": 180, "fx": {"upgrade_cost_mult": 0.70}},
	{"id": "s1", "branch": "spot", "name": "Œil de lynx", "desc": "Gain immédiat des spots x1,5.", "cost": 10, "fx": {"spot_gain_mult": 1.5}},
	{"id": "s2", "branch": "spot", "name": "Carnet d'adresses", "desc": "+1 mise à neuf gratuite par jour.", "cost": 30, "fx": {"extra_restores": 1}},
	{"id": "s3", "branch": "spot", "name": "Radar", "desc": "Spots plus fréquents (délai -30 %).", "cost": 40, "fx": {"spot_cooldown_mult": 0.70}},
	{"id": "s4", "branch": "spot", "name": "Réseau de spotters", "desc": "+2 mises à neuf gratuites par jour.", "cost": 70, "fx": {"extra_restores": 2}},
	{"id": "s5", "branch": "spot", "name": "Collectionneur", "desc": "Bonus de collection : +1,5 % par modèle au lieu de +1 %.", "cost": 100, "fx": {"collection_bonus": 0.005}},
	{"id": "s6", "branch": "spot", "name": "Légende de la rue", "desc": "Gain immédiat des spots x3.", "cost": 160, "fx": {"spot_gain_mult": 3.0}},
	{"id": "g1", "branch": "garage", "name": "Place réservée", "desc": "+1 place de garage au départ.", "cost": 10, "fx": {"start_slots": 1}},
	{"id": "g2", "branch": "garage", "name": "Plans d'architecte", "desc": "Étapes du garage -25 %.", "cost": 30, "fx": {"stage_cost_mult": 0.75}},
	{"id": "g3", "branch": "garage", "name": "Fond de caisse", "desc": "Repartir avec 50 K pièces.", "cost": 40, "fx": {"start_coins": 50000.0}},
	{"id": "g4", "branch": "garage", "name": "Promoteur", "desc": "Places de garage -50 %.", "cost": 70, "fx": {"slot_cost_mult": 0.5}},
	{"id": "g5", "branch": "garage", "name": "Atelier de départ", "desc": "Repartir directement à l'Atelier.", "cost": 100, "fx": {"start_stage": 1}},
	{"id": "g6", "branch": "garage", "name": "Showroom de départ", "desc": "Repartir directement au Showroom, +1 place.", "cost": 200, "fx": {"start_stage": 1, "start_slots": 1}},
]

const MULT_KEYS: Array[String] = ["income_mult", "upgrade_cost_mult", "stage_cost_mult", "slot_cost_mult", "spot_gain_mult", "spot_cooldown_mult", "rush_mult", "staff_speed_mult"]


static func skill(id: String) -> Dictionary:
	for s in SKILLS:
		if s["id"] == id:
			return s
	return {}


static func branch_skills(branch: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in SKILLS:
		if s["branch"] == branch:
			out.append(s)
	return out


## Nœud précédent dans la branche (prérequis), ou "" pour le premier.
static func prerequisite(id: String) -> String:
	var s := skill(id)
	var list := branch_skills(String(s["branch"]))
	for i in list.size():
		if list[i]["id"] == id:
			return "" if i == 0 else String(list[i - 1]["id"])
	return ""


static func empty_effects() -> Dictionary:
	var fx := {}
	for k in MULT_KEYS:
		fx[k] = 1.0
	for k in ["offline_full_h", "offline_max_h", "rush_duration", "extra_restores", "collection_bonus", "start_slots", "start_stage", "start_coins", "staff_slots", "income_bonus"]:
		fx[k] = 0.0
	return fx


static func add_effects(fx: Dictionary, add: Dictionary) -> void:
	for k in add:
		if k in MULT_KEYS:
			fx[k] = float(fx[k]) * float(add[k])
		else:
			fx[k] = float(fx[k]) + float(add[k])


# --- Collections ------------------------------------------------------------
## Séries de voitures : chaque palier (modèles mis à neuf de la série) donne un
## bonus de revenus. Les bonus de séries s'additionnent entre eux.

const SERIES: Array[Dictionary] = [
	{"id": "fr", "name": "Made in France", "brands": ["Renolt", "Peujo", "Citroan", "Dacio"], "tiers": [2, 4, 7]},
	{"id": "de", "name": "Autobahn", "brands": ["Volkswagon", "Audy", "BMV", "Mercedez", "Porshe"], "tiers": [2, 5, 10]},
	{"id": "jp", "name": "JDM", "brands": ["Toyata", "Nisan", "Mazdo"], "tiers": [2, 3, 5]},
	{"id": "it", "name": "Bella Italia", "brands": ["Ferari", "Lamborgino", "Pagany"], "tiers": [1, 2, 4]},
	{"id": "util", "name": "Utilitaires", "bodies": ["fourgon", "combi", "pickup", "monospace"], "tiers": [1, 2, 4]},
	{"id": "open", "name": "Cheveux au vent", "bodies": ["cabriolet", "roadster"], "tiers": [1, 2, 3]},
	{"id": "exo", "name": "Supercars", "bodies": ["supercar"], "tiers": [1, 3, 6]},
]
const SERIES_BONUS: Array[float] = [0.02, 0.04, 0.08]


static func in_series(series: Dictionary, model: Dictionary) -> bool:
	if series.has("brands"):
		return String(model["brand"]) in series["brands"]
	return String(model["body"]) in series["bodies"]


## Palier atteint (0 à 3) pour `count` modèles de la série.
static func series_tier(series: Dictionary, count: int) -> int:
	var t := 0
	for need in series["tiers"]:
		if count >= int(need):
			t += 1
	return t


static func series_bonus(tier: int) -> float:
	var b := 0.0
	for i in mini(tier, SERIES_BONUS.size()):
		b += SERIES_BONUS[i]
	return b


# --- Missions du jour -------------------------------------------------------
## Trois missions tirées chaque jour (graine = la date), récompensées en
## mises à neuf ou en minutes de revenus.

const MISSIONS: Array[Dictionary] = [
	{"id": "spots", "text": "Fais %d spots", "stat": "spots", "goal": [2, 3, 5], "reward": {"restores": 1}},
	{"id": "levels", "text": "Achète %d niveaux de pièces", "stat": "levels", "goal": [25, 60, 150], "reward": {"minutes": 30}},
	{"id": "taps", "text": "Touche ta voiture %d fois", "stat": "taps", "goal": [60, 100, 120], "reward": {"minutes": 20}},
	{"id": "restores", "text": "Mets %d voitures à neuf", "stat": "restores", "goal": [1, 2, 3], "reward": {"restores": 1}},
	{"id": "rush", "text": "Déclenche %d rush", "stat": "rushes", "goal": [2, 4, 6], "reward": {"minutes": 30}},
	{"id": "milestones", "text": "Franchis %d paliers x2", "stat": "milestones", "goal": [2, 4, 8], "reward": {"minutes": 45}},
]


static func daily_missions(day: String) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(day)
	var pool := MISSIONS.duplicate()
	var out: Array[Dictionary] = []
	for i in 3:
		var k := rng.randi() % pool.size()
		var m: Dictionary = pool[k]
		pool.remove_at(k)
		var goal: int = m["goal"][rng.randi() % 3]
		out.append({"id": m["id"], "text": String(m["text"]) % goal, "stat": m["stat"], "goal": goal, "reward": m["reward"]})
	return out


# --- Succès -----------------------------------------------------------------
## Objectifs permanents ; chacun se réclame une fois.

const ACHIEVEMENTS: Array[Dictionary] = [
	{"id": "first_restore", "name": "Comme neuve", "desc": "Mets une voiture à neuf.", "stat": "restores", "goal": 1, "reward": {"minutes": 10}},
	{"id": "spots_10", "name": "Spotter du dimanche", "desc": "Fais 10 spots.", "stat": "spots", "goal": 10, "reward": {"restores": 1}},
	{"id": "spots_100", "name": "Spotter acharné", "desc": "Fais 100 spots.", "stat": "spots", "goal": 100, "reward": {"restores": 3}},
	{"id": "models_10", "name": "Petite collection", "desc": "Possède 10 modèles mis à neuf.", "stat": "models", "goal": 10, "reward": {"restores": 2}},
	{"id": "models_25", "name": "Grande collection", "desc": "Possède 25 modèles mis à neuf.", "stat": "models", "goal": 25, "reward": {"restores": 5}},
	{"id": "levels_500", "name": "Cambouis", "desc": "Achète 500 niveaux de pièces.", "stat": "levels", "goal": 500, "reward": {"minutes": 60}},
	{"id": "levels_5000", "name": "Chef mécano", "desc": "Achète 5 000 niveaux de pièces.", "stat": "levels", "goal": 5000, "reward": {"minutes": 120}},
	{"id": "part_100", "name": "Pièce de course", "desc": "Monte une pièce au niveau 100.", "stat": "max_part", "goal": 100, "reward": {"restores": 2}},
	{"id": "part_200", "name": "Pièce parfaite", "desc": "Monte une pièce au niveau 200.", "stat": "max_part", "goal": 200, "reward": {"restores": 5}},
	{"id": "stage_1", "name": "Atelier ouvert", "desc": "Construis l'Atelier.", "stat": "stage", "goal": 1, "reward": {"minutes": 30}},
	{"id": "stage_3", "name": "Roi du hangar", "desc": "Construis le Hangar.", "stat": "stage", "goal": 3, "reward": {"restores": 3}},
	{"id": "taps_1000", "name": "Doigt de fer", "desc": "Touche ta voiture 1 000 fois.", "stat": "taps", "goal": 1000, "reward": {"minutes": 30}},
	{"id": "rush_25", "name": "Pied au plancher", "desc": "Déclenche 25 rush.", "stat": "rushes", "goal": 25, "reward": {"minutes": 60}},
	{"id": "prestige_1", "name": "Nouveau départ", "desc": "Repars à zéro une première fois (prestige).", "stat": "prestiges", "goal": 1, "reward": {"restores": 3}},
	{"id": "prestige_5", "name": "Légende du quartier", "desc": "Fais 5 prestiges.", "stat": "prestiges", "goal": 5, "reward": {"restores": 5}},
	{"id": "rare", "name": "Ça brille", "desc": "Mets à neuf une voiture Rare ou mieux.", "stat": "best_rarity", "goal": 2, "reward": {"restores": 2}},
	{"id": "legend", "name": "Licorne", "desc": "Mets à neuf une voiture Légendaire ou mieux.", "stat": "best_rarity", "goal": 4, "reward": {"restores": 5}},
	{"id": "series", "name": "Série complète", "desc": "Atteins le palier 3 d'une collection.", "stat": "best_series", "goal": 3, "reward": {"restores": 5}},
]
