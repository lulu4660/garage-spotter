## Scène du garage façon « HD-2D » : décor et voiture en pixels nets, lumière
## calculée à la résolution de l'écran.
##
## Couches, de l'arrière vers l'avant :
## 1. _draw : murs et accessoires de l'étape, ville en couches derrière les
##    ouvertures (ciel à l'heure réelle), sol mouillé, plateau ;
## 2. reflet de la voiture (flou) puis la voiture (liseré de lumière, reflet qui balaie) ;
## 3. brouillard, fumée et pluie (fondu normal) ;
## 4. lumières additives : halos des néons et des phares, rayons, poussières, reflets au sol ;
## 5. post-traitement : halo lumineux, étalonnage, vignettage.
extends Control

const CarRenderer = preload("res://scripts/car_renderer.gd")
const PixelUI = preload("res://scripts/pixel_ui.gd")
const Fx = preload("res://scripts/fx.gd")
const CITY_BACK = preload("res://assets/env/city_back.png")
const CITY_MIDDLE = preload("res://assets/env/city_middle.png")
const CITY_FRONT = preload("res://assets/env/city_front.png")

const NEON := Color(1.0, 0.52, 0.18)
const LAMP := Color(1.0, 0.92, 0.72)
const SIGN := Color(1.0, 0.24, 0.40)
const STAGE_SIGNS: Array[String] = ["BOX", "ATELIER", "SHOWROOM", "HANGAR"]

signal tapped(local_pos: Vector2)

var body_color := Color("8a5a3c")
var body_type := "citadine"
var model_id := ""
var rarity := 0
var tier := 0
var stage := 0
var show_backdrop := true
var interactive := true
## false : pas de voiture sur le plateau (garage vide).
var has_car := true

var _car := {}
var _car_scale := 0.0
var _car_pos := Vector2.ZERO
var _floor_y := 0.0
var _plat_c := Vector2.ZERO
var _plat_r := Vector2.ZERO
var _openings: Array[Rect2] = []
var _neons: Array[Rect2] = []

var _car_rect: TextureRect
var _reflect: TextureRect
var _under: Control
var _mirror: ColorRect
var _plat: Control
var _fog: Control
var _lights: Control
var _post: ColorRect

var _shake := 0.0
var _pulse := 0.0
var _flash := 0.0
var _shown_model := ""
var _flame := 0.0
var _time := 0.0
var _puffs: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _dust: Array[Dictionary] = []
var _rain: Array[Dictionary] = []
var _fog_blobs: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

# Éclairage dynamique (PointLight2D) : n'éclaire que la voiture et le décor
# (masque 2), jamais l'interface.
const LIGHT_MASK := 2
var _neon_lights: Array[PointLight2D] = []
var _city_light: PointLight2D
var _plat_light: PointLight2D
var _sweep_light: PointLight2D
var _beacon_light: PointLight2D
var _key_light: PointLight2D


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	_rng.seed = 7

	_under = Control.new()
	_under.material = Fx.additive()
	_under.draw.connect(_draw_under)
	_mirror = ColorRect.new()
	_mirror.material = Fx.material("mirror")
	# Le plateau a sa propre couche, au-dessus du reflet du sol, pour rester net.
	_plat = Control.new()
	_plat.draw.connect(_draw_platform)
	_reflect = TextureRect.new()
	_reflect.flip_v = true
	_reflect.material = Fx.material("reflection")
	_car_rect = TextureRect.new()
	_car_rect.material = Fx.material("car")
	_fog = Control.new()
	_fog.draw.connect(_draw_fog)
	_lights = Control.new()
	_lights.material = Fx.additive()
	_lights.draw.connect(_draw_lights)
	for c: Control in [_under, _mirror, _plat, _reflect, _car_rect, _fog, _lights]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(c)
	_mirror.visible = show_backdrop
	for c: Control in [_under, _mirror, _plat, _fog, _lights]:
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if show_backdrop:
		# Nouvelle capture de l'écran : le reflet du sol en a fait une avant la
		# voiture, le post-traitement doit voir l'image complète.
		var copy := BackBufferCopy.new()
		copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		add_child(copy)
		_post = ColorRect.new()
		_post.material = Fx.material("post")
		_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_post)

	light_mask = LIGHT_MASK
	_car_rect.light_mask = LIGHT_MASK
	# Un peu d'ombre ambiante sur la voiture : ce sont les lumières qui la révèlent.
	_car_rect.self_modulate = Color(0.86, 0.84, 0.88)
	for i in 2:
		_neon_lights.append(_make_light(NEON, 0.95, 60.0))
	_city_light = _make_light(Color(0.95, 0.4, 0.55), 0.55, 30.0)
	_plat_light = _make_light(Color.WHITE, 0.22, 24.0)
	_sweep_light = _make_light(Color(1.0, 0.93, 0.8), 0.0, 22.0)
	_beacon_light = _make_light(Color(1.0, 0.55, 0.1), 0.0, 25.0)
	_key_light = _make_light(Color(1.0, 0.95, 0.86), 0.42, 70.0)
	for i in 40:
		_dust.append({"p": Vector2(_rng.randf(), _rng.randf()), "v": Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-4, -1)), "s": _rng.randf_range(0.8, 2.2), "ph": _rng.randf() * TAU})
	for i in 70:
		_rain.append({"p": Vector2(_rng.randf(), _rng.randf()), "sp": _rng.randf_range(0.8, 1.3), "l": _rng.randf_range(5, 11)})
	for i in 7:
		_fog_blobs.append({"x": _rng.randf(), "y": _rng.randf_range(-0.15, 0.25), "s": _rng.randf_range(0.5, 0.9), "v": _rng.randf_range(0.004, 0.012) * (1 if i % 2 == 0 else -1)})
	resized.connect(_layout)
	_layout()


