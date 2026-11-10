## Parcours d'un nouveau joueur sur la vraie scène, sans affichage :
##   godot --headless --path . -s tests/test_playthrough.gd -- --fresh
extends SceneTree

var _failures := 0


func check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		printerr("ÉCHEC : " + what)
	else:
		print("ok  " + what)


func _press(main: Control, prefix: String) -> void:
	for b in main.popup_root.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(prefix) and not (b as Button).disabled:
			(b as Button).pressed.emit()
			return
	check(false, "bouton « %s » introuvable" % prefix)


func _init() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.2).timeout
	var s = main.state
	check(s.tutorial_step == 0 and main.popup_kind == "restore", "tuto : la première voiture offerte s'ouvre en mise à neuf")
	var tokens: int = s.restore_tokens
	_press(main, "METTRE")
	await create_timer(1.8).timeout
	check(s.tutorial_step == 1 and s.exhibited.size() == 1 and s.restore_tokens == tokens, "épave mise à neuf gratuitement et exposée")
	main._close_popup()
	await create_timer(0.2).timeout
	check(main.tutorial.visible, "tuto : le doigt montre la voiture")

	for i in 25:
		main._on_car_tapped(Vector2(100, 100))
	await create_timer(0.3).timeout
	check(s.tutorial_step == 2, "assez de taps pour une amélioration : le doigt passe à la carte")
	main._on_tile_pressed(0)
	check(s.tutorial_step == 3, "achat par la carte, tuto suivant")
	await create_timer(0.2).timeout
	check(main.popup_kind == "restore", "2e voiture offerte")
	_press(main, "METTRE")
	await create_timer(1.8).timeout
	main._close_popup()
	check(s.tutorial_step == 4, "2e voiture mise à neuf")
	main._on_tutorial_ok()
	await create_timer(0.2).timeout
	check(s.tutorial_step == 5 and main.popup_kind == "restore", "3e voiture offerte (peu commune)")
	_press(main, "METTRE")
	await create_timer(1.8).timeout
	main._close_popup()
	check(s.tutorial_step == 6 and s.exhibited.size() == 3 and s.restore_tokens == tokens, "3 voitures exposées, quota intact")
	main._on_spot_pressed()
	check(s.tutorial_step == 7, "SPOT termine le tuto")
	check(main.popup_kind in ["restore", "spot"], "le spot ouvre la mise à neuf (ou le doublon)")
	main._close_popup()
	await process_frame
	main._on_spot_pressed()
	check(main.popup_kind == "", "second spot bloqué par le délai de la phase 0")

	s.coins = 5.0e4
	main._show_atelier()
	check(main.popup_kind == "atelier", "l'atelier s'ouvre")
	var uid: int = main.selected_uid
	check(s.buy_part(uid, 0, -1), "achat Max dans l'atelier")
	await process_frame
	check(main.popup_kind == "atelier", "l'atelier reste ouvert après achat")
	main._close_popup()

	s.coins = 1.0e6
	check(s.buy_stage() and s.stage == 1, "construction de l'atelier (étape 2)")
	var slots_before: int = s.slots
	main._on_buy_slot()
	check(s.slots == slots_before + 1, "achat d'une place depuis la bande")
	main._show_album()
	check(main.popup_kind == "album", "l'album s'ouvre")
	main._close_popup()

	# Une heure de jeu passif à revenu constant (rush terminé).
	s.rush_left = 0.0
	s.rush_charge = 0.0
	s.staff.clear()  # les mécaniciens achèteraient pendant l'heure
	var inc: float = s.income()
	var c0: float = s.coins
	for i in 360:
		s.tick(10.0)
	check(absf(s.coins - (c0 + inc * 3600.0)) < 1.0, "1 h d'idle = revenu × 3600")

	print("%d échec(s)" % _failures)
	quit(1 if _failures > 0 else 0)
