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


## Texte sombre sans ombre, pour les bandeaux de couleur vive.
static func ink_label(text: String, style := "main") -> Label:
	var l := label(text, style, INK)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	return l


# --- Cadres et boutons ------------------------------------------------------
## Style « course de rue » : aplats nets, formes inclinées (parallélogrammes),
## coins coupés, une tranche sombre sous les boutons. Tout est dessiné sans
## lissage : les bords inclinés restent en marches de pixels.

const SKEW := 0.16
const FRAMES := {
	# fond, bordure, largeurs [gauche, haut, droite, bas], incliné, coins coupés [hg, hd, bd, bg]
	"panel": ["17141d", "2c2734", [0, 0, 0, 1], false, [0, 0, 0, 0]],
	"window": ["15121b", "4a4358", [1, 1, 1, 1], false, [0, 10, 0, 10]],
	"card": ["231f2b", "4a4358", [3, 0, 0, 0], false, [0, 0, 7, 0]],
	"inset": ["0c0a10", "2c2734", [1, 1, 1, 1], false, [0, 0, 0, 0]],
	"chip": ["262230", "0f0d13", [0, 0, 0, 2], true, [0, 0, 0, 0]],
	"button": ["4b4459", "292431", [0, 0, 0, 3], true, [0, 0, 0, 0]],
	"button_down": ["3a3446", "292431", [0, 0, 0, 1], true, [0, 0, 0, 0]],
	"orange": ["ff7a1a", "b0400a", [0, 0, 0, 3], true, [0, 0, 0, 0]],
	"orange_down": ["e2620c", "b0400a", [0, 0, 0, 1], true, [0, 0, 0, 0]],
	"gold": ["ffc23d", "a87408", [0, 0, 0, 3], true, [0, 0, 0, 0]],
	"gold_down": ["e0a520", "a87408", [0, 0, 0, 1], true, [0, 0, 0, 0]],
	"owned": ["2a2416", "ffc23d", [1, 1, 1, 3], true, [0, 0, 0, 0]],
	"disabled": ["2a2631", "19161f", [0, 0, 0, 3], true, [0, 0, 0, 0]],
	"vault": ["15121b", "ffc23d", [3, 0, 0, 0], false, [0, 0, 9, 0]],
	"title": ["ff7a1a", "b0400a", [0, 0, 0, 2], true, [0, 0, 0, 0]],
	"plaque": ["a3a3a8", "0b0a0e", [0, 0, 0, 2], true, [0, 0, 0, 0]],
	"tag": ["7ee08a", "2f7a3c", [0, 0, 0, 2], true, [0, 0, 0, 0]],
	"icon": ["1d1a24", "ff7a1a", [2, 2, 2, 2], false, [0, 6, 0, 6]],
}


## Cadre d'un type donné. color_override remplace la couleur d'accent : la
## bordure, ou le fond pour les bandeaux pleins (plaque, tag).
static func frame(kind: String, pad_x := 6, pad_y := 4, color_override := "") -> StyleBoxFlat:
	var spec: Array = FRAMES[kind]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(String(spec[0]))
	sb.border_color = Color(String(spec[1]))
	if color_override != "":
		if kind in ["plaque", "tag"]:
			sb.bg_color = Color(color_override)
			sb.border_color = Color(color_override).darkened(0.5)
		else:
			sb.border_color = Color(color_override)
	var widths: Array = spec[2]
	sb.border_width_left = widths[0]
	sb.border_width_top = widths[1]
	sb.border_width_right = widths[2]
	sb.border_width_bottom = widths[3]
	sb.anti_aliasing = false
	sb.corner_detail = 1
	var cuts: Array = spec[4]
	sb.corner_radius_top_left = cuts[0]
	sb.corner_radius_top_right = cuts[1]
	sb.corner_radius_bottom_right = cuts[2]
	sb.corner_radius_bottom_left = cuts[3]
	var lean := 0
	if spec[3]:
		sb.skew = Vector2(SKEW, 0)
		lean = 2
	var down := kind.ends_with("_down")
	if down:
		# Enfoncé : la face descend de 2 pixels.
		sb.expand_margin_top = -2
	sb.content_margin_left = pad_x + lean + int(widths[0])
	sb.content_margin_right = pad_x + lean
	sb.content_margin_top = pad_y + (2 if down else 0)
	sb.content_margin_bottom = pad_y + (1 if down else int(widths[3]))
	return sb


## Hauteur de la tranche sombre sous la face d'un bouton.
const BUTTON_RELIEF := 3
const BRIGHT_KINDS: Array[String] = ["orange", "gold"]


static func style_button(b: Button, kind := "button", text_color := TEXT) -> void:
	var down: String = kind + "_down" if FRAMES.has(kind + "_down") else "button_down"
	var bright := kind in BRIGHT_KINDS
	if bright:
		# Texte sombre sur aplat vif, sans ombre.
		text_color = INK
	b.add_theme_stylebox_override("normal", frame(kind))
	b.add_theme_stylebox_override("hover", frame(kind))
	b.add_theme_stylebox_override("pressed", frame(down))
	b.add_theme_stylebox_override("disabled", frame("disabled"))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", text_color)
	b.add_theme_color_override("font_hover_color", text_color)
	b.add_theme_color_override("font_pressed_color", text_color)
	b.add_theme_color_override("font_disabled_color", MUTED.darkened(0.25))
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.0 if bright else 0.55))
	b.add_theme_constant_override("shadow_offset_x", 0)
	b.add_theme_constant_override("shadow_offset_y", 1)
	b.add_theme_constant_override("h_separation", 3)
	# Boutons d'action : un reflet les traverse de temps en temps.
	b.material = Fx.material("shine") if bright else null
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
