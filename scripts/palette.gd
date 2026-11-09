## Couleurs et thème de l'interface (GDD « Direction artistique ») :
## noir charbon, accents orange / rouge / or, pas de bleu dominant.
extends RefCounted

const BG := Color("121214")
const PANEL := Color("1d1c21")
const PANEL_LIGHT := Color("2a2830")
const EDGE := Color("0a0a0c")
const ORANGE := Color("ff7a1a")
const ORANGE_DARK := Color("b84f0a")
const GOLD := Color("ffc23d")
const RED := Color("e8322f")
const TEXT := Color("ece6dc")
const MUTED := Color("8d877e")

## Couleur de rareté (voitures et pièces), du gris au rouge.
const RARITY: Array[Color] = [Color("9a9a9a"), Color("4caf50"), Color("3d7bd9"), Color("a256d6"), Color("ff8c1a"), Color("e8322f")]


static func bevel(fill: Color, border: Color = EDGE, bottom := 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.border_width_bottom = bottom
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	return sb


static func style_button(b: Button, fill: Color, font_color: Color = TEXT) -> void:
	b.add_theme_stylebox_override("normal", bevel(fill))
	b.add_theme_stylebox_override("hover", bevel(fill.lightened(0.08)))
	b.add_theme_stylebox_override("pressed", bevel(fill.darkened(0.15), EDGE, 1))
	b.add_theme_stylebox_override("disabled", bevel(fill.darkened(0.45)))
	b.add_theme_color_override("font_color", font_color)
	b.add_theme_color_override("font_hover_color", font_color)
	b.add_theme_color_override("font_pressed_color", font_color)
	b.add_theme_color_override("font_disabled_color", font_color.darkened(0.5))


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 13
	t.set_stylebox("normal", "Button", bevel(PANEL_LIGHT))
	t.set_stylebox("hover", "Button", bevel(PANEL_LIGHT.lightened(0.08)))
	t.set_stylebox("pressed", "Button", bevel(PANEL_LIGHT.darkened(0.2), EDGE, 1))
	t.set_stylebox("disabled", "Button", bevel(PANEL.darkened(0.2)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", MUTED.darkened(0.3))
	t.set_color("font_color", "Label", TEXT)
	var panel := bevel(PANEL, EDGE, 2)
	t.set_stylebox("panel", "PanelContainer", panel)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = EDGE
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = ORANGE
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = PANEL_LIGHT
	t.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("scroll", "HScrollBar", StyleBoxEmpty.new())
	t.set_stylebox("grabber", "HScrollBar", grabber)
	return t


static func chip(text_color: Color = TEXT) -> Array:
	var p := PanelContainer.new()
	var sb := bevel(PANEL, EDGE, 2)
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.add_theme_color_override("font_color", text_color)
	p.add_child(l)
	return [p, l]
