## Écran principal de la phase 0 : garage idle jouable sans photo.
## Interface construite en code, en vrai pixel art : le jeu est dessiné en
## 320 px de large puis agrandi d'un facteur entier (pixels nets).
extends Control

const Economy = preload("res://scripts/economy.gd")
const Catalog = preload("res://scripts/catalog.gd")
const GameState = preload("res://scripts/game_state.gd")
const GarageScene = preload("res://scripts/garage_scene.gd")
const CityMap = preload("res://scripts/city_map.gd")
const RevealView = preload("res://scripts/reveal_view.gd")
const TutorialOverlay = preload("res://scripts/tutorial_overlay.gd")
const PixelUI = preload("res://scripts/pixel_ui.gd")
const CarRenderer = preload("res://scripts/car_renderer.gd")
const Progression = preload("res://scripts/progression.gd")
const Fx = preload("res://scripts/fx.gd")
const SegBar = preload("res://scripts/seg_bar.gd")

const VERSION := "0.9 · phase 0"
const AUTOSAVE_EVERY := 10.0
const CARD_COUNT := 2

var state: GameState
var persist := true
var selected_uid := -1
var _autosave_left := AUTOSAVE_EVERY
var _refresh_left := 0.0
var _tile_targets: Array = []
var _reset_armed := false

var stage_label: Label
var collection_label: Label
var tokens_label: Label
var rep_label: Label
var badges := {}
var popup_tab := 0
var _tree_selected := ""
var _prestige_armed := false
var _day_check_left := 0.0
var coins_label: Label
var income_label: Label
var rush_bar: SegBar
var stage_bar: SegBar
var coin_badge: TextureRect
var _bg_material: ShaderMaterial
var _shown_name := ""
## Captures d'écran : pas d'animation d'entrée.
var _instant := false
var rush_label: Label
var car_name: Label
var car_rarity: Label
var car_rarity_chip: PanelContainer
var car_slot_label: Label
var scene: GarageScene
var city: CityMap
var deliver_button: Button
var showcase: Control
var showcase_title: Label
## Appuis rapprochés sur le bouton : de plus en plus de voitures sortent.
var _combo := 0.0
var _shot_hour := -1.0
var _shot_weather := ""
var cards: Array[Dictionary] = []
var spot_button: Button
var spot_label: Label
var spot_glow: TextureRect
var popup_layer: Control
var popup_kind := ""
var popup_root: Control
var popup_scroll: ScrollContainer
var toast: PanelContainer
var toast_label: Label
var tutorial: TutorialOverlay


func _ready() -> void:
	get_tree().root.size_changed.connect(_fit_window)
	_fit_window()
	theme = PixelUI.make_theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	state = GameState.new()
	state.rng.randomize()
	var shot_path := ""
	var shot_popup := ""
	var demo := false
	var fresh := false
	var shot_stage := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			shot_path = a.get_slice("=", 1)
		elif a.begins_with("--popup="):
			shot_popup = a.get_slice("=", 1)
		elif a == "--demo":
			demo = true
		elif a == "--fresh":
			fresh = true
		elif a.begins_with("--stage="):
			shot_stage = int(a.get_slice("=", 1))
		elif a.begins_with("--hour="):
			_shot_hour = float(a.get_slice("=", 1))
		elif a.begins_with("--weather="):
			_shot_weather = a.get_slice("=", 1)
	if shot_path != "" or demo or fresh:
		persist = false
	_instant = shot_path != ""

	var offline := {}
	if demo:
		state.setup_demo()
		if shot_stage >= 0:
			state.stage = shot_stage
	elif persist:
		var saved_at := state.load_game()
		if saved_at >= 0.0:
			offline = state.offline_result(saved_at, Time.get_unix_time_from_system())
		else:
			state.new_game()
	else:
		state.new_game()

	state.daily_refresh(Time.get_date_string_from_system())
	if demo:
		state.today = {"spots": 2, "levels": 41, "taps": 250, "restores": 1, "rushes": 1, "milestones": 2}
	_build_ui()
	state.changed.connect(_on_state_changed)
	_on_state_changed()
	if float(offline.get("gain", 0.0)) > 0.0:
		# Crédités tout de suite : fermer la fenêtre ne fait rien perdre.
		state.collect(float(offline["gain"]))
		if float(offline["seconds"]) >= 30.0:
			_show_offline(offline)
	if shot_path != "":
		_take_screenshot(shot_path, shot_popup)


## Remplit tout l'écran sans bandes noires : on garde un agrandissement entier
## (pixels nets) et on élargit la zone de jeu (au moins 320 × 568) pour occuper
## l'espace qui reste.
func _fit_window() -> void:
	var root := get_tree().root
	var win := Vector2(root.size)
	if win.x <= 0.0 or win.y <= 0.0:
		return
	var k := maxf(1.0, floorf(minf(win.x / 320.0, win.y / 568.0)))
	var target := Vector2i(int(floor(win.x / k)), int(floor(win.y / k)))
	if root.content_scale_size != target:
		root.content_scale_size = target
	if _bg_material != null:
		_bg_material.set_shader_parameter("px", k)


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
	_day_check_left -= delta
	if _day_check_left <= 0.0:
		_day_check_left = 5.0
		state.daily_refresh(Time.get_date_string_from_system())
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = AUTOSAVE_EVERY
		_save()
	_update_tutorial()
	_combo = maxf(0.0, _combo - delta * 3.0)
	var now := Time.get_ticks_msec() * 0.001
	if coin_badge != null:
		# La pièce flotte doucement ; les pastilles rouges clignotent.
		coin_badge.position.y = roundf(sin(now * 3.0))
	for key: String in badges:
		(badges[key] as ColorRect).color = PixelUI.RED.lerp(Color("ffb0a0"), 0.5 + 0.5 * sin(now * 6.0))
	if spot_glow != null:
		var ready := state.spot_cooldown <= 0.0
		var target := (0.45 + 0.25 * sin(Time.get_ticks_msec() * 0.004)) if ready else 0.0
		spot_glow.modulate.a = lerpf(spot_glow.modulate.a, target, minf(1.0, delta * 6.0))


# --- Construction de l'interface ---------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = PixelUI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# Bandes diagonales qui glissent lentement derrière l'interface.
	bg.material = Fx.material("stripes")
	_bg_material = bg.material
	_fit_window()

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 4)
	add_child(margin)
	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 4)
	margin.add_child(main)

	_build_top_bar(main)
	_build_hero(main)
	_build_income(main)
	_build_cards(main)
	_build_bottom(main)
	if not _instant:
		for i in main.get_child_count():
			var block: Control = main.get_child(i)
			block.modulate.a = 0.0
			var tw := block.create_tween()
			tw.tween_interval(0.08 + i * 0.07)
			tw.tween_property(block, "modulate:a", 1.0, 0.18)

	_build_showcase()
	popup_layer = Control.new()
	popup_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(popup_layer)

	toast = PanelContainer.new()
	toast.add_theme_stylebox_override("panel", PixelUI.frame("icon", 8, 4))
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_label = PixelUI.label("")
	toast.add_child(toast_label)
	toast.modulate.a = 0.0
	add_child(toast)

	tutorial = TutorialOverlay.new()
	tutorial.ok_pressed.connect(_on_tutorial_ok)
	add_child(tutorial)


