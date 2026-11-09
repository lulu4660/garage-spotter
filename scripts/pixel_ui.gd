## Boîte à outils graphique : couleurs, polices pixel, cadres biseautés
## (9-slice générés en code) et icônes pixel art.
## DA du GDD : noir charbon et métal sombre, accents orange / rouge / or.
extends RefCounted

# --- Couleurs -----------------------------------------------------------

const BG := Color("0e0d12")
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


# --- Cadres biseautés ---------------------------------------------------

const FRAMES := {
	# fill_top, fill_bottom, highlight, shadow, border (bordure colorée ou vide)
	"panel": ["302f37", "1f1e24", "4b4a54", "141318", ""],
	"card": ["383741", "26252c", "565560", "17161b", ""],
	"inset": ["121116", "19181e", "0a090d", "2a2930", ""],
	"chip": ["26252c", "1b1a20", "3f3e48", "111015", ""],
	"button": ["4a4954", "2f2e36", "6b6a76", "1c1b21", ""],
	"button_down": ["2f2e36", "3a3942", "1c1b21", "4a4954", ""],
	"orange": ["ffa04a", "e05a10", "ffd59a", "8a3405", ""],
	"orange_down": ["d9580f", "f07a2a", "8a3405", "ffb36a", ""],
	"disabled": ["2a2930", "222127", "33323a", "18171c", ""],
	"icon": ["2d2c34", "1c1b21", "45444e", "121116", "ff7a1a"],
}

static var _frame_cache := {}


static func frame_texture(kind: String, border_override := "") -> ImageTexture:
	var key := kind + border_override
	if _frame_cache.has(key):
		return _frame_cache[key]
	var spec: Array = FRAMES[kind]
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var top := Color(spec[0])
	var bottom := Color(spec[1])
	var hi := Color(spec[2])
	var sh := Color(spec[3])
	var border_hex: String = border_override if border_override != "" else spec[4]
	var has_border := border_hex != ""
	var inner := 2 if has_border else 1
	for y in size:
		for x in size:
			# Coins coupés de 2 pixels.
			var cx := mini(x, size - 1 - x)
			var cy := mini(y, size - 1 - y)
			if cx + cy < 2:
				continue
			var c := top.lerp(bottom, float(y) / (size - 1))
			if cx == 0 or cy == 0 or cx + cy == 2:
				c = INK
			elif has_border and (cx == 1 or cy == 1 or cx + cy == 3):
				c = Color(border_hex)
			elif y == inner:
				c = hi
			elif y == size - 1 - inner:
				c = sh
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_frame_cache[key] = tex
	return tex


## StyleBox 9-slice : les coins restent nets, le dégradé s'étire.
static func frame(kind: String, pad_x := 6, pad_y := 4, border_override := "") -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = frame_texture(kind, border_override)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		sb.set_texture_margin(side, 5)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


static func style_button(b: Button, kind := "button", text_color := TEXT) -> void:
	var down := "orange_down" if kind == "orange" else "button_down"
	b.add_theme_stylebox_override("normal", frame(kind))
	b.add_theme_stylebox_override("hover", frame(kind))
	var pressed := frame(down)
	pressed.content_margin_top += 1
	pressed.content_margin_bottom -= 1
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", frame("disabled"))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_color_override("font_hover_color", text_color)
	b.add_theme_color_override("font_pressed_color", text_color)
	b.add_theme_color_override("font_disabled_color", MUTED.darkened(0.25))


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font("main")
	t.default_font_size = SIZE_MAIN
	t.set_stylebox("normal", "Button", frame("button"))
	t.set_stylebox("hover", "Button", frame("button"))
	t.set_stylebox("pressed", "Button", frame("button_down"))
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


## Barre de progression pixel (fond creusé, remplissage avec reflet).
static func bar(color: Color, height := 6) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.max_value = 1.0
	p.custom_minimum_size = Vector2(0, height)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("0a090d")
	bg.border_color = Color("2a2930")
	bg.border_width_bottom = 1
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.border_color = color.lightened(0.45)
	fill.border_width_top = 1
	fill.border_width_bottom = 1
	fill.set_border_color(color.lightened(0.45))
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", fill)
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
