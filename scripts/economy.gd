## Règles de l'économie (GDD, « Formules v2 » et « Paramètres de départ »).
## Fonctions pures, sans état : ce fichier sera porté tel quel dans les
## Edge Functions Supabase, qui feront foi une fois le serveur en place.
extends RefCounted

const RARITY_NAMES: Array[String] = ["Commune", "Peu commune", "Rare", "Épique", "Légendaire", "Mythique"]
const BASE_INCOME: Array[float] = [1.0, 2.5, 6.0, 15.0, 40.0, 100.0]
const SPOT_CHANCE: Array[float] = [0.60, 0.25, 0.10, 0.04, 0.009, 0.001]
const SPOT_GAIN_MINUTES: Array[float] = [20.0, 30.0, 45.0, 60.0, 120.0, 240.0]

const MILESTONES: Array[int] = [25, 50, 100, 150, 200]
const MAX_LEVEL := 200
const COST_GROWTH := 1.10
const COST_FACTOR := 20.0

## 10 pièces par voiture, débloquées par étape du garage (GDD « Garage et améliorations »).
const PARTS: Array[Dictionary] = [
	{"name": "Admission", "stat": "Puissance"},
	{"name": "Échappement", "stat": "Puissance"},
	{"name": "Pneus", "stat": "Adhérence"},
	{"name": "Reprog moteur", "stat": "Puissance"},
	{"name": "Turbo", "stat": "Puissance"},
	{"name": "Boîte", "stat": "Accélération"},
	{"name": "Allègement", "stat": "Poids"},
	{"name": "Embrayage", "stat": "Départ"},
	{"name": "Aéro", "stat": "Vitesse max"},
	{"name": "Nitro", "stat": "Boost"},
]

const STAGES: Array[Dictionary] = [
	{"name": "Box", "parts": 3, "cost": 0.0},
	{"name": "Atelier", "parts": 6, "cost": 1.0e5},
	{"name": "Showroom", "parts": 8, "cost": 5.0e7},
	{"name": "Hangar", "parts": 10, "cost": 5.0e9},
]

const START_SLOTS := 3
const MAX_SLOTS := 20
const COLLECTION_BONUS := 0.01
const OFFLINE_FULL_SECONDS := 7200.0
const OFFLINE_MAX_SECONDS := 28800.0
const OFFLINE_LATE_RATE := 0.5

## Mise à neuf : chaque voiture spottée arrive grise (bloquée) ; la mettre à
## neuf génère son pixel art et la rend utilisable. Quota quotidien gratuit,
## plus des mises à neuf gagnées en regardant une pub (ou en Carats, plus tard).
const RESTORE_FREE_PER_DAY := 5
const RESTORE_ADS_PER_DAY := 5

const TAP_FRACTION := 0.05
const TAP_MIN := 1.0
const RUSH_TAPS := 20.0
const RUSH_DECAY := 0.12
const RUSH_DURATION := 30.0
const RUSH_MULT := 2.0


## C(ℓ) = 20 × B × 1,10^ℓ : prix pour passer du niveau ℓ au niveau ℓ+1.
static func part_cost(rarity: int, level: int) -> float:
	return COST_FACTOR * BASE_INCOME[rarity] * pow(COST_GROWTH, level)


## Prix de `count` niveaux d'affilée à partir de `level` (somme géométrique).
static func cost_for_levels(rarity: int, level: int, count: int) -> float:
	if count <= 0:
		return 0.0
	return part_cost(rarity, level) * (pow(COST_GROWTH, count) - 1.0) / (COST_GROWTH - 1.0)


## Nombre de niveaux qu'on peut payer avec `budget`, plafonné au niveau max.
static func max_affordable(rarity: int, level: int, budget: float) -> int:
	var remaining := MAX_LEVEL - level
	if remaining <= 0:
		return 0
	if is_inf(budget):
		return remaining
	var c0 := part_cost(rarity, level)
	if budget < c0:
		return 0
	var n := int(floor(log(budget * (COST_GROWTH - 1.0) / c0 + 1.0) / log(COST_GROWTH)))
	n = mini(n, remaining)
	while n > 0 and cost_for_levels(rarity, level, n) > budget * (1.0 + 1e-12):
		n -= 1
	return n