func _hbox(sep := 4) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func _chip(icon_name: String, color := PixelUI.TEXT) -> Array:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", PixelUI.frame("chip", 3, 2))
	var h := _hbox(2)
	p.add_child(h)
	h.add_child(PixelUI.icon_rect(icon_name))
	var l := PixelUI.label("", "main", color)
	h.add_child(l)
	return [p, l]


func _build_top_bar(parent: Control) -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", PixelUI.frame("panel", 2, 3))
	parent.add_child(bar)
	var h := _hbox(3)
	bar.add_child(h)
	var st := _chip("garage")
	stage_label = st[1]
	h.add_child(st[0])
	# Progression vers l'étape suivante, en jauge dans la pastille.
	stage_bar = PixelUI.bar(PixelUI.GOLD, 7)
	stage_bar.custom_minimum_size = Vector2(22, 7)
	stage_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	(st[1] as Label).get_parent().add_child(stage_bar)
	var col := _chip("album")
	collection_label = col[1]
	h.add_child(col[0])
	var tok := _chip("restore", PixelUI.GOLD)
	tokens_label = tok[1]
	h.add_child(tok[0])
	var rp := _chip("star", PixelUI.GOLD)
	rep_label = rp[1]
	h.add_child(rp[0])
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	var menu := Button.new()
	menu.icon = PixelUI.icon("gear")
	menu.custom_minimum_size = Vector2(26, 24)
	PixelUI.style_button(menu)
	menu.pressed.connect(_show_menu)
	h.add_child(menu)


func _build_hero(parent: Control) -> void:
	# La ville : on y voit les bâtiments du joueur et ses clients qui partent.
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", PixelUI.frame("inset", 1, 1))
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(frame)
	city = CityMap.new()
	city.custom_minimum_size = Vector2(0, 150)
	city.debug_hour = _shot_hour
	city.debug_weather = _shot_weather
	city.building_tapped.connect(func(_i: int) -> void: _show_showcase())
	frame.add_child(city)
	# Le bouton des clients, en bas de la ville.
	var bottom := CenterContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.size_flags_vertical = Control.SIZE_SHRINK_END
	frame.add_child(bottom)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_bottom", 6)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(pad)
	deliver_button = Button.new()
	deliver_button.text = "SERVIR"
	deliver_button.icon = PixelUI.icon("flame")
	deliver_button.custom_minimum_size = Vector2(104, 26)
	PixelUI.style_button(deliver_button, "orange")
	deliver_button.pressed.connect(_on_deliver)
	pad.add_child(deliver_button)


## Fenêtre du bâtiment (on touche le bâtiment sur la map) : la scène du garage
## avec la voiture exposée sur son plateau.
func _build_showcase() -> void:
	showcase = Control.new()
	showcase.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	showcase.visible = false
	add_child(showcase)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.03, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			showcase.hide())
	showcase.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PixelUI.frame("window", 4, 4))
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 4
	panel.offset_right = -4
	panel.offset_top = 40
	panel.offset_bottom = -150
	showcase.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", PixelUI.frame("title", 6, 2))
	vb.add_child(band)
	var header := _hbox(4)
	band.add_child(header)
	showcase_title = PixelUI.ink_label("")
	showcase_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(showcase_title)
	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(24, 22)
	PixelUI.style_button(close)
	close.pressed.connect(showcase.hide)
	header.add_child(close)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", PixelUI.frame("inset", 2, 2))
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(frame)
	scene = GarageScene.new()
	scene.custom_minimum_size = Vector2(0, 150)
	scene.tapped.connect(_on_car_tapped)
	frame.add_child(scene)

	# En bas de la scène : flèches et plaque de la voiture (nom, rareté, place).
	var nav := _hbox(3)
	nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nav.size_flags_vertical = Control.SIZE_SHRINK_END
	frame.add_child(nav)
	var prev := Button.new()
	prev.icon = PixelUI.icon("arrow_l")
	prev.custom_minimum_size = Vector2(26, 0)
	PixelUI.style_button(prev)
	prev.pressed.connect(_cycle_car.bind(-1))
	nav.add_child(prev)
	car_rarity_chip = PanelContainer.new()
	car_rarity_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	car_rarity_chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	car_rarity_chip.add_theme_stylebox_override("panel", PixelUI.frame("plaque", 6, 1))
	nav.add_child(car_rarity_chip)
	var plate := VBoxContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_constant_override("separation", -3)
	car_rarity_chip.add_child(plate)
	car_name = PixelUI.ink_label("")
	car_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	car_name.clip_text = true
	plate.add_child(car_name)
	var sub := _hbox(6)
	sub.alignment = BoxContainer.ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(sub)
	car_rarity = PixelUI.ink_label("", "small")
	sub.add_child(car_rarity)
	car_slot_label = PixelUI.ink_label("", "small")
	sub.add_child(car_slot_label)
	var next := Button.new()
	next.icon = PixelUI.icon("arrow_r")
	next.custom_minimum_size = Vector2(26, 0)
	PixelUI.style_button(next)
	next.pressed.connect(_cycle_car.bind(1))
	nav.add_child(next)


func _show_showcase() -> void:
	_close_popup()
	showcase_title.text = String(Economy.STAGES[state.stage]["name"]).to_upper() + " · TES VOITURES"
	showcase.show()
	showcase.modulate.a = 0.0
	create_tween().tween_property(showcase, "modulate:a", 1.0, 0.12)


func _build_income(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PixelUI.frame("vault", 7, 3))
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	panel.add_child(v)
	var row := _hbox(4)
	v.add_child(row)
	# La pastille est dans un support fixe pour pouvoir flotter sans gêner la mise en page.
	var coin_slot := Control.new()
	coin_slot.custom_minimum_size = Vector2(PixelUI.BADGE_SIZE, PixelUI.BADGE_SIZE)
	coin_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(coin_slot)
	coin_badge = PixelUI.badge("coin", Color("c98a1a"))
	coin_slot.add_child(coin_badge)
	coins_label = PixelUI.label("", "big", PixelUI.GOLD)
	coins_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(coins_label)
	var inc := PanelContainer.new()
	inc.add_theme_stylebox_override("panel", PixelUI.frame("tag", 5, 0))
	inc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(inc)
	income_label = PixelUI.ink_label("")
	inc.add_child(income_label)
	var rush_row := _hbox(4)
	v.add_child(rush_row)
	var flame := PixelUI.icon_rect("flame")
	flame.custom_minimum_size = Vector2(22, 16)
	flame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rush_row.add_child(flame)
	rush_label = PixelUI.label("", "small", PixelUI.MUTED)
	rush_label.custom_minimum_size = Vector2(70, 0)
	rush_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rush_row.add_child(rush_label)
	rush_bar = PixelUI.bar(PixelUI.ORANGE, 9)
	rush_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rush_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rush_row.add_child(rush_bar)


func _build_cards(parent: Control) -> void:
	var head := _hbox(4)
	parent.add_child(head)
	var t := PixelUI.label("AMÉLIORATIONS", "small", PixelUI.ORANGE)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(t)
	var rule := ColorRect.new()
	rule.color = Color("2c2b33")
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(rule)
	var all := Button.new()
	all.text = "Atelier"
	all.icon = PixelUI.icon("wrench")
	PixelUI.style_button(all, "button", PixelUI.ORANGE)
	all.pressed.connect(_show_atelier)
	head.add_child(all)

	for i in CARD_COUNT:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", PixelUI.frame("card", 4, 3))
		parent.add_child(card)
		var h := _hbox(5)
		card.add_child(h)
		var ic := PixelUI.badge("part0")
		h.add_child(ic)
		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_theme_constant_override("separation", 0)
		h.add_child(mid)
		var name_l := PixelUI.label("", "main")
		name_l.clip_text = true
		mid.add_child(name_l)
		var sub := PixelUI.label("", "small", PixelUI.MUTED)
		mid.add_child(sub)
		var prog := PixelUI.bar(PixelUI.ORANGE, 6)
		mid.add_child(prog)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(76, 0)
		btn.icon = PixelUI.icon("coin")
		PixelUI.style_button(btn, "orange", Color.WHITE)
		btn.pressed.connect(_on_tile_pressed.bind(i))
		h.add_child(btn)
		cards.append({"panel": card, "icon": ic, "name": name_l, "sub": sub, "bar": prog, "button": btn})


