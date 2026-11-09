## Rendu des voitures en pixel art.
##
## Chaque carrosserie est décrite par son profil (vue de côté) et sa largeur,
## extrudée en volume, puis rastérisée sur le CPU en vue 3/4 avant fixe :
## tampon de profondeur, ombrage en 5 paliers par matériau, reflets sur les
## vitres, liseré de lumière sur les arêtes et contour sombre d'un pixel.
## Le jeu n'affiche que l'image obtenue : pas de 3D ni de rotation à l'écran.
## Les images sont mises en cache par (carrosserie, couleur, palier, échelle).
extends RefCounted

## Direction vers la caméra : on voit l'avant (+x), le dessus et le flanc z = 0.
const EYE := Vector3(0.55, 0.42, -0.85)
## Direction vers la lumière : du dessus, un peu de face.
const LIGHT := Vector3(0.30, 1.0, -0.42)

enum Mat { NONE, BODY, GLASS, TRIM, TIRE, RIM, LAMP, CALIPER, SHADOW }

const OUTLINE := Color("0d0b12")
const SHADOW := Color(0.0, 0.0, 0.0, 0.5)
const RAMPS := {
	Mat.GLASS: ["0f1217", "171d26", "222b36", "3a4757", "6a7d90"],
	Mat.TRIM: ["0b0b0d", "131316", "1c1c21", "29292f", "3d3d45"],
	Mat.TIRE: ["09090a", "111113", "19191c", "242428", "303035"],
	Mat.RIM: ["34363a", "62666c", "92969d", "bfc3c8", "e9ecef"],
	Mat.LAMP: ["8a7f62", "cfc3a0", "f3ead0", "fffaf0", "ffffff"],
	Mat.CALIPER: ["4a0d0d", "7c1515", "b52020", "e04040", "ff8a7a"],
}
const RIM_GOLD: Array[String] = ["4f370f", "86601d", "b88e33", "dfba5a", "fbe7a2"]
const RIM_DARK: Array[String] = ["111114", "1f2024", "34363c", "50535a", "7a7e86"]

