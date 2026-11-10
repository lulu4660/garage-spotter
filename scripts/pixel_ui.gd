## Boîte à outils graphique : couleurs, polices pixel, cadres biseautés
## (9-slice générés en code) et icônes pixel art.
## DA du GDD : noir charbon et métal sombre, accents orange / rouge / or.
extends RefCounted

const SegBar = preload("res://scripts/seg_bar.gd")
const Fx = preload("res://scripts/fx.gd")

# --- Couleurs -----------------------------------------------------------

const BG := Color("121017")
const INK := Color("0b0a0e")
const TEXT := Color("f1ebe0")
const MUTED := Color("8f8a94")
const ORANGE := Color("ff7a1a")
const GOLD := Color("ffc23d")
const RED := Color("e8322f")
const MONEY := Color("7ee08a")
const RARITY: Array[Color] = [Color("a3a3a8"), Color("5fcf5f"), Color("4d8fe6"), Color("b45cf0"), Color("ff9a1f"), Color("ff3b3b")]

# --- Polices ------------------------------------------------------------
## Garage Jersey (Jersey 10 recalée) : 19 px par em, 38 en gros.
## Micro 5 : 11 px par em. À ces tailles, chaque pixel de la police tombe sur un pixel.

const SIZE_MAIN := 19
const SIZE_BIG := 38
const SIZE_SMALL := 11

static var _fonts := {}


static func font(name: String) -> FontFile:
	if _fonts.has(name):
		return _fonts[name]
	var path := "res://assets/fonts/GarageJersey-Regular.ttf" if name == "main" else "res://assets/fonts/Micro5-Regular.ttf"
	var f: FontFile = (load(path) as FontFile).duplicate()
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.generate_mipmaps = false
	_fonts[name] = f
	return f


## Applique un style de texte à un Label ou un Button.
## style : "main", "big", "small".
static func text_style(c: Control, style: String, color := TEXT, shadow := true) -> void:
	var is_small := style == "small"
	c.add_theme_font_override("font", font("small" if is_small else "main"))
	c.add_theme_font_size_override("font_size", SIZE_SMALL if is_small else (SIZE_BIG if style == "big" else SIZE_MAIN))
	c.add_theme_color_override("font_color", color)
	if shadow:
		c.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
		c.add_theme_constant_override("shadow_offset_x", 1)
		c.add_theme_constant_override("shadow_offset_y", 1)
		c.add_theme_constant_override("shadow_outline_size", 0)