func _build_bottom(parent: Control) -> void:
	var bar := _hbox(3)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(bar)
	var garage := _nav_button("Garage", "garage")
	garage.pressed.connect(func() -> void: _open_tab("garage", 0))
	bar.add_child(garage)
	var tree := _nav_button("Arbre", "star")
	tree.pressed.connect(func() -> void: _open_tab("tree", 0))
	bar.add_child(tree)
	spot_button = _nav_button("SPOT", "camera", "orange")
	spot_button.size_flags_stretch_ratio = 1.25
	spot_button.custom_minimum_size = Vector2(0, 54)
	# Halo qui respire derrière le bouton quand un spot est prêt.
	spot_glow = TextureRect.new()
	spot_glow.texture = Fx.soft_dot()
	spot_glow.material = Fx.additive()
	spot_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spot_glow.stretch_mode = TextureRect.STRETCH_SCALE
	spot_glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	spot_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spot_glow.show_behind_parent = true
	spot_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	spot_glow.offset_left = -18
	spot_glow.offset_right = 18
	spot_glow.offset_top = -16
	spot_glow.offset_bottom = 10
	spot_glow.modulate = Color(1.0, 0.5, 0.1, 0.0)
	spot_button.add_child(spot_glow)
	spot_button.pressed.connect(_on_spot_pressed)
	bar.add_child(spot_button)
	spot_label = spot_button.get_meta("label")
	var album := _nav_button("Album", "album")
	album.pressed.connect(func() -> void: _open_tab("album", 0))
	bar.add_child(album)
	var miss := _nav_button("Missions", "trophy")
	miss.pressed.connect(func() -> void: _open_tab("missions", 0))
	bar.add_child(miss)
	for b: Button in [garage, tree, album, miss]:
		b.size_flags_vertical = Control.SIZE_SHRINK_END
	badges = {"garage": _badge(garage), "tree": _badge(tree), "album": _badge(album), "missions": _badge(miss)}


## Petite pastille rouge en haut à droite d'un bouton.
func _badge(b: Button) -> ColorRect:
	var dot := ColorRect.new()
	dot.color = PixelUI.RED
	dot.custom_minimum_size = Vector2(5, 5)
	dot.size = Vector2(5, 5)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	dot.position = Vector2(-9, 4)
	dot.visible = false
	b.add_child(dot)
	return dot


func _refresh_badges() -> void:
	if badges.is_empty():
		return
	var can_skill := false
	for sk in Progression.SKILLS:
		if state.can_buy_skill(String(sk["id"])):
			can_skill = true
	badges["tree"].visible = can_skill or state.prestige_gain() >= maxi(1, state.rep_total / 2 + 1)
	badges["missions"].visible = state.claimable_count() > 0
	badges["album"].visible = state.locked_count() > 0 and state.restore_tokens > 0
	badges["garage"].visible = state.has_next_stage() and state.can_afford(state.stage_price())


