## La ville : la map peinte (assets/map/day.png), éclairée selon l'heure réelle
## et la météo, avec les bâtiments du joueur et les voitures des clients qui
## partent vers l'autoroute.
##
## Couches, de l'arrière vers l'avant :
## 1. la map, passée dans un shader : teinte du jour (aube et crépuscule
##    dorés), ombres de nuages, nuit (ambiance bleue + lumières de la carte
##    light.png qui s'allument une à une), sol mouillé, brouillard ;
## 2. les voitures (pixels nets), phares et feux la nuit ;
## 3. lumières additives douces : halos des lampadaires et des vitrines,
##    faisceaux des phares ;
## 4. pluie, puis étiquettes des bâtiments.
extends Control

const PixelUI = preload("res://scripts/pixel_ui.gd")
const Fx = preload("res://scripts/fx.gd")
const DAY := preload("res://assets/map/day.png")
const LIGHT := preload("res://assets/map/light.png")
const FRONT := preload("res://assets/map/front.png")
## Petites voitures des clients (tools/map/make_cars.py) : une rangée par modèle, une colonne par direction.
const CARS := preload("res://assets/map/cars.png")
const CARS_PAINT := preload("res://assets/map/cars_paint.png")
const DIR_COL := {"ne": 0, "se": 1, "sw": 2, "nw": 3}

## Voitures : la peinture grise de l'atlas prend la couleur passée en modulate,
## et tout s'assombrit la nuit comme la ville.
const CAR_SHADER := """
shader_type canvas_item;
uniform sampler2D paint_tex : filter_nearest;
uniform vec3 ambient = vec3(0.296, 0.3, 0.427);
uniform float night = 0.0;
varying vec4 tint;
void vertex() { tint = COLOR; }
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float g = dot(c.rgb, vec3(0.3333));
	vec3 col = mix(c.rgb, tint.rgb * g * 2.0, step(0.5, texture(paint_tex, UV).r));
	col *= mix(vec3(1.0), ambient * 1.25, night);
	COLOR = vec4(col, c.a);
}
"""

signal building_tapped(stage: int)

## Bâtiments du joueur, dans l'ordre des étapes : zone touchable et porte (coordonnées de la map).
const BUILDINGS := [
	{"rect": Rect2(160, 900, 150, 92), "door": Vector2(226, 976)},
	{"rect": Rect2(497, 748, 160, 112), "door": Vector2(548, 858)},
	{"rect": Rect2(352, 688, 160, 136), "door": Vector2(402, 836)},
	{"rect": Rect2(365, 288, 262, 132), "door": Vector2(526, 388)},
]
## Chemins des clients jusqu'à la bretelle de l'autoroute, puis l'autoroute vers la droite.
const ROUTES := [
	[Vector2(226, 976), Vector2(268, 956), Vector2(318, 916), Vector2(334, 860), Vector2(343, 792)],
	[Vector2(548, 858), Vector2(500, 866), Vector2(455, 852), Vector2(402, 838), Vector2(360, 816), Vector2(343, 792)],
	[Vector2(402, 836), Vector2(360, 816), Vector2(343, 792)],
	[Vector2(526, 388), Vector2(560, 412), Vector2(640, 440), Vector2(700, 462), Vector2(830, 500)],
]
const TO_RAMP := [Vector2(350, 760), Vector2(366, 716), Vector2(420, 698), Vector2(470, 690), Vector2(494, 662),
	Vector2(510, 630), Vector2(540, 604), Vector2(600, 545), Vector2(628, 514)]
const HIGHWAY_END := Vector2(900, 378)

