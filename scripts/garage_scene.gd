## Scène du garage, dessinée au pixel près à la résolution du jeu :
## murs et accessoires de l'étape, néons, ciel à l'heure réelle, sol mouillé,
## plateau lumineux à la couleur de la rareté, voiture et effets au toucher.
extends Control

const CarRenderer = preload("res://scripts/car_renderer.gd")
const PixelUI = preload("res://scripts/pixel_ui.gd")

signal tapped(local_pos: Vector2)

var body_color := Color("8a5a3c")
var body_type := "citadine"
var rarity := 0
var tier := 0
var stage := 0
## false : seulement la voiture sur son plateau (carte de spot).
var show_backdrop := true
var interactive := true

var _car := {}
var _car_scale := 0.0
var _shake := 0.0
var _flame := 0.0
var _time := 0.0
var _puffs: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	resized.connect(_refresh_car)


func configure(color: Color, body: String, rarity_index: int, tier_index: int, stage_index: int) -> void:
	body_color = color
	body_type = body
	rarity = rarity_index
	tier = tier_index
	stage = stage_index
	_car_scale = 0.0
	_refresh_car()


func _refresh_car() -> void:
	if size.x <= 0.0:
		return
	var target := size.x * (0.80 if show_backdrop else 0.84)
	var s := clampf(snappedf(target / 92.0, 0.1), 1.0, 3.2)
	if s == _car_scale and not _car.is_empty():
		return
	_car_scale = s
	_car = CarRenderer.render(body_type, body_color, tier, s)
	queue_redraw()


## Réaction au toucher : la voiture tremble, fume, étincelle, et crache parfois une flamme.
func bump() -> void:
	_shake = 0.16
	for i in 2:
		_puffs.append({"p": Vector2.ZERO, "v": Vector2(14.0 + _rng.randf() * 10.0, -6.0 - _rng.randf() * 8.0), "life": 0.8 + _rng.randf() * 0.3})
	for i in 5:
		_sparks.append({"p": Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.2, 0.1)), "v": Vector2(_rng.randf_range(-40, 40), _rng.randf_range(-70, -30)), "life": 0.45})
	if tier >= 3 or _rng.randf() < 0.2:
		_flame = 0.25


func _gui_input(event: InputEvent) -> void:
	if interactive and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit(event.position)
		accept_event()


func _process(delta: float) -> void:
	_time += delta
	_shake = maxf(0.0, _shake - delta)
	_flame = maxf(0.0, _flame - delta)
	for p in _puffs:
		p["p"] += p["v"] * delta
		p["life"] -= delta
	_puffs = _puffs.filter(func(p: Dictionary) -> bool: return p["life"] > 0.0)
	for p in _sparks:
		p["v"].y += 220.0 * delta
		p["p"] += p["v"] * delta / maxf(size.x, 1.0)
		p["life"] -= delta
	_sparks = _sparks.filter(func(p: Dictionary) -> bool: return p["life"] > 0.0)
	queue_redraw()


# --- Dessin -------------------------------------------------------------

func _r(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(floorf(x), floorf(y), floorf(w), floorf(h)), c)


func _draw() -> void:
	if _car.is_empty():
		return
	var w := size.x
	var hgt := size.y
	var floor_y := floorf(hgt * 0.60) if show_backdrop else floorf(hgt * 0.62)
	if show_backdrop:
		_draw_room(w, floor_y)
	var tex: ImageTexture = _car["texture"]
	var tsize := Vector2(tex.get_size())
	var anchor: Vector2 = _car["anchor"]
	var plat_c := Vector2(floorf(w * 0.5), floor_y + floorf((hgt - floor_y) * 0.36))
	_draw_platform(plat_c, floorf(w * (0.42 if show_backdrop else 0.44)), floorf(maxf(10.0, (hgt - floor_y) * 0.26)))

	var shake := Vector2.ZERO
	if _shake > 0.0:
		shake = Vector2(_rng.randi_range(-1, 1), _rng.randi_range(-1, 0))
	var pos := (plat_c - anchor).floor() + shake

	# Reflet de la voiture sur le plateau poli, sous l'avant.
	var mirror := pos.y + float(_car["ground"])
	draw_set_transform(Vector2(0, mirror * 2.0), 0.0, Vector2(1, -1))
	draw_texture_rect(tex, Rect2(pos, tsize), false, Color(1, 1, 1, 0.08))
	draw_set_transform(Vector2.ZERO)

	draw_texture_rect(tex, Rect2(pos, tsize), false)

	# Fumée, flamme et étincelles.
	var ex: Vector2 = pos + _car["exhaust"]
	for p in _puffs:
		var life: float = p["life"]
		var sz := floorf(2.0 + (1.0 - life) * 7.0)
		var pp: Vector2 = ex + p["p"]
		_r(pp.x - sz * 0.5, pp.y - sz * 0.5, sz, sz, Color(0.78, 0.76, 0.8, life * 0.55))
	if _flame > 0.0 or (tier >= 3 and fmod(_time, 3.0) < 0.1):
		var fl := 6.0 + _rng.randi_range(0, 3)
		_r(ex.x, ex.y - 2, fl, 3, Color("ff6a10"))
		_r(ex.x, ex.y - 1, fl * 0.6, 2, Color("ffd34a"))
		_r(ex.x, ex.y - 1, 2, 1, Color.WHITE)
	for s in _sparks:
		var sp: Vector2 = pos + tsize * Vector2(0.5, 0.55) + s["p"] * w
		_r(sp.x, sp.y, 1, 1, Color("ffd34a") if s["life"] > 0.2 else Color("ff7a1a"))