func _nav_button(text: String, icon_name: String, kind := "button") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_contents = false
	PixelUI.style_button(b, kind)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_bottom = -PixelUI.BUTTON_RELIEF
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -2)
	# Enfoncé, le contenu descend avec la face du bouton.
	b.button_down.connect(func() -> void: v.position.y = 2)
	b.button_up.connect(func() -> void: v.position.y = 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := PixelUI.icon_rect(icon_name)
	v.add_child(ic)
	var l := PixelUI.label(text, "main", Color.WHITE if kind == "orange" else PixelUI.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	b.set_meta("label", l)
	return b


# --- Rafraîchissement ---------------------------------------------------

func _on_state_changed() -> void:
	if state.get_car(selected_uid).is_empty() or not state.is_exhibited(selected_uid):
		selected_uid = state.exhibited[0] if not state.exhibited.is_empty() else -1
	_refresh_car()
	_refresh_live()
	if popup_kind in ["atelier", "garage", "album", "tree", "missions"]:
		_rebuild_popup()


func _refresh_car() -> void:
	if city.stage != state.stage:
		city.set_stage(state.stage)
	var colors: Array[Color] = []
	for uid in state.exhibited:
		colors.append(Color(String(state.get_car(uid)["color"])))
	if not colors.is_empty():
		city.car_colors = colors
	var car := state.get_car(selected_uid)
	if car.is_empty():
		scene.stage = state.stage
		scene.clear_car()
		car_name.text = "GARAGE VIDE"
		car_rarity.text = "Mets une voiture à neuf pour l'exposer"
		car_slot_label.text = ""
		return
	var model := Catalog.get_car(String(car["model"]))
	var rarity := int(model["rarity"])
	scene.configure(Color(String(car["color"])), String(model["body"]), rarity, state.visual_tier(car), state.stage, String(car["model"]))
	car_name.text = Catalog.display_name(String(car["model"])).to_upper()
	car_rarity.text = Economy.RARITY_NAMES[rarity].to_upper()
	car_rarity_chip.add_theme_stylebox_override("panel", PixelUI.frame("plaque", 6, 1, PixelUI.RARITY[rarity].to_html(false)))
	if car_name.text != _shown_name:
		# Nouvelle voiture : le nom s'écrit lettre par lettre, le bandeau s'allume.
		_shown_name = car_name.text
		car_name.visible_ratio = 0.0
		car_rarity_chip.modulate = Color(1.6, 1.6, 1.6)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(car_name, "visible_ratio", 1.0, 0.28)
		tw.tween_property(car_rarity_chip, "modulate", Color.WHITE, 0.3)
	car_slot_label.text = "·  %d / %d" % [state.exhibited.find(selected_uid) + 1, state.exhibited.size()]


func _refresh_live() -> void:
	coins_label.text = Economy.format_number(state.budget())
	income_label.text = "+%s /s" % Economy.format_number(state.income())
	var stage_text := String(Economy.STAGES[state.stage]["name"]).to_upper()
	stage_bar.visible = state.has_next_stage()
	if state.has_next_stage():
		stage_bar.value = clampf(state.coins / state.stage_price(), 0.0, 1.0)
	stage_label.text = stage_text
	collection_label.text = "%d" % state.unique_models()
	tokens_label.text = "MAX" if state.test_mode else "%d" % state.restore_tokens
	rep_label.text = "%d" % state.reputation
	_refresh_badges()
	if state.rush_left > 0.0:
		rush_bar.value = state.rush_left / Economy.RUSH_DURATION
		rush_label.text = "RUSH x2  %ds" % int(ceil(state.rush_left))
		rush_label.add_theme_color_override("font_color", PixelUI.ORANGE)
	else:
		rush_bar.value = state.rush_charge
		rush_label.text = "TAPE POUR LE RUSH"
		rush_label.add_theme_color_override("font_color", PixelUI.MUTED)
	_refresh_cards()
	spot_label.text = "SPOT %s" % _clock(state.spot_cooldown) if state.spot_cooldown > 0.0 else "SPOT"


func _clock(seconds: float) -> String:
	var s := int(ceil(seconds))
	return "%d:%02d" % [s / 60, s % 60]


## Les améliorations les moins chères parmi les voitures exposées.
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


func _refresh_cards() -> void:
	_tile_targets = _cheapest_upgrades(CARD_COUNT)
	for i in cards.size():
		var c: Dictionary = cards[i]
		var btn: Button = c["button"]
		if i >= _tile_targets.size():
			c["panel"].visible = false
			continue
		c["panel"].visible = true
		var t: Array = _tile_targets[i]
		var car := state.get_car(int(t[1]))
		var part := int(t[2])
		var level := int(car["levels"][part])
		var model := Catalog.get_car(String(car["model"]))
		var milestone := Economy.next_milestone(level)
		var prev := 0
		for m in Economy.MILESTONES:
			if m <= level:
				prev = m
		(c["icon"] as TextureRect).texture = PixelUI.badge_texture("part%d" % part)
		c["name"].text = String(Economy.PARTS[part]["name"])
		var hint := "  x2 au prochain !" if milestone == level + 1 else ""
		c["sub"].text = "%s  ·  NIV %d%s" % [String(model["name"]).to_upper(), level, hint]
		c["bar"].value = float(level - prev) / float(maxi(1, milestone - prev)) if milestone > 0 else 1.0
		btn.text = Economy.format_number(float(t[0]))
		btn.disabled = not state.can_afford(float(t[0]))


func _cycle_car(step: int) -> void:
	if state.exhibited.is_empty():
		return
	var i := state.exhibited.find(selected_uid)
	selected_uid = state.exhibited[posmod(i + step, state.exhibited.size())]
	_refresh_car()


# --- Actions du joueur --------------------------------------------------

## Le bouton des clients : chaque appui rapporte comme un toucher de voiture, et
## fait sortir des voitures du bâtiment, de plus en plus si l'on enchaîne.
func _on_deliver() -> void:
	var gain := state.tap()
	_combo = minf(_combo + 1.0, 24.0)
	city.spawn(1 + state.stage + int(_combo / 4.0))
	_float_text("+%s" % Economy.format_number(gain), deliver_button.global_position + Vector2(deliver_button.size.x * 0.5, 0))


func _on_car_tapped(local_pos: Vector2) -> void:
	var gain := state.tap()
	scene.bump()
	_float_text("+%s" % Economy.format_number(gain), scene.global_position + local_pos)


func _on_tile_pressed(i: int) -> void:
	if i >= _tile_targets.size():
		return
	var t: Array = _tile_targets[i]
	if state.buy_part(int(t[1]), int(t[2]), 1):
		if int(t[1]) == selected_uid:
			scene.pulse()
		var card: Control = cards[i]["panel"]
		card.modulate = Color(1.5, 1.4, 1.2)
		create_tween().tween_property(card, "modulate", Color.WHITE, 0.25)
		if state.tutorial_step == 2:
			state.tutorial_step = 3
		var level := int(state.get_car(int(t[1]))["levels"][int(t[2])])
		if level in Economy.MILESTONES:
			_toast("Palier %d : revenus x2 !" % level)


func _on_buy_slot() -> void:
	if state.buy_slot():
		_toast("Nouvelle place au garage")
	else:
		_toast("Il manque %s pièces" % Economy.format_number(state.slot_price() - state.coins))


func _on_spot_pressed() -> void:
	if state.tutorial_step == 6:
		state.tutorial_step = GameState.TUTORIAL_DONE
	if state.spot_cooldown > 0.0:
		_toast("Prochain spot dans %s" % _clock(state.spot_cooldown))
		return
	var result := state.spot_simulated()
	if result["is_new"]:
		_show_restore(int(result["uid"]), {"gain": result["gain"], "title": "Nouveau spot !"})
	else:
		_show_spot(result)


func _float_text(text: String, at: Vector2) -> void:
	var l := PixelUI.label(text, "main", PixelUI.GOLD)
	add_child(l)
	l.global_position = (at - Vector2(10, 20)).floor()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "global_position:y", floorf(at.y - 50.0), 0.7)
	tw.tween_property(l, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(l.queue_free)


func _toast(text: String) -> void:
	toast_label.text = text
	toast.reset_size()
	toast.position = Vector2(floorf((size.x - toast.size.x) * 0.5), floorf(size.y - 120.0))
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
	var animate := kind != popup_kind and not _instant
	_close_popup()
	popup_kind = kind
	popup_root = Control.new()
	popup_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	popup_layer.add_child(popup_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.03, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close_popup())
	popup_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", PixelUI.frame("window", 6, 5))
	if compact:
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		popup_root.add_child(center)
		panel.custom_minimum_size = Vector2(minf(280.0, size.x - 16.0), 0)
		center.add_child(panel)
	else:
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.offset_left = 6
		panel.offset_right = -6
		panel.offset_top = 30
		panel.offset_bottom = -30
		popup_root.add_child(panel)

	if animate:
		# Ouverture : fondu rapide, la fenêtre monte de quelques pixels.
		dim.modulate.a = 0.0
		panel.modulate.a = 0.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(dim, "modulate:a", 1.0, 0.12)
		tw.tween_property(panel, "modulate:a", 1.0, 0.10)
		if not compact:
			panel.offset_top = 38
			panel.offset_bottom = -22
			tw.tween_property(panel, "offset_top", 30.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(panel, "offset_bottom", -30.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", PixelUI.frame("title", 6, 2))
	vb.add_child(band)
	var header := _hbox(4)
	band.add_child(header)
	var t := PixelUI.ink_label(title.to_upper())
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.clip_text = true
	header.add_child(t)
	if animate:
		t.visible_ratio = 0.0
		create_tween().tween_property(t, "visible_ratio", 1.0, 0.22)
		_stagger.call_deferred(vb)
	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(24, 22)
	PixelUI.style_button(close)
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
	content.add_theme_constant_override("separation", 3)
	popup_scroll.add_child(content)
	return content


## Fait apparaître les lignes d'une fenêtre l'une après l'autre.
func _stagger(vb: VBoxContainer) -> void:
	if not is_instance_valid(vb):
		return
	var rows: Array = []
	for c in vb.get_children():
		if c is ScrollContainer and c.get_child_count() > 0:
			rows.append_array(c.get_child(0).get_children())
		elif c.get_index() > 0:
			rows.append(c)
	for i in mini(rows.size(), 12):
		var row: Control = rows[i]
		row.modulate.a = 0.0
		var tw := row.create_tween()
		tw.tween_interval(0.05 + i * 0.035)
		tw.tween_property(row, "modulate:a", 1.0, 0.12)


func _open_tab(kind: String, tab: int) -> void:
	popup_tab = tab
	_prestige_armed = false
	match kind:
		"garage":
			_show_garage()
		"tree":
			_show_tree()
		"album":
			_show_album()
		"missions":
			_show_missions()


## Rangée d'onglets en haut d'une fenêtre.
func _tabs(content: Control, kind: String, names: Array) -> void:
	var row := _hbox(3)
	content.add_child(row)
	for i in names.size():
		var b := Button.new()
		b.text = String(names[i])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		PixelUI.style_button(b, "orange" if i == popup_tab else "button", Color.WHITE if i == popup_tab else PixelUI.MUTED)
		b.pressed.connect(func() -> void: _open_tab(kind, i))
		row.add_child(b)


func _rebuild_popup() -> void:
	var scroll := popup_scroll.scroll_vertical if popup_scroll != null else 0
	match popup_kind:
		"atelier":
			_show_atelier()
		"garage":
			_show_garage()
		"album":
			_show_album()
		"tree":
			_show_tree()
		"missions":
			_show_missions()
	if popup_scroll != null:
		var sc := popup_scroll
		await get_tree().process_frame
		if is_instance_valid(sc):
			sc.scroll_vertical = scroll


func _row(parent: Control, icon_name := "", border := "") -> HBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", PixelUI.frame("card", 4, 3, border))
	parent.add_child(p)
	var h := _hbox(5)
	p.add_child(h)
	if icon_name != "":
		h.add_child(PixelUI.badge(icon_name))
	return h


func _texts(parent: Control, title: String, sub: String, title_color := PixelUI.TEXT) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	parent.add_child(v)
	var t := PixelUI.label(title, "main", title_color)
	t.clip_text = true
	v.add_child(t)
	if sub != "":
		v.add_child(PixelUI.label(sub, "small", PixelUI.MUTED, true))
	return v


func _buy_button(text: String, enabled: bool, action: Callable, with_coin := true) -> Button:
	var b := Button.new()
	b.text = text
	if with_coin:
		b.icon = PixelUI.icon("coin")
	b.custom_minimum_size = Vector2(0, 26)
	b.disabled = not enabled
	PixelUI.style_button(b, "orange", Color.WHITE)
	b.pressed.connect(action)
	return b


func _show_atelier() -> void:
	var car := state.get_car(selected_uid)
	if car.is_empty():
		_toast("Expose d'abord une voiture")
		return
	var model := Catalog.get_car(String(car["model"]))
	var content := _open_popup("atelier", "Atelier · %s" % model["name"])
	content.add_child(PixelUI.label("200 niveaux par pièce. Revenus x2 aux niveaux 25, 50, 100, 150 et 200.", "small", PixelUI.MUTED, true))
	for part in Economy.PARTS.size():
		var level := int(car["levels"][part])
		var info: Dictionary = Economy.PARTS[part]
		var locked := part >= state.unlocked_parts()
		var row := _row(content, "lock" if locked else "part%d" % part)
		if locked:
			var needed := ""
			for s in Economy.STAGES:
				if int(s["parts"]) > part:
					needed = String(s["name"])
					break
			_texts(row, String(info["name"]), "Se débloque avec : %s" % needed, PixelUI.MUTED)
			continue
		var m := Economy.next_milestone(level)
		var x2 := int(pow(2, Economy.milestones_passed(level)))
		var texts := _texts(row, "%s  niv %d" % [info["name"], level], "%s · x%d%s" % [info["stat"], x2, ("  ·  x2 au niv %d" % m) if m > 0 else ""])
		# Jauge vers le prochain palier x2.
		var prev_m := 0
		for ms in Economy.MILESTONES:
			if ms <= level:
				prev_m = ms
		var gauge := PixelUI.bar(PixelUI.ORANGE if m > 0 else PixelUI.GOLD, 7)
		gauge.value = float(level - prev_m) / float(maxi(1, m - prev_m)) if m > 0 else 1.0
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 4)
		texts.add_child(gap)
		texts.add_child(gauge)
		if level >= Economy.MAX_LEVEL:
			row.add_child(PixelUI.label("MAX", "main", PixelUI.GOLD))
			continue
		var uid := selected_uid
		var buttons := VBoxContainer.new()
		buttons.add_theme_constant_override("separation", 2)
		row.add_child(buttons)
		var q1 := state.part_quote(uid, part, 1)
		buttons.add_child(_buy_button(Economy.format_number(float(q1["cost"])), state.can_afford(float(q1["cost"])), func() -> void: state.buy_part(uid, part, 1)))
		var qm := state.part_quote(uid, part, -1)
		var max_ok := state.can_afford(float(qm["cost"])) and int(qm["count"]) > 1
		var mb := _buy_button("MAX +%d" % int(qm["count"]), max_ok, func() -> void: state.buy_part(uid, part, -1), false)
		PixelUI.style_button(mb, "button", PixelUI.ORANGE)
		buttons.add_child(mb)


func _show_garage() -> void:
	var content := _open_popup("garage", "Garage")
	_tabs(content, "garage", ["Étapes", "Mécanos"])
	if popup_tab == 1:
		_fill_staff(content)
		return
	content.add_child(PixelUI.label("Seules les voitures exposées rapportent. Chaque étape agrandit le garage et débloque des pièces.", "small", PixelUI.MUTED, true))
	for i in Economy.STAGES.size():
		var s: Dictionary = Economy.STAGES[i]
		var current := i == state.stage
		var row := _row(content, "garage", "ff7a1a" if current else "")
		var color := PixelUI.GOLD if current else (PixelUI.TEXT if i < state.stage else PixelUI.MUTED)
		_texts(row, String(s["name"]).to_upper(), "%d pièces par voiture" % int(s["parts"]), color)
		if i < state.stage:
			row.add_child(PixelUI.label("FAIT", "small", PixelUI.MONEY))
		elif current:
			row.add_child(PixelUI.label("ACTUEL", "small", PixelUI.GOLD))
		elif i == state.stage + 1:
			row.add_child(_buy_button(Economy.format_number(float(s["cost"])), state.can_afford(float(s["cost"])), func() -> void:
				if state.buy_stage():
					_toast("Bienvenue dans ton %s !" % Economy.STAGES[state.stage]["name"])))
		else:
			row.add_child(PixelUI.label(Economy.format_number(float(s["cost"])), "small", PixelUI.MUTED))
	var slots := _row(content, "album")
	_texts(slots, "PLACES  %d / %d" % [state.slots, Economy.MAX_SLOTS], "Collection : %d modèles, +%d %% de revenus" % [state.unique_models(), state.unique_models()])
	if state.slots < Economy.MAX_SLOTS:
		slots.add_child(_buy_button(Economy.format_number(state.slot_price()), state.can_afford(state.slot_price()), _on_buy_slot))


func _show_album() -> void:
	var content := _open_popup("album", "Album · %d modèles" % state.unique_models())
	_tabs(content, "album", ["Voitures", "Collections"])
	if popup_tab == 1:
		_fill_collections(content)
		return
	var intro := "Expose tes prises pour qu'elles rapportent (%d / %d places)." % [state.exhibited.size(), state.slots]
	if state.locked_count() > 0:
		intro += " %d voiture(s) à mettre à neuf ; il te reste %d mise(s) à neuf aujourd'hui." % [state.locked_count(), state.restore_tokens]
	content.add_child(PixelUI.label(intro, "small", PixelUI.MUTED, true))
	var sorted := state.cars.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["restored"] != b["restored"]:
			return not a["restored"]
		return state.car_income(a) > state.car_income(b))
	var mult := Economy.collection_multiplier(state.unique_models())
	for car in sorted:
		var uid := int(car["uid"])
		var model := Catalog.get_car(String(car["model"]))
		var rarity := int(model["rarity"])
		var locked := not bool(car["restored"])
		var row := _row(content, "", PixelUI.RARITY[rarity].to_html(false))
		var thumb := TextureRect.new()
		thumb.texture = CarRenderer.render(String(model["body"]), Color(String(car["color"])), state.visual_tier(car), 0.8, locked, String(car["model"]))["texture"]
		thumb.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		thumb.custom_minimum_size = Vector2(76, 0)
		row.add_child(thumb)
		if locked:
			_texts(row, "? ? ?", "%s  ·  %s" % [Economy.RARITY_NAMES[rarity].to_upper(), String(CarRenderer.BODY_NAMES.get(String(model["body"]), "")).to_upper()], PixelUI.MUTED)
		else:
			_texts(row, Catalog.display_name(String(car["model"])), "%s  ·  %s /s" % [Economy.RARITY_NAMES[rarity].to_upper(), Economy.format_number(state.car_income(car) * mult)], PixelUI.RARITY[rarity].lightened(0.35))
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 24)
		if locked:
			b.text = "À neuf"
			b.icon = PixelUI.icon("restore")
			PixelUI.style_button(b, "orange", Color.WHITE)
			b.pressed.connect(func() -> void: _show_restore(uid))
		elif state.is_exhibited(uid):
			b.text = "Retirer"
			PixelUI.style_button(b)
			b.pressed.connect(func() -> void: state.withdraw(uid))
		else:
			b.text = "Exposer"
			PixelUI.style_button(b, "orange", Color.WHITE)
			b.disabled = state.exhibited.size() >= state.slots
			b.pressed.connect(func() -> void: state.expose(uid))
		row.add_child(b)
	content.add_child(PixelUI.label("%d modèles sur %d au catalogue de la phase 0." % [state.unique_models(), Catalog.CARS.size()], "small", PixelUI.MUTED, true))


func _fill_staff(content: Control) -> void:
	var slots := state.staff_slots()
	content.add_child(PixelUI.label("Les mécaniciens achètent tout seuls l'amélioration la moins chère, toutes les %d s, sans jamais dépenser plus de %d %% de tes pièces." % [int(GameState.STAFF_INTERVAL / float(state.effects()["staff_speed_mult"])), int(GameState.STAFF_BUDGET * 100)], "small", PixelUI.MUTED, true))
	if slots == 0:
		var row := _row(content, "lock")
		_texts(row, "Aucun mécanicien", "Construis l'Atelier, ou achète « Mécano » dans l'arbre.", PixelUI.MUTED)
		return
	for i in slots:
		var target := state.staff[i]
		var row := _row(content, "wrench", "ff7a1a")
		var who := "Voiture la plus rentable"
		if target >= 0 and not state.get_car(target).is_empty():
			who = Catalog.display_name(String(state.get_car(target)["model"]))
		_texts(row, "Mécano %d" % (i + 1), "Travaille sur : %s" % who)
		var b := Button.new()
		b.text = "Changer"
		PixelUI.style_button(b)
		b.pressed.connect(func() -> void:
			# Tour suivant : auto, puis chaque voiture exposée.
			var options: Array[int] = [-1]
			options.append_array(state.exhibited)
			var k := options.find(state.staff[i])
			state.assign_staff(i, options[(k + 1) % options.size()]))
		row.add_child(b)


func _fill_collections(content: Control) -> void:
	content.add_child(PixelUI.label("Mets à neuf les voitures d'une série pour débloquer des bonus de revenus. Les bonus s'additionnent.", "small", PixelUI.MUTED, true))
	for sr in Progression.SERIES:
		var count := state.series_count(sr)
		var tier := state.series_tier(sr)
		var tiers: Array = sr["tiers"]
		var row := _row(content, "trophy", "ffc23d" if tier >= 3 else "")
		var next := ""
		if tier < tiers.size():
			next = "  ·  prochain palier à %d (+%d %%)" % [int(tiers[tier]), int(Progression.SERIES_BONUS[tier] * 100)]
		_texts(row, String(sr["name"]), "%d modèle(s)  ·  bonus +%d %%%s" % [count, int(Progression.series_bonus(tier) * 100), next], PixelUI.GOLD if tier > 0 else PixelUI.TEXT)
		var pips := _hbox(2)
		for t in 3:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(6, 6)
			pip.color = PixelUI.GOLD if t < tier else Color("3a3942")
			pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pips.add_child(pip)
		row.add_child(pips)


func _show_tree() -> void:
	var content := _open_popup("tree", "Réputation")
	var gain := state.prestige_gain()
	var head := _row(content, "star", "ffc23d")
	_texts(head, "%d point(s) à dépenser" % state.reputation, "Gagnés au total : %d, soit +%d %% de revenus pour toujours (10 %% × racine des points)." % [state.rep_total, int(round(Progression.rep_bonus(state.rep_total) * 100.0))], PixelUI.GOLD)
	# Prestige : repartir à zéro contre des points.
	var pres := Button.new()
	pres.custom_minimum_size = Vector2(0, 30)
	PixelUI.style_button(pres, "orange", Color.WHITE)
	if gain <= 0:
		pres.text = "Prestige : encore %s pièces pour 1 point" % Economy.format_number(maxf(0.0, Progression.earnings_for_points(1) - state.run_earnings))
		pres.disabled = true
	elif _prestige_armed:
		pres.text = "Sûr ? Tu repars au Box. Touche encore"
	else:
		pres.text = "Repartir à zéro : +%d point(s)" % gain
	pres.pressed.connect(func() -> void:
		if not _prestige_armed:
			_prestige_armed = true
			_show_tree()
			return
		_prestige_armed = false
		var got := state.prestige()
		_toast("Prestige ! +%d point(s) de réputation" % got)
		selected_uid = -1
		_on_state_changed())
	content.add_child(pres)
	content.add_child(PixelUI.label("Tu gardes ta collection, tes mises à neuf, ta réputation et l'arbre. Tu perds les pièces, les niveaux, l'étape et les places.", "small", PixelUI.MUTED, true))

	# Détail du nœud choisi.
	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", PixelUI.frame("inset", 6, 4))
	content.add_child(detail)
	var dv := _hbox(4)
	detail.add_child(dv)
	if _tree_selected == "":
		var hint := PixelUI.label("Touche une compétence pour voir ce qu'elle fait.", "small", PixelUI.MUTED, true)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dv.add_child(hint)
	else:
		var sk := Progression.skill(_tree_selected)
		_texts(dv, String(sk["name"]), String(sk["desc"]), PixelUI.GOLD)
		var buy := Button.new()
		if state.has_skill(_tree_selected):
			buy.text = "Acquis"
			buy.disabled = true
			PixelUI.style_button(buy)
		else:
			buy.text = "%d pt" % int(sk["cost"])
			buy.icon = PixelUI.icon("star")
			PixelUI.style_button(buy, "orange", Color.WHITE)
			buy.disabled = not state.can_buy_skill(_tree_selected)
			var id := _tree_selected
			buy.pressed.connect(func() -> void:
				if state.buy_skill(id):
					_toast("%s débloqué !" % Progression.skill(id)["name"]))
		dv.add_child(buy)

	# L'arbre : 4 branches en colonnes, nœuds reliés de haut en bas.
	var cols := _hbox(3)
	content.add_child(cols)
	for br in Progression.BRANCHES:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 0)
		cols.add_child(col)
		var title := PixelUI.label(String(br["name"]).to_upper(), "small", PixelUI.MUTED)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(title)
		var list := Progression.branch_skills(String(br["id"]))
		for i in list.size():
			var sk: Dictionary = list[i]
			var id := String(sk["id"])
			if i > 0:
				var link := ColorRect.new()
				link.custom_minimum_size = Vector2(2, 6)
				link.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
				link.color = PixelUI.GOLD if state.has_skill(id) else Color("3a3942")
				col.add_child(link)
			var node := Button.new()
			node.custom_minimum_size = Vector2(0, 40)
			node.icon = PixelUI.icon(String(br["icon"]))
			node.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			node.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			node.text = "%d" % int(sk["cost"])
			node.add_theme_font_override("font", PixelUI.font("small"))
			node.add_theme_font_size_override("font_size", PixelUI.SIZE_SMALL)
			var owned := state.has_skill(id)
			var buyable := state.can_buy_skill(id)
			var pre := Progression.prerequisite(id)
			var reachable := pre == "" or state.has_skill(pre)
			if owned:
				PixelUI.style_button(node, "button", PixelUI.GOLD)
				for st: String in ["normal", "hover", "pressed"]:
					node.add_theme_stylebox_override(st, PixelUI.frame("owned", 4, 3))
				node.text = "OK"
			elif buyable:
				PixelUI.style_button(node, "orange", Color.WHITE)
			else:
				PixelUI.style_button(node, "button", PixelUI.MUTED if reachable else PixelUI.MUTED.darkened(0.4))
				node.modulate = Color(1, 1, 1, 1.0 if reachable else 0.5)
			if id == _tree_selected:
				node.add_theme_stylebox_override("normal", PixelUI.frame("owned" if owned else ("orange" if buyable else "button"), 4, 3, "ffffff"))
			node.pressed.connect(func() -> void:
				_tree_selected = id
				_show_tree())
			col.add_child(node)


