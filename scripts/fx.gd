## Effets « HD-2D » : les objets restent en pixels nets, la lumière est
## calculée à la résolution de l'écran (halo lumineux, reflets doux, étalonnage).
## Shaders compatibles avec le rendu « Compatibility » (web, mobile).
extends RefCounted

## Post-traitement d'une zone : halo autour des zones claires (bloom),
## étalonnage chaud, ombres teintées, vignettage.
const POST := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float bloom = 0.55;
uniform float threshold = 0.6;
uniform float radius = 7.0;
uniform float vignette = 0.75;
uniform vec3 shadow_tint = vec3(0.07, 0.025, 0.06);
uniform vec3 warm = vec3(1.06, 0.98, 0.9);

// Seules les zones vraiment lumineuses (néons, phares, fenêtres) diffusent.
vec3 bright(vec2 uv) {
	vec3 c = texture(screen_tex, uv).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	return c * smoothstep(threshold, threshold + 0.25, l);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 base = texture(screen_tex, uv).rgb;
	vec3 glow = vec3(0.0);
	float total = 0.0;
	// Spirale de 24 échantillons sur deux rayons : flou large et doux.
	for (int i = 0; i < 24; i++) {
		float a = float(i) * 2.39996;
		float r = sqrt(float(i) + 0.5) / sqrt(24.0);
		vec2 o = vec2(cos(a), sin(a)) * r * radius * SCREEN_PIXEL_SIZE * 6.0;
		float w = 1.0 - r * 0.6;
		glow += bright(uv + o) * w;
		total += w;
	}
	glow /= total;
	vec3 col = base + glow * bloom * 2.2;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = col * mix(vec3(1.0), warm, smoothstep(0.2, 0.9, l));
	col += shadow_tint * (1.0 - smoothstep(0.0, 0.35, l));
	vec2 d = (UV - vec2(0.5, 0.45)) * vec2(1.0, 0.9);
	col *= 1.0 - dot(d, d) * vignette * 1.6;
	COLOR = vec4(col, 1.0);
}
"""

## Voiture : liseré de lumière sur les bords tournés vers la lumière et
## reflet qui balaie la carrosserie de temps en temps (effet showroom).
const CAR := """
shader_type canvas_item;
uniform vec3 rim_color = vec3(1.0, 0.66, 0.36);
uniform float rim = 0.55;
uniform float shine = 0.35;
uniform float period = 5.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = TEXTURE_PIXEL_SIZE;
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float body = step(0.09, lum) * c.a;
	// Bord éclairé : le pixel à 2 px vers le haut est vide (lumière du plafond).
	float up = texture(TEXTURE, UV + vec2(0.0, -2.0) * px).a;
	float left = texture(TEXTURE, UV + vec2(-2.0, -1.0) * px).a;
	float edge = body * max(1.0 - up, (1.0 - left) * 0.6);
	vec3 col = c.rgb + rim_color * edge * rim;
	// Reflet qui passe en diagonale.
	float t = fract(TIME / period);
	float band = UV.x + UV.y * 0.55 - (t * 2.6 - 0.6);
	float sweep = smoothstep(0.09, 0.0, abs(band)) * body;
	col += vec3(1.0, 0.95, 0.85) * sweep * shine;
	COLOR = vec4(col, c.a);
}
"""

## Reflet au sol : flou vertical et fondu.
const REFLECTION := """
shader_type canvas_item;
uniform float strength = 0.26;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec4 s = vec4(0.0);
	for (int i = -3; i <= 3; i++) {
		s += texture(TEXTURE, UV + vec2(float(i) * 0.6, float(i) * 1.4) * px);
	}
	s /= 7.0;
	float fade = smoothstep(0.35, 1.0, UV.y);
	COLOR = vec4(s.rgb * 0.8, s.a * strength * fade);
}
"""

## Fond de ville : flou de profondeur léger et voile de brume.
const DEPTH := """
shader_type canvas_item;
uniform float blur = 0.8;
uniform vec4 haze = vec4(0.25, 0.12, 0.2, 0.35);

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * blur;
	vec4 s = texture(TEXTURE, UV) * 0.4;
	s += texture(TEXTURE, UV + vec2(px.x, 0.0)) * 0.15;
	s += texture(TEXTURE, UV - vec2(px.x, 0.0)) * 0.15;
	s += texture(TEXTURE, UV + vec2(0.0, px.y)) * 0.15;
	s += texture(TEXTURE, UV - vec2(0.0, px.y)) * 0.15;
	vec3 col = mix(s.rgb * COLOR.rgb, haze.rgb, haze.a);
	COLOR = vec4(col, s.a * COLOR.a);
}
"""

## Sol mouillé : reflet en miroir de ce qui est au-dessus de la ligne du sol
## (néons, ville, murs), ondulé, de plus en plus flou et pâle en s'éloignant.
const MIRROR := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float floor_uv = 0.6;
uniform float strength = 0.6;
uniform float reach = 0.3;

void fragment() {
	vec2 uv = SCREEN_UV;
	float d = uv.y - floor_uv;
	if (d <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		float ripple = sin(uv.y * 340.0 + TIME * 2.4) * 0.5 + sin(uv.x * 90.0 - TIME * 1.3) * 0.5;
		vec2 ruv = vec2(uv.x + ripple * 0.0015 * (1.0 + d * 10.0), floor_uv - d * 0.9);
		vec3 c = vec3(0.0);
		float spread = 1.5 + d * 90.0;
		for (int i = -3; i <= 3; i++) {
			c += texture(screen_tex, ruv + vec2(0.0, float(i)) * SCREEN_PIXEL_SIZE * spread).rgb;
		}
		c /= 7.0;
		float fade = (1.0 - smoothstep(0.0, reach, d)) * strength;
		COLOR = vec4(c * vec3(1.0, 0.92, 0.95), fade);
	}
}
"""

static var _cache := {}


static func material(code_name: String) -> ShaderMaterial:
	var code: String = {"post": POST, "car": CAR, "reflection": REFLECTION, "depth": DEPTH, "mirror": MIRROR}[code_name]
	if not _cache.has(code_name):
		var sh := Shader.new()
		sh.code = code
		_cache[code_name] = sh
	var m := ShaderMaterial.new()
	m.shader = _cache[code_name]
	return m


static var _soft: GradientTexture2D


## Disque doux (blanc au centre, transparent au bord) pour halos, poussières, brouillard.
static func soft_dot() -> GradientTexture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.55))
		_soft = GradientTexture2D.new()
		_soft.gradient = g
		_soft.fill = GradientTexture2D.FILL_RADIAL
		_soft.fill_from = Vector2(0.5, 0.5)
		_soft.fill_to = Vector2(1.0, 0.5)
		_soft.width = 64
		_soft.height = 64
	return _soft


static func additive() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m