func _make_light(color: Color, energy: float, height: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = Fx.soft_dot()
	l.color = color
	l.energy = energy
	l.height = height
	l.range_item_cull_mask = LIGHT_MASK
	l.blend_mode = Light2D.BLEND_MODE_ADD
	add_child(l)
	return l


func configure(color: Color, body: String, rarity_index: int, tier_index: int, stage_index: int, model := "") -> void:
	body_color = color
	body_type = body
	model_id = model
	rarity = rarity_index
	tier = tier_index
	stage = stage_index
	has_car = true
	_car_scale = 0.0
	if model != _shown_model:
		# Nouvelle voiture sur le plateau : éclair bref et onde de lumière.
		_shown_model = model
		_flash = 0.25
		_pulse = 0.6
	_layout()


func clear_car() -> void:
	has_car = false
	_layout()


## Onde de lumière sur le plateau (amélioration achetée, nouvelle voiture).
func pulse() -> void:
	_pulse = 0.6


## Réaction au toucher : la voiture tremble, fume, étincelle, et crache parfois une flamme.
func bump() -> void:
	_shake = 0.16
	for i in 3:
		_puffs.append({"p": Vector2.ZERO, "v": Vector2(14.0 + _rng.randf() * 10.0, -6.0 - _rng.randf() * 8.0), "life": 0.9 + _rng.randf() * 0.4})
	for i in 7:
		_sparks.append({"p": Vector2(_rng.randf_range(-0.25, 0.25), _rng.randf_range(-0.15, 0.1)), "v": Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-90, -40)), "life": 0.55})
	if tier >= 3 or _rng.randf() < 0.2:
		_flame = 0.28


func _gui_input(event: InputEvent) -> void:
	if interactive and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit(event.position)
		accept_event()


# --- Mise en page -------------------------------------------------------

func _layout() -> void:
	if _car_rect == null or size.x <= 0.0:
		return
	var w := size.x
	var h := size.y
	_floor_y = floorf(h * (0.60 if show_backdrop else 0.62))
	_plat_c = Vector2(floorf(w * 0.5), _floor_y + floorf((h - _floor_y) * (0.30 if show_backdrop else 0.36)))
	_plat_r = Vector2(floorf(w * (0.42 if show_backdrop else 0.44)), floorf(maxf(10.0, (h - _floor_y) * 0.26)))
	_compute_room(w)
	_car_rect.visible = has_car
	_reflect.visible = has_car
	if has_car:
		var s := CarRenderer.fit_scale(body_type, Vector2(w * (0.70 if show_backdrop else 0.84), h * 0.56))
		if s != _car_scale or _car.is_empty():
			_car_scale = s
			_car = CarRenderer.render(body_type, body_color, tier, s, false, model_id)
		var tex: Texture2D = _car["texture"]
		var tsize := Vector2(tex.get_size())
		_car_pos = (_plat_c - Vector2(_car["anchor"])).floor()
		var ct := CanvasTexture.new()
		ct.diffuse_texture = tex
		if _car["normal"] != null:
			ct.normal_texture = _car["normal"]
		ct.specular_texture = _car["specular"]
		ct.specular_color = Color(1.0, 0.95, 0.9)
		ct.specular_shininess = 0.75
		ct.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_car_rect.texture = ct
		_car_rect.size = tsize
		_car_rect.position = _car_pos
		_reflect.texture = tex
		_reflect.size = tsize
		_reflect.position = Vector2(_car_pos.x, _car_pos.y + float(_car["ground"]) * 2.0 - tsize.y).floor()
	_place_lights()
	queue_redraw()


## Position et taille des lumières selon la mise en page.
func _place_lights() -> void:
	var w := size.x
	for i in _neon_lights.size():
		var l := _neon_lights[i]
		l.visible = show_backdrop and i < _neons.size()
		if l.visible:
			l.position = _neons[i].get_center() + Vector2(0, 6)
			l.texture_scale = w * 0.9 / 64.0
	_city_light.visible = show_backdrop and not _openings.is_empty()
	if _city_light.visible:
		var o := _openings[0]
		_city_light.position = Vector2(o.get_center().x, o.end.y)
		_city_light.texture_scale = o.size.x * 1.4 / 64.0
	_plat_light.color = PixelUI.RARITY[rarity]
	_plat_light.position = _plat_c + Vector2(_plat_r.x * 0.3, -_plat_r.y * 0.5)
	_plat_light.texture_scale = _plat_r.x * 2.4 / 64.0
	_key_light.visible = show_backdrop
	_key_light.position = _plat_c + Vector2(-_plat_r.x * 0.25, -_plat_r.y * 3.4)
	_key_light.texture_scale = w * 1.1 / 64.0
	_sweep_light.texture_scale = w * 0.5 / 64.0
	_beacon_light.texture_scale = w * 0.7 / 64.0