func _show_missions() -> void:
	var content := _open_popup("missions", "Missions")
	_tabs(content, "missions", ["Du jour", "Succès"])
	if popup_tab == 0:
		content.add_child(PixelUI.label("Trois nouvelles missions chaque jour.", "small", PixelUI.MUTED, true))
		for i in state.missions.size():
			var m: Dictionary = state.missions[i]
			var prog := mini(state.mission_progress(i), int(m["goal"]))
			var row := _row(content, "trophy", "ffc23d" if prog >= int(m["goal"]) and not m["claimed"] else "")
			var v := VBoxContainer.new()
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_theme_constant_override("separation", 1)
			row.add_child(v)
			v.add_child(PixelUI.label(String(m["text"]), "main", PixelUI.TEXT))
			v.add_child(PixelUI.label("%d / %d  ·  %s" % [prog, int(m["goal"]), _reward_text(m["reward"])], "small", PixelUI.MUTED))
			var bar := PixelUI.bar(PixelUI.ORANGE, 6)
			bar.value = float(prog) / float(m["goal"])
			v.add_child(bar)
			row.add_child(_claim_button(m["claimed"], prog >= int(m["goal"]), func() -> void: state.claim_mission(i)))
		return
	for a in Progression.ACHIEVEMENTS:
		var done := state.achievement_done(a)
		var claimed := state.achievements_claimed.has(a["id"])
		var row := _row(content, "trophy", "ffc23d" if done and not claimed else "")
		var cur := mini(state.stat(String(a["stat"])), int(a["goal"]))
		_texts(row, String(a["name"]), "%s  ·  %d / %d  ·  %s" % [a["desc"], cur, int(a["goal"]), _reward_text(a["reward"])], PixelUI.GOLD if claimed else PixelUI.TEXT)
		var id := String(a["id"])
		row.add_child(_claim_button(claimed, done, func() -> void: state.claim_achievement(id)))