const SHADER := """
shader_type canvas_item;
uniform sampler2D light_tex : filter_nearest;
uniform vec3 ambient = vec3(0.296, 0.3, 0.427);
uniform vec2 map_size = vec2(719.0, 1288.0);
uniform float night = 0.0;
uniform float warm = 0.0;
uniform float lamps = 0.0;
uniform float wet = 0.0;
uniform float fog = 0.0;
uniform float clouds = 0.0;
uniform float t = 0.0;
uniform sampler2D mask_tex : filter_nearest;
uniform bool masked = false;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return noise(p) * 0.55 + noise(p * 2.1) * 0.3 + noise(p * 4.3) * 0.15; }

void fragment() {
	vec3 day = texture(TEXTURE, UV).rgb;
	vec2 p = floor(UV * map_size);
	// Jour : lumière dorée à l'aube et au crépuscule, ombres de nuages qui défilent.
	vec3 lit = day * mix(vec3(1.0), vec3(1.14, 0.94, 0.76), warm);
	float cl = smoothstep(0.48, 0.72, fbm(p / 170.0 + vec2(t * 0.006, t * 0.0025)));
	lit *= 1.0 - cl * clouds * 0.32;
	// Nuit : ambiance bleue, puis les lumières de la ville s'allument par petits blocs.
	vec3 col = mix(lit, day * ambient, night);
	float on = step(hash(floor(p / 5.0)), lamps);
	col += texture(light_tex, UV).rgb * on * smoothstep(0.15, 0.85, night);
	// Pluie : sol plus sombre et plus froid ; brouillard : voile clair le jour, sombre la nuit.
	col *= mix(vec3(1.0), vec3(0.84, 0.87, 0.94), wet);
	vec3 haze = mix(vec3(0.78, 0.78, 0.8), vec3(0.11, 0.11, 0.17), night);
	col = mix(col, haze, fog * 0.42);
	COLOR = vec4(col, masked ? step(0.5, texture(mask_tex, UV).r) : 1.0);
}
"""

## Heure forcée (captures, tests) : -1 = heure réelle.
var debug_hour := -1.0
## Météo forcée : "" = au hasard, sinon "clear", "clouds", "rain" ou "fog".
var debug_weather := ""
var stage := 0
## Couleurs des voitures des clients (celles de la collection du joueur).
var car_colors: Array[Color] = [Color("c8202a"), Color("2f6fd1"), Color("e3c84a"), Color("e8e4dc"), Color("4a4d52")]

var _map: TextureRect
var _mat: ShaderMaterial
## Copie de la map limitée aux bâtiments d'avant-plan, dessinée par-dessus les voitures.
var _front: TextureRect
var _front_mat: ShaderMaterial
var _cars_layer: Control
var _car_mat: ShaderMaterial
var _shadows: Control
var _car_cell := Vector2(32, 26)
var _glow: Control
var _rain_layer: Control
var _tags: Array[PanelContainer] = []
var _cam := Vector2.ZERO
var _cam_target := Vector2.ZERO
var _drag_from := Vector2.ZERO
var _dragging := false
var _drag_moved := 0.0
var _time := 0.0
var _cars: Array[Dictionary] = []
var _lamps: Array = []
var _rain: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _night := 0.0
var _lamps_on := 0.0
var _weather := {"clouds": 0.0, "rain": 0.0, "fog": 0.0}


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rng.randomize()
	_map = TextureRect.new()
	_map.texture = DAY
	_map.size = Vector2(DAY.get_size())
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("light_tex", LIGHT)
	_mat.set_shader_parameter("map_size", Vector2(DAY.get_size()))
	var info: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map/lamps.json"))
	if typeof(info) == TYPE_DICTIONARY:
		var a: Array = info["ambient"]
		_mat.set_shader_parameter("ambient", Vector3(a[0], a[1], a[2]))
		for l in info["lamps"]:
			if int(l[2]) >= 10:
				_lamps.append(l)
	_map.material = _mat
	add_child(_map)
	_cars_layer = Control.new()
	_cars_layer.draw.connect(_draw_cars)
	var csh := Shader.new()
	csh.code = CAR_SHADER
	_car_mat = ShaderMaterial.new()
	_car_mat.shader = csh
	_car_mat.set_shader_parameter("paint_tex", CARS_PAINT)
	_cars_layer.material = _car_mat
	_shadows = Control.new()
	_shadows.draw.connect(_draw_shadows)
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map/cars.json"))
	if typeof(meta) == TYPE_DICTIONARY:
		_car_cell = Vector2(meta["cell"][0], meta["cell"][1])
	_front = TextureRect.new()
	_front.texture = DAY
	_front.size = _map.size
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front_mat = _mat.duplicate()
	_front_mat.set_shader_parameter("mask_tex", FRONT)
	_front_mat.set_shader_parameter("masked", true)
	_front.material = _front_mat
	_glow = Control.new()
	_glow.material = Fx.additive()
	_glow.draw.connect(_draw_glow)
	_rain_layer = Control.new()
	_rain_layer.draw.connect(_draw_rain)
	for c: Control in [_shadows, _cars_layer, _glow, _rain_layer]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(c)
		if c == _cars_layer:
			add_child(_front)
	for i in BUILDINGS.size():
		var tag := PanelContainer.new()
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := PixelUI.ink_label("", "small")
		tag.add_child(l)
		add_child(tag)
		_tags.append(tag)
	for i in 90:
		_rain.append({"p": Vector2(_rng.randf(), _rng.randf()), "sp": _rng.randf_range(0.9, 1.4), "l": _rng.randf_range(4, 8)})
	# La taille n'est connue qu'après la mise en page : on recentre à chaque changement.
	resized.connect(func() -> void: set_stage(stage, true))
	set_stage(stage, true)