## Profils (unités ≈ pixels à l'échelle 1). x : de l'arrière (0) à l'avant (len),
## y : hauteur. « upper » parcourt le haut de la caisse de l'avant vers l'arrière
## (le 2e point est le haut du pare-chocs) ; « cabin » est l'habitacle : base
## arrière, base avant, haut du pare-brise, haut de lunette, bas de lunette.
## Options : open (décapotée, « seats » = x des sièges), bed (benne [x0, x1]),
## panel (fourgon tôlé), pillars (montants en plus), wing (aileron possible).
const BODIES := {
	"citadine": {
		"len": 48.0, "w": 25.0, "r": 5.8, "axles": [9.0, 39.0], "yb": 3.0,
		"upper": [[48, 5], [48, 10], [46.5, 12.6], [42.5, 14.2], [38, 15.0], [2, 16.0], [0.5, 15.0], [0, 5.5]],
		"cabin": [[2.5, 15.8], [38, 15.0], [30, 27.0], [5, 27.4], [1.5, 19.0]],
	},
	"compacte": {
		"len": 62.0, "w": 27.0, "r": 6.4, "axles": [12.0, 49.5], "yb": 3.0,
		"upper": [[62, 5], [62, 9.5], [60.5, 12.5], [56, 13.8], [46, 15.0], [5, 16.0], [1.5, 15.5], [0, 12], [0, 5.5]],
		"cabin": [[4, 15.6], [46, 15.0], [34, 24.5], [9, 25.0], [3.5, 19.0]],
	},
	"berline": {
		"len": 72.0, "w": 28.0, "r": 6.8, "axles": [14.0, 57.0], "yb": 3.2,
		"upper": [[72, 5], [72, 10], [70, 13.0], [64, 15.0], [52, 15.6], [10, 15.8], [2, 15.8], [0, 13], [0, 5.5]],
		"cabin": [[11, 15.7], [52, 15.6], [41, 24.3], [21, 24.8], [12, 16.4]],
	},
	"break": {
		"len": 74.0, "w": 28.0, "r": 6.8, "axles": [14.0, 58.0], "yb": 3.2,
		"upper": [[74, 5], [74, 10], [72, 13.0], [66, 15.0], [54, 15.6], [3, 16.2], [0.5, 15.8], [0, 13], [0, 5.5]],
		"cabin": [[3, 16.0], [54, 15.6], [43, 24.4], [5, 24.6], [1.6, 17.5]], "pillars": 2,
	},
	"4x4": {
		"len": 68.0, "w": 30.0, "r": 8.0, "axles": [13.0, 54.0], "yb": 5.0,
		"upper": [[68, 6], [68, 14], [67, 17.0], [62, 18.6], [50, 19.0], [2, 19.5], [0, 18], [0, 6.5]],
		"cabin": [[2, 19.3], [50, 19.0], [44, 30.0], [4, 30.4], [1.5, 20.5]], "pillars": 2,
	},
	"suv": {
		"len": 68.0, "w": 29.0, "r": 7.5, "axles": [13.5, 54.0], "yb": 4.4,
		"upper": [[68, 6], [68, 12], [66, 15.0], [60, 17.0], [49, 17.6], [4, 18.2], [1, 17.5], [0, 14], [0, 6]],
		"cabin": [[4, 18.0], [49, 17.6], [38, 27.0], [9, 27.4], [3, 21.0]],
	},
	"monospace": {
		"len": 66.0, "w": 28.0, "r": 6.8, "axles": [12.0, 52.0], "yb": 3.4,
		"upper": [[66, 5], [66, 10], [64, 13.2], [60, 15.2], [56, 15.8], [3, 16.5], [0.5, 16], [0, 13], [0, 5.5]],
		"cabin": [[3, 16.4], [56, 15.8], [42, 28.0], [7, 28.5], [2, 19.0]], "pillars": 2,
	},
	"combi": {
		"len": 66.0, "w": 29.0, "r": 6.8, "axles": [11.0, 52.0], "yb": 3.6,
		"upper": [[66, 5], [66, 13], [64.5, 16.0], [62, 17.2], [1, 17.5], [0, 16], [0, 5.5]],
		"cabin": [[1, 17.5], [62, 17.2], [57, 31.0], [2, 31.2], [0.8, 18.0]], "pillars": 3, "wing": false,
	},
	"fourgon": {
		"len": 78.0, "w": 30.0, "r": 7.2, "axles": [14.0, 61.0], "yb": 4.0,
		"upper": [[78, 6], [78, 13], [76.5, 16.5], [72, 18.0], [1, 18.5], [0, 17], [0, 6]],
		"cabin": [[1, 18.4], [72, 18.0], [62, 37.0], [2, 37.5], [0.8, 19.0]], "panel": true, "wing": false,
	},
	"coupe": {
		"len": 70.0, "w": 28.0, "r": 6.8, "axles": [14.0, 55.5], "yb": 3.0,
		"upper": [[70, 4.8], [70, 9.5], [67.5, 12.8], [61, 15.2], [55, 15.5], [47, 15.6], [4, 15.6], [0.5, 15], [0, 5]],
		"cabin": [[8, 15.6], [47, 15.6], [36, 22.6], [22, 23.0], [9, 16.5]],
	},
	"fastback": {
		"len": 74.0, "w": 29.0, "r": 7.0, "axles": [14.0, 58.0], "yb": 3.0,
		"upper": [[74, 5], [74, 9.5], [71.5, 13.0], [64, 15.7], [52, 15.9], [4, 15.9], [0.5, 15.2], [0, 12], [0, 5]],
		"cabin": [[5, 15.8], [52, 15.9], [41, 23.8], [27, 24.2], [6, 16.7]],
	},
	"sportback": {
		"len": 66.0, "w": 28.0, "r": 6.8, "axles": [13.0, 53.0], "yb": 3.0,
		"upper": [[66, 5], [66, 9.5], [64, 12.8], [58, 15.0], [48, 15.4], [3, 16.0], [0.5, 15.5], [0, 12], [0, 5]],
		"cabin": [[4, 15.8], [48, 15.4], [38, 23.2], [17, 23.5], [3.5, 17.5]],
	},
	"cabriolet": {
		"len": 70.0, "w": 28.0, "r": 6.8, "axles": [14.0, 55.5], "yb": 3.0,
		"upper": [[70, 4.8], [70, 9.5], [67.5, 12.8], [61, 15.2], [55, 15.5], [47, 15.6], [4, 15.6], [0.5, 15], [0, 5]],
		"cabin": [[12, 15.6], [47, 15.6], [42, 21.5], [20, 21.5], [12, 16.0]], "open": true, "seats": [22.0, 34.0],
	},
	"roadster": {
		"len": 62.0, "w": 27.0, "r": 6.6, "axles": [12.0, 50.0], "yb": 3.0,
		"upper": [[62, 4.6], [62, 9.0], [59.5, 12.6], [52, 15.0], [40, 15.2], [4, 15.2], [0.5, 14.4], [0, 5]],
		"cabin": [[14, 15.2], [40, 15.2], [35.5, 20.4], [20, 20.4], [14, 15.6]], "open": true, "seats": [26.0],
	},
	"pickup": {
		"len": 80.0, "w": 30.0, "r": 7.8, "axles": [14.0, 62.0], "yb": 5.0,
		"upper": [[80, 6], [80, 14], [78.5, 17.0], [73, 18.6], [58, 19.2], [34, 19.4], [2, 19.6], [0, 18.5], [0, 6.5]],
		"cabin": [[33, 19.4], [58, 19.2], [52, 30.0], [35, 30.4], [33, 20.0]], "bed": [2.0, 31.5], "wing": false,
	},
	"supercar": {
		"len": 74.0, "w": 30.0, "r": 6.4, "axles": [15.0, 58.0], "yb": 2.6,
		"upper": [[74, 4.5], [74, 7.2], [71, 10.4], [65, 14.0], [56, 14.6], [47, 14.7], [8, 14.8], [1, 14.2], [0, 10], [0, 5]],
		"cabin": [[16, 14.8], [47, 14.7], [36, 21.0], [28, 21.3], [15, 15.4]],
	},
}