func _reward_text(reward: Dictionary) -> String:
	if reward.has("restores"):
		return "+%d mise(s) à neuf" % int(reward["restores"])
	return "+%s pièces" % Economy.format_number(state.reward_value(reward))


func _claim_button(claimed: bool, done: bool, action: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(64, 24)
	if claimed:
		b.text = "Reçu"
		b.disabled = true
		PixelUI.style_button(b)
	else:
		b.text = "Réclamer"
		b.disabled = not done
		PixelUI.style_button(b, "orange", Color.WHITE)
		b.pressed.connect(action)
	return b


## Spot d'un modèle déjà dans la collection : seulement le gain immédiat.
func _show_spot(result: Dictionary) -> void:
	var model := Catalog.get_car(String(result["model"]))
	var rarity := int(result["rarity"])
	var vb := _open_popup("spot", "Spot !", true)
	var preview := RevealView.new()
	preview.custom_minimum_size = Vector2(0, 110)
	vb.add_child(preview)
	preview.setup(String(model["body"]), Color(String(model["color"])), rarity, true, String(result["model"]))
	var name_label := PixelUI.label(Catalog.display_name(String(result["model"])).to_upper(), "main", PixelUI.RARITY[rarity].lightened(0.35))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(name_label)
	vb.add_child(_gain_row(float(result["gain"])))
	var w := PixelUI.label("Déjà dans ta collection.", "small", PixelUI.TEXT, true)
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(w)
	var ok := Button.new()
	ok.text = "SUPER !"
	ok.custom_minimum_size = Vector2(0, 28)
	PixelUI.style_button(ok, "orange", Color.WHITE)
	ok.pressed.connect(_close_popup)
	vb.add_child(ok)


func _gain_row(gain: float) -> CenterContainer:
	var row := CenterContainer.new()
	var h := _hbox(3)
	row.add_child(h)
	h.add_child(PixelUI.icon_rect("coin"))
	h.add_child(PixelUI.label("+%s" % Economy.format_number(gain), "main", PixelUI.GOLD))
	return row


## Voiture bloquée : silhouette grise, puis mise à neuf animée.
## info : title, gain (spot), tutorial (voiture offerte pendant le tutoriel).
func _show_restore(uid: int, info := {}) -> void:
	var car := state.get_car(uid)
	if car.is_empty():
		return
	var model := Catalog.get_car(String(car["model"]))
	var rarity := int(model["rarity"])
	var body := String(model["body"])
	var gift := state.restore_is_free(uid)
	var vb := _open_popup("restore", String(info.get("title", "Cadeau !" if gift else "Mise à neuf")), true)
	var reveal := RevealView.new()
	reveal.custom_minimum_size = Vector2(0, 116)
	vb.add_child(reveal)
	reveal.setup(body, Color(String(car["color"])), rarity, false, String(car["model"]))
	var name_label := PixelUI.label("? ? ?", "main", PixelUI.MUTED)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(name_label)
	var chip_row := CenterContainer.new()
	vb.add_child(chip_row)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", PixelUI.frame("chip", 6, 1, PixelUI.RARITY[rarity].to_html(false)))
	chip.add_child(PixelUI.label("%s  ·  %s" % [Economy.RARITY_NAMES[rarity].to_upper(), String(CarRenderer.BODY_NAMES.get(body, body)).to_upper()], "small", PixelUI.RARITY[rarity].lightened(0.35)))
	chip_row.add_child(chip)
	if info.has("gain"):
		vb.add_child(_gain_row(float(info["gain"])))
	var text := PixelUI.label("", "small", PixelUI.TEXT, true)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(text)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 3)
	vb.add_child(actions)

	var finish := func() -> void:
		name_label.text = Catalog.display_name(String(car["model"])).to_upper()
		name_label.add_theme_color_override("font_color", PixelUI.RARITY[rarity].lightened(0.35))
		text.text = "Exposée au garage !" if state.is_exhibited(uid) else "Garage plein : elle t'attend dans l'Album."
		for c in actions.get_children():
			c.queue_free()
		var ok := Button.new()
		ok.text = "SUPER !"
		ok.custom_minimum_size = Vector2(0, 28)
		PixelUI.style_button(ok, "orange", Color.WHITE)
		ok.pressed.connect(_close_popup)
		actions.add_child(ok)
		if state.is_exhibited(uid):
			selected_uid = uid
			_refresh_car()

	var do_restore := func() -> void:
		if not state.restore(uid):
			return
		if gift and state.tutorial_step in GameState.TUTORIAL_GIFTS:
			state.tutorial_step += 1
		for c in actions.get_children():
			c.queue_free()
		text.text = "Mise à neuf en cours…"
		reveal.finished.connect(finish, CONNECT_ONE_SHOT)
		reveal.play()

	if gift:
		text.text = "Mets-la à neuf pour la découvrir : c'est offert."
	elif state.can_restore(uid):
		text.text = "Mets-la à neuf pour la découvrir et la faire rouler. Il t'en reste %s aujourd'hui." % ("autant que tu veux" if state.test_mode else str(state.restore_tokens))
	else:
		text.text = "Plus de mise à neuf aujourd'hui. Elle t'attend dans l'Album, ou gagne-en une :"
	var main_btn := Button.new()
	main_btn.text = "METTRE À NEUF" + ("  ·  GRATUIT" if gift else "")
	main_btn.icon = PixelUI.icon("restore")
	main_btn.custom_minimum_size = Vector2(0, 30)
	PixelUI.style_button(main_btn, "orange", Color.WHITE)
	main_btn.disabled = not state.can_restore(uid)
	main_btn.pressed.connect(do_restore)
	actions.add_child(main_btn)
	if not state.can_restore(uid):
		var ad := Button.new()
		ad.text = "Regarder une pub : +1" if state.can_watch_ad() else "Plus de pub aujourd'hui"
		ad.icon = PixelUI.icon("ad")
		PixelUI.style_button(ad)
		ad.disabled = not state.can_watch_ad()
		ad.pressed.connect(func() -> void:
			if state.reward_ad():
				_toast("Pub simulée : +1 mise à neuf")
				_show_restore(uid, info))
		actions.add_child(ad)
		var carats := Button.new()
		carats.text = "Payer en Carats (bientôt)"
		PixelUI.style_button(carats)
		carats.disabled = true
		actions.add_child(carats)
	if not gift:
		var later := Button.new()
		later.text = "Plus tard"
		PixelUI.style_button(later)
		later.pressed.connect(_close_popup)
		actions.add_child(later)