func _sky() -> Color:
	var hour := int(Time.get_datetime_dict_from_system()["hour"])
	if hour < 6 or hour >= 21:
		return Color("0c0d18")
	if hour < 9:
		return Color("b8643c")
	if hour < 17:
		return Color("6e7a80")
	return Color("6a2f4a")


func _draw_room(w: float, floor_y: float) -> void:
	var wall_top := Color("15141a")
	var wall_bot := Color("23212a")
	if stage == 1:
		wall_top = Color("1c1414")
		wall_bot = Color("2c1f1c")
	elif stage == 3:
		wall_top = Color("16181a")
		wall_bot = Color("24272a")
	var y := 0.0
	while y < floor_y:
		_r(0, y, w, 2, wall_top.lerp(wall_bot, y / floor_y))
		y += 2.0

	match stage:
		0:
			_draw_box(w, floor_y)
		1:
			_draw_workshop(w, floor_y)
		2:
			_draw_showroom(w, floor_y)
		_:
			_draw_hangar(w, floor_y)

	# Néons du plafond, avec halo et cône de lumière.
	var flick := 0.5 if fmod(_time + 1.3, 5.1) < 0.07 else 1.0
	for span in [[0.10, 0.40], [0.60, 0.90]]:
		var x0 := floorf(w * span[0])
		var x1 := floorf(w * span[1])
		var cone := PackedVector2Array([Vector2(x0, 9), Vector2(x1, 9), Vector2(x1 + 18, floor_y), Vector2(x0 - 18, floor_y)])
		draw_colored_polygon(cone, Color(1.0, 0.55, 0.2, 0.035 * flick))
		_r(x0 - 3, 5, x1 - x0 + 6, 8, Color(1.0, 0.5, 0.15, 0.10 * flick))
		_r(x0 - 1, 7, x1 - x0 + 2, 4, Color(1.0, 0.5, 0.15, 0.22 * flick))
		_r(x0, 8, x1 - x0, 2, Color("ff8a2a"))
		_r(x0 + 1, 8, x1 - x0 - 2, 1, Color("ffd9a8") if flick > 0.6 else Color("ff8a2a"))
		_r(x0 + 4, 4, 1, 4, Color("3a3942"))
		_r(x1 - 5, 4, 1, 4, Color("3a3942"))

	# Sol mouillé : dégradé, lignes de fuite, reflets des néons.
	var hgt := size.y
	y = floor_y
	while y < hgt:
		_r(0, y, w, 1, Color("1a191f").lerp(Color("0c0b10"), (y - floor_y) / maxf(1.0, hgt - floor_y)))
		y += 1.0
	_r(0, floor_y, w, 1, Color("34323c"))
	var vp := Vector2(w * 0.5, floor_y - 60.0)
	for k in range(-6, 7):
		var bx := w * 0.5 + k * w * 0.22
		var t0 := 0.0
		var a := vp.lerp(Vector2(bx, hgt), (floor_y - vp.y) / (hgt - vp.y))
		draw_line(a.floor(), Vector2(bx, hgt).floor(), Color("24232b"), 1.0)
		t0 += 1.0
	for span in [[0.10, 0.40], [0.60, 0.90]]:
		var x0 := floorf(w * span[0]) + 6.0
		var x1 := floorf(w * span[1]) - 6.0
		var yy := floor_y + 2.0
		var k2 := 0
		while yy < hgt:
			var a2 := 0.16 * (1.0 - (yy - floor_y) / (hgt - floor_y))
			if k2 % 2 == 0:
				_r(x0 + k2, yy, x1 - x0 - k2 * 2.0, 1, Color(1.0, 0.55, 0.2, a2))
			yy += 2.0
			k2 += 1


