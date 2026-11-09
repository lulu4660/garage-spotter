## Écran principal de la phase 0 : garage idle jouable sans photo.
## Construit l'interface en code (une seule scène), relie l'état de la
## partie à l'affichage, gère les fenêtres, le tutoriel et la sauvegarde.
extends Control

const Economy = preload("res://scripts/economy.gd")
const Catalog = preload("res://scripts/catalog.gd")
const GameState = preload("res://scripts/game_state.gd")
const CarView = preload("res://scripts/car_view.gd")
const TutorialOverlay = preload("res://scripts/tutorial_overlay.gd")
const Palette = preload("res://scripts/palette.gd")

const VERSION := "0.6 · phase 0"
const AUTOSAVE_EVERY := 10.0

var state: GameState
var persist := true
var selected_uid := -1
var _autosave_left := AUTOSAVE_EVERY
var _refresh_left := 0.0
var _tile_targets: Array = []
var _reset_armed := false

var coins_label: Label
var stage_label: Label
var income_label: Label
var rush_bar: ProgressBar
var rush_label: Label
var car_title: Label
var car_view: CarView
var tile_buttons: Array[Button] = []
var collection_box: HBoxContainer
var spot_button: Button
var popup_layer: Control
var popup_kind := ""
var popup_root: Control
var popup_scroll: ScrollContainer
var toast: PanelContainer
var toast_label: Label
var tutorial: TutorialOverlay


func _ready() -> void:
	theme = Palette.make_theme()
	state = GameState.new()
	state.rng.randomize()
	var shot_path := ""
	var shot_popup := ""
	var demo := false
	var fresh := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			shot_path = a.get_slice("=", 1)
		elif a.begins_with("--popup="):
			shot_popup = a.get_slice("=", 1)
		elif a == "--demo":
			demo = true
		elif a == "--fresh":
			fresh = true
	if shot_path != "" or demo or fresh:
		persist = false

	var offline := {}
	if demo:
		state.setup_demo()
	elif persist:
		var saved_at := state.load_game()
		if saved_at >= 0.0:
			offline = state.offline_result(saved_at, Time.get_unix_time_from_system())
		else:
			state.new_game()
	else:
		state.new_game()

	_build_ui()
	state.changed.connect(_on_state_changed)
	_on_state_changed()
	if float(offline.get("gain", 0.0)) > 0.0:
		# Les gains hors ligne sont crédités tout de suite : fermer la fenêtre ne fait rien perdre.
		state.collect(float(offline["gain"]))
		if float(offline["seconds"]) >= 30.0:
			_show_offline(offline)
	if shot_path != "":
		_take_screenshot(shot_path, shot_popup)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_save()


func _save() -> void:
	if persist and state != null:
		state.save_game(Time.get_unix_time_from_system())


func _process(delta: float) -> void:
	state.tick(delta)
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh_left = 0.1
		_refresh_live()
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = AUTOSAVE_EVERY
		_save()
	_update_tutorial()


