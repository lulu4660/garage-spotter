## Scène du garage : décor de l'étape, ciel à l'heure réelle, plateau lumineux
## et voiture en pixel art vue de profil, avec reflet au sol.
## Le sprite est provisoire : dessiné par code et recoloré, en attendant les
## sprites générés (phase 1) ou ceux du pack de référence.
extends Control

const Palette = preload("res://scripts/palette.gd")

signal tapped(local_pos: Vector2)

## Silhouettes par type de carrosserie (en pixels de sprite).
## len : longueur, body : épaisseur de caisse, c0/c1 : début/fin du toit,
## ch : hauteur de l'habitacle, sf/sb : pente du pare-brise / de la lunette.
const BODIES := {
	"citadine": {"len": 40, "body": 7, "c0": 0.22, "c1": 0.72, "ch": 7, "sf": 5, "sb": 2},
	"compacte": {"len": 44, "body": 7, "c0": 0.22, "c1": 0.68, "ch": 6, "sf": 6, "sb": 3},
	"berline": {"len": 50, "body": 7, "c0": 0.26, "c1": 0.64, "ch": 6, "sf": 6, "sb": 5},
	"coupe": {"len": 50, "body": 6, "c0": 0.30, "c1": 0.62, "ch": 5, "sf": 7, "sb": 7},
	"supercar": {"len": 54, "body": 5, "c0": 0.30, "c1": 0.56, "ch": 5, "sf": 10, "sb": 8},
}
const WHEEL_R := 4
const OUTLINE := Color("0e0e10")
const GLASS := Color("232a30")
const GLASS_HI := Color("4b5862")
const ARCH := Color("0b0b0d")
const TIRE := Color("1b1b1d")
const RIM := Color("9a9ea3")
const RIM_GOLD := Color("d9a83a")
const HUB := Color("3a3a3e")
const HEADLIGHT := Color("ffe9a8")
const TAILLIGHT := Color("e8322f")
const WING := Color("26262b")

var body_color := Color("8a5a3c")
var body_type := "citadine"
var rarity := 0
var tier := 0
var stage := 0
var show_backdrop := true
var interactive := true

var _tex: ImageTexture
var _img_size := Vector2i.ZERO
var _exhaust := Vector2.ZERO
var _shake := 0.0
var _flame := 0.0
var _time := 0.0
var _puffs: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	if _tex == null:
		_rebuild()


func configure(color: Color, body: String, rarity_index: int, tier_index: int, stage_index: int) -> void:
	body_color = color
	body_type = body if BODIES.has(body) else "citadine"
	rarity = rarity_index
	tier = tier_index
	stage = stage_index
	_rebuild()
	queue_redraw()


## Réaction à un toucher : la voiture tremble, fume, et crache une flamme une fois préparée.
func bump() -> void:
	_shake = 0.18
	_puffs.append({"p": _exhaust, "v": Vector2(-6.0 - _rng.randf() * 4.0, -3.0 - _rng.randf() * 3.0), "life": 0.9})
	if tier >= 3 or _rng.randf() < 0.15:
		_flame = 0.22


func _gui_input(event: InputEvent) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
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
	queue_redraw()


# --- Sprite -------------------------------------------------------------

