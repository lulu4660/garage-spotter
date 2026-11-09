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


func _init() -> void:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.2).timeout
	var s = main.state
	check(s.tutorial_step == 0 and main.tutorial.visible, "tuto : étape 1 visible (toucher la voiture)")

	for i in 25:
		main._on_car_tapped(Vector2(100, 100))
	await create_timer(0.3).timeout
	check(s.tutorial_step == 1, "assez de taps pour une amélioration : le doigt passe à la tuile")
	check(not main.tile_buttons[0].disabled, "la première tuile est achetable")

	var lvl_before: int = s.get_car(s.exhibited[0])["levels"].reduce(func(a, b): return a + b, 0)
	main._on_tile_pressed(0)
	var lvl_after: int = s.get_car(s.exhibited[0])["levels"].reduce(func(a, b): return a + b, 0)
	check(lvl_after == lvl_before + 1 and s.tutorial_step == 2, "achat par la tuile, tuto suivant")
	main._on_tutorial_ok()
	check(s.tutorial_step == 3, "tuto : revenus hors ligne expliqués")
	main._on_spot_pressed()
	check(s.tutorial_step == 4 and main.popup_kind == "spot", "SPOT ouvre la carte de spot et finit le tuto")
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
	var inc: float = s.income()
	var c0: float = s.coins
	for i in 360:
		s.tick(10.0)
	check(absf(s.coins - (c0 + inc * 3600.0)) < 1.0, "1 h d'idle = revenu × 3600")

	print("%d échec(s)" % _failures)
	quit(1 if _failures > 0 else 0)