# --- Construction de l'interface ---------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 6)
	margin.add_child(main)

	# Puces en haut : solde, étape, menu.
	var top := HBoxContainer.new()
	main.add_child(top)
	var c := Palette.chip(Palette.GOLD)
	coins_label = c[1]
	top.add_child(c[0])
	var s := Palette.chip(Palette.MUTED)
	stage_label = s[1]
	top.add_child(s[0])
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var menu := Button.new()
	menu.text = "Menu"
	menu.pressed.connect(_show_menu)
	top.add_child(menu)

	# Gros chiffre des revenus par seconde, et jauge de rush.
	income_label = Label.new()
	income_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	income_label.add_theme_font_size_override("font_size", 26)
	income_label.add_theme_color_override("font_color", Palette.GOLD)
	main.add_child(income_label)
	var rush_row := HBoxContainer.new()
	main.add_child(rush_row)
	rush_label = Label.new()
	rush_label.add_theme_font_size_override("font_size", 11)
	rush_label.add_theme_color_override("font_color", Palette.MUTED)
	rush_label.custom_minimum_size = Vector2(92, 0)
	rush_row.add_child(rush_label)
	rush_bar = ProgressBar.new()
	rush_bar.show_percentage = false
	rush_bar.max_value = 1.0
	rush_bar.custom_minimum_size = Vector2(0, 6)
	rush_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rush_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rush_row.add_child(rush_bar)

	# Scène du garage.
	var scene := PanelContainer.new()
	var scene_sb := Palette.bevel(Palette.EDGE, Palette.EDGE, 2)
	scene_sb.content_margin_left = 0
	scene_sb.content_margin_right = 0
	scene_sb.content_margin_top = 0
	scene_sb.content_margin_bottom = 0
	scene.add_theme_stylebox_override("panel", scene_sb)
	scene.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(scene)
	car_view = CarView.new()
	car_view.custom_minimum_size = Vector2(0, 200)
	car_view.tapped.connect(_on_car_tapped)
	scene.add_child(car_view)
	car_title = Label.new()
	car_title.add_theme_font_size_override("font_size", 12)
	car_title.add_theme_constant_override("outline_size", 4)
	car_title.add_theme_color_override("font_outline_color", Palette.EDGE)
	car_title.size_flags_vertical = Control.SIZE_SHRINK_END
	car_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	car_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(car_title)

	# Trois tuiles d'amélioration rapide + l'atelier complet.
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 4)
	main.add_child(tiles)
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 11)
		b.clip_text = true
		b.pressed.connect(_on_tile_pressed.bind(i))
		tiles.add_child(b)
		tile_buttons.append(b)
	var atelier := Button.new()
	atelier.text = "Atelier"
	atelier.custom_minimum_size = Vector2(62, 58)
	atelier.add_theme_font_size_override("font_size", 11)
	Palette.style_button(atelier, Palette.PANEL_LIGHT, Palette.ORANGE)
	atelier.pressed.connect(_show_atelier)
	tiles.add_child(atelier)

	# Bande de la collection exposée.
	var strip := ScrollContainer.new()
	strip.custom_minimum_size = Vector2(0, 54)
	strip.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(strip)
	collection_box = HBoxContainer.new()
	collection_box.add_theme_constant_override("separation", 4)
	strip.add_child(collection_box)

	# Trois boutons en bas : Garage, SPOT, Album.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 6)
	main.add_child(bottom)
	var garage := Button.new()
	garage.text = "Garage"
	garage.custom_minimum_size = Vector2(0, 52)
	garage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	garage.pressed.connect(_show_garage)
	bottom.add_child(garage)
	spot_button = Button.new()
	spot_button.text = "SPOT"
	spot_button.custom_minimum_size = Vector2(0, 52)
	spot_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spot_button.size_flags_stretch_ratio = 1.4
	spot_button.add_theme_font_size_override("font_size", 20)
	Palette.style_button(spot_button, Palette.ORANGE_DARK, Color.WHITE)
	spot_button.pressed.connect(_on_spot_pressed)
	bottom.add_child(spot_button)
	var album := Button.new()
	album.text = "Album"
	album.custom_minimum_size = Vector2(0, 52)
	album.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	album.pressed.connect(_show_album)
	bottom.add_child(album)

	# Couches du dessus : fenêtres, message bref, tutoriel.
	popup_layer = Control.new()
	popup_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(popup_layer)

	toast = PanelContainer.new()
	toast.add_theme_stylebox_override("panel", Palette.bevel(Color("26221d"), Palette.ORANGE, 2))
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label = Label.new()
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_child(toast_label)
	toast.modulate.a = 0.0
	add_child(toast)

	tutorial = TutorialOverlay.new()
	tutorial.ok_pressed.connect(_on_tutorial_ok)
	add_child(tutorial)


# --- Rafraîchissement ---------------------------------------------------

func _on_state_changed() -> void:
	if state.get_car(selected_uid).is_empty() or not state.is_exhibited(selected_uid):
		selected_uid = state.exhibited[0] if not state.exhibited.is_empty() else -1
	_refresh_car_view()
	_rebuild_collection()
	_refresh_live()
	if popup_kind in ["atelier", "garage", "album"]:
		_rebuild_popup()