## Étape du joueur : la caméra se recentre sur son bâtiment.
func set_stage(s: int, instant := false) -> void:
	stage = clampi(s, 0, BUILDINGS.size() - 1)
	var b: Rect2 = BUILDINGS[stage]["rect"]
	_cam_target = _clamp_cam(b.get_center() - Vector2(size.x * 0.5, size.y * 0.55))
	if instant:
		_cam = _cam_target
	_refresh_tags()


## Un appui sur le bouton : count clients sortent du bâtiment, l'un après l'autre.
func spawn(count: int) -> void:
	var route: Array = ROUTES[stage]
	var path: Array[Vector2] = []
	for p in route:
		path.append(p)
	if stage < 3:
		for p in TO_RAMP:
			path.append(p)
		path.append(HIGHWAY_END)
	# Les voitures sortent l'une après l'autre, à la suite de celles qui attendent déjà.
	var queued := 0.0
	for c in _cars:
		queued = maxf(queued, float(c["delay"]))
	for i in mini(count, 12):
		if _cars.size() >= 40:
			break
		var lane := Vector2(0, _rng.randi_range(-1, 1))
		_cars.append({"path": path, "seg": 0, "pos": path[0] + lane, "lane": lane, "delay": queued + 0.32 * (i + 1), "speed": 0.0, "model": _rng.randi() % 2,
			"color": car_colors[_rng.randi() % car_colors.size()]})


