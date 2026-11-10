## Voiture sur son plateau, bloquée (silhouette grise) ou révélée.
## La mise à neuf la fait passer de l'une à l'autre pixel par pixel : un
## shader choisit, pour chaque pixel, la silhouette ou la voiture neuve selon
## la progression, avec un liseré lumineux sur le front de révélation.
extends Control

const CarRenderer = preload("res://scripts/car_renderer.gd")
const PixelUI = preload("res://scripts/pixel_ui.gd")
const Fx = preload("res://scripts/fx.gd")

## Fondu pixel par pixel en coordonnées d'écran : la silhouette (appear = false)
## disparaît exactement là où la voiture neuve (appear = true) apparaît, même si
## les deux images n'ont pas la même taille. Liseré lumineux sur le front.
const SHADER := """
shader_type canvas_item;
uniform float progress = 0.0;
uniform bool appear = true;
uniform float cell = 6.0;

float noise(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float n = noise(floor(FRAGCOORD.xy / cell)) * 0.75 + (1.0 - SCREEN_UV.x) * 0.25;
	float shown = appear ? step(n, progress) : step(progress, n);
	float edge = step(abs(n - progress), 0.045) * step(0.5, c.a) * step(0.001, progress) * step(progress, 0.999);
	COLOR = vec4(mix(c.rgb, vec3(1.0, 0.92, 0.7), edge), c.a * max(shown, edge));
}
"""

signal finished

var body := "compacte"
var model := ""
var color := Color.WHITE
var rarity := 0
var progress := 0.0:
	set(v):
		progress = v
		if _mat:
			_mat.set_shader_parameter("progress", v)
			_mat_before.set_shader_parameter("progress", v)
		queue_redraw()

var _car: TextureRect
var _before: TextureRect
var _mat: ShaderMaterial
var _mat_before: ShaderMaterial
var _scale := 2.0
var _sparks: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _glow: Control
var _time := 0.0
var _burst := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_car = TextureRect.new()
	_car.stretch_mode = TextureRect.STRETCH_KEEP
	_car.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_car.material = _mat
	_before = TextureRect.new()
	_before.stretch_mode = TextureRect.STRETCH_KEEP
	_before.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat_before = ShaderMaterial.new()
	_mat_before.shader = sh
	_mat_before.set_shader_parameter("appear", false)
	_before.material = _mat_before
	# Lumière douce derrière la voiture (additif) : halo et rayons pendant la révélation.
	_glow = Control.new()
	_glow.material = Fx.additive()
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	add_child(_before)
	add_child(_car)
	resized.connect(_layout)
	_layout()


func setup(body_type: String, car_color: Color, rarity_index: int, revealed: bool, model_id := "") -> void:
	body = body_type
	model = model_id
	color = car_color
	rarity = rarity_index
	progress = 1.0 if revealed else 0.0
	_layout()


func _layout() -> void:
	if _car == null or size.x <= 0.0:
		return
	_scale = CarRenderer.fit_scale(body, Vector2(size.x * 0.86, size.y * 0.80), 1.0, 3.0)
	# Les sprites dessinés ont deux tailles fixes (168 et 72 px) : la grande dès qu'elle tient.
	var s := maxf(_scale, 1.6) if size.x >= 190.0 else _scale
	var after: Dictionary = CarRenderer.render(body, color, 0, s, false, model)
	var before: Dictionary = CarRenderer.render(body, color, 0, s, true)
	var ground := Vector2(size.x * 0.5, size.y * 0.76)
	for pair in [[_car, after], [_before, before]]:
		var rect: TextureRect = pair[0]
		var d: Dictionary = pair[1]
		rect.texture = d["texture"]
		rect.size = Vector2(d["texture"].get_size())
		rect.position = (ground - Vector2(d["anchor"])).floor()
	_mat.set_shader_parameter("progress", progress)
	_mat_before.set_shader_parameter("progress", progress)
	queue_redraw()


## Lance la mise à neuf animée (environ 1,4 s).
func play() -> void:
	for i in 26:
		_sparks.append({"p": Vector2(_rng.randf_range(0.15, 0.85), _rng.randf_range(0.25, 0.7)), "v": Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-50, -15)), "life": _rng.randf_range(0.6, 1.4), "delay": _rng.randf_range(0.0, 1.0)})
	_burst = 1.0
	var tw := create_tween()
	tw.tween_property(self, "progress", 1.0, 1.4).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: finished.emit())


func _process(delta: float) -> void:
	_time += delta
	_burst = maxf(0.0, _burst - delta * 0.45)
	if _glow:
		_glow.queue_redraw()
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
	var c := Vector2(floorf(size.x * 0.5), floorf(size.y * 0.76))
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


func _draw_glow() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.55)
	var col: Color = PixelUI.RARITY[rarity]
	var dot := Fx.soft_dot()
	var lit := progress
	# Halo de la rareté, qui grandit avec la révélation.
	var r := Vector2(size.x * (0.35 + 0.15 * lit), size.y * (0.45 + 0.1 * lit))
	_glow.draw_texture_rect(dot, Rect2(c - r, r * 2.0), false, Color(col, 0.10 + 0.25 * lit))
	# Rayons qui tournent pendant la révélation.
	if _burst > 0.0:
		for k in 10:
			var a := TAU * k / 10.0 + _time * 0.6
			var d := Vector2(cos(a), sin(a))
			var n := Vector2(-d.y, d.x)
			var far := c + d * size.x * 0.9
			_glow.draw_polygon(PackedVector2Array([c, far + n * 14.0, far - n * 14.0]),
				PackedColorArray([Color(col.lightened(0.4), 0.35 * _burst), Color(col, 0.0), Color(col, 0.0)]))
	for s in _sparks:
		if s["delay"] > 0.0:
			continue
		var p: Vector2 = s["p"] * size
		_glow.draw_texture_rect(dot, Rect2(p - Vector2(3, 3), Vector2(6, 6)), false, Color(1.0, 0.85, 0.5, 0.6 * clampf(float(s["life"]), 0.0, 1.0)))