func _refresh_car_view() -> void:
	var car := state.get_car(selected_uid)
	if car.is_empty():
		car_title.text = "Garage vide : expose une voiture depuis l'Album"
		car_view.visible = true
		return
	var model := Catalog.get_car(String(car["model"]))
	var rarity := int(model["rarity"])
	car_view.configure(Color(String(car["color"])), String(model["body"]), rarity, state.visual_tier(car), state.stage)
	car_title.text = "%s · %s · %s/s" % [Catalog.display_name(String(car["model"])), Economy.RARITY_NAMES[rarity], Economy.format_number(state.car_income(car))]
	car_title.add_theme_color_override("font_color", Palette.RARITY[rarity].lightened(0.25))


func _refresh_live() -> void:
	coins_label.text = "%s pièces" % Economy.format_number(state.budget())
	var stage_text: String = Economy.STAGES[state.stage]["name"]
	if state.has_next_stage():
		var pct := clampf(state.coins / state.stage_price(), 0.0, 1.0) * 100.0
		stage_text += " · %s %d %%" % [Economy.STAGES[state.stage + 1]["name"], int(pct)]
	stage_label.text = stage_text
	income_label.text = "%s /s" % Economy.format_number(state.income())
	if state.rush_left > 0.0:
		rush_bar.value = state.rush_left / Economy.RUSH_DURATION
		rush_label.text = "RUSH x2 · %d s" % int(ceil(state.rush_left))
		rush_label.add_theme_color_override("font_color", Palette.ORANGE)
	else:
		rush_bar.value = state.rush_charge
		rush_label.text = "Rush (tape vite)"
		rush_label.add_theme_color_override("font_color", Palette.MUTED)
	_refresh_tiles()
	if state.spot_cooldown > 0.0:
		spot_button.text = "SPOT  %s" % _clock(state.spot_cooldown)
	else:
		spot_button.text = "SPOT"
	var car := state.get_car(selected_uid)
	if not car.is_empty():
		car_title.text = "%s · %s · %s/s" % [Catalog.display_name(String(car["model"])), Economy.RARITY_NAMES[state.rarity_of(car)], Economy.format_number(state.car_income(car) * Economy.collection_multiplier(state.unique_models()))]


func _clock(seconds: float) -> String:
	var s := int(ceil(seconds))
	return "%d:%02d" % [s / 60, s % 60]


## Les trois améliorations les moins chères parmi les voitures exposées.
func _cheapest_upgrades(count: int) -> Array:
	var options: Array = []
	for uid in state.exhibited:
		var car := state.get_car(uid)
		var rarity := state.rarity_of(car)
		for part in state.unlocked_parts():
			var level := int(car["levels"][part])
			if level < Economy.MAX_LEVEL:
				options.append([Economy.part_cost(rarity, level), uid, part])
	options.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return options.slice(0, count)


func _refresh_tiles() -> void:
	_tile_targets = _cheapest_upgrades(3)
	for i in tile_buttons.size():
		var b := tile_buttons[i]
		if i >= _tile_targets.size():
			b.text = "-"
			b.disabled = true
			continue
		var t: Array = _tile_targets[i]
		var car := state.get_car(int(t[1]))
		var part := int(t[2])
		var level := int(car["levels"][part])
		var model := Catalog.get_car(String(car["model"]))
		var milestone := Economy.next_milestone(level + 1)
		var hint := " x2!" if milestone == level + 1 else ""
		b.text = "%s%s\n%s · niv %d\n%s" % [Economy.PARTS[part]["name"], hint, model["name"], level, Economy.format_number(float(t[0]))]
		b.disabled = not state.can_afford(float(t[0]))