func _draw_box(w: float, floor_y: float) -> void:
	# Box en ruelle : rideau de fer derrière la voiture, béton, petite fenêtre.
	var dx := floorf(w * 0.14)
	var top := 22.0
	_r(dx - 3, top - 3, w - dx * 2 + 6, floor_y - top + 3, Color("0f0e12"))
	var y := top
	var i := 0
	while y < floor_y:
		_r(dx, y, w - dx * 2, 3, Color("3b3a43") if i % 2 == 0 else Color("2e2d35"))
		_r(dx, y + 2, w - dx * 2, 1, Color("1f1e25"))
		y += 3.0
		i += 1
	_r(dx, floor_y - 6, w - dx * 2, 2, Color("4a4954"))
	_r(w * 0.5 - 6, floor_y - 5, 12, 2, Color("6b6a76"))
	_r(6, 20, 26, 16, Color("0b0a0e"))
	_r(7, 21, 24, 14, _sky())
	_r(7, 27, 24, 1, Color("0b0a0e"))
	_r(18, 21, 1, 14, Color("0b0a0e"))
	_draw_cans(w - 22, floor_y)


func _draw_workshop(w: float, floor_y: float) -> void:
	# Atelier : briques, panneau à outils, pile de pneus, établi.
	var by := 16.0
	var row := 0
	while by < floor_y:
		var off := 0.0 if row % 2 == 0 else 7.0
		var bx := -off
		while bx < w:
			_r(bx + 1, by + 1, 13, 5, Color("3a2622"))
			_r(bx + 1, by + 1, 13, 1, Color("47302a"))
			bx += 14.0
		by += 6.0
		row += 1
	var px := 10.0
	var py := 26.0
	_r(px, py, 70, 42, Color("2a2420"))
	_r(px, py, 70, 1, Color("3a322c"))
	for yy in range(int(py) + 4, int(py) + 40, 5):
		for xx in range(int(px) + 4, int(px) + 68, 5):
			_r(xx, yy, 1, 1, Color("181412"))
	_draw_tool(px + 10, py + 6, "wrench")
	_draw_tool(px + 30, py + 5, "hammer")
	_draw_tool(px + 50, py + 6, "wrench")
	_r(8, floor_y - 18, 80, 3, Color("5a4030"))
	_r(12, floor_y - 15, 3, 15, Color("3a2a20"))
	_r(80, floor_y - 15, 3, 15, Color("3a2a20"))
	_r(20, floor_y - 24, 8, 6, Color("c8202a"))
	_r(32, floor_y - 22, 12, 4, Color("6b6a76"))
	_draw_tires(w - 46, floor_y)


func _draw_showroom(w: float, floor_y: float) -> void:
	# Showroom : baie vitrée sur la ville, carrelage brillant.
	var top := 18.0
	var sky := _sky()
	var y := top
	while y < floor_y:
		_r(8, y, w - 16, 2, sky.darkened(0.45 * (1.0 - (y - top) / (floor_y - top))))
		y += 2.0
	var bx := 8.0
	var i := 0
	while bx < w - 8:
		var bw := 14.0 + float((i * 7) % 12)
		var bh := floorf((floor_y - top) * (0.35 + 0.45 * fmod(i * 0.37 + 0.2, 1.0)))
		_r(bx, floor_y - bh, minf(bw, w - 8 - bx), bh, Color("0a0a0e"))
		var wy := floor_y - bh + 4
		while wy < floor_y - 3:
			for wx in range(int(bx) + 2, int(bx + bw) - 2, 4):
				if (wx + int(wy) + i) % 5 < 2 and wx < w - 10:
					_r(wx, wy, 2, 2, Color("ffb050"))
			wy += 5
		bx += bw + 2.0
		i += 1
	for mx in [8.0, w * 0.35, w * 0.65, w - 11.0]:
		_r(mx, top, 3, floor_y - top, Color("2c2b33"))
		_r(mx, top, 1, floor_y - top, Color("4a4954"))
	_r(8, top, w - 16, 3, Color("2c2b33"))


