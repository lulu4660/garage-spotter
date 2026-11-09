## Tests de l'économie et de l'état de partie, sans affichage :
##   godot --headless --path . -s tests/run_tests.gd
extends SceneTree

const Economy = preload("res://scripts/economy.gd")
const GameState = preload("res://scripts/game_state.gd")

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
	check(s.cars.size() == 1 and s.exhibited.size() == 1, "on démarre avec une épave exposée")
	check(near(s.base_income(), 1.0 * 1.01), "épave commune + 1 modèle = 1,01/s")
	check(not s.buy_part(s.exhibited[0], 0, 1), "pas d'achat sans pièces")
	s.coins = 1000.0
	check(s.buy_part(s.exhibited[0], 0, 1) and near(s.coins, 980.0), "achat d'un niveau à 20")
	check(not s.buy_part(s.exhibited[0], 5, 1), "pièce verrouillée au box")
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
	var before := s.cars.size()
	var r := s.spot_simulated()
	check(float(r["gain"]) > 0.0 and s.spot_cooldown > 0.0, "spot simulé : gain immédiat et délai")
	check(s.cars.size() == before + (1 if r["is_new"] else 0), "un nouveau modèle s'ajoute, un doublon non")
	s.test_mode = true
	var c := s.coins
	check(s.buy_part(s.exhibited[0], 1, -1) and s.coins == c, "mode test : achats gratuits")


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