## Noms des carrosseries pour l'interface.
const BODY_NAMES := {
	"citadine": "Citadine", "compacte": "Compacte", "berline": "Berline", "break": "Break",
	"4x4": "4x4", "suv": "SUV", "monospace": "Monospace", "combi": "Combi", "fourgon": "Fourgon",
	"coupe": "Coupé", "fastback": "Berline sport", "sportback": "Sportback", "cabriolet": "Cabriolet",
	"roadster": "Roadster", "pickup": "Pick-up", "supercar": "Supercar",
}

## Rendu « bloqué » : silhouette grise, phares à peine allumés.
const LOCKED_BODY := Color("3e3f45")
const LOCKED_GLASS: Array[String] = ["0a0b0d", "101216", "171a1f", "22262d", "343a43"]

static var _cache := {}


## Renvoie {texture, image, exhaust, anchor, ground} pour une voiture.
## locked : silhouette grise d'une voiture pas encore mise à neuf.
static func render(body: String, color: Color, tier: int, scale: float, locked := false) -> Dictionary:
	if locked:
		color = LOCKED_BODY
		tier = 0
	var key := "%s|%s|%d|%.2f|%s" % [body, color.to_html(false), tier, scale, locked]
	if _cache.has(key):
		return _cache[key]
	var r := _Renderer.new()
	r.locked = locked
	var out := r.run(BODIES.get(body, BODIES["compacte"]), color, tier, scale)
	out["texture"] = ImageTexture.create_from_image(out["image"])
	_cache[key] = out
	return out


## Échelle qui fait tenir une carrosserie dans une boîte (largeur, hauteur).
static func fit_scale(body: String, box: Vector2, lo := 1.0, hi := 3.2) -> float:
	var ref: Dictionary = render(body, LOCKED_BODY, 0, 1.0, true)
	var sz := Vector2(ref["texture"].get_size())
	return clampf(snappedf(minf(box.x / sz.x, box.y / sz.y), 0.1), lo, hi)