func _rebuild_collection() -> void:
	for child in collection_box.get_children():
		child.queue_free()
	for i in state.slots:
		var b := Button.new()
		b.custom_minimum_size = Vector2(70, 48)
		b.add_theme_font_size_override("font_size", 10)
		if i < state.exhibited.size():
			var uid := state.exhibited[i]
			var car := state.get_car(uid)
			var model := Catalog.get_car(String(car["model"]))
			var rarity := int(model["rarity"])
			b.text = "%s\n%s" % [model["name"], Economy.RARITY_NAMES[rarity]]
			var sb := Palette.bevel(Palette.PANEL_LIGHT if uid != selected_uid else Palette.PANEL_LIGHT.lightened(0.12), Palette.RARITY[rarity], 3)
			b.add_theme_stylebox_override("normal", sb)
			b.add_theme_stylebox_override("hover", sb)
			b.add_theme_color_override("font_color", Palette.RARITY[rarity].lightened(0.3))
			b.pressed.connect(_select_car.bind(uid))
		else:
			b.text = "Place\nlibre"
			b.add_theme_color_override("font_color", Palette.MUTED)
			b.pressed.connect(_show_album)
		collection_box.add_child(b)
	if state.slots < Economy.MAX_SLOTS:
		var buy := Button.new()
		buy.custom_minimum_size = Vector2(70, 48)
		buy.add_theme_font_size_override("font_size", 10)
		buy.text = "+ Place\n%s" % Economy.format_number(state.slot_price())
		Palette.style_button(buy, Palette.PANEL, Palette.GOLD)
		buy.pressed.connect(_on_buy_slot)
		collection_box.add_child(buy)


func _select_car(uid: int) -> void:
	selected_uid = uid
	_refresh_car_view()
	_rebuild_collection()


# --- Actions du joueur --------------------------------------------------

func _on_car_tapped(local_pos: Vector2) -> void:
	var gain := state.tap()
	car_view.bump()
	_float_text("+%s" % Economy.format_number(gain), car_view.global_position + local_pos)


func _on_tile_pressed(i: int) -> void:
	if i >= _tile_targets.size():
		return
	var t: Array = _tile_targets[i]
	if state.buy_part(int(t[1]), int(t[2]), 1):
		if state.tutorial_step == 1:
			state.tutorial_step = 2
		var level := int(state.get_car(int(t[1]))["levels"][int(t[2])])
		if level in Economy.MILESTONES:
			_toast("Palier %d : revenus x2 sur cette pièce !" % level)


func _on_buy_slot() -> void:
	if state.buy_slot():
		_toast("Nouvelle place au garage")
	else:
		_toast("Il manque %s pièces" % Economy.format_number(state.slot_price() - state.coins))


func _on_spot_pressed() -> void:
	if state.tutorial_step == 3:
		state.tutorial_step = 4
	if state.spot_cooldown > 0.0:
		_toast("Prochain spot simulé dans %s" % _clock(state.spot_cooldown))
		return
	_show_spot(state.spot_simulated())


func _float_text(text: String, at: Vector2) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Palette.GOLD)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Palette.EDGE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.global_position = at - Vector2(10, 20)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "global_position:y", at.y - 60.0, 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(l.queue_free)


func _toast(text: String) -> void:
	toast_label.text = text
	toast.reset_size()
	toast.position = Vector2((size.x - toast.size.x) * 0.5, size.y - 150.0)
	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, 0.12)
	tw.tween_interval(1.8)
	tw.tween_property(toast, "modulate:a", 0.0, 0.3)


# --- Fenêtres -----------------------------------------------------------

func _close_popup() -> void:
	if popup_root != null:
		popup_root.queue_free()
	popup_root = null
	popup_scroll = null
	popup_kind = ""
	_reset_armed = false