func _draw_hangar(w: float, floor_y: float) -> void:
	# Hangar : tôle ondulée, charpente, grande porte ouverte.
	var x := 0.0
	while x < w:
		_r(x, 14, 2, floor_y - 14, Color("1e2023"))
		x += 6.0
	var dx := floorf(w * 0.12)
	var top := 26.0
	_r(dx - 2, top - 2, w - dx * 2 + 4, floor_y - top + 2, Color("0b0a0e"))
	var sky := _sky()
	var y := top
	while y < floor_y:
		_r(dx, y, w - dx * 2, 2, sky.darkened(0.5 * (1.0 - (y - top) / (floor_y - top))))
		y += 2.0
	_r(dx, floor_y - 12, w - dx * 2, 12, Color("101015"))
	for k in 5:
		var tx := dx + k * (w - dx * 2) / 4.0
		draw_line(Vector2(tx, 14), Vector2(w * 0.5, 2), Color("2c2e32"), 1.0)
	_r(0, 14, w, 2, Color("2c2e32"))
	_draw_tires(w - 40, floor_y)
	_draw_cans(14, floor_y)


func _draw_tires(x: float, floor_y: float) -> void:
	for k in 4:
		var ty := floor_y - 8 - k * 7
		_r(x + 1, ty, 26, 7, Color("0d0d10"))
		_r(x, ty + 1, 28, 5, Color("1b1b20"))
		_r(x + 3, ty + 1, 22, 1, Color("2d2d34"))
		_r(x + 9, ty + 3, 10, 2, Color("08080a"))


func _draw_cans(x: float, floor_y: float) -> void:
	for k in 3:
		var c: Color = [Color("c8202a"), Color("ff8a1f"), Color("4a4954")][k]
		_r(x + k * 7, floor_y - 10, 6, 10, c.darkened(0.2))
		_r(x + k * 7, floor_y - 10, 6, 1, c.lightened(0.3))
		_r(x + k * 7 + 1, floor_y - 7, 4, 3, Color("e8e2d4"))


func _draw_tool(x: float, y: float, kind: String) -> void:
	var c := Color("8f939b")
	if kind == "wrench":
		_r(x + 2, y + 4, 2, 22, c)
		_r(x, y, 6, 5, c)
		_r(x + 2, y, 2, 2, Color("2a2420"))
	else:
		_r(x + 3, y + 5, 2, 22, Color("6a4a30"))
		_r(x, y, 9, 5, c)


func _draw_platform(c: Vector2, rx: float, ry: float) -> void:
	# Plateau tournant poli, bordure lumineuse à la couleur de la rareté.
	var glow: Color = PixelUI.RARITY[rarity]
	var pts := PackedVector2Array()
	var side := PackedVector2Array()
	var seg := 28
	for k in seg:
		var t := TAU * k / seg
		pts.append((c + Vector2(cos(t) * rx, sin(t) * ry)).floor())
	for k in range(0, seg / 2 + 1):
		var t := TAU * k / seg
		side.append((c + Vector2(cos(t) * rx, sin(t) * ry + 5)).floor())
	for k in range(seg / 2, -1, -1):
		var t := TAU * k / seg
		side.append((c + Vector2(cos(t) * rx, sin(t) * ry)).floor())
	for g in 4:
		var halo := PackedVector2Array()
		for k in seg:
			var t := TAU * k / seg
			halo.append(c + Vector2(cos(t) * (rx + 4 + g * 4), sin(t) * (ry + 2 + g * 2) + 3))
		draw_colored_polygon(halo, Color(glow, 0.07 - g * 0.014))
	draw_colored_polygon(side, Color("121116"))
	draw_colored_polygon(pts, Color("2a2930"))
	var inner := PackedVector2Array()
	for k in seg:
		var t := TAU * k / seg
		inner.append((c + Vector2(cos(t) * rx * 0.86, sin(t) * ry * 0.82)).floor())
	draw_colored_polygon(inner, Color("222128"))
	for k in seg:
		var t0 := TAU * k / seg
		var t1 := TAU * (k + 1) / seg
		var a := (c + Vector2(cos(t0) * rx, sin(t0) * ry)).floor()
		var b := (c + Vector2(cos(t1) * rx, sin(t1) * ry)).floor()
		var lit := sin(t0) > -0.15
		draw_line(a, b, glow if lit else glow.darkened(0.5), 1.0)
		if lit:
			draw_line(a + Vector2(0, 5), b + Vector2(0, 5), Color(glow, 0.55), 1.0)