class _Renderer:
	var locked := false
	var faces: Array[Dictionary] = []
	var e := EYE.normalized()
	var light := LIGHT.normalized()
	var right: Vector3
	var up: Vector3
	var s := 1.0
	var ox := 0.0
	var oy := 0.0
	var w := 0
	var h := 0
	var zbuf := PackedFloat32Array()
	var fbuf := PackedInt32Array()
	var mbuf := PackedInt32Array()
	var sbuf := PackedInt32Array()

	func _init() -> void:
		right = Vector3.UP.cross(e).normalized()
		up = e.cross(right).normalized()

	# --- Géométrie ------------------------------------------------------

	func face(pts: Array, n: Vector3, mat: int, shade := -1, parent := -1, bias := 0.0) -> int:
		faces.append({"pts": pts, "n": n, "mat": mat, "shade": shade, "parent": parent, "bias": bias})
		return faces.size() - 1

	## Extrude un profil (x, y) fermé, sens trigonométrique, entre z0 et z1.
	## Renvoie l'indice de la face du flanc visible (z = z0) et des arêtes.
	func extrude(profile: Array, z0: float, z1: float, mat: int, edge_mats := {}, side_mat := -1) -> Dictionary:
		var near: Array = []
		var far: Array = []
		for p in profile:
			near.append(Vector3(p.x, p.y, z0))
			far.append(Vector3(p.x, p.y, z1))
		var sm := mat if side_mat < 0 else side_mat
		var side := face(near, Vector3(0, 0, -1), sm)
		far.reverse()
		face(far, Vector3(0, 0, 1), sm)
		var edges: Array[int] = []
		for i in profile.size():
			var a: Vector2 = profile[i]
			var b: Vector2 = profile[(i + 1) % profile.size()]
			var d := b - a
			if d.length() < 0.001:
				edges.append(-1)
				continue
			var n := Vector3(d.y, -d.x, 0).normalized()
			edges.append(face([Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1)], n, edge_mats.get(i, mat)))
		return {"side": side, "edges": edges}

	## Cylindre d'axe z (roue). Renvoie l'indice du flanc côté caméra.
	func cylinder(c: Vector2, radius: float, z0: float, z1: float, mat: int, seg := 18) -> int:
		var ring: Array = []
		for k in seg:
			var t := TAU * k / seg
			ring.append(c + Vector2(cos(t), sin(t)) * radius)
		var near: Array = []
		for p in ring:
			near.append(Vector3(p.x, p.y, z0))
		near.reverse()
		var side := face(near, Vector3(0, 0, -1), mat)
		for k in seg:
			var a: Vector2 = ring[k]
			var b: Vector2 = ring[(k + 1) % seg]
			var mid := (a + b) * 0.5 - c
			face([Vector3(a.x, a.y, z0), Vector3(b.x, b.y, z0), Vector3(b.x, b.y, z1), Vector3(a.x, a.y, z1)], Vector3(mid.x, mid.y, 0).normalized(), mat)
		return side

	func disc(c: Vector2, radius: float, z: float, mat: int, shade: int, parent: int, bias: float, seg := 18) -> void:
		var pts: Array = []
		for k in seg:
			var t := TAU * k / seg
			pts.append(Vector3(c.x + cos(t) * radius, c.y + sin(t) * radius, z))
		face(pts, Vector3(0, 0, -1), mat, shade, parent, bias)

	## Quadrilatère posé sur une face existante (détail : phare, montant, joint…).
	func decal(pts2: Array, z: float, mat: int, shade: int, parent: int, bias := 0.5) -> void:
		var pts: Array = []
		for p in pts2:
			pts.append(Vector3(p[0], p[1], z))
		face(pts, Vector3(0, 0, -1), mat, shade, parent, bias)

	func decal3(pts: Array, mat: int, shade: int, parent: int, bias := 0.5) -> void:
		face(pts, Vector3.ZERO, mat, shade, parent, bias)

	# --- Construction d'une voiture ------------------------------------

	func build(d: Dictionary, tier: int) -> Dictionary:
		var length: float = d["len"]
		var width: float = d["w"]
		var r: float = d["r"]
		var yb: float = d["yb"]
		var axles: Array = d["axles"]
		var low := -0.8 if tier >= 4 else 0.0

		# Caisse : dessous avec passages de roue, puis le haut fourni par le profil.
		var ra := r + 1.0
		var prof: Array = [Vector2(1.0, yb + low)]
		for ax in axles:
			var cx: float = ax
			prof.append(Vector2(cx - ra, yb + low))
			for k in range(0, 13):
				var t := PI - PI * k / 12.0
				prof.append(Vector2(cx + cos(t) * ra, r + sin(t) * ra + low * 0.5))
			prof.append(Vector2(cx + ra, yb + low))
		prof.append(Vector2(length - 1.0, yb + low))
		for p in d["upper"]:
			prof.append(Vector2(p[0], p[1] + low))
		# Caisse en deux étages : le bas sur toute la largeur, le haut (capot,
		# ceinture, toit de coffre) un peu plus étroit pour arrondir le volume ;
		# la marche entre les deux fait la ligne d'épaule.
		var cut: float = float(d["upper"][1][1]) + low
		var bev := 0.9
		var big := 1000.0
		var below := PackedVector2Array([Vector2(-big, -big), Vector2(big, -big), Vector2(big, cut), Vector2(-big, cut)])
		var above := PackedVector2Array([Vector2(-big, cut), Vector2(big, cut), Vector2(big, big), Vector2(-big, big)])
		var sides: Array = []
		var bumper := -1
		var nose := -1
		var bumper_edge: Array = []
		var nose_edge: Array = []
		var best_b := -INF
		var best_n := -INF
		var tops: Array = []
		for piece in [[below, 0.0], [above, bev]]:
			var zi: float = piece[1]
			for poly in Geometry2D.intersect_polygons(PackedVector2Array(prof), piece[0]):
				var pts := _ccw(poly)
				var ex := extrude(pts, zi, width - zi, Mat.BODY)
				sides.append([ex["side"], zi])
				for i in pts.size():
					var fi: int = ex["edges"][i]
					if fi < 0:
						continue
					var n: Vector3 = faces[fi]["n"]
					var a: Vector2 = pts[i]
					var b: Vector2 = pts[(i + 1) % pts.size()]
					var lo_p := a if a.y <= b.y else b
					var hi_p := b if a.y <= b.y else a
					var mx := maxf(a.x, b.x)
					if zi == 0.0 and n.x > 0.9 and mx > best_b:
						best_b = mx
						bumper = fi
						bumper_edge = [lo_p, hi_p]
					if zi > 0.0 and n.x > 0.2 and n.y > 0.2 and mx > best_n:
						best_n = mx
						nose = fi
						nose_edge = [lo_p, hi_p]
					if zi > 0.0 and n.y > 0.85:
						tops.append([fi, a, b])

		var cab: Array = []
		for p in d["cabin"]:
			cab.append(Vector2(p[0], p[1] + low))
		var base_r: Vector2 = cab[0]
		var base_f: Vector2 = cab[1]
		var top_f: Vector2 = cab[2]
		var top_r: Vector2 = cab[3]
		var belt := base_f.y
		var inset := 2.2
		var is_open: bool = d.get("open", false)
		var bx := lerpf(top_r.x, top_f.x, 0.45)
		var c_w := 3.5 if length > 60 else 2.0

		if is_open:
			# Décapotée : pare-brise seul, sièges et appuie-tête, habitacle sombre.
			extrude([base_f, base_f + Vector2(1.2, 0), top_f + Vector2(1.2, 0), top_f], inset, width - inset, Mat.GLASS, {2: Mat.BODY})
			for t in tops:
				var a: Vector2 = t[1]
				var b: Vector2 = t[2]
				var x0 := maxf(minf(a.x, b.x), base_r.x)
				var x1 := minf(maxf(a.x, b.x), base_f.x)
				if x1 - x0 > 1.0:
					decal3(_on_edge_x(a, b, x0, x1, 2.6, width - 2.6), Mat.TRIM, 0, t[0])
			for sx in d.get("seats", []):
				for zr in [[5.0, 10.5], [width - 10.5, width - 5.0]]:
					extrude([Vector2(sx, belt - 1.0), Vector2(sx + 2.8, belt - 1.0), Vector2(sx + 2.6, belt + 4.6), Vector2(sx + 0.4, belt + 4.4)], zr[0], zr[1], Mat.TRIM)
			bx = lerpf(base_r.x, base_f.x, 0.5)
		else:
			# Habitacle, plus étroit que la caisse ; tôlé pour un fourgon.
			var panel: bool = d.get("panel", false)
			var cabin := extrude(cab, inset, width - inset, Mat.GLASS, {2: Mat.BODY}, Mat.BODY if panel else Mat.GLASS)
			var cside: int = cabin["side"]
			decal([[base_f.x + 0.3, base_f.y], [top_f.x + 0.3, top_f.y], [top_f.x - 1.6, top_f.y], [base_f.x - 1.6, base_f.y]], inset, Mat.BODY, -1, cside)
			decal([[top_f.x, top_f.y + 0.3], [top_r.x, top_r.y + 0.3], [top_r.x, top_r.y - 1.0], [top_f.x, top_f.y - 1.0]], inset, Mat.BODY, -1, cside)
			if panel:
				var pw := base_f.lerp(top_f, 0.5)
				decal([[base_f.x - 13.0, belt + 1.5], [base_f.x - 0.5, belt + 1.5], [pw.x - 1.0, pw.y], [base_f.x - 13.0, pw.y]], inset, Mat.GLASS, 2, cside)
				bx = base_f.x - 14.0
			else:
				var count: int = d.get("pillars", 1)
				for k in count:
					var px := lerpf(top_r.x, top_f.x, 0.45 if count == 1 else 0.22 + 0.5 * k / float(count - 1))
					decal([[px - 0.9, base_f.y - 0.5], [px + 0.9, base_f.y - 0.5], [px + 0.9, top_f.y], [px - 0.9, top_f.y]], inset, Mat.TRIM, 2, cside)
				var rb: Vector2 = cab[4]
				decal([[base_r.x - 0.5, base_r.y - 0.5], [rb.x + c_w, base_r.y - 0.5], [top_r.x + c_w * 0.6, top_r.y], [top_r.x - 0.5, top_r.y + 0.3]], inset, Mat.BODY, -1, cside)
				decal([[base_r.x, base_f.y - 0.4], [base_f.x, base_f.y - 0.4], [base_f.x, base_f.y + 0.5], [base_r.x, base_f.y + 0.5]], inset, Mat.TRIM, 1, cside)

		# Benne de pick-up : creux sombre sur le dessus.
		if d.has("bed"):
			var bed: Array = d["bed"]
			for t in tops:
				var a: Vector2 = t[1]
				var b: Vector2 = t[2]
				var x0 := maxf(minf(a.x, b.x), float(bed[0]))
				var x1 := minf(maxf(a.x, b.x), float(bed[1]))
				if x1 - x0 > 1.0:
					decal3(_on_edge_x(a, b, x0, x1, 2.4, width - 2.4), Mat.TRIM, 0, t[0])

		# Flancs : bas de caisse sombre, jupe, joints de portes, poignées.
		for sd in sides:
			var sf: int = sd[0]
			var z: float = sd[1]
			decal([[1.0, yb + low], [length - 1.0, yb + low], [length - 1.0, yb + low + 3.2], [1.0, yb + low + 3.2]], z, Mat.BODY, 1, sf, 0.2)
			decal([[1.5, yb + low + 0.2], [length - 1.5, yb + low + 0.2], [length - 1.5, yb + low + 1.4], [1.5, yb + low + 1.4]], z, Mat.TRIM, 1, sf, 0.3)
			decal([[3, belt - 1.0], [length - 4, belt - 1.6], [length - 4, belt - 2.3], [3, belt - 1.7]], z, Mat.BODY, 3, sf, 0.3)
			for x in [base_f.x - 1.0, bx, base_r.x + c_w + 1.0]:
				decal([[x - 0.25, yb + low + 1.6], [x + 0.25, yb + low + 1.6], [x + 0.25, belt - 0.3], [x - 0.25, belt - 0.3]], z, Mat.TRIM, 0, sf, 0.4)
			for x in [bx + 4.0, base_r.x + c_w + 4.5]:
				if x < base_f.x - 3.0:
					decal([[x, belt - 3.4], [x + 2.6, belt - 3.4], [x + 2.6, belt - 2.7], [x, belt - 2.7]], z, Mat.TRIM, 3, sf, 0.4)

		# Face avant : calandre, prise d'air, phares.
		var gz := width * 0.27
		if bumper >= 0:
			var b0: Vector2 = bumper_edge[0]
			var b1: Vector2 = bumper_edge[1]
			decal3(_on_edge(b0, b1, 0.35, 0.92, gz, width - gz), Mat.TRIM, 1, bumper)
			for k in range(0, 4):
				var t0 := 0.40 + k * 0.14
				decal3(_on_edge(b0, b1, t0, t0 + 0.05, gz + 0.5, width - gz - 0.5), Mat.TRIM, 0, bumper, 0.6)
			decal3(_on_edge(b0, b1, 0.02, 0.28, 3.0, width - 3.0), Mat.TRIM, 0, bumper)
		if nose >= 0:
			var n0: Vector2 = nose_edge[0]
			var n1: Vector2 = nose_edge[1]
			for zr in [[1.6 + bev, gz - 0.6], [width - gz + 0.6, width - 1.6 - bev]]:
				decal3(_on_edge(n0, n1, 0.05, 0.85, zr[0], zr[1]), Mat.LAMP, 1, nose)
				decal3(_on_edge(n0, n1, 0.25, 0.65, zr[0] + 0.8, zr[1] - 0.8), Mat.LAMP, 3, nose, 0.6)
			decal3(_on_edge(n0, n1, 0.30, 0.70, gz + 1.0, width - gz - 1.0), Mat.TRIM, 2, nose)

		# Aileron au 2e palier.
		if tier >= 2 and d.get("wing", true):
			var top_rear := 0.0
			for p in d["upper"]:
				if float(p[0]) < 10.0:
					top_rear = maxf(top_rear, float(p[1]) + low)
			var wy := top_rear + 3.5
			extrude([Vector2(0.0, wy), Vector2(7.5, wy - 0.2), Vector2(7.5, wy + 1.0), Vector2(0.0, wy + 1.6)], 0.6, width - 0.6, Mat.TRIM)
			for zc in [4.5, width - 5.5]:
				extrude([Vector2(3.5, top_rear - 0.5), Vector2(4.6, top_rear - 0.5), Vector2(4.6, wy), Vector2(3.5, wy)], zc, zc + 1.0, Mat.TRIM)

		# Roues.
		for ax in axles:
			for near in [true, false]:
				var z0 := -0.8 if near else width - 4.6
				var z1 := 4.6 if near else width + 0.8
				var c := Vector2(ax, r)
				var tire := cylinder(c, r, z0, z1, Mat.TIRE)
				if not near:
					continue
				disc(c, r * 0.70, z0, Mat.RIM, 2, tire, 0.3)
				disc(c, r * 0.56, z0, Mat.TRIM, 0, tire, 0.4)
				if tier >= 3:
					var cal: Array = []
					for k in range(0, 6):
						var t := 0.2 + k * 0.22
						cal.append(Vector3(c.x + cos(t) * r * 0.50, c.y + sin(t) * r * 0.50, z0))
					for k in range(5, -1, -1):
						var t := 0.2 + k * 0.22
						cal.append(Vector3(c.x + cos(t) * r * 0.30, c.y + sin(t) * r * 0.30, z0))
					decal3(cal, Mat.CALIPER, 2, tire, 0.45)
				for k in 5:
					var t := TAU * k / 5.0 + 0.3
					var dir := Vector2(cos(t), sin(t))
					var nrm := Vector2(-dir.y, dir.x) * r * 0.075
					var a := c + dir * r * 0.14
					var b := c + dir * r * 0.62
					decal3([Vector3(a.x + nrm.x, a.y + nrm.y, z0), Vector3(b.x + nrm.x * 1.6, b.y + nrm.y * 1.6, z0), Vector3(b.x - nrm.x * 1.6, b.y - nrm.y * 1.6, z0), Vector3(a.x - nrm.x, a.y - nrm.y, z0)], Mat.RIM, 3 if dir.y > -0.3 else 2, tire, 0.5)
				disc(c, r * 0.16, z0, Mat.RIM, 4, tire, 0.6, 8)

		return {"length": length, "width": width, "exhaust": Vector3(0.0, yb + low + 1.0, 5.0)}

	## Polygone remis dans le sens trigonométrique (y vers le haut).
	func _ccw(poly: PackedVector2Array) -> Array:
		var area := 0.0
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			area += a.x * b.y - b.x * a.y
		var out: Array = Array(poly)
		if area < 0.0:
			out.reverse()
		return out

	## Bande d'une face d'arête, entre deux abscisses x.
	func _on_edge_x(a: Vector2, b: Vector2, x0: float, x1: float, z0: float, z1: float) -> Array:
		var dx := b.x - a.x
		var t0 := (x0 - a.x) / dx
		var t1 := (x1 - a.x) / dx
		return _on_edge(a, b, minf(t0, t1), maxf(t0, t1), z0, z1)

	func _on_edge(a: Vector2, b: Vector2, t0: float, t1: float, z0: float, z1: float) -> Array:
		var p0 := a.lerp(b, t0)
		var p1 := a.lerp(b, t1)
		return [Vector3(p0.x, p0.y, z0), Vector3(p1.x, p1.y, z0), Vector3(p1.x, p1.y, z1), Vector3(p0.x, p0.y, z1)]

	# --- Rastérisation --------------------------------------------------

	func project(p: Vector3) -> Vector3:
		return Vector3(p.dot(right) * s + ox, -p.dot(up) * s + oy, p.dot(e) * s)

	func run(d: Dictionary, color: Color, tier: int, scale: float) -> Dictionary:
		s = scale
		var info := build(d, tier)
		var length: float = info["length"]
		var width: float = info["width"]
		var shadow_pts: Array = [Vector3(-2, 0, -3), Vector3(length + 2, 0, -3), Vector3(length + 2, 0, width + 2), Vector3(-2, 0, width + 2)]

		# Cadre de l'image : toutes les faces et l'ombre au sol, plus une marge.
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for f in faces:
			for p in f["pts"]:
				var q := project(p)
				lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
				hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		for p in shadow_pts:
			var q := project(p)
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		ox = -floor(lo.x) + 2.0
		oy = -floor(lo.y) + 2.0
		w = int(ceil(hi.x - lo.x)) + 5
		h = int(ceil(hi.y - lo.y)) + 5
		var n := w * h
		zbuf.resize(n)
		zbuf.fill(-INF)
		fbuf.resize(n)
		fbuf.fill(-1)
		mbuf.resize(n)
		mbuf.fill(Mat.NONE)
		sbuf.resize(n)
		sbuf.fill(0)

		var shadow_proj: Array = []
		for p in shadow_pts:
			shadow_proj.append(project(p))
		_fill(shadow_proj, -2, -1, Mat.SHADOW, 0, -1.0e9)

		var visible := {}
		for i in faces.size():
			var f: Dictionary = faces[i]
			var parent: int = f["parent"]
			if parent >= 0:
				continue
			if (f["n"] as Vector3).dot(e) <= 0.001:
				continue
			visible[i] = true
			var shade: int = f["shade"]
			if shade < 0:
				shade = _shade_for(f["n"])
			var proj: Array = []
			for p in f["pts"]:
				proj.append(project(p))
			_fill(proj, i, -1, f["mat"], shade, float(f["bias"]))
		for i in faces.size():
			var f: Dictionary = faces[i]
			var parent: int = f["parent"]
			if parent < 0 or not visible.has(parent):
				continue
			var proj: Array = []
			for p in f["pts"]:
				proj.append(project(p))
			var shade: int = f["shade"]
			if shade < 0:
				shade = _shade_for(faces[parent]["n"])
			_fill(proj, i, parent, f["mat"], shade, 0.0)

		var img := _compose(color, tier)
		var ex := project(info["exhaust"])
		# Centre de l'empreinte au sol : c'est ce point qu'on pose au centre du plateau.
		var an := project(Vector3(length * 0.5, 0.0, width * 0.5))
		var front := project(Vector3(length, 0.0, 0.0))
		return {"image": img, "exhaust": Vector2(ex.x, ex.y), "anchor": Vector2(an.x, an.y), "ground": front.y}

	func _shade_for(nrm: Vector3) -> int:
		var i := nrm.normalized().dot(light)
		if i >= 0.80:
			return 3
		if i >= 0.36:
			return 2
		if i >= 0.18:
			return 1
		return 0

	## Remplissage d'un polygone projeté (pair-impair), avec test de profondeur.
	## Un détail (parent ≥ 0) ne s'écrit que sur les pixels de sa face parente.
	func _fill(pts: Array, id: int, parent: int, mat: int, shade: int, bias: float) -> void:
		var count := pts.size()
		if count < 3:
			return
		var a := 0.0
		var b := 0.0
		var c := 0.0
		if parent < 0:
			var p0: Vector3 = pts[0]
			var plane := Vector3.ZERO
			for k in range(1, count - 1):
				plane = (pts[k] - p0).cross(pts[k + 1] - p0)
				if absf(plane.z) > 1e-6:
					break
			if absf(plane.z) <= 1e-6:
				if bias > -1.0e8:
					return
				plane = Vector3(0, 0, 1)
			a = -plane.x / plane.z
			b = -plane.y / plane.z
			c = p0.z - a * p0.x - b * p0.y + bias * s
			if bias <= -1.0e8:
				a = 0.0
				b = 0.0
				c = -1.0e9
		var ymin := INF
		var ymax := -INF
		for p in pts:
			ymin = minf(ymin, p.y)
			ymax = maxf(ymax, p.y)
		var y0 := maxi(0, int(floor(ymin)))
		var y1 := mini(h - 1, int(ceil(ymax)))
		var xs: Array[float] = []
		for y in range(y0, y1 + 1):
			var sy := y + 0.5
			xs.clear()
			for k in count:
				var p: Vector3 = pts[k]
				var q: Vector3 = pts[(k + 1) % count]
				if (p.y <= sy and q.y > sy) or (q.y <= sy and p.y > sy):
					xs.append(p.x + (sy - p.y) * (q.x - p.x) / (q.y - p.y))
			xs.sort()
			var k2 := 0
			while k2 + 1 < xs.size():
				var x0 := maxi(0, int(ceil(xs[k2] - 0.5)))
				var x1 := mini(w - 1, int(floor(xs[k2 + 1] - 0.5)))
				for x in range(x0, x1 + 1):
					var idx := y * w + x
					if parent >= 0:
						if fbuf[idx] == parent:
							mbuf[idx] = mat
							sbuf[idx] = shade
					elif mat == Mat.SHADOW:
						if mbuf[idx] == Mat.NONE:
							mbuf[idx] = Mat.SHADOW
					else:
						var dep := a * (x + 0.5) + b * sy + c
						if dep > zbuf[idx]:
							zbuf[idx] = dep
							fbuf[idx] = id
							mbuf[idx] = mat
							sbuf[idx] = shade
				k2 += 2

	func _is_car(m: int) -> bool:
		return m != Mat.NONE and m != Mat.SHADOW

	## Retouches de pixel art, puis couleurs finales.
	func _compose(color: Color, tier: int) -> Image:
		var ramps := {}
		for k in RAMPS:
			var arr: Array[Color] = []
			for hex in RAMPS[k]:
				arr.append(Color(hex))
			ramps[k] = arr
		ramps[Mat.BODY] = CarRendererRamp.body(color)
		if locked:
			var glass: Array[Color] = []
			for hex in LOCKED_GLASS:
				glass.append(Color(hex))
			ramps[Mat.GLASS] = glass
			var rim: Array[Color] = []
			for hex in RIM_DARK:
				rim.append(Color(hex))
			ramps[Mat.RIM] = rim
		# Jantes : argent, puis noires sport au 1er palier, dorées au 3e.
		if tier >= 1:
			var rim: Array[Color] = []
			for hex in (RIM_GOLD if tier >= 3 else RIM_DARK):
				rim.append(Color(hex))
			ramps[Mat.RIM] = rim

		var out := sbuf.duplicate()
		for y in h:
			for x in w:
				var idx := y * w + x
				var m := mbuf[idx]
				if not _is_car(m):
					continue
				# Liseré de lumière sur les arêtes hautes de la caisse.
				if (m == Mat.BODY or m == Mat.TRIM) and (y == 0 or not _is_car(mbuf[idx - w])):
					out[idx] = mini(4, sbuf[idx] + 1)
				# Vitres : cadre sombre et reflets en diagonale.
				if m == Mat.GLASS:
					var edge := false
					for nb in [idx - 1, idx + 1, idx - w, idx + w]:
						if nb >= 0 and nb < w * h and mbuf[nb] != Mat.GLASS and _is_car(mbuf[nb]):
							edge = true
					if edge and s >= 2.0:
						out[idx] = 0
					else:
						var band := (x + y) % 19
						if band < 2:
							out[idx] = mini(4, sbuf[idx] + 2)
						elif band == 3:
							out[idx] = mini(4, sbuf[idx] + 1)

		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		for y in h:
			for x in w:
				var idx := y * w + x
				var m := mbuf[idx]
				if _is_car(m):
					var ramp: Array = ramps[m]
					img.set_pixel(x, y, ramp[clampi(out[idx], 0, 4)])
					continue
				var touches := false
				for nb in [Vector2i(x - 1, y), Vector2i(x + 1, y), Vector2i(x, y - 1), Vector2i(x, y + 1)]:
					if nb.x >= 0 and nb.y >= 0 and nb.x < w and nb.y < h and _is_car(mbuf[nb.y * w + nb.x]):
						touches = true
						break
				if touches:
					img.set_pixel(x, y, OUTLINE)
				elif m == Mat.SHADOW:
					img.set_pixel(x, y, SHADOW)
		return img


class CarRendererRamp:
	static func body(c: Color) -> Array[Color]:
		return [
			c.darkened(0.62).lerp(Color("1b1230"), 0.35),
			c.darkened(0.36).lerp(Color("2a1f45"), 0.15),
			c,
			c.lightened(0.22).lerp(Color("fff1d6"), 0.10),
			c.lightened(0.50).lerp(Color("fff8e8"), 0.25),
		]
