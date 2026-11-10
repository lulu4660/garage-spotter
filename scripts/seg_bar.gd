## Jauge à segments, façon interface de jeu d'arcade : capsule creusée, cellules
## éclairées par le haut, remplissage animé, reflet qui court, éclair quand elle monte.
extends Control

const INK := Color("0b0a0e")

var color := Color("ff7a1a")
## Compatibilité avec ProgressBar : la valeur va de 0 à max_value.
var max_value := 1.0
var value := 0.0:
	set(v):
		if v > value + 0.001:
			_flash = 1.0
		value = v

var _shown := 0.0
var _flash := 0.0
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shown = _ratio()


func _ratio() -> float:
	return clampf(value / maxf(max_value, 0.0001), 0.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	_shown = lerpf(_shown, _ratio(), minf(1.0, delta * 10.0))
	_flash = maxf(0.0, _flash - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	var w := floorf(size.x)
	var h := floorf(size.y)
	if w < 8.0 or h < 5.0:
		return
	draw_rect(Rect2(1, 0, w - 2, h), INK)
	draw_rect(Rect2(0, 1, w, h - 2), INK)
	draw_rect(Rect2(1, 1, w - 2, h - 2), Color("0d0b11"))
	draw_rect(Rect2(1, h - 2, w - 2, 1), Color("2c2734"))
	var cell := 3.0
	var gap := 1.0
	var n := int((w - 4.0 + gap) / (cell + gap))
	if n <= 0:
		return
	var x0 := floorf((w - (n * (cell + gap) - gap)) * 0.5)
	var filled := _shown * n
	var glint := int(fposmod(_time * 0.55, 1.8) * n)
	for i in n:
		var r := Rect2(x0 + i * (cell + gap), 2, cell, h - 4)
		if i + 0.5 <= filled or (i == 0 and filled > 0.05):
			var c := color.lerp(color.lightened(0.3), float(i) / n)
			if i == glint:
				c = c.lightened(0.6)
			c = c.lerp(Color.WHITE, _flash * 0.6)
			draw_rect(r, c)
			draw_rect(Rect2(r.position, Vector2(cell, 1)), c.lightened(0.45))
			if h >= 7.0:
				draw_rect(Rect2(r.position.x, r.end.y - 1, cell, 1), c.darkened(0.3))
		else:
			draw_rect(r, Color("1e1a25"))
