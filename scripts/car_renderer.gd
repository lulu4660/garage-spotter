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
## y : hauteur. « upper » parcourt le haut de la caisse de l'avant vers l'arrière ;
## « cabin » est l'habitacle (base avant, haut du pare-brise, haut de lunette,
## base arrière). Le dessous et les passages de roue sont calculés.
const BODIES := {
	"citadine": {
		"len": 56.0, "w": 26.0, "r": 6.0, "axles": [11.0, 45.5], "yb": 3.0,
		"upper": [[56, 5], [56, 10], [54.5, 12.8], [51, 14.0], [44, 15.0], [4, 16.0], [0.5, 15.0], [0, 5.5]],
		"cabin": [[4, 15.8], [44, 15.0], [33, 26.0], [8, 26.5], [3, 19.0]],
	},
	"compacte": {
		"len": 64.0, "w": 27.0, "r": 6.5, "axles": [12.5, 51.0], "yb": 3.0,
		"upper": [[64, 5], [64, 9.5], [62.5, 12.5], [58, 13.8], [47, 15.0], [6, 16.0], [1.5, 15.5], [0, 12], [0, 5.5]],
		"cabin": [[5, 15.6], [47, 15.0], [35, 24.5], [10, 25.0], [4.5, 19.0]],
	},
	"berline": {
		"len": 72.0, "w": 28.0, "r": 6.8, "axles": [14.0, 57.0], "yb": 3.2,
		"upper": [[72, 5], [72, 10], [70, 13.0], [64, 15.0], [52, 15.6], [10, 15.8], [2, 15.8], [0, 13], [0, 5.5]],
		"cabin": [[11, 15.7], [52, 15.6], [41, 24.3], [21, 24.8], [12, 16.4]],
	},
	"coupe": {
		"len": 70.0, "w": 28.0, "r": 6.8, "axles": [14.0, 55.5], "yb": 3.0,
		"upper": [[70, 4.8], [70, 9.5], [67.5, 12.8], [61, 15.2], [55, 15.5], [47, 15.6], [4, 15.6], [0.5, 15], [0, 5]],
		"cabin": [[8, 15.6], [47, 15.6], [36, 22.6], [22, 23.0], [9, 16.5]],
	},
	"supercar": {
		"len": 74.0, "w": 30.0, "r": 6.4, "axles": [15.0, 58.0], "yb": 2.6,
		"upper": [[74, 4.5], [74, 7.2], [71, 10.4], [65, 14.0], [56, 14.6], [47, 14.7], [8, 14.8], [1, 14.2], [0, 10], [0, 5]],
		"cabin": [[16, 14.8], [47, 14.7], [36, 21.0], [28, 21.3], [15, 15.4]],
	},
}

static var _cache := {}


## Renvoie {texture, image, exhaust (Vector2), ground (float)} pour une voiture.
static func render(body: String, color: Color, tier: int, scale: float) -> Dictionary:
	var key := "%s|%s|%d|%.2f" % [body, color.to_html(false), tier, scale]
	if _cache.has(key):
		return _cache[key]
	var r := _Renderer.new()
	var out := r.run(BODIES.get(body, BODIES["compacte"]), color, tier, scale)
	out["texture"] = ImageTexture.create_from_image(out["image"])
	_cache[key] = out
	return out


