## État d'une partie et actions du joueur. En phase 0 tout est local ;
## en phase 1 ces actions deviendront des appels aux Edge Functions,
## qui recalculeront tout côté serveur.
extends RefCounted

const Economy = preload("res://scripts/economy.gd")
const Catalog = preload("res://scripts/catalog.gd")

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 2
## Phase 0 : pas encore de caméra, on simule un spot toutes les 3 minutes.
const SPOT_COOLDOWN := 180.0
## Voitures offertes pendant le tutoriel (étape → modèle), toutes bloquées et
## mises à neuf gratuitement : deux communes puis une peu commune.
const TUTORIAL_GIFTS := {0: ["clia5", "8a5a3c"], 3: ["yariz", ""], 5: ["gulf_gti", ""]}
const TUTORIAL_DONE := 7

signal changed

var coins := 0.0
var lifetime := 0.0
var cars: Array[Dictionary] = []
var exhibited: Array[int] = []
var slots := Economy.START_SLOTS
var stage := 0
var next_uid := 1
var tutorial_step := 0
var test_mode := false
var spot_cooldown := 0.0
var rush_charge := 0.0
var rush_left := 0.0
var restore_tokens := Economy.RESTORE_FREE_PER_DAY
var ads_today := 0
var token_day := ""
var rng := RandomNumberGenerator.new()


func new_game() -> void:
	coins = 0.0
	lifetime = 0.0
	cars.clear()
	exhibited.clear()
	slots = Economy.START_SLOTS
	stage = 0
	next_uid = 1
	tutorial_step = 0
	test_mode = false
	spot_cooldown = 0.0
	rush_charge = 0.0
	rush_left = 0.0
	restore_tokens = Economy.RESTORE_FREE_PER_DAY
	ads_today = 0
	token_day = ""
	# Le tutoriel offre la première voiture (une épave) dès l'arrivée.
	ensure_gift(0)
	changed.emit()


# --- Voitures -----------------------------------------------------------

func add_car(model_id: String, color := "", restored := false) -> int:
	var model := Catalog.get_car(model_id)
	var levels: Array[int] = []
	levels.resize(Economy.PARTS.size())
	levels.fill(0)
	var car := {
		"uid": next_uid,
		"model": model_id,
		"color": color if color != "" else String(model["color"]),
		"levels": levels,
		"restored": restored,
		"gift": false,
	}
	next_uid += 1
	cars.append(car)
	return int(car["uid"])


func get_car(uid: int) -> Dictionary:
	for c in cars:
		if int(c["uid"]) == uid:
			return c
	return {}


func rarity_of(car: Dictionary) -> int:
	return int(Catalog.get_car(String(car["model"]))["rarity"])


func owns_model(model_id: String) -> bool:
	for c in cars:
		if c["model"] == model_id:
			return true
	return false


## Modèles uniques mis à neuf : eux seuls comptent pour le bonus de collection.
func unique_models() -> int:
	var seen := {}
	for c in cars:
		if c["restored"]:
			seen[c["model"]] = true
	return seen.size()


func is_restored(uid: int) -> bool:
	var car := get_car(uid)
	return not car.is_empty() and bool(car["restored"])


func locked_count() -> int:
	var n := 0
	for c in cars:
		if not c["restored"]:
			n += 1
	return n


func unlocked_parts() -> int:
	return int(Economy.STAGES[stage]["parts"])


func is_exhibited(uid: int) -> bool:
	return exhibited.has(uid)


## Palier visuel le plus haut atteint sur une pièce (jantes, aileron, flammes…).
func visual_tier(car: Dictionary) -> int:
	var best := 0
	for l in car["levels"]:
		best = maxi(best, Economy.milestones_passed(int(l)))
	return best


# --- Revenus ------------------------------------------------------------

func car_income(car: Dictionary) -> float:
	return Economy.car_income(rarity_of(car), car["levels"])


## Revenu par seconde sans le rush : ce que rapporte le garage au repos.
func base_income() -> float:
	var total := 0.0
	for uid in exhibited:
		var car := get_car(uid)
		if not car.is_empty():
			total += car_income(car)
	return total * Economy.collection_multiplier(unique_models())


func income() -> float:
	return base_income() * (Economy.RUSH_MULT if rush_left > 0.0 else 1.0)


func tick(dt: float) -> void:
	var gain := income() * dt
	coins += gain
	lifetime += gain
	if rush_left > 0.0:
		rush_left = maxf(0.0, rush_left - dt)
	else:
		rush_charge = maxf(0.0, rush_charge - Economy.RUSH_DECAY * dt)
	spot_cooldown = maxf(0.0, spot_cooldown - dt)


func tap() -> float:
	var gain := Economy.tap_gain(income())
	coins += gain
	lifetime += gain
	if rush_left <= 0.0:
		rush_charge += 1.0 / Economy.RUSH_TAPS
		if rush_charge >= 1.0:
			rush_charge = 0.0
			rush_left = Economy.RUSH_DURATION
	return gain