func _rebuild() -> void:
	var p: Dictionary = BODIES[body_type]
	var length: int = p["len"]
	var body_h: int = p["body"]
	var cabin_h: int = p["ch"]
	var r := WHEEL_R
	var w := length + 6
	var h := r + body_h + cabin_h + 6
	var ox := 3
	var low := 1 if tier >= 4 else 0
	var cy := float(h - 1 - r)
	var body_bottom := int(cy) + 1 + low
	var body_top := body_bottom - body_h + 1
	var light := body_color.lightened(0.28)
	var dark := body_color.darkened(0.32)
	var cells := {}

	# Caisse, avec coins arrondis et nez plongeant à l'avant (à droite).
	var nose: int = 2 if int(p["sf"]) >= 9 else 1
	for y in range(body_top, body_bottom + 1):
		for x in range(ox, ox + length):
			var row := y - body_top
			if row == 0 and (x == ox or x >= ox + length - 1 - nose):
				continue
			if row == 1 and nose == 2 and x == ox + length - 1:
				continue
			var c := body_color
			if row == 0:
				c = light
			elif y == body_bottom:
				c = dark
			elif row == 2:
				c = body_color.darkened(0.08)
			cells[Vector2i(x, y)] = c

	# Habitacle : trapèze vitré avec montant central.
	var c0: float = ox + float(p["c0"]) * length
	var c1: float = ox + float(p["c1"]) * length
	var sb: float = p["sb"]
	var sf: float = p["sf"]
	for k in range(1, cabin_h + 1):
		var y := body_top - k
		var t := float(k - 1) / maxf(1.0, float(cabin_h - 1))
		var a := int(round(lerpf(c0 - sb, c0, t)))
		var b := int(round(lerpf(c1 + sf, c1, t)))
		var pillar := int(round((a + b) * 0.5))
		for x in range(a, b + 1):
			var edge := x == a or x == b or k == cabin_h or x == pillar
			var c := light if k == cabin_h else body_color
			if not edge:
				c = GLASS_HI if (x + k) % 9 == 0 else GLASS
			cells[Vector2i(x, y)] = c

	# Phares et feux.
	cells[Vector2i(ox + length - 1, body_top + 1)] = HEADLIGHT
	cells[Vector2i(ox + length - 2, body_top + 1)] = HEADLIGHT
	cells[Vector2i(ox, body_top + 1)] = TAILLIGHT
	cells[Vector2i(ox + 1, body_top + 1)] = TAILLIGHT

	# Aileron au 2e palier.
	if tier >= 2:
		for y in range(body_top - 2, body_top):
			cells[Vector2i(ox + 3, y)] = WING
		for x in range(ox - 1, ox + 7):
			cells[Vector2i(x, body_top - 3)] = WING
		cells[Vector2i(ox - 1, body_top - 4)] = WING

	# Passages de roue puis roues (jantes dorées dès le 1er palier).
	var wheels := [ox + 0.19 * length, ox + 0.81 * length]
	for wx in wheels:
		for y in range(int(cy) - r - 2, h):
			for x in range(int(wx) - r - 2, int(wx) + r + 3):
				var d := Vector2(x + 0.5 - wx, y + 0.5 - cy).length()
				var key := Vector2i(x, y)
				if d <= r + 0.9 and cells.has(key) and y <= int(cy) + 1:
					cells[key] = ARCH
				if d <= r:
					var c := TIRE
					if d <= 0.9:
						c = HUB
					elif d <= r - 1.4:
						c = RIM_GOLD if tier >= 1 else RIM
					cells[key] = c

	# Contour sombre d'un pixel (post-traitement commun du GDD).
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for key in cells:
		var k: Vector2i = key
		if k.x >= 0 and k.y >= 0 and k.x < w and k.y < h:
			img.set_pixelv(k, cells[key])
	for y in h:
		for x in w:
			var key := Vector2i(x, y)
			if cells.has(key):
				continue
			for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if cells.has(key + n):
					img.set_pixel(x, y, OUTLINE)
					break
	_tex = ImageTexture.create_from_image(img)
	_img_size = Vector2i(w, h)
	_exhaust = Vector2(ox - 1, body_bottom - 1)


# --- Dessin -------------------------------------------------------------