## Ouvre une fenêtre ; renvoie le conteneur où mettre son contenu.
func _open_popup(kind: String, title: String, compact := false) -> VBoxContainer:
	_close_popup()
	popup_kind = kind
	popup_root = Control.new()
	popup_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup_layer.add_child(popup_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close_popup())
	popup_root.add_child(dim)

	var panel := PanelContainer.new()
	var sb := Palette.bevel(Palette.PANEL, Palette.EDGE, 3)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	if compact:
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		popup_root.add_child(center)
		panel.custom_minimum_size = Vector2(minf(310.0, size.x - 24.0), 0)
		center.add_child(panel)
	else:
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.offset_left = 10
		panel.offset_right = -10
		panel.offset_top = 40
		panel.offset_bottom = -40
		popup_root.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var header := HBoxContainer.new()
	vb.add_child(header)
	var t := Label.new()
	t.text = title
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("font_size", 18)
	t.add_theme_color_override("font_color", Palette.GOLD)
	header.add_child(t)
	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(34, 30)
	close.pressed.connect(_close_popup)
	header.add_child(close)
	if compact:
		return vb
	popup_scroll = ScrollContainer.new()
	popup_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	popup_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(popup_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	popup_scroll.add_child(content)
	return content


func _rebuild_popup() -> void:
	var scroll := popup_scroll.scroll_vertical if popup_scroll != null else 0
	match popup_kind:
		"atelier":
			_show_atelier()
		"garage":
			_show_garage()
		"album":
			_show_album()
	if popup_scroll != null:
		var sc := popup_scroll
		await get_tree().process_frame
		if is_instance_valid(sc):
			sc.scroll_vertical = scroll


func _label(text: String, font_size := 13, color := Palette.TEXT, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _row_panel(parent: Control) -> HBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", Palette.bevel(Palette.PANEL_LIGHT, Palette.EDGE, 2))
	parent.add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	p.add_child(h)
	return h


func _small_button(text: String, enabled: bool, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(58, 40)
	b.add_theme_font_size_override("font_size", 10)
	b.disabled = not enabled
	b.pressed.connect(action)
	return b


func _show_atelier() -> void:
	var car := state.get_car(selected_uid)
	if car.is_empty():
		_toast("Expose d'abord une voiture")
		return
	var model := Catalog.get_car(String(car["model"]))
	var content := _open_popup("atelier", "Atelier · %s" % model["name"])
	content.add_child(_label("Chaque pièce a 200 niveaux. Aux niveaux 25, 50, 100, 150 et 200, ses revenus doublent.", 11, Palette.MUTED))
	for part in Economy.PARTS.size():
		var level := int(car["levels"][part])
		var info: Dictionary = Economy.PARTS[part]
		var row := _row_panel(content)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		text.add_child(_label("%s · niv %d" % [info["name"], level], 13))
		if part >= state.unlocked_parts():
			var needed := ""
			for s in Economy.STAGES:
				if int(s["parts"]) > part:
					needed = s["name"]
					break
			text.add_child(_label("%s · se débloque avec : %s" % [info["stat"], needed], 10, Palette.MUTED))
			continue
		var m := Economy.next_milestone(level)
		var x2 := int(pow(2, Economy.milestones_passed(level)))
		var sub := "%s · x%d" % [info["stat"], x2]
		if m > 0:
			sub += " · prochain x2 au niv %d" % m
		text.add_child(_label(sub, 10, Palette.MUTED))
		if level >= Economy.MAX_LEVEL:
			row.add_child(_label("MAX", 13, Palette.GOLD, false))
			continue
		var uid := selected_uid
		for count in [1, 10, -1]:
			var q := state.part_quote(uid, part, count)
			var label := ("+%d" % int(q["count"])) if count > 0 else ("Max +%d" % int(q["count"]))
			var ok: bool = state.can_afford(float(q["cost"])) and int(q["count"]) > 0 and (count < 0 or int(q["count"]) == count)
			row.add_child(_small_button("%s\n%s" % [label, Economy.format_number(float(q["cost"]))], ok, func() -> void: state.buy_part(uid, part, count)))


func _show_garage() -> void:
	var content := _open_popup("garage", "Garage")
	content.add_child(_label("Seules les voitures exposées rapportent. Chaque étape agrandit le garage et débloque de nouvelles pièces.", 11, Palette.MUTED))
	for i in Economy.STAGES.size():
		var s: Dictionary = Economy.STAGES[i]
		var row := _row_panel(content)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var color := Palette.GOLD if i == state.stage else (Palette.TEXT if i < state.stage else Palette.MUTED)
		text.add_child(_label(String(s["name"]), 14, color))
		text.add_child(_label("%d pièces par voiture" % int(s["parts"]), 10, Palette.MUTED))
		if i <= state.stage:
			row.add_child(_label("Construit" if i < state.stage else "Actuel", 12, color, false))
		elif i == state.stage + 1:
			row.add_child(_small_button("Construire\n%s" % Economy.format_number(float(s["cost"])), state.can_afford(float(s["cost"])), func() -> void:
				if state.buy_stage():
					_toast("Bienvenue dans ton %s !" % Economy.STAGES[state.stage]["name"])))
		else:
			row.add_child(_label(Economy.format_number(float(s["cost"])), 12, Palette.MUTED, false))
	var slots_row := _row_panel(content)
	var slots_text := VBoxContainer.new()
	slots_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_row.add_child(slots_text)
	slots_text.add_child(_label("Places : %d / %d" % [state.slots, Economy.MAX_SLOTS], 14))
	slots_text.add_child(_label("Collection : %d modèles (+%d %% de revenus)" % [state.unique_models(), state.unique_models()], 10, Palette.MUTED))
	if state.slots < Economy.MAX_SLOTS:
		slots_row.add_child(_small_button("+1 place\n%s" % Economy.format_number(state.slot_price()), state.can_afford(state.slot_price()), _on_buy_slot))


func _show_album() -> void:
	var content := _open_popup("album", "Album · %d modèles" % state.unique_models())
	content.add_child(_label("Toutes tes prises. Expose-les pour qu'elles rapportent (%d / %d places)." % [state.exhibited.size(), state.slots], 11, Palette.MUTED))
	var sorted := state.cars.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return state.car_income(a) > state.car_income(b))
	for car in sorted:
		var uid := int(car["uid"])
		var model := Catalog.get_car(String(car["model"]))
		var rarity := int(model["rarity"])
		var row := _row_panel(content)
		var swatch := ColorRect.new()
		swatch.color = Color(String(car["color"]))
		swatch.custom_minimum_size = Vector2(8, 0)
		row.add_child(swatch)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		text.add_child(_label(Catalog.display_name(String(car["model"])), 13, Palette.RARITY[rarity].lightened(0.3)))
		text.add_child(_label("%s · %s/s" % [Economy.RARITY_NAMES[rarity], Economy.format_number(state.car_income(car) * Economy.collection_multiplier(state.unique_models()))], 10, Palette.MUTED))
		if state.is_exhibited(uid):
			row.add_child(_small_button("Retirer", true, func() -> void: state.withdraw(uid)))
		else:
			row.add_child(_small_button("Exposer", state.exhibited.size() < state.slots, func() -> void: state.expose(uid)))
	var total := Catalog.CARS.size()
	content.add_child(_label("%d modèles sur %d au catalogue de la phase 0." % [state.unique_models(), total], 10, Palette.MUTED))


func _show_spot(result: Dictionary) -> void:
	var model := Catalog.get_car(String(result["model"]))
	var rarity := int(result["rarity"])
	var vb := _open_popup("spot", "Spot !", true)
	var preview := CarView.new()
	preview.show_backdrop = false
	preview.interactive = false
	preview.custom_minimum_size = Vector2(0, 150)
	vb.add_child(preview)
	preview.configure(Color(String(model["color"])), String(model["body"]), rarity, 0, 0)
	var name_label := _label(Catalog.display_name(String(result["model"])), 20, Palette.RARITY[rarity].lightened(0.3))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(name_label)
	var r := _label(Economy.RARITY_NAMES[rarity].to_upper(), 14, Palette.RARITY[rarity])
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(r)
	var what := "Déjà dans ta collection."
	if result["is_new"]:
		what = "Nouveau modèle ! Exposé au garage." if result["placed"] else "Nouveau modèle ! Garage plein : il t'attend dans l'Album."
	var g := _label("+%s pièces\n%s" % [Economy.format_number(float(result["gain"])), what], 13)
	g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(g)
	var note := _label("Phase 0 : spot simulé. La vraie caméra arrive en phase 1.", 10, Palette.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(note)
	var ok := Button.new()
	ok.text = "Super !"
	Palette.style_button(ok, Palette.ORANGE_DARK, Color.WHITE)
	ok.pressed.connect(_close_popup)
	vb.add_child(ok)
	popup_root.modulate.a = 0.0
	create_tween().tween_property(popup_root, "modulate:a", 1.0, 0.25)
	if result["is_new"] and result["placed"]:
		_select_car(int(result["uid"]))


func _show_offline(offline: Dictionary) -> void:
	var vb := _open_popup("offline", "Bon retour !", true)
	var l := _label("Pendant ton absence (%s), ton garage a gagné :" % Economy.format_duration(float(offline["seconds"])), 13)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	var g := _label("+%s pièces" % Economy.format_number(float(offline["gain"])), 24, Palette.GOLD)
	g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(g)
	var note := _label("100 % pendant 2 h, puis 50 % jusqu'à 8 h.", 10, Palette.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(note)
	var ok := Button.new()
	ok.text = "Récolter"
	Palette.style_button(ok, Palette.ORANGE_DARK, Color.WHITE)
	ok.pressed.connect(_close_popup)
	vb.add_child(ok)


func _show_menu() -> void:
	var vb := _open_popup("menu", "Menu", true)
	var test := CheckButton.new()
	test.text = "Mode test : argent illimité"
	test.button_pressed = state.test_mode
	test.toggled.connect(func(on: bool) -> void:
		state.test_mode = on
		if on:
			state.spot_cooldown = 0.0
		state.changed.emit())
	vb.add_child(test)
	var tuto := Button.new()
	tuto.text = "Relancer le tutoriel"
	tuto.pressed.connect(func() -> void:
		state.tutorial_step = 0
		_close_popup())
	vb.add_child(tuto)
	var reset := Button.new()
	reset.text = "Recommencer la partie"
	Palette.style_button(reset, Palette.PANEL_LIGHT, Palette.RED)
	reset.pressed.connect(func() -> void:
		if not _reset_armed:
			_reset_armed = true
			reset.text = "Sûr ? Touche encore pour tout effacer"
			return
		state.delete_save()
		state.new_game()
		_close_popup())
	vb.add_child(reset)
	var v := _label("Garage Spotter %s" % VERSION, 10, Palette.MUTED)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(v)


# --- Tutoriel -----------------------------------------------------------

func _update_tutorial() -> void:
	if popup_kind != "" or state.tutorial_step >= 4:
		tutorial.hide()
		return
	match state.tutorial_step:
		0:
			_set_tutorial(car_view, "Touche ta voiture pour gagner tes premières pièces.", false)
			if not _tile_targets.is_empty() and state.can_afford(float(_tile_targets[0][0])):
				state.tutorial_step = 1
		1:
			_set_tutorial(tile_buttons[0], "Achète une amélioration : ta voiture rapportera plus.", false)
		2:
			_set_tutorial(income_label, "Ton garage gagne de l'argent chaque seconde, même jeu fermé.", true)
		3:
			_set_tutorial(spot_button, "Tu croises une belle voiture ? Photographie-la avec SPOT.", true)


func _set_tutorial(target: Control, text: String, with_ok: bool) -> void:
	if tutorial.visible and tutorial.target == target:
		return
	tutorial.show_step(target, text, with_ok)


func _on_tutorial_ok() -> void:
	state.tutorial_step += 1
	tutorial.hide()


# --- Captures d'écran (outil de revue) ---------------------------------

func _take_screenshot(path: String, popup: String) -> void:
	match popup:
		"atelier":
			_show_atelier()
		"garage":
			_show_garage()
		"album":
			_show_album()
		"spot":
			_show_spot({"model": "huracon", "rarity": 3, "is_new": true, "placed": false, "uid": -1, "gain": 51234.0})
		"offline":
			_show_offline({"seconds": 4380.0, "gain": 98765.0})
		"menu":
			_show_menu()
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