# --- Achats -------------------------------------------------------------

func can_afford(cost: float) -> bool:
	return test_mode or coins >= cost


func _spend(cost: float) -> void:
	if not test_mode:
		coins -= cost


func budget() -> float:
	return INF if test_mode else coins


## Devis pour `count` niveaux (count = -1 : le maximum payable, au moins 1 pour l'affichage).
func part_quote(uid: int, part: int, count: int) -> Dictionary:
	var car := get_car(uid)
	var rarity := rarity_of(car)
	var level := int(car["levels"][part])
	var n := count
	if count < 0:
		n = maxi(1, Economy.max_affordable(rarity, level, budget()))
	n = mini(n, Economy.MAX_LEVEL - level)
	return {"count": n, "cost": Economy.cost_for_levels(rarity, level, n)}


func buy_part(uid: int, part: int, count: int) -> bool:
	var car := get_car(uid)
	if car.is_empty() or not car["restored"] or part >= unlocked_parts():
		return false
	var q := part_quote(uid, part, count)
	var n := int(q["count"])
	if n <= 0 or not can_afford(float(q["cost"])):
		return false
	_spend(float(q["cost"]))
	car["levels"][part] = int(car["levels"][part]) + n
	changed.emit()
	return true


func slot_price() -> float:
	return Economy.slot_cost(slots + 1)


func buy_slot() -> bool:
	if slots >= Economy.MAX_SLOTS or not can_afford(slot_price()):
		return false
	_spend(slot_price())
	slots += 1
	_fill_free_slots()
	changed.emit()
	return true


func has_next_stage() -> bool:
	return stage + 1 < Economy.STAGES.size()


func stage_price() -> float:
	return float(Economy.STAGES[stage + 1]["cost"]) if has_next_stage() else INF


func buy_stage() -> bool:
	if not has_next_stage() or not can_afford(stage_price()):
		return false
	_spend(stage_price())
	stage += 1
	changed.emit()
	return true


# --- Garage et album ----------------------------------------------------

func expose(uid: int) -> bool:
	if not is_restored(uid) or exhibited.has(uid) or exhibited.size() >= slots:
		return false
	exhibited.append(uid)
	changed.emit()
	return true


func withdraw(uid: int) -> bool:
	if not exhibited.has(uid):
		return false
	exhibited.erase(uid)
	changed.emit()
	return true


func _fill_free_slots() -> void:
	for c in cars:
		if exhibited.size() >= slots:
			return
		var uid := int(c["uid"])
		if c["restored"] and not exhibited.has(uid):
			exhibited.append(uid)


# --- Spot simulé (phase 0) ----------------------------------------------

func spot_simulated() -> Dictionary:
	var rarity := Economy.roll_rarity(rng.randf())
	var pool := Catalog.by_rarity(rarity)
	var fresh: Array[Dictionary] = []
	for m in pool:
		if not owns_model(String(m["id"])):
			fresh.append(m)
	var is_new := not fresh.is_empty()
	var picked: Dictionary = fresh[rng.randi() % fresh.size()] if is_new else pool[rng.randi() % pool.size()]
	var gain := Economy.spot_gain(rarity, base_income())
	coins += gain
	lifetime += gain
	var uid := -1
	if is_new:
		uid = add_car(String(picked["id"]))
	if not test_mode:
		spot_cooldown = SPOT_COOLDOWN
	changed.emit()
	return {"model": picked["id"], "rarity": rarity, "is_new": is_new, "uid": uid, "gain": gain}


# --- Mise à neuf --------------------------------------------------------

## Nouveau jour (date locale « AAAA-MM-JJ ») : le quota gratuit revient.
## Les mises à neuf gagnées en plus et pas encore utilisées sont gardées.
func daily_refresh(today: String) -> void:
	if today == token_day:
		return
	token_day = today
	restore_tokens = maxi(restore_tokens, Economy.RESTORE_FREE_PER_DAY)
	ads_today = 0
	changed.emit()


func restore_is_free(uid: int) -> bool:
	return bool(get_car(uid).get("gift", false))


func can_restore(uid: int) -> bool:
	var car := get_car(uid)
	if car.is_empty() or car["restored"]:
		return false
	return test_mode or restore_is_free(uid) or restore_tokens > 0


## Met une voiture à neuf : elle devient utilisable et s'expose si une place est libre.
func restore(uid: int) -> bool:
	if not can_restore(uid):
		return false
	var car := get_car(uid)
	if not test_mode and not restore_is_free(uid):
		restore_tokens -= 1
	car["restored"] = true
	if exhibited.size() < slots:
		exhibited.append(uid)
	changed.emit()
	return true


func can_watch_ad() -> bool:
	return ads_today < Economy.RESTORE_ADS_PER_DAY


## Phase 0 : la pub est simulée ; elle rapporte une mise à neuf.
func reward_ad() -> bool:
	if not can_watch_ad():
		return false
	ads_today += 1
	restore_tokens += 1
	changed.emit()
	return true