func _clamp_cam(c: Vector2) -> Vector2:
	var lim := Vector2(DAY.get_size()) - size
	return Vector2(clampf(c.x, 0.0, maxf(0.0, lim.x)), clampf(c.y, 0.0, maxf(0.0, lim.y)))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_moved = 0.0
			_drag_from = event.position
		else:
			_dragging = false
			if _drag_moved < 6.0:
				_tap(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var d: Vector2 = event.position - _drag_from
		_drag_from = event.position
		_drag_moved += d.length()
		_cam = _clamp_cam(_cam - d)
		_cam_target = _cam
		accept_event()


func _tap(pos: Vector2) -> void:
	var p := pos + _cam
	for i in BUILDINGS.size():
		if (BUILDINGS[i]["rect"] as Rect2).has_point(p) and i <= stage:
			building_tapped.emit(i)
			return


# --- Heure et météo -------------------------------------------------------

func _hour() -> float:
	if debug_hour >= 0.0:
		return debug_hour
	var t := Time.get_time_dict_from_system()
	return float(t["hour"]) + float(t["minute"]) / 60.0


## Météo de la demi-heure en cours : tirée au hasard, mais la même pour tous
## pendant 30 minutes (graine = numéro de la demi-heure).
func _target_weather() -> Dictionary:
	var kind := debug_weather
	if kind == "":
		var r := RandomNumberGenerator.new()
		r.seed = int(Time.get_unix_time_from_system() / 1800.0)
		var x := r.randf()
		kind = "clear" if x < 0.45 else ("clouds" if x < 0.7 else ("rain" if x < 0.88 else "fog"))
	match kind:
		"clouds":
			return {"clouds": 1.0, "rain": 0.0, "fog": 0.0}
		"rain":
			return {"clouds": 1.0, "rain": 1.0, "fog": 0.15}
		"fog":
			return {"clouds": 0.4, "rain": 0.0, "fog": 1.0}
	return {"clouds": 0.25, "rain": 0.0, "fog": 0.0}


func _process(delta: float) -> void:
	_time += delta
	if not _dragging:
		_cam = _cam.lerp(_cam_target, minf(1.0, delta * 4.0))
	var cam := _cam.round()
	_map.position = -cam
	_front.position = -cam
	var h := _hour()
	# Nuit de 20 h 30 à 5 h 30, transitions d'une heure et demie à deux heures.
	_night = 1.0 - clampf((h - 5.5) / 2.0, 0.0, 1.0) + clampf((h - 18.5) / 2.0, 0.0, 1.0)
	_night = clampf(_night, 0.0, 1.0)
	var warm := maxf(1.0 - absf(h - 7.0) / 1.6, 1.0 - absf(h - 19.0) / 1.8)
	# Les lumières s'allument une à une au crépuscule.
	_lamps_on = smoothstep(0.15, 0.75, _night)
	var target := _target_weather()
	for k: String in _weather:
		_weather[k] = lerpf(float(_weather[k]), float(target[k]), minf(1.0, delta * 0.3))
	for m: ShaderMaterial in [_mat, _front_mat]:
		_set_light(m, warm)
	_move_cars(delta)
	for r in _rain:
		r["p"].y += r["sp"] * delta * 1.8
		if r["p"].y > 1.0:
			r["p"] = Vector2(_rng.randf(), 0.0)
	_place_tags()
	_car_mat.set_shader_parameter("night", _night)
	_shadows.queue_redraw()
	_cars_layer.queue_redraw()
	_glow.queue_redraw()
	_rain_layer.queue_redraw()


func _set_light(m: ShaderMaterial, warm: float) -> void:
	m.set_shader_parameter("night", _night)
	m.set_shader_parameter("warm", clampf(warm, 0.0, 1.0) * (1.0 - _weather["clouds"] * 0.5))
	m.set_shader_parameter("lamps", _lamps_on)
	m.set_shader_parameter("clouds", _weather["clouds"] * (1.0 - _night))
	m.set_shader_parameter("wet", _weather["rain"])
	m.set_shader_parameter("fog", _weather["fog"])
	m.set_shader_parameter("t", _time)


# --- Voitures des clients ---------------------------------------------------

func _move_cars(delta: float) -> void:
	for c in _cars:
		if c["delay"] > 0.0:
			c["delay"] -= delta
			continue
		var path: Array = c["path"]
		var on_highway: bool = c["seg"] >= path.size() - 2 and stage < 3
		var top := 260.0 if on_highway else 70.0
		c["speed"] = minf(top, float(c["speed"]) + delta * (300.0 if on_highway else 140.0))
		var step: float = c["speed"] * delta
		while step > 0.0 and c["seg"] < path.size() - 1:
			var to: Vector2 = path[c["seg"] + 1] + c["lane"]
			var d: Vector2 = to - c["pos"]
			if d.length() <= step:
				c["pos"] = to
				c["seg"] += 1
				step -= d.length()
			else:
				c["pos"] += d.normalized() * step
				c["dir"] = d.normalized()
				step = 0.0
	_cars = _cars.filter(func(c: Dictionary) -> bool: return c["seg"] < c["path"].size() - 1)


## Direction de l'atlas la plus proche du mouvement (les rues de la map suivent les diagonales).
func _dir_name(dir: Vector2) -> String:
	if dir.x >= 0.0:
		return "ne" if dir.y < 0.0 else "se"
	return "nw" if dir.y < 0.0 else "sw"


func _draw_car(at: Vector2, dir: Vector2, col: Color, model: int) -> void:
	var src := Rect2(Vector2(DIR_COL[_dir_name(dir)], model) * _car_cell, _car_cell)
	var pos := (at - Vector2(_car_cell.x * 0.5, _car_cell.y - 3.0)).round()
	_cars_layer.draw_texture_rect_region(CARS, Rect2(pos, _car_cell), src, col)


## Ombres douces sous les voitures (couche à part : le shader des voitures ne s'y applique pas).
func _draw_shadows() -> void:
	var cam := _cam.round()
	var dot := Fx.soft_dot()
	for c in _cars:
		if c["delay"] > 0.0:
			continue
		var p: Vector2 = c["pos"] - cam
		_shadows.draw_texture_rect(dot, Rect2(p - Vector2(13, 5), Vector2(26, 10)), false, Color(0, 0, 0, 0.45))


func _draw_cars() -> void:
	var cam := _cam.round()
	var visible: Array = []
	for c in _cars:
		if c["delay"] <= 0.0:
			visible.append(c)
	visible.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["pos"].y < b["pos"].y)
	for c in visible:
		_draw_car(c["pos"] - cam, c.get("dir", Vector2(1, -0.5)), c["color"], int(c["model"]))