## Lumières qui bougent : phares d'une voiture qui passe dans la rue (toutes les
## 14 s) et gyrophare orange d'une dépanneuse de temps en temps.
func _animate_lights() -> void:
	if not show_backdrop or _openings.is_empty():
		_sweep_light.energy = 0.0
		_beacon_light.energy = 0.0
		return
	var o := _openings[0]
	var w := size.x
	var t := fmod(_time, 14.0)
	if t < 3.0:
		var k := t / 3.0
		_sweep_light.position = Vector2(lerpf(-w * 0.3, w * 1.3, k), o.end.y - 4.0)
		_sweep_light.energy = sin(k * PI) * 1.3
	else:
		_sweep_light.energy = 0.0
	var b := fmod(_time + 9.0, 37.0)
	if b < 5.0:
		_beacon_light.position = Vector2(o.end.x - 10.0, o.end.y - 6.0)
		_beacon_light.energy = maxf(0.0, sin(_time * 9.0)) * 1.1 * sin(b / 5.0 * PI)
	else:
		_beacon_light.energy = 0.0
	for i in _neon_lights.size():
		if i < _neons.size():
			var n := _neons[i]
			var flick := 0.45 if fmod(_time + n.position.x * 0.01, 5.3) < 0.06 else 1.0
			_neon_lights[i].energy = 0.95 * flick


## Ouvertures sur la rue (pluie) et néons, selon l'étape.
func _compute_room(w: float) -> void:
	_openings.clear()
	_neons.clear()
	var fy := _floor_y
	match stage:
		0:
			_openings.append(Rect2(8, 18, 34, 20))
		1:
			_openings.append(Rect2(floorf(w * 0.14), floorf(fy * 0.20) + floorf((fy - fy * 0.20) * 0.45), floorf(w * 0.72), floorf((fy - fy * 0.20) * 0.55)))
		2:
			_openings.append(Rect2(8, 18, w - 16, fy - 18))
		_:
			_openings.append(Rect2(floorf(w * 0.12), 26, floorf(w * 0.76), fy - 26))
	_neons.append(Rect2(floorf(w * 0.10), 8, floorf(w * 0.30), 2))
	_neons.append(Rect2(floorf(w * 0.60), 8, floorf(w * 0.30), 2))


# --- Animation ----------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	_shake = maxf(0.0, _shake - delta)
	_pulse = maxf(0.0, _pulse - delta)
	_flash = maxf(0.0, _flash - delta)
	_flame = maxf(0.0, _flame - delta)
	if has_car and _car_rect != null:
		var off := Vector2.ZERO
		if _shake > 0.0:
			off = Vector2(_rng.randi_range(-1, 1), _rng.randi_range(-1, 0))
		_car_rect.position = _car_pos + off
		var fl := 1.0 + _flash * 5.0
		_car_rect.modulate = Color(fl, fl, fl)
	for p in _puffs:
		p["p"] += p["v"] * delta
		p["life"] -= delta
	_puffs = _puffs.filter(func(p: Dictionary) -> bool: return p["life"] > 0.0)
	for p in _sparks:
		p["v"].y += 260.0 * delta
		p["p"] += p["v"] * delta / maxf(size.x, 1.0)
		p["life"] -= delta
	_sparks = _sparks.filter(func(p: Dictionary) -> bool: return p["life"] > 0.0)
	for d in _dust:
		d["p"] += d["v"] * delta / maxf(size.x, 1.0)
		if d["p"].y < 0.0:
			d["p"] = Vector2(_rng.randf(), 1.0)
		d["p"].x = fposmod(d["p"].x, 1.0)
	for r in _rain:
		r["p"].y += r["sp"] * delta * 1.6
		if r["p"].y > 1.0:
			r["p"] = Vector2(_rng.randf(), 0.0)
	for f in _fog_blobs:
		f["x"] = fposmod(f["x"] + f["v"] * delta, 1.3)
	queue_redraw()
	_fog.queue_redraw()
	_plat.queue_redraw()
	_lights.queue_redraw()
	_under.queue_redraw()
	_animate_lights()
	if _mirror.visible:
		var vp := get_viewport_rect().size
		_mirror.material.set_shader_parameter("floor_uv", (global_position.y + _floor_y) / maxf(vp.y, 1.0))


# --- Décor (pixels) -----------------------------------------------------

func _r(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(floorf(x), floorf(y), floorf(w), floorf(h)), c)


func _draw() -> void:
	var w := size.x
	var h := size.y
	if show_backdrop:
		_draw_room(w, _floor_y)
		# Pluie dans la rue, derrière les ouvertures (donc derrière la voiture).
		for o in _openings:
			for r in _rain:
				var p := Vector2(o.position.x + r["p"].x * o.size.x, o.position.y + r["p"].y * o.size.y)
				var l: float = r["l"]
				var e := p + Vector2(-l * 0.25, l)
				if e.y > o.end.y:
					continue
				draw_line(p, e, Color(0.85, 0.8, 0.9, 0.22), 0.5)
		_draw_floor(w, h)


