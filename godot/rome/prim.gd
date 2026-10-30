extends RefCounted
class_name RomePrim
# Primitives du kit romain : boîtes, prismes (toits), pyramides, colonnes cannelées, arcs, escaliers, dômes.
# Tout est ajouté à un SurfaceTool avec une couleur par sommet et des normales plates (look peint, aucune texture).
# Chaque primitive prend une transformation `xf` (position + rotation) : les coordonnées locales ont l'origine au sol, au centre.

static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, xf: Transform3D) -> void:
	var n := (b - a).cross(c - a).normalized()
	n = xf.basis * n
	st.set_normal(n)
	st.set_color(col)
	for v in [a, b, c, a, c, d]:
		st.add_vertex(xf * v)

static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, xf: Transform3D) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_normal(xf.basis * n)
	st.set_color(col)
	for v in [a, b, c]:
		st.add_vertex(xf * v)

# Boîte posée au sol : `pos` = centre de la base, `size` = largeur (x), hauteur (y), profondeur (z). `top` = couleur du dessus.
static func box(st: SurfaceTool, pos: Vector3, size: Vector3, col: Color, xf: Transform3D, top: Color = Color.TRANSPARENT, rot_y: float = 0.0) -> void:
	var t := top if top.a > 0.0 else col
	var x := size.x / 2.0
	var z := size.z / 2.0
	var h := size.y
	var local := Transform3D(Basis(Vector3.UP, rot_y), pos)
	var X := xf * local
	var p000 := Vector3(-x, 0, -z)
	var p100 := Vector3(x, 0, -z)
	var p110 := Vector3(x, h, -z)
	var p010 := Vector3(-x, h, -z)
	var p001 := Vector3(-x, 0, z)
	var p101 := Vector3(x, 0, z)
	var p111 := Vector3(x, h, z)
	var p011 := Vector3(-x, h, z)
	quad(st, p001, p101, p111, p011, col, X)   # avant (+z)
	quad(st, p100, p000, p010, p110, col, X)   # arrière (-z)
	quad(st, p000, p001, p011, p010, col, X)   # gauche (-x)
	quad(st, p101, p100, p110, p111, col, X)   # droite (+x)
	quad(st, p010, p011, p111, p110, t, X)     # dessus
	quad(st, p000, p100, p101, p001, col.darkened(0.3), X)   # dessous

# Prisme triangulaire (toit à deux pentes) : faîte le long de x. `w` longueur du faîte, `d` largeur (z), `h` hauteur.
# `ends` = couleur des pignons (le tympan d'un fronton).
static func prism(st: SurfaceTool, pos: Vector3, w: float, d: float, h: float, col: Color, xf: Transform3D, ends: Color = Color.TRANSPARENT, rot_y: float = 0.0) -> void:
	var e := ends if ends.a > 0.0 else col.darkened(0.12)
	var X := xf * Transform3D(Basis(Vector3.UP, rot_y), pos)
	var x := w / 2.0
	var z := d / 2.0
	var a0 := Vector3(-x, 0, -z)
	var a1 := Vector3(x, 0, -z)
	var b0 := Vector3(-x, 0, z)
	var b1 := Vector3(x, 0, z)
	var r0 := Vector3(-x, h, 0)
	var r1 := Vector3(x, h, 0)
	quad(st, b0, b1, r1, r0, col, X)           # pente avant (+z)
	quad(st, a1, a0, r0, r1, col, X)           # pente arrière (-z)
	tri(st, a0, b0, r0, e, X)                  # pignon gauche
	tri(st, b1, a1, r1, e, X)                  # pignon droit
	quad(st, a0, a1, b1, b0, col.darkened(0.3), X)

