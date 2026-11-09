## Voiture sur son plateau, bloquée (silhouette grise) ou révélée.
## La mise à neuf la fait passer de l'une à l'autre pixel par pixel : un
## shader choisit, pour chaque pixel, la silhouette ou la voiture neuve selon
## la progression, avec un liseré lumineux sur le front de révélation.
extends Control

const CarRenderer = preload("res://scripts/car_renderer.gd")
const PixelUI = preload("res://scripts/pixel_ui.gd")

const SHADER := """
shader_type canvas_item;
uniform sampler2D locked_tex : filter_nearest;
uniform float progress = 0.0;

float noise(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
	float n = noise(px) * 0.75 + (1.0 - UV.x) * 0.25;
	vec4 before = texture(locked_tex, UV);
	vec4 after = texture(TEXTURE, UV);
	vec4 c = n < progress ? after : before;
	if (abs(n - progress) < 0.045 && max(before.a, after.a) > 0.5) {
		c = vec4(1.0, 0.92, 0.7, 1.0);
	}
	COLOR = c;
}
"""

signal finished

var body := "compacte"
var color := Color.WHITE
var rarity := 0
var progress := 0.0:
	set(v):
		progress = v
		if _mat:
			_mat.set_shader_parameter("progress", v)
		queue_redraw()

var _car: TextureRect
var _mat: ShaderMaterial
var _scale := 2.0
var _sparks: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_car = TextureRect.new()
	_car.stretch_mode = TextureRect.STRETCH_KEEP
	_car.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_car.material = _mat
	add_child(_car)
	resized.connect(_layout)
	_layout()


func setup(body_type: String, car_color: Color, rarity_index: int, revealed: bool) -> void:
	body = body_type
	color = car_color
	rarity = rarity_index
	progress = 1.0 if revealed else 0.0
	_layout()


func _layout() -> void:
	if _car == null or size.x <= 0.0:
		return
	_scale = CarRenderer.fit_scale(body, Vector2(size.x * 0.86, size.y * 0.80), 1.0, 3.0)
	var after: Dictionary = CarRenderer.render(body, color, 0, _scale)
	var before: Dictionary = CarRenderer.render(body, color, 0, _scale, true)
	_car.texture = after["texture"]
	_mat.set_shader_parameter("locked_tex", before["texture"])
	_mat.set_shader_parameter("progress", progress)
	var tsize := Vector2(after["texture"].get_size())
	var anchor: Vector2 = after["anchor"]
	_car.size = tsize
	_car.position = (Vector2(size.x * 0.5, size.y * 0.66) - anchor).floor()
	queue_redraw()


## Lance la mise à neuf animée (environ 1,4 s).
func play() -> void:
	for i in 26:
		_sparks.append({"p": Vector2(_rng.randf_range(0.15, 0.85), _rng.randf_range(0.25, 0.7)), "v": Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-50, -15)), "life": _rng.randf_range(0.6, 1.4), "delay": _rng.randf_range(0.0, 1.0)})
	var tw := create_tween()
	tw.tween_property(self, "progress", 1.0, 1.4).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: finished.emit())


func _process(delta: float) -> void:
	if _sparks.is_empty():
		return
	for s in _sparks:
		if s["delay"] > 0.0:
			s["delay"] -= delta
			continue
		s["p"] += s["v"] * delta / maxf(size.x, 1.0)
		s["life"] -= delta
	_sparks = _sparks.filter(func(s: Dictionary) -> bool: return s["life"] > 0.0)
	queue_redraw()


func _draw() -> void:
	# Plateau : halo à la couleur de la rareté une fois révélée, gris avant.
	var glow: Color = PixelUI.RARITY[rarity].lerp(Color("55565c"), 1.0 - progress)
	var c := Vector2(floorf(size.x * 0.5), floorf(size.y * 0.66))
	var rx := floorf(size.x * 0.42)
	var ry := floorf(size.y * 0.13)
	for g in 3:
		var halo := PackedVector2Array()
		for k in 24:
			var t := TAU * k / 24.0
			halo.append(c + Vector2(cos(t) * (rx + 3 + g * 4), sin(t) * (ry + 2 + g * 2) + 2))
		draw_colored_polygon(halo, Color(glow, 0.08 - g * 0.02))
	var top := PackedVector2Array()
	for k in 24:
		var t := TAU * k / 24.0
		top.append((c + Vector2(cos(t) * rx, sin(t) * ry)).floor())
	draw_colored_polygon(top, Color("24232a"))
	for k in 24:
		var t0 := TAU * k / 24.0
		var t1 := TAU * (k + 1) / 24.0
		if sin(t0) > -0.2:
			draw_line((c + Vector2(cos(t0) * rx, sin(t0) * ry)).floor(), (c + Vector2(cos(t1) * rx, sin(t1) * ry)).floor(), glow, 1.0)
	for s in _sparks:
		if s["delay"] > 0.0:
			continue
		var p: Vector2 = (s["p"] * size).floor()
		var col := Color("fff2c8") if s["life"] > 0.4 else PixelUI.RARITY[rarity]
		draw_rect(Rect2(p, Vector2(1, 1)), col)
		if s["life"] > 0.8:
			draw_rect(Rect2(p + Vector2(-1, 0), Vector2(3, 1)), Color(col, 0.5))