static func label(text: String, style := "main", color := TEXT, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	text_style(l, style, color)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# --- Cadres et boutons en relief ------------------------------------------
## Chaque cadre est une petite image 24 × 24 générée en code puis étirée en
## 9 tranches : coins arrondis, contour sombre, reflet en haut. Les boutons ont
## une tranche visible en bas (« lip ») : enfoncés, ils descendent de 2 pixels.

const FRAMES := {
	# dessus, dessous, reflet, ombre, bordure, hauteur de tranche, couleur de tranche, descente, brillant
	"panel": ["2e2937", "211d29", "4a4358", "16131c", "", 0, "", 0, false],
	"window": ["2b2634", "1c1923", "4a4358", "121018", "5d5570", 0, "", 0, false],
	"card": ["37313f", "27222e", "575066", "18151e", "", 0, "", 0, false],
	"inset": ["110f15", "18151d", "08070b", "2a2631", "", 0, "", 0, false],
	"chip": ["25212c", "1a1720", "3f394a", "100e14", "", 0, "", 0, false],
	"button": ["5d566b", "3e3849", "8f879f", "2c2735", "", 3, "1f1b27", 0, true],
	"button_down": ["3e3849", "4b4559", "2c2735", "5d566b", "", 1, "1f1b27", 2, false],
	"orange": ["ffae45", "f06414", "ffe6ae", "c9500c", "", 3, "8a2c06", 0, true],
	"orange_down": ["e8640f", "f58a2e", "b84408", "ffb36a", "", 1, "8a2c06", 2, false],
	"gold": ["ffd95a", "e89a14", "fff3c0", "b87408", "", 3, "7a4a06", 0, true],
	"gold_down": ["e09a14", "f2b83a", "a86a06", "ffe08a", "", 1, "7a4a06", 2, false],
	"owned": ["2a2416", "17130c", "4a3c1c", "0c0a06", "ffc23d", 3, "5a4410", 0, false],
	"disabled": ["2e2a36", "25212c", "3a3543", "1b1821", "", 3, "15121a", 0, false],
	"vault": ["211c17", "120f0d", "3f3422", "08070a", "6b5218", 0, "", 0, false],
	"title": ["3d2b1c", "261b14", "6f4c22", "140e0a", "ff7a1a", 0, "", 0, false],
	"plaque": ["1c1922", "100e14", "34303d", "08070a", "3f394a", 0, "", 0, false],
	"icon": ["2f2a38", "1d1a24", "474054", "121018", "ff7a1a", 0, "", 0, false],
}
const FRAME_SIZE := 24
const FRAME_RADIUS := 3.0

static var _frame_cache := {}


static func _in_round(x: int, y: int, y0: int, y1: int) -> bool:
	if y < y0 or y >= y1:
		return false
	var p := Vector2(x + 0.5, y + 0.5)
	var c := Vector2(clampf(p.x, FRAME_RADIUS, FRAME_SIZE - FRAME_RADIUS), clampf(p.y, y0 + FRAME_RADIUS, y1 - FRAME_RADIUS))
	return p.distance_to(c) <= FRAME_RADIUS


static func frame_texture(kind: String, border_override := "") -> ImageTexture:
	var key := kind + border_override
	if _frame_cache.has(key):
		return _frame_cache[key]
	var spec: Array = FRAMES[kind]
	var n := FRAME_SIZE
	var top := Color(String(spec[0]))
	var bottom := Color(String(spec[1]))
	var hi := Color(String(spec[2]))
	var sh := Color(String(spec[3]))
	var border_hex: String = border_override if border_override != "" else spec[4]
	var has_border := border_hex != ""
	var lip: int = spec[5]
	var drop: int = spec[7]
	var relief := lip > 0 or drop > 0
	var below := (lip + 1) if relief else 0
	var y0 := drop
	var y1 := n - below
	var body := func(x: int, y: int) -> bool: return _in_round(x, y, y0, y1)
	var solid := func(x: int, y: int) -> bool: return _in_round(x, y, y0, y1) or (lip > 0 and _in_round(x, y, y0 + lip, y1 + lip))
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			if not solid.call(x, y):
				if relief and _in_round(x, y, y0 + lip + 1, y1 + lip + 1):
					img.set_pixel(x, y, Color(0, 0, 0, 0.4))
				continue
			var edge := false
			var ring := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if not solid.call(x + d.x, y + d.y):
					edge = true
				elif not solid.call(x + d.x * 2, y + d.y * 2):
					ring = true
			for d: Vector2i in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
				if not solid.call(x + d.x, y + d.y):
					ring = true
			var c: Color
			if edge:
				c = INK
			elif not body.call(x, y):
				# Tranche du bouton.
				c = Color(String(spec[6]))
				if not solid.call(x, y + 2):
					c = c.darkened(0.3)
			elif has_border and ring:
				c = Color(border_hex)
			else:
				var yb := y - y0
				var hb := y1 - y0
				var first := 2 if has_border else 1
				if yb == first:
					c = hi
				elif not body.call(x, y + 1) or (yb == hb - 2 and lip == 0):
					c = sh
				else:
					c = top.lerp(bottom, float(yb) / (hb - 1))
					if spec[8] and yb < int(hb * 0.45):
						c = c.lightened(0.10)
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_frame_cache[key] = tex
	return tex


## StyleBox 9 tranches : les coins restent nets, le dégradé s'étire.
static func frame(kind: String, pad_x := 6, pad_y := 4, border_override := "") -> StyleBoxTexture:
	var spec: Array = FRAMES[kind]
	var lip: int = spec[5]
	var drop: int = spec[7]
	var below := (lip + 1) if (lip > 0 or drop > 0) else 0
	var sb := StyleBoxTexture.new()
	sb.texture = frame_texture(kind, border_override)
	sb.set_texture_margin(SIDE_LEFT, 5)
	sb.set_texture_margin(SIDE_RIGHT, 5)
	sb.set_texture_margin(SIDE_TOP, 5 + drop)
	sb.set_texture_margin(SIDE_BOTTOM, 5 + below)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y + drop
	sb.content_margin_bottom = pad_y + below
	return sb


## Hauteur prise par le relief d'un bouton sous sa face (tranche + ombre).
const BUTTON_RELIEF := 4


static func style_button(b: Button, kind := "button", text_color := TEXT) -> void:
	var down: String = kind + "_down" if FRAMES.has(kind + "_down") else "button_down"
	b.add_theme_stylebox_override("normal", frame(kind))
	b.add_theme_stylebox_override("hover", frame(kind))
	b.add_theme_stylebox_override("pressed", frame(down))
	b.add_theme_stylebox_override("disabled", frame("disabled"))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_color_override("font_hover_color", text_color)
	b.add_theme_color_override("font_pressed_color", text_color)
	b.add_theme_color_override("font_disabled_color", MUTED.darkened(0.25))
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	b.add_theme_constant_override("shadow_offset_x", 0)
	b.add_theme_constant_override("shadow_offset_y", 1)
	b.add_theme_constant_override("h_separation", 3)
	# Boutons d'action : un reflet les traverse de temps en temps.
	b.material = Fx.material("shine") if kind in ["orange", "gold"] else null
	if not b.has_meta("juice"):
		b.set_meta("juice", true)
		# Éclair bref au clic.
		b.pressed.connect(func() -> void:
			if not is_instance_valid(b) or not b.is_inside_tree():
				return
			b.modulate = Color(1.45, 1.45, 1.45)
			b.create_tween().tween_property(b, "modulate", Color.WHITE, 0.22))


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font("main")
	t.default_font_size = SIZE_MAIN
	t.set_stylebox("normal", "Button", frame("button"))
	t.set_stylebox("hover", "Button", frame("button"))
	t.set_stylebox("pressed", "Button", frame("button_down"))
	t.set_stylebox("panel", "PopupPanel", frame("window"))
	t.set_stylebox("disabled", "Button", frame("disabled"))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", MUTED.darkened(0.25))
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", frame("panel"))
	t.set_stylebox("background", "ProgressBar", frame("inset", 0, 0))
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color("3a3942")
	grab.content_margin_left = 2
	grab.content_margin_right = 2
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	t.set_stylebox("scroll", "HScrollBar", StyleBoxEmpty.new())
	t.set_stylebox("grabber", "HScrollBar", grab)
	return t


## Jauge à segments (voir seg_bar.gd).
static func bar(color: Color, height := 6) -> SegBar:
	var p := SegBar.new()
	p.color = color
	p.custom_minimum_size = Vector2(0, height)
	return p


# --- Icônes -------------------------------------------------------------
## Chaque icône 16×16 est une liste de formes simples, rastérisées puis
## ombrées automatiquement (haut éclairé, bas sombre) et détourées d'un pixel.

const ICONS := {
	"coin": [["circle", 8, 8, 6.5, "f2b630"], ["circle", 8, 8, 4.6, "d99a1e"], ["rect", 7, 5, 9, 11, "ffe08a"]],
	"gear": [["gear", 8, 8, 7.0, 5.3, 8, 2.2, "a9adb5"]],
	"camera": [["rect", 1, 5, 15, 14, "4a4d55"], ["rect", 5, 3, 10, 5, "4a4d55"], ["circle", 8, 9.5, 3.8, "17171c"], ["circle", 8, 9.5, 2.2, "e0a050"], ["rect", 12, 6, 14, 7, "ffd34a"]],
	"garage": [["rect", 2, 7, 14, 15, "5d606a"], ["poly", [[0, 8], [8, 1], [16, 8]], "ff7a1a"], ["rect", 4, 9, 12, 15, "22232a"], ["rect", 4, 10, 12, 11, "4a4d55"], ["rect", 4, 12, 12, 13, "4a4d55"]],
	"album": [["rect", 1, 4, 10, 15, "9a9ea6"], ["rect", 5, 1, 15, 13, "f4f1ea"], ["rect", 6, 2, 14, 8, "ff7a1a"], ["rect", 6, 9, 14, 10, "7d8088"], ["rect", 6, 11, 11, 12, "7d8088"]],
	"wrench": [["line", 3, 13, 10, 6, 2.6, "c4c8cd"], ["circle", 11.5, 4.5, 3.4, "c4c8cd"], ["erase", 13.2, 2.8, 1.8]],
	"lock": [["ring", 8, 6.5, 4.2, 2.4, "bfc3c8"], ["rect", 3, 7, 13, 15, "ffc23d"], ["rect", 7, 9, 9, 13, "5a3f12"]],
	"arrow_l": [["poly", [[11, 2], [11, 14], [4, 8]], "f1ebe0"]],
	"arrow_r": [["poly", [[5, 2], [5, 14], [12, 8]], "f1ebe0"]],
	"restore": [["poly", [[8, 0], [10, 6], [16, 8], [10, 10], [8, 16], [6, 10], [0, 8], [6, 6]], "ffc23d"], ["circle", 8, 8, 1.6, "fff4c8"], ["rect", 12, 1, 14, 3, "fff4c8"]],
	"ad": [["rect", 1, 3, 15, 13, "4a4d55"], ["rect", 2, 4, 14, 12, "17171c"], ["poly", [[6, 5], [6, 11], [11, 8]], "7ee08a"]],
	"star": [["poly", [[8, 0], [10, 5], [16, 6], [11, 10], [13, 16], [8, 13], [3, 16], [5, 10], [0, 6], [6, 5]], "ffc23d"], ["circle", 8, 8, 1.6, "fff4c8"]],
	"trophy": [["ring", 3.5, 5, 3.2, 1.6, "d99a1e"], ["ring", 12.5, 5, 3.2, 1.6, "d99a1e"], ["poly", [[3, 1], [13, 1], [12, 7], [9, 10], [7, 10], [4, 7]], "ffc23d"], ["rect", 7, 10, 9, 13, "d99a1e"], ["rect", 4, 13, 12, 16, "8a6a2a"]],
	"flame": [["poly", [[8, 1], [13, 8], [12, 13], [8, 15], [4, 13], [3, 8], [6, 9]], "ff7a1a"], ["poly", [[8, 6], [11, 11], [8, 14], [5, 11]], "ffd34a"]],
	# Pièces de la voiture, dans l'ordre de Economy.PARTS.
	"part0": [["poly", [[1, 4], [9, 2], [9, 14], [1, 12]], "e8322f"], ["rect", 3, 4, 4, 12, "9a1a1a"], ["rect", 6, 3, 7, 13, "9a1a1a"], ["rect", 9, 6, 15, 10, "c4c8cd"]],
	"part1": [["rect", 1, 6, 9, 10, "7d8088"], ["rect", 9, 4, 15, 12, "c4c8cd"], ["circle", 12.2, 8, 2.3, "17171c"]],
	"part2": [["circle", 8, 8, 7.2, "26262b"], ["circle", 8, 8, 4.4, "c4c8cd"], ["circle", 8, 8, 1.6, "6b6f75"]],
	"part3": [["rect", 3, 3, 13, 13, "2b2c32"], ["rect", 4, 1, 5, 3, "c4c8cd"], ["rect", 7, 1, 8, 3, "c4c8cd"], ["rect", 10, 1, 11, 3, "c4c8cd"], ["rect", 4, 13, 5, 15, "c4c8cd"], ["rect", 7, 13, 8, 15, "c4c8cd"], ["rect", 10, 13, 11, 15, "c4c8cd"], ["rect", 6, 6, 10, 10, "4fd17a"]],
	"part4": [["circle", 9, 8, 6.2, "c4c8cd"], ["circle", 9, 8, 3.6, "7d8088"], ["circle", 9, 8, 1.4, "2b2c32"], ["rect", 1, 9, 6, 14, "c4c8cd"]],
	"part5": [["rect", 3, 12, 13, 15, "4a4d55"], ["rect", 7, 6, 9, 13, "8a8e96"], ["circle", 8, 4.5, 3.4, "2b2c32"]],
	"part6": [["poly", [[3, 14], [11, 2], [14, 3], [6, 14]], "f4f1ea"], ["line", 4, 13, 12, 3, 1.0, "bfc3c8"]],
	"part7": [["circle", 8, 8, 7.0, "b07a3a"], ["circle", 8, 8, 4.2, "c4c8cd"], ["circle", 8, 8, 1.6, "2b2c32"]],
	"part8": [["rect", 0, 4, 16, 7, "2b2c32"], ["rect", 4, 7, 6, 13, "4a4d55"], ["rect", 10, 7, 12, 13, "4a4d55"], ["rect", 0, 2, 2, 8, "ff7a1a"], ["rect", 14, 2, 16, 8, "ff7a1a"]],
	"part9": [["rect", 5, 5, 11, 15, "3f9fbf"], ["rect", 6, 2, 10, 5, "c4c8cd"], ["rect", 5, 9, 11, 11, "f4f1ea"], ["rect", 7, 1, 9, 2, "e8322f"]],
}

static var _icon_cache := {}


static func icon(name: String) -> ImageTexture:
	if _icon_cache.has(name):
		return _icon_cache[name]
	var n := 16
	var cols: Array = []
	cols.resize(n * n)
	for shape in ICONS[name]:
		_paint(cols, n, shape)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var c = cols[y * n + x]
			if c == null:
				var touches := false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var q: Vector2i = Vector2i(x, y) + d
					if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n and cols[q.y * n + q.x] != null:
						touches = true
						break
				if touches:
					img.set_pixel(x, y, INK)
				continue
			var col: Color = c
			var above = cols[(y - 1) * n + x] if y > 0 else null
			var below = cols[(y + 1) * n + x] if y < n - 1 else null
			if above == null or above != c:
				col = col.lightened(0.28)
			elif below == null or below != c:
				col = col.darkened(0.30)
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_icon_cache[name] = tex
	return tex


static func _paint(cols: Array, n: int, shape: Array) -> void:
	var kind: String = shape[0]
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var hit := false
			var color = null
			match kind:
				"rect":
					hit = x >= shape[1] and y >= shape[2] and x < shape[3] and y < shape[4]
					color = shape[5]
				"circle":
					hit = p.distance_to(Vector2(shape[1], shape[2])) <= shape[3]
					color = shape[4]
				"ring":
					var dd := p.distance_to(Vector2(shape[1], shape[2]))
					hit = dd <= shape[3] and dd >= shape[4]
					color = shape[5]
				"erase":
					hit = p.distance_to(Vector2(shape[1], shape[2])) <= shape[3]
				"line":
					var a := Vector2(shape[1], shape[2])
					var b := Vector2(shape[3], shape[4])
					var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
					hit = p.distance_to(a.lerp(b, t)) <= float(shape[5]) * 0.5
					color = shape[6]
				"poly":
					var poly := PackedVector2Array()
					for v in shape[1]:
						poly.append(Vector2(v[0], v[1]))
					hit = Geometry2D.is_point_in_polygon(p, poly)
					color = shape[2]
				"gear":
					var c := Vector2(shape[1], shape[2])
					var dd := p.distance_to(c)
					var ang := atan2(p.y - c.y, p.x - c.x)
					var tooth := fposmod(ang / TAU * float(shape[5]), 1.0) < 0.5
					var rr: float = shape[3] if tooth else shape[4]
					hit = dd <= rr and dd >= float(shape[6])
					color = shape[7]
			if hit:
				cols[y * n + x] = Color(color) if color != null else null


## Icône dans un TextureRect, à l'échelle 1 (pas de pixels étirés).
static func icon_rect(name: String) -> TextureRect:
	var t := TextureRect.new()
	t.texture = icon(name)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.custom_minimum_size = Vector2(16, 16)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static var _weave: ImageTexture


## Trame de fond 8 × 8 : fines diagonales à peine plus claires que le fond.
static func weave_texture() -> ImageTexture:
	if _weave == null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for i in 8:
			img.set_pixel(i, 7 - i, Color(1, 1, 1, 0.035))
			img.set_pixel(i, (8 - i) % 8, Color(0, 0, 0, 0.18))
		_weave = ImageTexture.create_from_image(img)
	return _weave


# --- Pastilles ------------------------------------------------------------
## Icône dans une pastille ronde en relief (22 × 22), à la couleur donnée.

const BADGE_SIZE := 22
static var _badge_cache := {}


## Couleur de pastille par icône : chaque pièce a la sienne, pour repérer d'un coup d'œil.
const BADGE_TINTS := {
	"part0": "d23a30", "part1": "8f96a3", "part2": "d9902a", "part3": "3fae5a", "part4": "3aa39a",
	"part5": "9a5cd0", "part6": "c9c2b0", "part7": "c8742a", "part8": "ff7a1a", "part9": "38a8c8",
	"coin": "c98a1a", "garage": "c8642a", "album": "b8862a", "star": "b8862a", "trophy": "b8862a",
	"restore": "b8862a", "camera": "c8642a", "wrench": "8f96a3", "lock": "5d566b", "flame": "d23a30", "ad": "3fae5a",
}


## tint transparent : couleur choisie d'après l'icône (BADGE_TINTS).
static func badge_texture(icon_name: String, tint := Color(0, 0, 0, 0)) -> ImageTexture:
	if tint.a == 0.0:
		tint = Color(String(BADGE_TINTS.get(icon_name, "5d566b")))
	var key := icon_name + tint.to_html(false)
	if _badge_cache.has(key):
		return _badge_cache[key]
	var n := BADGE_SIZE
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(n * 0.5, n * 0.5 - 0.5)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(c)
			if d <= 10.3:
				var col := tint.darkened(0.25).lerp(tint.darkened(0.6), float(y) / n)
				if d > 9.2:
					col = INK
				elif d > 8.0:
					col = tint.lightened(0.35) if y < n * 0.5 else tint.darkened(0.05)
				img.set_pixel(x, y, col)
			elif p.distance_to(c + Vector2(0, 1)) <= 10.3:
				img.set_pixel(x, y, Color(0, 0, 0, 0.4))
	var ic := icon(icon_name).get_image()
	img.blend_rect(ic, Rect2i(0, 0, 16, 16), Vector2i(3, 2))
	var tex := ImageTexture.create_from_image(img)
	_badge_cache[key] = tex
	return tex


static func badge(icon_name: String, tint := Color(0, 0, 0, 0)) -> TextureRect:
	var t := TextureRect.new()
	t.texture = badge_texture(icon_name, tint)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t