func _draw_glow() -> void:
	var cam := _cam.round()
	var dot := Fx.soft_dot()
	var view := Rect2(Vector2(-40, -40), size + Vector2(80, 80))
	if _lamps_on > 0.0:
		for l in _lamps:
			var p := Vector2(l[0], l[1]) - cam
			if not view.has_point(p):
				continue
			# Même tirage que le shader n'est pas nécessaire : un halo s'allume avec le crépuscule.
			var col: Array = l[3]
			var r := 5.0 + sqrt(float(l[2])) * 1.4
			var tw := 0.9 + 0.1 * sin(_time * 2.0 + float(l[0]))
			_glow.draw_texture_rect(dot, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(col[0], col[1], col[2], 0.22 * _lamps_on * tw))
	if _night > 0.3:
		for c in _cars:
			if c["delay"] > 0.0:
				continue
			var p: Vector2 = c["pos"] - cam
			var dir: Vector2 = c.get("dir", Vector2(1, -0.5))
			_glow.draw_texture_rect(dot, Rect2(p + dir * 9.0 - Vector2(7, 5), Vector2(14, 10)), false, Color(1.0, 0.92, 0.7, 0.45 * _night))


func _draw_rain() -> void:
	var a: float = _weather["rain"]
	if a < 0.05:
		return
	for r in _rain:
		var p := Vector2(r["p"].x * size.x, r["p"].y * size.y)
		var l: float = r["l"]
		_rain_layer.draw_line(p, p + Vector2(-l * 0.3, l), Color(0.8, 0.82, 0.92, 0.35 * a), 1.0)


# --- Étiquettes des bâtiments -------------------------------------------------

func _refresh_tags() -> void:
	for i in _tags.size():
		var tag := _tags[i]
		var l: Label = tag.get_child(0)
		var names := ["BOX", "ATELIER", "SHOWROOM", "HANGAR"]
		if i == stage:
			l.text = names[i]
			tag.add_theme_stylebox_override("panel", PixelUI.frame("title", 4, 0))
		elif i < stage:
			l.text = names[i]
			tag.add_theme_stylebox_override("panel", PixelUI.frame("plaque", 4, 0, "8f8a94"))
		else:
			l.text = "?"
			tag.add_theme_stylebox_override("panel", PixelUI.frame("plaque", 4, 0, "4a4358"))
		tag.reset_size()


func _place_tags() -> void:
	var cam := _cam.round()
	for i in _tags.size():
		var b: Rect2 = BUILDINGS[i]["rect"]
		var tag := _tags[i]
		var bob := roundf(sin(_time * 3.0) * 1.5) if i == stage else 0.0
		tag.position = (Vector2(b.get_center().x, b.position.y) - cam - Vector2(tag.size.x * 0.5, tag.size.y + 2.0 - bob)).round()