func _hour() -> int:
	return int(Time.get_datetime_dict_from_system()["hour"])


## Ciel et teinte de la ville selon l'heure réelle.
func _sky() -> Array[Color]:
	var hr := _hour()
	if hr < 6 or hr >= 21:
		return [Color("06060f"), Color("1d1030"), Color(0.62, 0.5, 0.8)]
	if hr < 9:
		return [Color("2a1a3a"), Color("d0784a"), Color(1.0, 0.78, 0.7)]
	if hr < 17:
		return [Color("3b3f52"), Color("9a8a8a"), Color(0.85, 0.82, 0.86)]
	return [Color("1a0f2a"), Color("b0445a"), Color(1.0, 0.68, 0.75)]


func _is_night() -> bool:
	var hr := _hour()
	return hr < 7 or hr >= 19


## La ville en trois couches, cadrée dans une ouverture, qui défile doucement.
func _draw_city(rect: Rect2, near := true) -> void:
	var sky := _sky()
	var r := Rect2(rect.position.floor(), rect.size.floor())
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([sky[0], sky[0], sky[1], sky[1]]))
	var tint: Color = sky[2]
	_tile(CITY_BACK, r, r.end.y, _time * 1.5, tint.darkened(0.25))
	_tile(CITY_MIDDLE, r, r.end.y + 8.0, _time * 3.0, tint.darkened(0.1))
	if near:
		_tile(CITY_FRONT, r, r.end.y + 70.0, _time * 5.0, tint.darkened(0.35))
	# Brume de profondeur.
	draw_polygon(PackedVector2Array([Vector2(r.position.x, r.end.y - r.size.y * 0.5), Vector2(r.end.x, r.end.y - r.size.y * 0.5), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([Color(0.5, 0.2, 0.3, 0.0), Color(0.5, 0.2, 0.3, 0.0), Color(0.55, 0.22, 0.3, 0.35), Color(0.55, 0.22, 0.3, 0.35)]))


## Répète une texture horizontalement, alignée en bas, coupée au cadre.
func _tile(tex: Texture2D, clip: Rect2, bottom: float, scroll: float, mod: Color) -> void:
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var top := floorf(bottom - th)
	var x := clip.position.x - fposmod(floorf(scroll), tw)
	while x < clip.end.x:
		var dst := Rect2(floorf(x), top, tw, th)
		var inter := dst.intersection(clip)
		if inter.size.x > 0.0 and inter.size.y > 0.0:
			var src := Rect2(inter.position - dst.position, inter.size)
			draw_texture_rect_region(tex, inter, src, mod)
		x += tw


func _draw_room(w: float, fy: float) -> void:
	var top_c := Color("120f16")
	var bot_c := Color("221d26")
	if stage == 1:
		top_c = Color("170f10")
		bot_c = Color("2c1c1a")
	elif stage == 3:
		top_c = Color("101215")
		bot_c = Color("22262a")
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, fy), Vector2(0, fy)]), PackedColorArray([top_c, top_c, bot_c, bot_c]))
	match stage:
		0:
			_draw_box(w, fy)
		1:
			_draw_workshop(w, fy)
		2:
			_draw_showroom(w, fy)
		_:
			_draw_hangar(w, fy)
	for n in _neons:
		_r(n.position.x + 4, 3, 1, 5, Color("3a3942"))
		_r(n.end.x - 5, 3, 1, 5, Color("3a3942"))
		var flick := 0.55 if fmod(_time + n.position.x * 0.01, 5.3) < 0.06 else 1.0
		_r(n.position.x, n.position.y, n.size.x, n.size.y, NEON.lerp(Color.WHITE, 0.25) * flick)
		_r(n.position.x + 1, n.position.y, n.size.x - 2, 1, Color(1.0, 0.9, 0.75) * flick)
	_draw_sign(w)


func _sign_flicker() -> float:
	var t := fmod(_time, 9.0)
	return 0.35 if (t > 6.0 and t < 6.08) or (t > 6.2 and t < 6.26) else 1.0


## Enseigne néon suspendue au plafond : le nom de l'étape.
func _draw_sign(w: float) -> void:
	var text: String = STAGE_SIGNS[clampi(stage, 0, STAGE_SIGNS.size() - 1)]
	var font := PixelUI.font("small")
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, PixelUI.SIZE_SMALL).x
	var bw := floorf(tw) + 10.0
	var x := floorf((w - bw) * 0.5)
	_r(x + 3, 0, 1, 4, Color("3a3942"))
	_r(x + bw - 4, 0, 1, 4, Color("3a3942"))
	_r(x, 4, bw, 13, Color("0b0a0e"))
	_r(x + 1, 5, bw - 2, 11, Color("1a1820"))
	_r(x + 1, 5, bw - 2, 1, Color("2c2a33"))
	var f := _sign_flicker()
	draw_string(font, Vector2(x + 5, 14), text, HORIZONTAL_ALIGNMENT_LEFT, -1, PixelUI.SIZE_SMALL, Color(1.0, 0.86, 0.9) * f)