static func milestones_passed(level: int) -> int:
	var m := 0
	for s in MILESTONES:
		if level >= s:
			m += 1
	return m


## Prochain palier ×2, ou -1 si tous sont franchis.
static func next_milestone(level: int) -> int:
	for s in MILESTONES:
		if level < s:
			return s
	return -1


## R_voiture = B × 1/10 × Σ (1 + ℓᵢ) × 2^mᵢ, sur les 10 pièces.
## Les échelles s'additionnent : jamais de produit entre pièces.
static func car_income(rarity: int, levels: Array) -> float:
	var sum := 0.0
	for l in levels:
		var level := int(l)
		sum += (1.0 + level) * pow(2.0, milestones_passed(level))
	return BASE_INCOME[rarity] * 0.1 * sum


static func collection_multiplier(unique_models: int) -> float:
	return 1.0 + COLLECTION_BONUS * unique_models


## Prix de la place n (n = numéro de la place achetée) : 100 × 5^(n−3).
static func slot_cost(n: int) -> float:
	return 100.0 * pow(5.0, n - 3)


## 100 % pendant 2 h, puis 50 % jusqu'à 8 h.
## Les durées se règlent avec l'arbre de compétences (full_s, max_s).
static func offline_gain(income_per_s: float, seconds: float, full_s := OFFLINE_FULL_SECONDS, max_s := OFFLINE_MAX_SECONDS) -> float:
	var s := clampf(seconds, 0.0, max_s)
	var full := minf(s, full_s)
	var late := maxf(0.0, s - full_s)
	return income_per_s * (full + OFFLINE_LATE_RATE * late)


## Tirage de rareté à partir d'un nombre uniforme dans [0, 1).
static func roll_rarity(u: float) -> int:
	var acc := 0.0
	for i in SPOT_CHANCE.size():
		acc += SPOT_CHANCE[i]
		if u < acc:
			return i
	return 0


## Gain immédiat d'un spot : 20 à 240 minutes du revenu actuel.
static func spot_gain(rarity: int, income_per_s: float) -> float:
	return maxf(income_per_s, TAP_MIN) * SPOT_GAIN_MINUTES[rarity] * 60.0


static func tap_gain(income_per_s: float) -> float:
	return maxf(income_per_s * TAP_FRACTION, TAP_MIN)


const _SUFFIXES: Array[String] = ["K", "M", "B", "T"]

## 999 → « 999 », 12 345 → « 12,3 K », 1e18 → « 1,00 ab ».
static func format_number(x: float) -> String:
	if is_inf(x):
		return "illimité"
	if x < 0.0:
		return "-" + format_number(-x)
	if x < 1000.0:
		if x < 10.0 and absf(x - roundf(x)) > 0.05:
			return ("%.1f" % x).replace(".", ",")
		return str(int(floor(x)))
	var e := int(floor(log(x) / log(1000.0)))
	var v := x / pow(1000.0, e)
	if v >= 999.95:
		e += 1
		v /= 1000.0
	var suffix: String
	if e - 1 < _SUFFIXES.size():
		suffix = _SUFFIXES[e - 1]
	else:
		var k := e - 1 - _SUFFIXES.size()
		suffix = char(97 + int(k / 26.0) % 26) + char(97 + k % 26)
	var digits := "%.2f" % v if v < 10.0 else ("%.1f" % v if v < 100.0 else "%d" % int(v))
	return digits.replace(".", ",") + " " + suffix


static func format_duration(seconds: float) -> String:
	var s := int(seconds)
	if s < 60:
		return "%d s" % s
	if s < 3600:
		return "%d min %02d" % [s / 60, s % 60]
	return "%d h %02d" % [s / 3600, (s % 3600) / 60]