## Voiture offerte à cette étape du tutoriel (créée au besoin) ; -1 s'il n'y en a pas.
func ensure_gift(step: int) -> int:
	if not TUTORIAL_GIFTS.has(step):
		return -1
	for c in cars:
		if int(c.get("gift_step", -1)) == step:
			return int(c["uid"])
	var spec: Array = TUTORIAL_GIFTS[step]
	var uid := add_car(String(spec[0]), String(spec[1]))
	var car := get_car(uid)
	car["gift"] = true
	car["gift_step"] = step
	return uid


# --- Hors ligne ---------------------------------------------------------

## Revenus accumulés appli fermée, d'après l'heure de la dernière sauvegarde.
func offline_result(last_seen: float, now: float) -> Dictionary:
	var seconds := maxf(0.0, now - last_seen)
	return {"seconds": seconds, "gain": Economy.offline_gain(base_income(), seconds)}


func collect(amount: float) -> void:
	coins += amount
	lifetime += amount
	changed.emit()


# --- Sauvegarde ---------------------------------------------------------

func to_dict(now: float) -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"saved_at": now,
		"coins": coins,
		"lifetime": lifetime,
		"cars": cars,
		"exhibited": exhibited,
		"slots": slots,
		"stage": stage,
		"next_uid": next_uid,
		"tutorial_step": tutorial_step,
		"test_mode": test_mode,
		"spot_cooldown": spot_cooldown,
		"restore_tokens": restore_tokens,
		"ads_today": ads_today,
		"token_day": token_day,
	}


## Charge un dictionnaire de sauvegarde ; renvoie l'heure de sauvegarde, ou -1 si invalide.
func from_dict(d: Dictionary) -> float:
	# Version 1 (avant la mise à neuf) : toutes les voitures étaient utilisables.
	if not int(d.get("version", 0)) in [1, SAVE_VERSION]:
		return -1.0
	coins = float(d.get("coins", 0.0))
	lifetime = float(d.get("lifetime", 0.0))
	cars.clear()
	for raw in d.get("cars", []):
		var levels: Array[int] = []
		for l in raw.get("levels", []):
			levels.append(int(l))
		levels.resize(Economy.PARTS.size())
		cars.append({
			"uid": int(raw["uid"]), "model": String(raw["model"]), "color": String(raw["color"]), "levels": levels,
			"restored": bool(raw.get("restored", true)), "gift": bool(raw.get("gift", false)), "gift_step": int(raw.get("gift_step", -1)),
		})
	exhibited.clear()
	for u in d.get("exhibited", []):
		exhibited.append(int(u))
	slots = int(d.get("slots", Economy.START_SLOTS))
	stage = clampi(int(d.get("stage", 0)), 0, Economy.STAGES.size() - 1)
	next_uid = int(d.get("next_uid", cars.size() + 1))
	tutorial_step = int(d.get("tutorial_step", 0))
	test_mode = bool(d.get("test_mode", false))
	spot_cooldown = float(d.get("spot_cooldown", 0.0))
	restore_tokens = int(d.get("restore_tokens", Economy.RESTORE_FREE_PER_DAY))
	ads_today = int(d.get("ads_today", 0))
	token_day = String(d.get("token_day", ""))
	changed.emit()
	return float(d.get("saved_at", 0.0))


func save_game(now: float) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict(now)))


## Renvoie l'heure de la dernière sauvegarde, ou -1 s'il n'y en a pas.
func load_game() -> float:
	if not FileAccess.file_exists(SAVE_PATH):
		return -1.0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return -1.0
	return from_dict(data)


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## Partie de démonstration pour les captures d'écran.
func setup_demo() -> void:
	new_game()
	cars[0]["restored"] = true
	stage = 2
	slots = 5
	tutorial_step = TUTORIAL_DONE
	cars[0]["levels"] = _levels([52, 41, 30, 26, 18, 12, 4, 0, 0, 0])
	for spec in [["gtx_r35", [27, 25, 14, 9, 3, 0, 0, 0, 0, 0]], ["gulf_gti", [30, 12, 10, 5, 0, 0, 0, 0, 0, 0]], ["huracon", [8, 6, 2, 0, 0, 0, 0, 0, 0, 0]], ["peujo280", [25, 20, 16, 2, 0, 0, 0, 0, 0, 0]]]:
		var uid := add_car(String(spec[0]), "", true)
		get_car(uid)["levels"] = _levels(spec[1])
	add_car("yariz", "", true)
	add_car("m3_e64", "", true)
	add_car("hilox")
	add_car("transiz")
	restore_tokens = 3
	exhibited.assign([cars[2]["uid"], cars[0]["uid"], cars[1]["uid"], cars[3]["uid"], cars[4]["uid"]])
	coins = 1.84e6
	changed.emit()


func _levels(values: Array) -> Array[int]:
	var out: Array[int] = []
	for v in values:
		out.append(int(v))
	return out