func _draw_box(w: float, fy: float) -> void:
	# Box en ruelle : rideau de fer, petite fenêtre haute sur la ville.
	var o := _openings[0]
	_draw_city(o, false)
	_r(o.position.x - 2, o.position.y - 2, o.size.x + 4, 2, Color("0b0a0e"))
	_r(o.position.x - 2, o.end.y, o.size.x + 4, 2, Color("3a3942"))
	_r(o.position.x + o.size.x * 0.5, o.position.y, 1, o.size.y, Color("0b0a0e"))
	var dx := floorf(w * 0.14)
	var top := 22.0
	_r(dx - 3, top - 3, w - dx * 2 + 6, fy - top + 3, Color("0c0b0f"))
	var y := top
	var i := 0
	while y < fy:
		_r(dx, y, w - dx * 2, 3, Color("35343c") if i % 2 == 0 else Color("2b2a31"))
		_r(dx, y + 2, w - dx * 2, 1, Color("1b1a20"))
		y += 3.0
		i += 1
	_r(dx, fy - 6, w - dx * 2, 2, Color("4a4954"))
	_r(w * 0.5 - 6, fy - 5, 12, 2, Color("6b6a76"))
	_draw_cans(w - 26, fy)
	_draw_tires(4, fy)


func _draw_workshop(w: float, fy: float) -> void:
	# Atelier : briques, panneau à outils, pile de pneus, rideau à moitié levé sur la rue.
	var by := 14.0
	var row := 0
	while by < fy:
		var off := 0.0 if row % 2 == 0 else 7.0
		var bx := -off
		while bx < w:
			_r(bx + 1, by + 1, 13, 5, Color("34211d"))
			_r(bx + 1, by + 1, 13, 1, Color("43302a"))
			bx += 14.0
		by += 6.0
		row += 1
	var o := _openings[0]
	var shutter_top := floorf(fy * 0.20)
	_r(o.position.x - 3, shutter_top - 3, o.size.x + 6, fy - shutter_top + 3, Color("0b0a0e"))
	_draw_city(o, true)
	var y := shutter_top
	var i := 0
	while y < o.position.y:
		_r(o.position.x, y, o.size.x, 3, Color("3b3a43") if i % 2 == 0 else Color("2e2d35"))
		y += 3.0
		i += 1
	_r(o.position.x, o.position.y - 2, o.size.x, 2, Color("56555f"))
	var px := 8.0
	var py := 24.0
	_r(px, py, 50, 34, Color("26201c"))
	for yy in range(int(py) + 3, int(py) + 32, 5):
		for xx in range(int(px) + 3, int(px) + 48, 5):
			_r(xx, yy, 1, 1, Color("15110f"))
	_draw_tool(px + 8, py + 5, "wrench")
	_draw_tool(px + 22, py + 4, "hammer")
	_draw_tool(px + 38, py + 5, "wrench")
	_draw_tires(w - 34, fy)


func _draw_showroom(w: float, fy: float) -> void:
	# Showroom : baie vitrée sur la ville, montants, carrelage brillant.
	var o := _openings[0]
	_draw_city(o, true)
	for mx in [o.position.x, floorf(w * 0.35), floorf(w * 0.65), o.end.x - 3.0]:
		_r(mx, o.position.y, 3, o.size.y, Color("24232a"))
		_r(mx, o.position.y, 1, o.size.y, Color("4a4954"))
	_r(o.position.x, o.position.y, o.size.x, 3, Color("24232a"))
	_r(o.position.x, fy - 3, o.size.x, 3, Color("2c2b33"))
	# Reflet du ciel sur la vitre.
	draw_polygon(PackedVector2Array([o.position + Vector2(o.size.x * 0.1, 0), o.position + Vector2(o.size.x * 0.22, 0), o.position + Vector2(o.size.x * 0.12, o.size.y), o.position + Vector2(o.size.x * 0.0, o.size.y)]),
		PackedColorArray([Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.06), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0)]))


func _draw_hangar(w: float, fy: float) -> void:
	# Hangar : tôle ondulée, charpente, grande porte ouverte.
	var x := 0.0
	while x < w:
		_r(x, 14, 2, fy - 14, Color("1b1d20"))
		x += 6.0
	var o := _openings[0]
	_r(o.position.x - 2, o.position.y - 2, o.size.x + 4, o.size.y + 2, Color("0b0a0e"))
	_draw_city(o, true)
	_r(o.position.x, o.position.y, o.size.x, 5, Color("1a1b1d"))
	for k in 5:
		var tx := o.position.x + k * o.size.x / 4.0
		draw_line(Vector2(tx, 14), Vector2(w * 0.5, 2), Color("2c2e32"), 1.0)
	_r(0, 14, w, 2, Color("2c2e32"))
	_draw_tires(w - 30, fy)
	_draw_cans(6, fy)