# Pyramide (toit en croupe ou acrotère) : base w×d, sommet à h.
static func pyramid(st: SurfaceTool, pos: Vector3, w: float, d: float, h: float, col: Color, xf: Transform3D) -> void:
	var X := xf * Transform3D(Basis.IDENTITY, pos)
	var x := w / 2.0
	var z := d / 2.0
	var top := Vector3(0, h, 0)
	var c := [Vector3(-x, 0, -z), Vector3(x, 0, -z), Vector3(x, 0, z), Vector3(-x, 0, z)]
	for i in 4:
		tri(st, c[(i + 1) % 4], c[i], top, col, X)
	quad(st, c[0], c[1], c[2], c[3], col.darkened(0.3), X)

# Cylindre vertical : `pos` = centre de la base. `flute` > 0 creuse une cannelure un côté sur deux (colonnes).
static func cylinder(st: SurfaceTool, pos: Vector3, r_bottom: float, r_top: float, h: float, sides: int, col: Color, xf: Transform3D, flute: float = 0.0, cap_top := true, cap_bottom := false) -> void:
	var X := xf * Transform3D(Basis.IDENTITY, pos)
	var pb := []
	var pt := []
	for i in sides:
		var a := float(i) / sides * TAU
		var f := 1.0 - flute * float(i % 2)
		pb.append(Vector3(cos(a) * r_bottom * f, 0, sin(a) * r_bottom * f))
		pt.append(Vector3(cos(a) * r_top * f, h, sin(a) * r_top * f))
	for i in sides:
		var j := (i + 1) % sides
		quad(st, pb[j], pb[i], pt[i], pt[j], col, X)
	if cap_top:
		for i in range(1, sides - 1):
			tri(st, pt[0], pt[i], pt[i + 1], col, X)
	if cap_bottom:
		for i in range(1, sides - 1):
			tri(st, pb[0], pb[i + 1], pb[i], col.darkened(0.3), X)

# Colonne romaine complète : socle, fût cannelé légèrement conique, chapiteau. `pos` = centre de la base, `h` hauteur totale.
static func column(st: SurfaceTool, pos: Vector3, h: float, r: float, col: Color, xf: Transform3D, broken: float = 0.0) -> void:
	var base_h := r * 0.5
	box(st, pos, Vector3(r * 2.6, base_h, r * 2.6), col.darkened(0.08), xf)
	if broken > 0.0:
		cylinder(st, pos + Vector3(0, base_h, 0), r, r * 0.92, h * broken, 12, col, xf, 0.12, true)
		return
	var shaft := h - base_h - r * 0.9
	cylinder(st, pos + Vector3(0, base_h, 0), r, r * 0.85, shaft, 12, col, xf, 0.12, false)
	var cy := base_h + shaft
	cylinder(st, pos + Vector3(0, cy, 0), r * 0.85, r * 1.15, r * 0.45, 12, col.lightened(0.05), xf, 0.0, false)
	box(st, pos + Vector3(0, cy + r * 0.45, 0), Vector3(r * 2.6, r * 0.45, r * 2.6), col.lightened(0.08), xf)

# Arc en plein cintre dans le plan xy (profondeur z) : deux piédroits et une voussure. `w` largeur totale, `h` hauteur sous clef.
static func arch(st: SurfaceTool, pos: Vector3, w: float, h: float, depth: float, thick: float, col: Color, xf: Transform3D, segments: int = 8) -> void:
	var r_in := w / 2.0 - thick
	var r_out := w / 2.0
	var spring := h - r_in
	var X := xf * Transform3D(Basis.IDENTITY, pos)
	box(st, pos + Vector3(-(r_in + thick / 2.0), 0, 0), Vector3(thick, spring, depth), col, xf)
	box(st, pos + Vector3(r_in + thick / 2.0, 0, 0), Vector3(thick, spring, depth), col, xf)
	var zf := depth / 2.0
	for i in segments:
		var a0 := PI * float(i) / segments
		var a1 := PI * float(i + 1) / segments
		var i0 := Vector3(cos(a0) * r_in, spring + sin(a0) * r_in, 0)
		var i1 := Vector3(cos(a1) * r_in, spring + sin(a1) * r_in, 0)
		var o0 := Vector3(cos(a0) * r_out, spring + sin(a0) * r_out, 0)
		var o1 := Vector3(cos(a1) * r_out, spring + sin(a1) * r_out, 0)
		var zp := Vector3(0, 0, zf)
		quad(st, i1 + zp, o1 + zp, o0 + zp, i0 + zp, col, X)          # face avant
		quad(st, i0 - zp, o0 - zp, o1 - zp, i1 - zp, col, X)          # face arrière
		quad(st, o0 + zp, o1 + zp, o1 - zp, o0 - zp, col, X)          # extrados
		quad(st, i1 + zp, i0 + zp, i0 - zp, i1 - zp, col.darkened(0.15), X)   # intrados
	# attique au-dessus de la voussure
	box(st, pos + Vector3(0, h, 0), Vector3(w, thick * 0.6, depth), col, xf)