func _show_offline(offline: Dictionary) -> void:
	var vb := _open_popup("offline", "Bon retour !", true)
	var l := PixelUI.label("Pendant ton absence (%s), ton garage a gagné :" % Economy.format_duration(float(offline["seconds"])), "small", PixelUI.TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	var row := CenterContainer.new()
	vb.add_child(row)
	var h := _hbox(4)
	row.add_child(h)
	var coin := PixelUI.icon_rect("coin")
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(coin)
	h.add_child(PixelUI.label("+%s" % Economy.format_number(float(offline["gain"])), "big", PixelUI.GOLD))
	var note := PixelUI.label("100 % pendant 2 h, puis 50 % jusqu'à 8 h.", "small", PixelUI.MUTED, true)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(note)
	var ok := Button.new()
	ok.text = "RÉCOLTER"
	ok.custom_minimum_size = Vector2(0, 28)
	PixelUI.style_button(ok, "orange", Color.WHITE)
	ok.pressed.connect(_close_popup)
	vb.add_child(ok)


func _show_menu() -> void:
	var vb := _open_popup("menu", "Réglages", true)
	var test := CheckButton.new()
	test.text = "Mode test : argent illimité"
	PixelUI.text_style(test, "main")
	test.button_pressed = state.test_mode
	test.toggled.connect(func(on: bool) -> void:
		state.test_mode = on
		if on:
			state.spot_cooldown = 0.0
		state.changed.emit())
	vb.add_child(test)
	var tuto := Button.new()
	tuto.text = "Relancer le tutoriel"
	PixelUI.style_button(tuto)
	tuto.pressed.connect(func() -> void:
		state.tutorial_step = 0
		_close_popup())
	vb.add_child(tuto)
	var reset := Button.new()
	reset.text = "Recommencer la partie"
	PixelUI.style_button(reset, "button", PixelUI.RED)
	reset.pressed.connect(func() -> void:
		if not _reset_armed:
			_reset_armed = true
			reset.text = "Sûr ? Touche encore"
			return
		state.delete_save()
		state.new_game()
		_close_popup())
	vb.add_child(reset)
	var v := PixelUI.label("Garage Spotter %s" % VERSION, "small", PixelUI.MUTED)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(v)


# --- Tutoriel -----------------------------------------------------------

## Tutoriel : trois voitures offertes (étapes 0, 3, 5), mises à neuf gratuitement,
## entrecoupées des gestes de base (toucher, améliorer, revenus, SPOT).
func _update_tutorial() -> void:
	var step := state.tutorial_step
	if step >= GameState.TUTORIAL_DONE:
		tutorial.hide()
		return
	if step in GameState.TUTORIAL_GIFTS:
		tutorial.hide()
		if popup_kind == "":
			var uid := state.ensure_gift(step)
			var titles := {0: "Ta première voiture", 3: "Un pote te prête sa voiture", 5: "Dernier cadeau"}
			_show_restore(uid, {"title": titles[step]})
		return
	if popup_kind != "":
		tutorial.hide()
		return
	match step:
		1:
			_set_tutorial(deliver_button, "Appuie sur SERVIR : chaque client qui repart avec sa voiture te rapporte des pièces.", false)
			if not _tile_targets.is_empty() and state.can_afford(float(_tile_targets[0][0])):
				state.tutorial_step = 2
		2:
			_set_tutorial(cards[0]["button"], "Achète une amélioration : ta voiture rapportera plus.", false)
		4:
			_set_tutorial(income_label, "Ton garage gagne de l'argent chaque seconde, même jeu fermé.", true)
		6:
			_set_tutorial(spot_button, "Croise une voiture, prends-la en photo avec SPOT, puis mets-la à neuf. Tu as %d mises à neuf par jour." % Economy.RESTORE_FREE_PER_DAY, true)


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
		"showcase":
			_show_showcase()
		"serve":
			for i in 10:
				_on_deliver()
				await get_tree().create_timer(0.12).timeout
			await get_tree().create_timer(1.6).timeout
		"atelier":
			_show_atelier()
		"garage":
			_show_garage()
		"album":
			_show_album()
		"spot":
			_show_restore(state.cars[-1]["uid"], {"title": "Nouveau spot !", "gain": 51234.0})
		"reveal":
			_show_restore(state.cars[-1]["uid"], {"title": "Nouveau spot !", "gain": 51234.0})
			var buttons := popup_root.find_children("*", "Button", true, false)
			for b in buttons:
				if (b as Button).text.begins_with("METTRE"):
					(b as Button).pressed.emit()
			await get_tree().create_timer(float(OS.get_environment("REVEAL_WAIT")) if OS.get_environment("REVEAL_WAIT") != "" else 2.0).timeout
		"offline":
			_show_offline({"seconds": 4380.0, "gain": 98765.0})
		"menu":
			_show_menu()
		"tree":
			_open_tab("tree", 0)
		"staff":
			_open_tab("garage", 1)
		"collections":
			_open_tab("album", 1)
		"missions":
			_open_tab("missions", 0)
		"succes":
			_open_tab("missions", 1)
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	# Capture à la résolution de la fenêtre (lancer avec --resolution 960x1704 pour du x3).
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	get_tree().quit()