func _draw_floor(w: float, h: float) -> void:
	var fy := _floor_y
	var floor_top := Color("1d1b22") if stage == 2 else Color("17161b")
	draw_polygon(PackedVector2Array([Vector2(0, fy), Vector2(w, fy), Vector2(w, h), Vector2(0, h)]), PackedColorArray([floor_top, floor_top, Color("08080b"), Color("08080b")]))
	_r(0, fy, w, 1, Color("3a3842"))
	var vp := Vector2(w * 0.5, fy - 60.0)
	for k in range(-6, 7):
		var bx := w * 0.5 + k * w * 0.22
		var a := vp.lerp(Vector2(bx, h), (fy - vp.y) / (h - vp.y))
		draw_line(a.floor(), Vector2(bx, h).floor(), Color("25242c"), 1.0)
	# Joints des dalles, de plus en plus espacés vers l'avant (perspective).
	var yy := fy + 5.0
	var step := 4.0
	var joint := Color("2a2932") if stage == 2 else Color("201f26")
	while yy < h:
		draw_line(Vector2(0, floorf(yy)), Vector2(w, floorf(yy)), joint, 1.0)
		_r(0, yy + 1, w, 1, Color(0, 0, 0, 0.25))
		step += 3.0
		yy += step
	# Plinthe au pied du mur.
	if stage != 2:
		_r(0, fy - 3, w, 3, Color("0c0b0f"))
		_r(0, fy - 3, w, 1, Color("2c2b33"))
	# Flaques : reflet du ciel des ouvertures.
	for o in _openings:
		var pud := Rect2(o.position.x + o.size.x * 0.1, fy + 4, o.size.x * 0.8, (h - fy) * 0.5)
		draw_polygon(PackedVector2Array([pud.position, Vector2(pud.end.x, pud.position.y), pud.end, Vector2(pud.position.x, pud.end.y)]),
			PackedColorArray([Color(0.6, 0.35, 0.45, 0.10), Color(0.6, 0.35, 0.45, 0.10), Color(0, 0, 0, 0), Color(0, 0, 0, 0)]))


func _draw_tires(x: float, fy: float) -> void:
	for k in 4:
		var ty := fy - 8 - k * 7
		_r(x + 1, ty, 26, 7, Color("0d0d10"))
		_r(x, ty + 1, 28, 5, Color("1b1b20"))
		_r(x + 3, ty + 1, 22, 1, Color("2d2d34"))
		_r(x + 9, ty + 3, 10, 2, Color("08080a"))


func _draw_cans(x: float, fy: float) -> void:
	for k in 3:
		var c: Color = [Color("c8202a"), Color("ff8a1f"), Color("4a4954")][k]
		_r(x + k * 7, fy - 10, 6, 10, c.darkened(0.25))
		_r(x + k * 7, fy - 10, 6, 1, c.lightened(0.3))
		_r(x + k * 7 + 1, fy - 7, 4, 3, Color("e8e2d4").darkened(0.2))


func _draw_tool(x: float, y: float, kind: String) -> void:
	var c := Color("8f939b")
	if kind == "wrench":
		_r(x + 2, y + 4, 2, 18, c)
		_r(x, y, 6, 5, c)
		_r(x + 2, y, 2, 2, Color("26201c"))
	else:
		_r(x + 3, y + 5, 2, 18, Color("6a4a30"))
		_r(x, y, 9, 5, c)


func _ell(c: Vector2, rx: float, ry: float, t: float) -> Vector2:
	return (c + Vector2(cos(t) * rx, sin(t) * ry)).floor()


func _draw_platform() -> void:
	# Plateau tournant : socle en métal strié, anneau de LED à la couleur de la
	# rareté, disque central dont les rayons tournent lentement.
	var c := _plat_c
	var rx := _plat_r.x
	var ry := _plat_r.y
	var glow: Color = PixelUI.RARITY[rarity]
	var seg := 40
	var thick := 8.0
	var top := PackedVector2Array()
	var side := PackedVector2Array()
	for k in seg:
		top.append(_ell(c, rx, ry, TAU * k / seg))
	for k in range(0, seg / 2 + 1):
		side.append(_ell(c, rx, ry, TAU * k / seg) + Vector2(0, thick))
	for k in range(seg / 2, -1, -1):
		side.append(_ell(c, rx, ry, TAU * k / seg))
	_plat.draw_colored_polygon(side, Color("09090c"))
	# Stries verticales du socle, plus claires face à nous.
	var ribs := int(rx / 3.0)
	for k in range(1, ribs):
		var t := PI * k / ribs
		var p := _ell(c, rx, ry, t)
		var facing := sin(t)
		_plat.draw_rect(Rect2(floorf(p.x), floorf(p.y + 2), 1, thick - 3), Color("1c1b22").lerp(Color("4a4954"), facing * facing) if k % 2 == 0 else Color("0e0d12"))
	_plat.draw_colored_polygon(top, Color("4a4954"))
	var inner := PackedVector2Array()
	for k in seg:
		inner.append(_ell(c, rx * 0.88, ry * 0.86, TAU * k / seg))
	_plat.draw_colored_polygon(inner, Color("25242c"))
	# Rayons du disque, en rotation lente.
	for k in 6:
		var a := _time * 0.22 + k * PI / 3.0
		_plat.draw_line(_ell(c, rx * 0.16, ry * 0.16, a), _ell(c, rx * 0.86, ry * 0.84, a), Color("34333d"), 1.0)
	var ring := PackedVector2Array()
	for k in seg + 1:
		ring.append(_ell(c, rx * 0.56, ry * 0.54, TAU * k / seg))
	_plat.draw_polyline(ring, Color("3a3942"), 1.0)
	# Bord : liseré clair en haut du socle, trait lumineux à la couleur de la rareté.
	for k in seg:
		var t0 := TAU * k / seg
		var t1 := TAU * (k + 1) / seg
		var a := _ell(c, rx, ry, t0)
		var b := _ell(c, rx, ry, t1)
		if sin(t0) > -0.15:
			_plat.draw_line(a + Vector2(0, 1), b + Vector2(0, 1), Color("4d4c57"), 1.0)
		_plat.draw_line(a, b, glow if sin(t0) > -0.15 else glow.darkened(0.55), 1.0)
	# Anneau de LED : une vague de lumière fait le tour.
	var n := 30
	for k in n:
		var t := TAU * k / n
		var p := _ell(c, rx * 0.94, ry * 0.92, t)
		var lit := fposmod(float(k) / n - _time * 0.12, 1.0) < 0.22
		var front := sin(t) > 0.3
		_plat.draw_rect(Rect2(floorf(p.x), floorf(p.y), 2 if front else 1, 2 if front else 1), glow.lerp(Color.WHITE, 0.55) if lit else glow.darkened(0.5))
	if has_car:
		# Ombre douce de contact sous la voiture.
		var sh := Vector2(rx * 0.92, ry * 0.95)
		_plat.draw_texture_rect(Fx.soft_dot(), Rect2(c - sh + Vector2(0, -2), sh * 2.0), false, Color(0, 0, 0, 0.8))