# Escalier vers +z (il monte en s'éloignant de +z vers l'intérieur) : `pos` = centre du bord bas, `w` largeur, `n` marches de `rise`×`run`.
static func stairs(st: SurfaceTool, pos: Vector3, w: float, n: int, rise: float, run: float, col: Color, xf: Transform3D) -> void:
	for i in n:
		box(st, pos + Vector3(0, i * rise, -run * (i + 0.5)), Vector3(w, rise, run * (n - i)), col, xf)

# Dôme (demi-sphère en anneaux) : `pos` = centre de la base.
static func dome(st: SurfaceTool, pos: Vector3, r: float, col: Color, xf: Transform3D, rings: int = 5, sides: int = 16, squash: float = 1.0) -> void:
	var X := xf * Transform3D(Basis.IDENTITY, pos)
	var prev := []
	for i in sides:
		var a := float(i) / sides * TAU
		prev.append(Vector3(cos(a) * r, 0, sin(a) * r))
	for k in range(1, rings + 1):
		var t := float(k) / rings * PI / 2.0
		var rr := cos(t) * r
		var y := sin(t) * r * squash
		var cur := []
		for i in sides:
			var a := float(i) / sides * TAU
			cur.append(Vector3(cos(a) * rr, y, sin(a) * rr))
		for i in sides:
			var j := (i + 1) % sides
			if k == rings:
				tri(st, prev[j], prev[i], Vector3(0, r * squash, 0), col, X)
			else:
				quad(st, prev[j], prev[i], cur[i], cur[j], col, X)
		prev = cur

# Rangées de tuiles sur un toit à deux pentes : fines arêtes posées le long de chaque pente. Mêmes paramètres que `prism`.
static func tiles(st: SurfaceTool, pos: Vector3, w: float, d: float, h: float, col: Color, xf: Transform3D, rot_y: float = 0.0, spacing: float = 0.34) -> void:
	var X := xf * Transform3D(Basis(Vector3.UP, rot_y), pos)
	var z := d / 2.0
	var n := int(w / spacing)
	var lift := Vector3(0, 0.05, 0)
	for i in n + 1:
		var x := -w / 2.0 + i * spacing
		var a := Vector3(x - 0.04, 0, z) + lift
		var b := Vector3(x + 0.04, 0, z) + lift
		var top_a := Vector3(x - 0.04, h, 0) + lift
		var top_b := Vector3(x + 0.04, h, 0) + lift
		quad(st, a, b, top_b, top_a, col, X)                                  # pente +z
		var a2 := Vector3(x - 0.04, 0, -z) + lift
		var b2 := Vector3(x + 0.04, 0, -z) + lift
		quad(st, b2, a2, top_a, top_b, col, X)                                # pente -z
	box(st, pos + Vector3(0, h - 0.02, 0), Vector3(w + 0.1, 0.12, 0.22), col.darkened(0.2), xf, Color.TRANSPARENT, rot_y)   # faîtière
