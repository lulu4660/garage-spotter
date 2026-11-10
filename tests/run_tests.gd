## Tests de l'économie et de l'état de partie, sans affichage :
##   godot --headless --path . -s tests/run_tests.gd
extends SceneTree

const Economy = preload("res://scripts/economy.gd")
const GameState = preload("res://scripts/game_state.gd")
const Progression = preload("res://scripts/progression.gd")

var _failures := 0
var _count := 0


func _init() -> void:
	_test_costs()
	_test_affordable()
	_test_income()
	_test_offline()
	_test_rarity()
	_test_format()
	_test_state_flow()
	_test_save_roundtrip()
	_test_prestige_and_skills()
	_test_staff()
	_test_missions_and_achievements()
	_test_collections()
	print("%d vérifications, %d échec(s)" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func check(cond: bool, what: String) -> void:
	_count += 1
	if not cond:
		_failures += 1
		printerr("ÉCHEC : " + what)


func near(a: float, b: float, rel := 1e-9) -> bool:
	return absf(a - b) <= rel * maxf(1.0, absf(b))


func _test_costs() -> void:
	check(near(Economy.part_cost(0, 0), 20.0), "coût niv 0 commune = 20")
	check(near(Economy.part_cost(5, 10), 20.0 * 100.0 * pow(1.1, 10)), "coût suit 20 × B × 1,10^ℓ")
	var total := 0.0
	for l in range(7, 7 + 25):
		total += Economy.part_cost(2, l)
	check(near(Economy.cost_for_levels(2, 7, 25), total), "somme géométrique = somme niveau par niveau")
	check(Economy.cost_for_levels(0, 0, 0) == 0.0, "0 niveau ne coûte rien")
	check(near(Economy.slot_cost(4), 500.0), "4e place = 100 × 5")
	check(near(Economy.slot_cost(3), 100.0), "place n = 100 × 5^(n−3)")


func _test_affordable() -> void:
	check(Economy.max_affordable(0, 0, 19.99) == 0, "pas assez pour 1 niveau")
	check(Economy.max_affordable(0, 0, 20.0) == 1, "pile 1 niveau")
	var budget := Economy.cost_for_levels(1, 3, 17)
	check(Economy.max_affordable(1, 3, budget) == 17, "budget exact de 17 niveaux")
	check(Economy.max_affordable(1, 3, budget * 0.999) == 16, "un peu moins = 16")
	check(Economy.max_affordable(0, 195, 1e300) == 5, "plafonné au niveau 200")
	check(Economy.max_affordable(0, 0, INF) == 200, "budget illimité = tout")


func _test_income() -> void:
	var zero: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	check(near(Economy.car_income(0, zero), 1.0), "commune neuve = 1 pièce/s (revenu de base du GDD)")
	check(near(Economy.car_income(5, zero), 100.0), "mythique neuve = 100 pièces/s")
	check(Economy.milestones_passed(24) == 0 and Economy.milestones_passed(25) == 1 and Economy.milestones_passed(200) == 5, "paliers 25/…/200")
	check(Economy.next_milestone(25) == 50 and Economy.next_milestone(200) == -1, "prochain palier")
	var one: Array[int] = [25, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	check(near(Economy.car_income(0, one), (26.0 * 2.0 + 9.0) / 10.0), "x2 sur la seule pièce au palier")
	# Régression v1 du GDD : les paliers des pièces ne doivent jamais se multiplier entre eux.
	var all_max: Array[int] = [200, 200, 200, 200, 200, 200, 200, 200, 200, 200]
	check(near(Economy.car_income(0, all_max), 201.0 * 32.0), "max théorique additif = 201 × 2⁵ par commune")
	check(near(Economy.collection_multiplier(12), 1.12), "+1 % par modèle unique")


func _test_offline() -> void:
	check(near(Economy.offline_gain(10.0, 3600.0), 36000.0), "1 h hors ligne à 100 %")
	check(near(Economy.offline_gain(10.0, 4.0 * 3600.0), 10.0 * (7200.0 + 0.5 * 7200.0)), "4 h : 2 h pleines + 2 h à 50 %")
	check(near(Economy.offline_gain(10.0, 48.0 * 3600.0), 10.0 * (7200.0 + 0.5 * 21600.0)), "plafond à 8 h")
	check(Economy.offline_gain(10.0, -50.0) == 0.0, "horloge reculée : rien")


func _test_rarity() -> void:
	check(Economy.roll_rarity(0.0) == 0 and Economy.roll_rarity(0.5999) == 0, "60 % communes")
	check(Economy.roll_rarity(0.6) == 1 and Economy.roll_rarity(0.849) == 1, "25 % peu communes")
	check(Economy.roll_rarity(0.9995) == 5, "0,1 % mythiques")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var counts := [0, 0, 0, 0, 0, 0]
	for i in 100000:
		counts[Economy.roll_rarity(rng.randf())] += 1
	check(absf(counts[0] / 100000.0 - 0.60) < 0.01 and absf(counts[2] / 100000.0 - 0.10) < 0.01, "distribution des raretés")
	check(near(Economy.spot_gain(0, 2.0), 2.0 * 20.0 * 60.0), "spot commune = 20 min de revenu")


func _test_format() -> void:
	check(Economy.format_number(999.0) == "999", "999")
	check(Economy.format_number(1.5) == "1,5", "1,5")
	check(Economy.format_number(12345.0) == "12,3 K", "12,3 K, got " + Economy.format_number(12345.0))
	check(Economy.format_number(2.0e6) == "2,00 M", "2,00 M")
	check(Economy.format_number(999999.0) == "1,00 M", "arrondi au suffixe suivant, got " + Economy.format_number(999999.0))
	check(Economy.format_number(1.0e15) == "1,00 aa", "après T : aa")


func _test_state_flow() -> void:
	var s := GameState.new()
	s.new_game()
	check(s.cars.size() == 1 and s.exhibited.is_empty(), "on démarre avec une épave offerte, pas encore exposée")
	var first: int = s.cars[0]["uid"]
	check(not s.is_restored(first) and s.restore_is_free(first), "l'épave est bloquée et sa mise à neuf est offerte")
	check(s.unique_models() == 0 and s.base_income() == 0.0, "une voiture bloquée ne rapporte rien et ne compte pas en collection")
	check(not s.expose(first), "on ne peut pas exposer une voiture bloquée")
	s.coins = 1000.0
	check(not s.buy_part(first, 0, 1), "pas de pièce sur une voiture bloquée")
	var tokens := s.restore_tokens
	check(s.restore(first) and s.restore_tokens == tokens and s.is_exhibited(first), "mise à neuf offerte : quota intact, voiture exposée")
	check(near(s.base_income(), 1.0 * 1.01), "épave commune + 1 modèle = 1,01/s")
	check(s.buy_part(first, 0, 1) and near(s.coins, 980.0), "achat d'un niveau à 20")
	check(not s.buy_part(first, 5, 1), "pièce verrouillée au box")
	s.coins = 0.0
	s.tick(10.0)
	check(near(s.coins, s.base_income() * 10.0), "revenu idle sur 10 s")
	for i in int(Economy.RUSH_TAPS):
		s.tap()
	check(s.rush_left > 0.0 and near(s.income(), s.base_income() * 2.0), "rush x2 après une série de taps")
	s.rush_left = 0.0
	s.coins = 1e9
	check(s.buy_stage() and s.stage == 1 and s.unlocked_parts() == 6, "construire l'atelier")
	check(s.buy_slot() and s.slots == 4, "acheter une 4e place")

	# Spot : la voiture arrive grise ; seul le gain immédiat compte.
	var before := s.cars.size()
	var income_before := s.base_income()
	var r := s.spot_simulated()
	check(float(r["gain"]) > 0.0 and s.spot_cooldown > 0.0, "spot simulé : gain immédiat et délai")
	check(s.cars.size() == before + (1 if r["is_new"] else 0), "un nouveau modèle s'ajoute, un doublon non")
	if r["is_new"]:
		var uid := int(r["uid"])
		check(not s.is_restored(uid) and near(s.base_income(), income_before), "nouvelle voiture bloquée : pas de revenu, pas de bonus de collection")
		check(s.restore(uid) and s.restore_tokens == tokens - 1, "mise à neuf : une du quota en moins")

	# Quota du jour et pubs.
	s.restore_tokens = 0
	var extra := s.add_car("transiz")
	check(not s.restore(extra), "plus de quota : pas de mise à neuf")
	check(s.reward_ad() and s.restore_tokens == 1 and s.restore(extra), "une pub rapporte une mise à neuf")
	for i in Economy.RESTORE_ADS_PER_DAY:
		s.reward_ad()
	check(not s.can_watch_ad(), "pubs plafonnées par jour")
	s.token_day = "2026-01-01"
	s.restore_tokens = 1
	s.daily_refresh("2026-01-02")
	check(s.restore_tokens == Economy.RESTORE_FREE_PER_DAY and s.can_watch_ad(), "nouveau jour : quota et pubs reviennent")
	s.restore_tokens = 8
	s.daily_refresh("2026-01-03")
	check(s.restore_tokens == 8, "les mises à neuf gagnées en plus sont gardées")

	s.test_mode = true
	var c := s.coins
	check(s.buy_part(first, 1, -1) and s.coins == c, "mode test : achats gratuits")


func _test_save_roundtrip() -> void:
	var s := GameState.new()
	s.setup_demo()
	var d := s.to_dict(1000.0)
	var copy := GameState.new()
	var t := copy.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(t == 1000.0, "heure de sauvegarde relue")
	check(copy.cars.size() == s.cars.size() and copy.stage == s.stage and copy.slots == s.slots, "sauvegarde relue à l'identique")
	check(near(copy.base_income(), s.base_income()), "même revenu après rechargement")
	var off := copy.offline_result(1000.0, 1000.0 + 3600.0)
	check(near(float(off["gain"]), copy.base_income() * 3600.0), "gains hors ligne depuis la sauvegarde")
	s.save_game(2000.0)
	var from_disk := GameState.new()
	check(from_disk.load_game() == 2000.0 and from_disk.cars.size() == s.cars.size(), "sauvegarde sur disque relue")
	s.delete_save()
	check(GameState.new().load_game() == -1.0, "sauvegarde effacée")
	var locked_saved := 0
	for car in copy.cars:
		if not car["restored"]:
			locked_saved += 1
	check(locked_saved == 2, "les voitures bloquées restent bloquées après rechargement")
	var old := d.duplicate(true)
	old["version"] = 1
	for car in old["cars"]:
		car.erase("restored")
	var migrated := GameState.new()
	check(migrated.from_dict(old) >= 0.0 and migrated.locked_count() == 0, "ancienne sauvegarde : toutes les voitures restent utilisables")


func _ready_state() -> GameState:
	var s := GameState.new()
	s.new_game()
	s.restore(s.cars[0]["uid"])
	s.tutorial_step = GameState.TUTORIAL_DONE
	s.daily_refresh("2026-11-10")
	return s


func _test_prestige_and_skills() -> void:
	check(Progression.prestige_points(Progression.PRESTIGE_DIVISOR) == 1 and Progression.prestige_points(Progression.PRESTIGE_DIVISOR * 100.0) == 10, "points de prestige en racine carrée")
	check(Progression.prestige_points(0.0) == 0, "pas de point sans gains")
	for sk in Progression.SKILLS:
		var pre := Progression.prerequisite(String(sk["id"]))
		check(pre == "" or Progression.skill(pre)["branch"] == sk["branch"], "prérequis dans la même branche : %s" % sk["id"])
	var s := _ready_state()
	var uid: int = s.cars[0]["uid"]
	s.coins = 1e6
	s.buy_part(uid, 0, 30)
	s.buy_stage()
	check(s.prestige() == 0, "pas de prestige sans assez de gains")
	s.collect(Progression.earnings_for_points(4))
	var models := s.unique_models()
	var tokens := s.restore_tokens
	var gain := s.prestige_gain()
	check(gain >= 4 and s.prestige() == gain, "prestige : points selon les gains de la partie")
	check(s.reputation == gain and s.rep_total == gain and s.prestige_count == 1, "réputation créditée")
	check(s.coins == 0.0 and s.stage == 0 and int(s.cars[0]["levels"][0]) == 0 and s.run_earnings == 0.0, "prestige : pièces, niveaux, étape remis à zéro")
	check(s.unique_models() == models and s.restore_tokens == tokens and s.is_restored(uid), "prestige : collection et mises à neuf gardées")
	check(near(s.income_multiplier(), 1.0 + 0.01 * models + 0.10 * sqrt(float(gain))), "réputation : +10 % × √points, ajouté aux autres bonus")
	check(not s.can_buy_skill("r2"), "prérequis : r2 demande r1")
	var mult := s.income_multiplier()
	s.reputation += 10
	check(s.buy_skill("r1") and near(s.income_multiplier(), mult + 0.10), "Huile de coude : +10 % de revenus (ajouté)")
	check(s.reputation == gain and not s.buy_skill("r1"), "compétence achetée une seule fois")
	var price := s.part_price(0, 5)
	s.reputation += 10
	check(s.buy_skill("a1") and near(s.part_price(0, 5), price * 0.9), "Clé à choc : améliorations -10 %")
	var off := s.offline_result(0.0, 4.0 * 3600.0)
	s.reputation += 20
	s.buy_skill("r2")
	check(float(s.offline_result(0.0, 4.0 * 3600.0)["gain"]) > float(off["gain"]), "Clients fidèles : hors ligne plus long à 100 %")
	s.reputation += 500
	for id in ["g1", "g2", "g3", "g4", "g5"]:
		s.buy_skill(id)
	s.collect(Progression.earnings_for_points(2))
	s.prestige()
	check(s.stage == 1 and s.slots == 4 and near(s.coins, 50000.0), "départ : Atelier, +1 place, 50 K pièces")
	var copy := GameState.new()
	copy.from_dict(JSON.parse_string(JSON.stringify(s.to_dict(5.0))))
	check(copy.has_skill("g5") and copy.rep_total == s.rep_total and copy.prestige_count == 2, "arbre et réputation sauvegardés")


func _test_staff() -> void:
	var s := _ready_state()
	check(s.staff_slots() == 0, "pas de mécano au Box")
	s.coins = 1e6
	s.buy_stage()
	check(s.staff_slots() == 1 and s.staff.size() == 1, "un mécano avec l'Atelier")
	var levels := 0
	for l in s.cars[0]["levels"]:
		levels += int(l)
	s.tick(GameState.STAFF_INTERVAL + 0.1)
	var after := 0
	for l in s.cars[0]["levels"]:
		after += int(l)
	check(after == levels + 1, "le mécano achète une amélioration")
	s.coins = 1.0
	s.tick(GameState.STAFF_INTERVAL + 0.1)
	var after2 := 0
	for l in s.cars[0]["levels"]:
		after2 += int(l)
	check(after2 == after, "le mécano ne dépense pas plus que son budget")


func _test_missions_and_achievements() -> void:
	var s := _ready_state()
	check(s.missions.size() == 3, "trois missions par jour")
	var ids := {}
	for m in s.missions:
		ids[m["id"]] = true
	check(ids.size() == 3, "missions différentes")
	var same := Progression.daily_missions("2026-11-10")
	check(same[0]["id"] == s.missions[0]["id"], "les missions dépendent seulement de la date")
	for i in s.missions.size():
		var m: Dictionary = s.missions[i]
		check(not s.claim_mission(i), "mission pas finie : rien à réclamer")
		s.today[m["stat"]] = int(m["goal"])
		var tok := s.restore_tokens
		var coins := s.coins
		check(s.claim_mission(i) and (s.restore_tokens > tok or s.coins > coins), "mission finie : récompense")
		check(not s.claim_mission(i), "une mission ne se réclame qu'une fois")
	s.daily_refresh("2026-11-11")
	check(s.today.is_empty() and not s.missions[0]["claimed"], "nouveau jour : nouvelles missions")
	check(s.achievement_done(Progression.ACHIEVEMENTS[0]) and s.claim_achievement("first_restore"), "succès « Comme neuve » après la 1re mise à neuf")
	check(not s.claim_achievement("first_restore"), "un succès ne se réclame qu'une fois")
	check(not s.claim_achievement("spots_100"), "succès pas atteint")
	for i in 3:
		s.tap()
	check(s.stat("taps") == 3 and int(s.today.get("taps", 0)) == 3, "les touchers sont comptés")


func _test_collections() -> void:
	var s := _ready_state()
	var jdm: Dictionary = Progression.SERIES[2]
	check(s.series_count(jdm) == 0, "aucune voiture JDM au départ")
	var base := s.income_multiplier()
	for id in ["yariz", "gtx_r35"]:
		var uid := s.add_car(id)
		s.restore(uid)
	check(s.series_count(jdm) == 2 and s.series_tier(jdm) == 1, "2 JDM : palier 1")
	check(near(s.income_multiplier(), 1.0 + 0.01 * s.unique_models() + 0.02), "palier 1 : +2 % de revenus (ajouté)")
	var locked := s.add_car("mx6")
	check(s.series_count(jdm) == 2, "une voiture grise ne compte pas")
	s.restore(locked)
	check(s.series_tier(jdm) == 2 and s.income_multiplier() > base, "3 JDM : palier 2")