# --- Brouillard, fumée, pluie (fondu normal) -----------------------------

func _draw_fog() -> void:
	var w := size.x
	var h := size.y
	var dot := Fx.soft_dot()
	if show_backdrop:
		# Nappes de brouillard au ras du sol.
		for f in _fog_blobs:
			var cx: float = (f["x"] - 0.15) * w
			var cy: float = _floor_y + f["y"] * (h - _floor_y)
			var s: float = f["s"] * w
			_fog.draw_texture_rect(dot, Rect2(cx - s, cy - s * 0.18, s * 2.0, s * 0.36), false, Color(0.62, 0.45, 0.52, 0.07))
	# Fumée d'échappement.
	if has_car:
		var ex: Vector2 = _car_rect.position + Vector2(_car["exhaust"])
		for p in _puffs:
			var life: float = p["life"]
			var sz := 3.0 + (1.3 - life) * 12.0
			var pp: Vector2 = ex + p["p"]
			_fog.draw_texture_rect(dot, Rect2(pp - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(0.8, 0.78, 0.82, life * 0.45))


# --- Lumières (additif) ---------------------------------------------------

## Sous la voiture : halo du plateau à la couleur de la rareté, reflets au sol.
func _draw_under() -> void:
	var glow: Color = PixelUI.RARITY[rarity]
	var pulse := 0.85 + 0.15 * sin(_time * 1.7)
	var d := Fx.soft_dot()
	_under.draw_texture_rect(d, Rect2(_plat_c + Vector2(0, 4) - _plat_r * Vector2(1.3, 1.7), _plat_r * Vector2(2.6, 3.4)), false, Color(glow, 0.22 * pulse))
	_under.draw_texture_rect(d, Rect2(_plat_c - _plat_r * 0.9, _plat_r * 1.8), false, Color(glow, 0.10 * pulse))
	if show_backdrop:
		# Flaque de lumière des projecteurs sur le plateau.
		_under.draw_texture_rect(d, Rect2(_plat_c - _plat_r * Vector2(1.0, 1.2), _plat_r * Vector2(2.0, 2.4)), false, Color(1.0, 0.9, 0.75, 0.10))
	var leds := 30
	for k in leds:
		if fposmod(float(k) / leds - _time * 0.12, 1.0) < 0.22:
			var p := _plat_c + Vector2(cos(TAU * k / leds) * _plat_r.x * 0.94, sin(TAU * k / leds) * _plat_r.y * 0.92)
			_under.draw_texture_rect(d, Rect2(p - Vector2(5, 3), Vector2(10, 6)), false, Color(glow, 0.5))
	if show_backdrop:
		for n in _neons:
			# Reflet net du tube sur le sol mouillé.
			var x0 := n.position.x + 8.0
			var x1 := n.end.x - 8.0
			var y := _floor_y + (size.y - _floor_y) * 0.55
			_under.draw_polygon(PackedVector2Array([Vector2(x0, y), Vector2(x1, y), Vector2(x1, y + 2), Vector2(x0, y + 2)]),
				PackedColorArray([Color(NEON, 0.0), Color(NEON, 0.0), Color(NEON, 0.0), Color(NEON, 0.0)]))
			_under.draw_texture_rect(d, Rect2(Vector2(x0, y - 2), Vector2(x1 - x0, 5)), false, Color(NEON, 0.28))


func _halo(center: Vector2, radius: Vector2, color: Color) -> void:
	_lights.draw_texture_rect(Fx.soft_dot(), Rect2(center - radius, radius * 2.0), false, color)


## Rayon de lumière doux : plus fort au centre, nul sur les bords et en bas.
func _cone(top_l: Vector2, top_r: Vector2, bot_r: Vector2, bot_l: Vector2, color: Color) -> void:
	var top_c := (top_l + top_r) * 0.5
	var bot_c := (bot_l + bot_r) * 0.5
	var clear := Color(color, 0.0)
	_lights.draw_polygon(PackedVector2Array([top_l, top_c, bot_c, bot_l]), PackedColorArray([clear, color, clear, clear]))
	_lights.draw_polygon(PackedVector2Array([top_c, top_r, bot_r, bot_c]), PackedColorArray([color, clear, clear, clear]))


func _draw_lights() -> void:
	var w := size.x
	var h := size.y
	var glow: Color = PixelUI.RARITY[rarity]
	if show_backdrop:
		for n in _neons:
			var flick := 0.4 if fmod(_time + n.position.x * 0.01, 5.3) < 0.06 else 1.0
			var cx := n.get_center().x
			# Halo du tube, rayon de lumière vers le sol, reflet sur le sol mouillé.
			_halo(Vector2(cx, n.position.y + 1), Vector2(n.size.x * 0.75, 10), Color(NEON, 0.55 * flick))
			_halo(Vector2(cx, n.position.y + 1), Vector2(n.size.x * 0.55, 4), Color(1, 0.85, 0.6, 0.5 * flick))
			_cone(n.position + Vector2(0, 3), Vector2(n.end.x, n.position.y + 3), Vector2(n.end.x + 22, _floor_y + 12), Vector2(n.position.x - 22, _floor_y + 12), Color(NEON, 0.10 * flick))
			# Projecteur : faisceau blanc chaud resserré sur le plateau.
			_cone(Vector2(cx - 5, n.position.y + 3), Vector2(cx + 5, n.position.y + 3), _plat_c + Vector2(_plat_r.x * 0.75, _plat_r.y * 0.4), _plat_c + Vector2(-_plat_r.x * 0.75, _plat_r.y * 0.4), Color(1.0, 0.93, 0.8, 0.13 * flick))
			_cone(Vector2(n.position.x + 6, _floor_y + 2), Vector2(n.end.x - 6, _floor_y + 2), Vector2(n.end.x - 14, h), Vector2(n.position.x + 14, h), Color(NEON, 0.12 * flick))
		# Halo de l'enseigne.
		var sf := _sign_flicker()
		_halo(Vector2(w * 0.5, 10), Vector2(34, 11), Color(SIGN, 0.7 * sf))
		_halo(Vector2(w * 0.5, 10), Vector2(60, 26), Color(SIGN, 0.10 * sf))
		# Lumière de la ville qui entre par les ouvertures.
		for o in _openings:
			var city := Color(0.9, 0.35, 0.5) if _is_night() else Color(0.9, 0.7, 0.6)
			_halo(Vector2(o.get_center().x, o.end.y), Vector2(o.size.x * 0.6, 14), Color(city, 0.10))
		# Poussières dans la lumière.
		for d in _dust:
			var p := Vector2(d["p"].x * w, d["p"].y * _floor_y * 1.1)
			var tw := 0.5 + 0.5 * sin(_time * 2.0 + float(d["ph"]))
			var s: float = d["s"]
			_halo(p, Vector2(s, s), Color(1.0, 0.8, 0.55, 0.35 * tw))
	if _pulse > 0.0:
		# Onde de lumière qui s'élargit depuis le plateau.
		var k := 1.0 - _pulse / 0.6
		var ring := PackedVector2Array()
		for i in 41:
			ring.append(_plat_c + Vector2(cos(TAU * i / 40.0) * _plat_r.x, sin(TAU * i / 40.0) * _plat_r.y) * (1.0 + k * 0.45))
		_lights.draw_polyline(ring, Color(glow.lerp(Color.WHITE, 0.4), (1.0 - k) * 0.9), 2.0)
		_halo(_plat_c, _plat_r * (1.2 + k * 0.6), Color(glow, (1.0 - k) * 0.35))
	if not has_car:
		return
	# Phares : halo et faisceau vers l'avant-gauche, sur le sol.
	for lp in _car.get("lamps", []):
		var p: Vector2 = _car_rect.position + Vector2(lp)
		_halo(p, Vector2(7, 5), Color(LAMP, 0.9))
		_halo(p, Vector2(18, 10), Color(LAMP, 0.25))
		_cone(p + Vector2(0, -1), p + Vector2(0, 2), p + Vector2(-w * 0.45, 26), p + Vector2(-w * 0.45, -6), Color(LAMP, 0.10))
	# Flamme et étincelles.
	var ex: Vector2 = _car_rect.position + Vector2(_car["exhaust"])
	if _flame > 0.0 or (tier >= 3 and fmod(_time, 3.0) < 0.1):
		var fl := 7.0 + _rng.randf_range(0, 4)
		_halo(ex + Vector2(fl * 0.5, -1), Vector2(fl, 4), Color(1.0, 0.45, 0.1, 0.9))
		_halo(ex + Vector2(fl * 0.3, -1), Vector2(fl * 0.5, 2), Color(1.0, 0.9, 0.5, 0.9))
	for s in _sparks:
		var sp: Vector2 = _car_rect.position + _car_rect.size * Vector2(0.5, 0.55) + s["p"] * w
		_lights.draw_rect(Rect2(sp.floor(), Vector2(1, 1)), Color(1.0, 0.85, 0.4) if s["life"] > 0.25 else Color(1.0, 0.45, 0.1))
		_halo(sp, Vector2(2.5, 2.5), Color(1.0, 0.6, 0.2, 0.5))