func _draw() -> void:
	if _tex == null:
		return
	var floor_y := size.y * (0.74 if show_backdrop else 0.80)
	if show_backdrop:
		_draw_backdrop(floor_y)
	var cs := maxf(1.0, floor(minf(size.x / (_img_size.x + 12.0), size.y * 0.55 / _img_size.y)))
	var car_size := Vector2(_img_size) * cs
	var shake := Vector2.ZERO
	if _shake > 0.0:
		shake = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * cs * 0.6
	var pos := Vector2(round((size.x - car_size.x) * 0.5), floor_y - car_size.y + cs * 2.0) + shake

	# Plateau lumineux à la couleur de la rareté.
	var glow: Color = Palette.RARITY[rarity]
	var cx := size.x * 0.5
	for i in 6:
		var half := car_size.x * (0.62 - i * 0.07)
		var a := 0.06 + i * 0.035
		draw_rect(Rect2(cx - half, floor_y - cs + i * cs * 0.5, half * 2.0, cs * 3.0), Color(glow, a))
	draw_rect(Rect2(cx - car_size.x * 0.56, floor_y + cs, car_size.x * 1.12, cs), Color(glow, 0.55))

	# Reflet sur le sol mouillé.
	var mirror_y := pos.y + car_size.y
	draw_set_transform(Vector2(0, mirror_y * 2.0 - cs * 2.0), 0.0, Vector2(1, -1))
	draw_texture_rect(_tex, Rect2(pos, car_size), false, Color(1, 1, 1, 0.16))
	draw_set_transform(Vector2.ZERO)

	# Fumée et flamme d'échappement.
	for p in _puffs:
		var life: float = p["life"]
		var sz := cs * (2.0 + (0.9 - life) * 4.0)
		var pp: Vector2 = pos + p["p"] * cs
		draw_rect(Rect2(pp - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(0.75, 0.75, 0.78, life * 0.6))
	if _flame > 0.0 or (tier >= 3 and fmod(_time, 2.5) < 0.12):
		var fp := pos + _exhaust * cs
		draw_rect(Rect2(fp + Vector2(-cs * 3, 0), Vector2(cs * 3, cs)), Color("ff7a1a"))
		draw_rect(Rect2(fp + Vector2(-cs * 2, 0), Vector2(cs * 2, cs)), Color("ffd84a"))

	draw_texture_rect(_tex, Rect2(pos, car_size), false)


func _sky_color() -> Color:
	var hour := int(Time.get_datetime_dict_from_system()["hour"])
	if hour < 6 or hour >= 21:
		return Color("0b0d16")
	if hour < 9:
		return Color("c7774a")
	if hour < 17:
		return Color("7b858a")
	return Color("6b3550")


func _draw_backdrop(floor_y: float) -> void:
	var w := size.x
	var sky := _sky_color()
	match stage:
		0:
			# Box : béton et rideau de fer, petite fenêtre haute.
			draw_rect(Rect2(0, 0, w, floor_y), Color("2a2927"))
			draw_rect(Rect2(w * 0.08, floor_y * 0.06, w * 0.18, floor_y * 0.12), sky)
			draw_rect(Rect2(w * 0.08, floor_y * 0.06, w * 0.18, floor_y * 0.12), Color("111"), false, 2.0)
			var dx := w * 0.12
			draw_rect(Rect2(dx, floor_y * 0.22, w - dx * 2.0, floor_y * 0.78), Color("34353a"))
			var y := floor_y * 0.22
			while y < floor_y:
				draw_line(Vector2(dx, y), Vector2(w - dx, y), Color("26272b"), 2.0)
				y += 6.0
		1:
			# Atelier : briques, rideau à moitié levé sur la rue.
			draw_rect(Rect2(0, 0, w, floor_y), Color("3a2722"))
			var row := 0
			var by := 0.0
			while by < floor_y:
				var off := 0.0 if row % 2 == 0 else 9.0
				var bx := -off
				while bx < w:
					draw_rect(Rect2(bx + 1, by + 1, 16, 6), Color("4a3029"))
					bx += 18.0
				by += 8.0
				row += 1
			var dx := w * 0.14
			var top := floor_y * 0.20
			draw_rect(Rect2(dx, top, w - dx * 2.0, floor_y - top), sky.darkened(0.35))
			draw_rect(Rect2(dx, top, w - dx * 2.0, (floor_y - top) * 0.45), Color("34353a"))
			for i in 5:
				draw_rect(Rect2(dx + i * 10.0 + 4.0, floor_y - 10.0 - (i % 2) * 6.0, 9, 10 + (i % 2) * 6.0), Color("161618"))
		2:
			# Showroom : baie vitrée sur la ville.
			draw_rect(Rect2(0, 0, w, floor_y), Color("1c1b20"))
			var top := floor_y * 0.08
			draw_rect(Rect2(w * 0.05, top, w * 0.9, floor_y - top), sky)
			var bx := w * 0.05
			var i := 0
			while bx < w * 0.95:
				var bh := floor_y * (0.25 + 0.35 * fmod(i * 0.37, 1.0))
				var bw := 18.0 + (i * 7) % 14
				draw_rect(Rect2(bx, floor_y - bh, minf(bw, w * 0.95 - bx), bh), Color("0d0d11"))
				for wy in range(int(floor_y - bh + 6), int(floor_y - 4), 8):
					if (i + wy) % 3 == 0:
						draw_rect(Rect2(bx + 4, wy, 3, 3), Color("ffb347", 0.8))
				bx += bw + 3.0
				i += 1
			for mx in [0.05, 0.35, 0.65, 0.95]:
				draw_rect(Rect2(w * mx - 2.0, top, 4, floor_y - top), Color("2a2830"))
		_:
			# Hangar : tôle ondulée, grande porte ouverte.
			draw_rect(Rect2(0, 0, w, floor_y), Color("2b2d2f"))
			var x := 0.0
			while x < w:
				draw_rect(Rect2(x, 0, 3, floor_y), Color("232527"))
				x += 7.0
			var dx := w * 0.10
			draw_rect(Rect2(dx, floor_y * 0.14, w - dx * 2.0, floor_y * 0.86), sky)
			draw_rect(Rect2(dx, floor_y * 0.14, w - dx * 2.0, 6), Color("1a1b1d"))
	# Néon orange qui grésille en haut.
	var flicker := 0.55 if fmod(_time, 4.3) < 0.08 else 1.0
	draw_rect(Rect2(w * 0.2, 4, w * 0.6, 3), Color(Palette.ORANGE, 0.9 * flicker))
	draw_rect(Rect2(w * 0.15, 0, w * 0.7, 14), Color(Palette.ORANGE, 0.08 * flicker))
	# Sol sombre et mouillé.
	draw_rect(Rect2(0, floor_y, w, size.y - floor_y), Color("151517") if stage != 2 else Color("1d1d22"))
	draw_line(Vector2(0, floor_y), Vector2(w, floor_y), Color("2e2d33"), 2.0)
	if stage == 2:
		var gx := 0.0
		while gx < w:
			draw_line(Vector2(gx, floor_y), Vector2(gx - 20.0, size.y), Color("25252b"), 1.0)
			gx += 32.0