class _Renderer:
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
	func extrude(profile: Array, z0: float, z1: float, mat: int, edge_mats := {}) -> Dictionary:
		var near: Array = []
		var far: Array = []
		for p in profile:
			near.append(Vector3(p.x, p.y, z0))
			far.append(Vector3(p.x, p.y, z1))
		var side := face(near, Vector3(0, 0, -1), mat)
		far.reverse()
		face(far, Vector3(0, 0, 1), mat)
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
		var body := extrude(prof, 0.0, width, Mat.BODY)
		var side: int = body["side"]
		var upper_start := 2 + axles.size() * 15
		var bumper: int = body["edges"][upper_start]
		var nose: int = body["edges"][upper_start + 1]

		# Habitacle, plus étroit que la caisse.
		var cab: Array = []
		for p in d["cabin"]:
			cab.append(Vector2(p[0], p[1] + low))
		var inset := 2.2
		var cabin := extrude(cab, inset, width - inset, Mat.GLASS, {2: Mat.BODY})
		var cside: int = cabin["side"]
		var shield: int = cabin["edges"][1]

		# Montants et cadre des vitres (couleur caisse) sur le flanc de l'habitacle.
		var base_f: Vector2 = cab[1]
		var top_f: Vector2 = cab[2]
		var top_r: Vector2 = cab[3]
		var base_r: Vector2 = cab[4]
		decal([[base_f.x + 0.3, base_f.y], [top_f.x + 0.3, top_f.y], [top_f.x - 1.6, top_f.y], [base_f.x - 1.6, base_f.y]], inset, Mat.BODY, -1, cside)
		decal([[top_f.x, top_f.y + 0.3], [top_r.x, top_r.y + 0.3], [top_r.x, top_r.y - 1.0], [top_f.x, top_f.y - 1.0]], inset, Mat.BODY, -1, cside)
		var bx := lerpf(top_r.x, top_f.x, 0.45)
		decal([[bx - 0.9, base_f.y - 0.5], [bx + 0.9, base_f.y - 0.5], [bx + 0.9, top_f.y], [bx - 0.9, top_f.y]], inset, Mat.TRIM, 2, cside)
		var c_w := 3.5 if length > 60 else 2.0
		decal([[base_r.x - 0.5, base_r.y - 0.5], [base_r.x + c_w, base_r.y - 0.5], [top_r.x + c_w * 0.6, top_r.y], [top_r.x - 0.5, top_r.y + 0.3]], inset, Mat.BODY, -1, cside)
		decal([[base_r.x, base_f.y - 0.4], [base_f.x, base_f.y - 0.4], [base_f.x, base_f.y + 0.5], [base_r.x, base_f.y + 0.5]], inset, Mat.TRIM, 1, cside)

		# Flanc : ligne d'épaule, bas de caisse, portes, poignées.
		var belt := base_f.y
		decal([[3, belt - 1.0], [length - 4, belt - 1.6], [length - 4, belt - 2.3], [3, belt - 1.7]], 0.0, Mat.BODY, 3, side, 0.3)
		decal([[1.0, yb + low], [length - 1.0, yb + low], [length - 1.0, yb + low + 3.2], [1.0, yb + low + 3.2]], 0.0, Mat.BODY, 1, side, 0.2)
		decal([[1.5, yb + low + 0.2], [length - 1.5, yb + low + 0.2], [length - 1.5, yb + low + 1.4], [1.5, yb + low + 1.4]], 0.0, Mat.TRIM, 1, side, 0.3)
		for x in [base_f.x - 1.0, bx, base_r.x + c_w + 1.0]:
			decal([[x - 0.25, yb + low + 1.6], [x + 0.25, yb + low + 1.6], [x + 0.25, belt - 0.3], [x - 0.25, belt - 0.3]], 0.0, Mat.TRIM, 0, side, 0.4)
		for x in [bx + 4.0, base_r.x + c_w + 4.5]:
			if x < base_f.x - 3.0:
				decal([[x, belt - 3.4], [x + 2.6, belt - 3.4], [x + 2.6, belt - 2.7], [x, belt - 2.7]], 0.0, Mat.TRIM, 3, side, 0.4)

		# Face avant : calandre, prise d'air, phares.
		var pb: Array = d["upper"]
		var b0 := Vector2(pb[0][0], pb[0][1] + low)
		var b1 := Vector2(pb[1][0], pb[1][1] + low)
		var n1 := Vector2(pb[2][0], pb[2][1] + low)
		var gz := width * 0.27
		decal3(_on_edge(b0, b1, 0.35, 0.92, gz, width - gz), Mat.TRIM, 1, bumper)
		for k in range(0, 4):
			var t0 := 0.40 + k * 0.14
			decal3(_on_edge(b0, b1, t0, t0 + 0.05, gz + 0.5, width - gz - 0.5), Mat.TRIM, 0, bumper, 0.6)
		decal3(_on_edge(b0, b1, 0.02, 0.28, 3.0, width - 3.0), Mat.TRIM, 0, bumper)
		for zr in [[1.6, gz - 0.6], [width - gz + 0.6, width - 1.6]]:
			decal3(_on_edge(b1, n1, 0.05, 0.85, zr[0], zr[1]), Mat.LAMP, 1, nose)
			decal3(_on_edge(b1, n1, 0.25, 0.65, zr[0] + 0.8, zr[1] - 0.8), Mat.LAMP, 3, nose, 0.6)
		decal3(_on_edge(b1, n1, 0.30, 0.70, gz + 1.0, width - gz - 1.0), Mat.TRIM, 2, nose)

		# Aileron au 2e palier.
		if tier >= 2:
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
