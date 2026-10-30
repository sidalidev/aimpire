extends RefCounted
class_name RomeKit
# Kit romain procédural : bâtiments (par type, niveau, ruine), enceintes de village, Forum, monuments.
# Chaque fonction retourne un ArrayMesh à une surface, couleurs par sommet, matériau `rome.gdshader`. Mis en cache par clé.
# Repère : origine au sol au centre de la parcelle, la porte regarde vers -z (village.gd tourne ensuite vers le Forum).

const P := preload("res://rome/prim.gd")

const MARBLE := Color("f1ebdd")
const MARBLE_SHADE := Color("d8cfbb")
const STUCCO := Color("ead9b8")
const OCHRE := Color("d9a441")
const POMPEI := Color("b8553f")      # rouge pompéien
const TILE := Color("c4603f")
const TILE_DARK := Color("9e4a30")
const STONE := Color("aaa596")
const STONE_DARK := Color("807b6f")
const WOOD := Color("8a5a34")
const DOOR := Color("5a3a22")
const WINDOW := Color("33414f")
const BRONZE := Color("8c6a2f")
const GOLD := Color("e8c04a")
const PURPLE := Color("6b1f33")
const IVY := Color("4f7a3a")
const WATER := Color("5aa7c9")
const EMBER := Color("ff7a2a")

static var _cache := {}
static var _mat: ShaderMaterial
static var _mat_ruin: ShaderMaterial
static var _mat_leaf: ShaderMaterial

const CYPRESS := Color("2f4a2b")
const PINE := Color("4e6b38")
const OLIVE := Color("8a9a6a")
const LAUREL := Color("3f6a3a")
const TRUNK := Color("6a4a30")

static func material(ruin := false) -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = preload("res://shaders/rome.gdshader")
		_mat_ruin = ShaderMaterial.new()
		_mat_ruin.shader = preload("res://shaders/rome.gdshader")
		_mat_ruin.set_shader_parameter("ruin", 1.0)
	return _mat_ruin if ruin else _mat

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

static func _end(st: SurfaceTool, ruin := false) -> ArrayMesh:
	var mesh := st.commit()
	mesh.surface_set_material(0, material(ruin))
	return mesh

# --- Bâtiments ---

# `type` cabane | atelier | forge | bibliotheque | tour | chateau ; `level` 1..5 ; `seed` varie les détails.
static func building(type: String, level: int, ruin: bool, seed: int) -> ArrayMesh:
	var key := "b|%s|%d|%s|%d" % [type, level, ruin, seed % 4]
	if _cache.has(key):
		return _cache[key]
	var st := _begin()
	var I := Transform3D.IDENTITY
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	if ruin:
		_ruin(st, type, rng)
	else:
		match type:
			"cabane": _cabane(st, level, rng)
			"atelier": _atelier(st, level, rng)
			"forge": _forge(st, level, rng)
			"bibliotheque": _basilica(st, level, rng)
			"tour": _tour(st, level, rng)
			"chateau": _palais(st, level, rng)
			_: _cabane(st, level, rng)
		# bannières de niveau devant, à gauche de la porte
		for i in range(1, level):
			_banner(st, Vector3(-1.9 + i * 0.5, 0, 2.3), 1.6, PURPLE if i % 2 else POMPEI, I)
	var mesh := _end(st, ruin)
	_cache[key] = mesh
	return mesh

static func _wall_color(level: int) -> Color:
	return MARBLE if level >= 4 else (STUCCO if level >= 2 else STUCCO.darkened(0.06))

static func _door(st: SurfaceTool, z: float, w: float = 0.7, h: float = 1.3, x: float = 0.0) -> void:
	P.box(st, Vector3(x, 0, z), Vector3(w, h, 0.08), DOOR, Transform3D.IDENTITY)
	P.box(st, Vector3(x, h, z), Vector3(w + 0.2, 0.1, 0.12), MARBLE_SHADE, Transform3D.IDENTITY)   # linteau

static func _window(st: SurfaceTool, pos: Vector3, rot_y: float = 0.0) -> void:
	P.box(st, pos, Vector3(0.45, 0.55, 0.08), WINDOW, Transform3D.IDENTITY, Color.TRANSPARENT, rot_y)

static func _banner(st: SurfaceTool, pos: Vector3, h: float, cloth: Color, xf: Transform3D) -> void:
	P.cylinder(st, pos, 0.04, 0.04, h, 6, WOOD, xf)
	P.box(st, pos + Vector3(0, h - 0.75, 0), Vector3(0.32, 0.7, 0.04), cloth, xf)
	P.pyramid(st, pos + Vector3(0, h, 0), 0.12, 0.12, 0.14, GOLD, xf)

static func _amphora(st: SurfaceTool, pos: Vector3, xf: Transform3D) -> void:
	P.cylinder(st, pos, 0.1, 0.18, 0.22, 8, TILE, xf)
	P.cylinder(st, pos + Vector3(0, 0.22, 0), 0.18, 0.1, 0.2, 8, TILE, xf)

# Toit à deux pentes avec tuiles, débord 0.3, faîte le long de x (ou z si `along_z`).
static func _roof(st: SurfaceTool, y: float, w: float, d: float, h: float, col: Color, along_z := false, ends: Color = Color.TRANSPARENT) -> void:
	var I := Transform3D.IDENTITY
	var rot := PI / 2.0 if along_z else 0.0
	var ww := (d if along_z else w) + 0.5
	var dd := (w if along_z else d) + 0.5
	P.prism(st, Vector3(0, y, 0), ww, dd, h, col, I, ends, rot)
	P.tiles(st, Vector3(0, y, 0), ww, dd, h, col.darkened(0.18), I, rot)

static func _cabane(st: SurfaceTool, level: int, rng: RandomNumberGenerator) -> void:
	var I := Transform3D.IDENTITY
	P.box(st, Vector3.ZERO, Vector3(2.0, 1.6, 2.0), STUCCO.darkened(0.08), I, POMPEI.darkened(0.1))
	P.box(st, Vector3(0, 1.6, 0), Vector3(2.4, 0.14, 2.4), TILE, I)
	_door(st, -1.0)
	# auvent de bois devant la porte
	P.box(st, Vector3(0, 1.45, -1.55), Vector3(1.8, 0.07, 1.0), WOOD, I)
	for x in [-0.8, 0.8]:
		P.cylinder(st, Vector3(x, 0, -2.0), 0.05, 0.05, 1.45, 6, WOOD, I)
	_amphora(st, Vector3(1.3, 0, -0.9), I)
	if rng.randf() < 0.5:
		_amphora(st, Vector3(-1.3, 0, 0.4), I)

static func _atelier(st: SurfaceTool, level: int, rng: RandomNumberGenerator) -> void:
	var I := Transform3D.IDENTITY
	var floors := 2 if level >= 3 else 1
	var h := 2.1 * floors
	var wall := _wall_color(level)
	P.box(st, Vector3.ZERO, Vector3(3.0, h, 3.0), wall, I)
	P.box(st, Vector3.ZERO, Vector3(3.08, 0.5, 3.08), POMPEI, I)                      # soubassement rouge pompéien
	if floors == 2:
		P.box(st, Vector3(0, 2.1, 0), Vector3(3.1, 0.12, 3.1), MARBLE_SHADE, I)        # corniche entre étages
	_roof(st, h, 3.0, 3.0, 1.0, TILE)
	_door(st, -1.5)
	_window(st, Vector3(-0.9, 0.8, -1.5))
	_window(st, Vector3(0.9, 0.8, -1.5))
	if floors == 2:
		for x in [-0.9, 0.0, 0.9]:
			_window(st, Vector3(x, 2.9, -1.5))
	if level >= 2:   # portique : deux colonnes et un petit toit devant la porte
		for x in [-1.1, 1.1]:
			P.column(st, Vector3(x, 0, -2.3), 2.0, 0.14, MARBLE, I)
		P.box(st, Vector3(0, 2.0, -1.95), Vector3(3.0, 0.22, 1.2), MARBLE_SHADE, I)
		P.prism(st, Vector3(0, 2.22, -1.95), 3.2, 1.3, 0.4, TILE, I)
	if level >= 5:
		for x in [-1.75, 1.75]:
			P.pyramid(st, Vector3(x, h + 1.0, 0), 0.25, 0.25, 0.35, GOLD, I)
	# établi, planches et amphores
	P.box(st, Vector3(2.0, 0, 0.6), Vector3(0.9, 0.55, 0.5), WOOD, I, Color.TRANSPARENT, 0.3)
	for i in 3:
		P.box(st, Vector3(-2.1, i * 0.09, 0.4 + i * 0.05), Vector3(0.3, 0.08, 1.4), WOOD.lightened(0.1 * i), I, Color.TRANSPARENT, -0.2)
	_amphora(st, Vector3(1.9, 0, -0.5), I)

static func _forge(st: SurfaceTool, level: int, rng: RandomNumberGenerator) -> void:
	var I := Transform3D.IDENTITY
	var h := 2.2 + (0.6 if level >= 3 else 0.0)
	P.box(st, Vector3.ZERO, Vector3(3.0, h, 3.0), STONE, I)
	P.box(st, Vector3.ZERO, Vector3(3.08, 0.4, 3.08), STONE_DARK, I)
	if level >= 4:
		P.box(st, Vector3(0, h - 0.15, 0), Vector3(3.12, 0.15, 3.12), MARBLE_SHADE, I)
	P.pyramid(st, Vector3(0, h, 0), 3.5, 3.5, 1.1, TILE_DARK, I)
	_door(st, -1.5, 0.9, 1.4)
	_window(st, Vector3(1.1, 0.9, -1.5))
	# cheminée (la fumée sort à son sommet : building.gd place les particules en (0.9, h+1.5, -0.6))
	P.box(st, Vector3(0.9, h - 0.2, -0.6), Vector3(0.5, 1.5, 0.5), STONE_DARK, I)
	if level >= 3:
		P.box(st, Vector3(-0.9, h - 0.2, 0.7), Vector3(0.45, 1.3, 0.45), STONE_DARK, I)
	# enclume, brasero, lingots
	P.box(st, Vector3(-1.4, 0, -2.2), Vector3(0.5, 0.45, 0.3), STONE_DARK.darkened(0.3), I)
	P.cylinder(st, Vector3(1.5, 0, -2.2), 0.25, 0.32, 0.5, 8, BRONZE.darkened(0.3), I)
	P.cylinder(st, Vector3(1.5, 0.5, -2.2), 0.22, 0.1, 0.25, 8, EMBER, I)
	for i in 3:
		P.box(st, Vector3(2.0, i * 0.12, 0.8), Vector3(0.5, 0.12, 0.25), BRONZE, I)

static func _basilica(st: SurfaceTool, level: int, rng: RandomNumberGenerator) -> void:
	var I := Transform3D.IDENTITY
	var wall := _wall_color(maxi(level, 2))
	var h := 2.6 + (0.5 if level >= 3 else 0.0)
	var w := 3.0 + (0.6 if level >= 4 else 0.0)
	P.box(st, Vector3(0, 0, 0.3), Vector3(w, h, 3.4), wall, I)
	P.box(st, Vector3(0, 0, 0.3), Vector3(w + 0.1, 0.4, 3.5), MARBLE_SHADE, I)
	# pilastres sur les côtés
	for z in [-1.0, 0.3, 1.6]:
		for x in [-w / 2.0, w / 2.0]:
			P.box(st, Vector3(x, 0.4, z), Vector3(0.2, h - 0.4, 0.3), wall.darkened(0.08), I)
	# colonnade de façade et fronton tourné vers la porte (faîte le long de z)
	var n := 2 + mini(level, 4)    # 3 à 6 colonnes
	n = 4 if level < 3 else 6
	for i in n:
		var x := -w / 2.0 + 0.3 + i * (w - 0.6) / (n - 1)
		P.column(st, Vector3(x, 0, -1.9), h, 0.13, MARBLE, I)
	P.box(st, Vector3(0, h, -0.6), Vector3(w + 0.6, 0.3, 4.9), MARBLE_SHADE, I)               # entablement
	_roof(st, h + 0.3, w + 0.4, 5.0, 1.1, TILE, true, POMPEI if level >= 2 else MARBLE_SHADE)   # fronton rouge
	_door(st, -1.4, 0.9, 1.6)
	P.stairs(st, Vector3(0, 0, -2.7), w - 0.4, 3, 0.14, 0.3, MARBLE_SHADE, I)
	if level >= 5:
		P.pyramid(st, Vector3(0, h + 1.4, -2.2), 0.3, 0.3, 0.45, GOLD, I)
	# rouleaux rangés dehors
	for i in 4:
		P.cylinder(st, Vector3(1.9 + (i % 2) * 0.22, 0.0, 0.6 + (i / 2) * 0.22), 0.09, 0.09, 0.5, 6, MARBLE, I)

static func _tour(st: SurfaceTool, level: int, rng: RandomNumberGenerator) -> void:
	var I := Transform3D.IDENTITY
	var h := 3.2 + 0.6 * level
	var s := 1.8
	if level >= 3:
		P.box(st, Vector3.ZERO, Vector3(s + 0.8, 0.5, s + 0.8), STONE_DARK, I)       # soubassement
	P.box(st, Vector3.ZERO, Vector3(s, h, s), STONE, I)
	P.box(st, Vector3(0, h, 0), Vector3(s + 0.5, 0.3, s + 0.5), STONE_DARK, I)        # plateforme
	for i in 4:   # créneaux
		var a := i * PI / 2.0 + PI / 4.0
		var r := (s + 0.5) / 2.0 - 0.12
		P.box(st, Vector3(cos(a) * r * 1.3, h + 0.3, sin(a) * r * 1.3), Vector3(0.3, 0.5, 0.3), STONE, I)
	for i in 4:
		var a := i * PI / 2.0
		P.box(st, Vector3(cos(a) * ((s + 0.5) / 2.0 - 0.1), h + 0.3, sin(a) * ((s + 0.5) / 2.0 - 0.1)), Vector3(0.5 if i % 2 else 0.25, 0.4, 0.25 if i % 2 else 0.5), STONE, I)
	_door(st, -s / 2.0, 0.6, 1.2)
	for y in range(1, int(h / 1.3)):
		_window(st, Vector3(0, y * 1.3, -s / 2.0))
	if level >= 5:
		P.pyramid(st, Vector3(0, h + 0.3, 0), s + 0.3, s + 0.3, 0.9, BRONZE, I)
	else:
		P.cylinder(st, Vector3(0, h + 0.3, 0), 0.08, 0.08, 0.6, 6, WOOD, I)               # torche
		P.cylinder(st, Vector3(0, h + 0.9, 0), 0.12, 0.02, 0.3, 6, EMBER, I)

static func _palais(st: SurfaceTool, level: int, rng: RandomNumberGenerator) -> void:
	var I := Transform3D.IDENTITY
	var h := 2.8
	P.box(st, Vector3(0, 0, 0.4), Vector3(4.0, h, 3.0), MARBLE, I)
	P.box(st, Vector3(0, 0, 0.4), Vector3(4.1, 0.5, 3.1), MARBLE_SHADE, I)
	P.box(st, Vector3(0, h - 0.25, 0.4), Vector3(4.1, 0.25, 3.1), GOLD.darkened(0.15), I)     # frise dorée
	for i in 6:
		var x := -1.75 + i * 0.7
		P.column(st, Vector3(x, 0, -1.6), h, 0.14, MARBLE, I)
		if level >= 2 and i % 2 == 0 and i < 5:
			P.box(st, Vector3(x + 0.35, h - 1.4, -1.6), Vector3(0.5, 1.2, 0.04), PURPLE, I)   # tentures pourpres
	P.box(st, Vector3(0, h, -0.4), Vector3(4.6, 0.3, 4.4), MARBLE_SHADE, I)
	_roof(st, h + 0.3, 4.4, 4.5, 1.2, TILE, true, POMPEI)
	_door(st, -1.1, 1.0, 1.8)
	P.stairs(st, Vector3(0, 0, -2.3), 3.6, 3, 0.14, 0.3, MARBLE_SHADE, I)
	if level >= 3:   # ailes latérales
		for x in [-2.8, 2.8]:
			P.box(st, Vector3(x, 0, 0.6), Vector3(1.4, 2.0, 2.4), MARBLE, I)
			P.prism(st, Vector3(x, 2.0, 0.6), 1.7, 2.7, 0.6, TILE, I)
			P.tiles(st, Vector3(x, 2.0, 0.6), 1.7, 2.7, 0.6, TILE_DARK, I)
	if level >= 4:   # statues sur socles devant
		for x in [-2.4, 2.4]:
			P.box(st, Vector3(x, 0, -2.6), Vector3(0.5, 0.7, 0.5), MARBLE_SHADE, I)
			_statuette(st, Vector3(x, 0.7, -2.6), 0.9, BRONZE, I)
	for x in [-2.2, 2.2]:
		P.pyramid(st, Vector3(x, h + 0.3, -2.3), 0.3, 0.3, 0.4, GOLD, I)

# Petite figure stylisée (statue) : jambes, corps, tête.
static func _statuette(st: SurfaceTool, pos: Vector3, h: float, col: Color, xf: Transform3D) -> void:
	P.cylinder(st, pos, 0.12 * h, 0.1 * h, 0.45 * h, 8, col, xf)
	P.box(st, pos + Vector3(0, 0.45 * h, 0), Vector3(0.34 * h, 0.4 * h, 0.2 * h), col, xf)
	P.dome(st, pos + Vector3(0, 0.85 * h, 0), 0.12 * h, col, xf, 3, 8)
	P.cylinder(st, pos + Vector3(0, 0.85 * h - 0.12 * h, 0), 0.12 * h, 0.12 * h, 0.12 * h, 8, col, xf)

# Ruine : pans de murs de hauteurs inégales, colonnes brisées, gravats, lierre.
static func _ruin(st: SurfaceTool, type: String, rng: RandomNumberGenerator) -> void:
	var I := Transform3D.IDENTITY
	var s := 3.0 if type != "tour" else 1.8
	var segs := [[Vector3(0, 0, -s / 2.0), 0.0], [Vector3(0, 0, s / 2.0), 0.0], [Vector3(-s / 2.0, 0, 0), PI / 2.0], [Vector3(s / 2.0, 0, 0), PI / 2.0]]
	for sg in segs:
		var n := 3
		for i in n:
			var hh := rng.randf_range(0.25, 1.4)
			var off := Vector3(-s / 2.0 + 0.5 + i * (s - 1.0) / (n - 1), 0, 0)
			var pos: Vector3 = sg[0] + Basis(Vector3.UP, sg[1]) * off
			P.box(st, pos, Vector3(0.95, hh, 0.3), STONE, I, Color.TRANSPARENT, sg[1])
	for i in 3:
		var a := rng.randf() * TAU
		P.column(st, Vector3(cos(a) * 1.9, 0, sin(a) * 1.9), 2.0, 0.13, MARBLE_SHADE, I, rng.randf_range(0.2, 0.6))
	for i in 6:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.6, 2.4)
		P.box(st, Vector3(cos(a) * r, 0, sin(a) * r), Vector3(0.35, 0.25, 0.3), STONE_DARK, I, Color.TRANSPARENT, a)
	for i in 4:
		var a := rng.randf() * TAU
		P.box(st, Vector3(cos(a) * 1.5, 0, sin(a) * 1.5), Vector3(0.6, rng.randf_range(0.4, 1.0), 0.5), IVY, I, Color.TRANSPARENT, a)

# --- Enceintes de village (pièces répétées par batch.gd) ---

# `kind` muret (oppidum) | rempart (urbs) | colonnade (métropole) ; pièce de 1 m le long de x, face extérieure vers -z.
static func wall_piece(kind: String) -> ArrayMesh:
	var key := "w|" + kind
	if _cache.has(key):
		return _cache[key]
	var st := _begin()
	var I := Transform3D.IDENTITY
	match kind:
		"muret":
			P.box(st, Vector3.ZERO, Vector3(1.0, 0.7, 0.3), STONE, I, STONE_DARK)
		"rempart":
			P.box(st, Vector3.ZERO, Vector3(1.0, 1.8, 0.5), STONE, I, STONE_DARK)
			P.box(st, Vector3(-0.25, 1.8, -0.1), Vector3(0.4, 0.35, 0.25), STONE, I)
		"colonnade":   # travée de 2 m : une colonne et son entablement
			P.column(st, Vector3.ZERO, 2.2, 0.12, MARBLE, I)
			P.box(st, Vector3(1.0, 2.2, 0), Vector3(2.0, 0.25, 0.5), MARBLE_SHADE, I)
		"porte":
			P.arch(st, Vector3(0, 0, 0), 3.2, 2.6, 0.7, 0.5, MARBLE_SHADE, I)
		"tourelle":
			P.cylinder(st, Vector3.ZERO, 0.55, 0.5, 2.4, 10, STONE, I)
			P.cylinder(st, Vector3(0, 2.4, 0), 0.6, 0.0, 0.7, 10, TILE_DARK, I)
		"statue":
			P.box(st, Vector3.ZERO, Vector3(0.6, 0.8, 0.6), MARBLE_SHADE, I)
			_statuette(st, Vector3(0, 0.8, 0), 1.0, MARBLE, I)
		"haie":
			P.box(st, Vector3.ZERO, Vector3(1.0, 0.6, 0.45), IVY, I, IVY.lightened(0.15))
	var mesh := _end(st)
	_cache[key] = mesh
	return mesh

# --- Forum ---

static func fountain() -> ArrayMesh:
	var st := _begin()
	var I := Transform3D.IDENTITY
	P.cylinder(st, Vector3.ZERO, 3.2, 3.2, 0.5, 16, MARBLE_SHADE, I)
	P.cylinder(st, Vector3(0, 0.5, 0), 2.8, 2.8, 0.02, 16, WATER, I)
	P.cylinder(st, Vector3(0, 0.3, 0), 0.9, 0.9, 0.3, 12, MARBLE_SHADE, I)
	P.column(st, Vector3(0, 0.6, 0), 1.9, 0.22, MARBLE, I)
	P.cylinder(st, Vector3(0, 2.5, 0), 1.0, 1.0, 0.18, 12, MARBLE_SHADE, I)
	P.cylinder(st, Vector3(0, 2.68, 0), 0.85, 0.85, 0.02, 12, WATER, I)
	for i in 4:   # dalles autour
		var a := i * PI / 2.0 + PI / 4.0
		P.box(st, Vector3(cos(a) * 3.9, 0, sin(a) * 3.9), Vector3(1.0, 0.12, 1.0), MARBLE_SHADE, I, Color.TRANSPARENT, a)
	return _end(st)

static func forum_slab() -> ArrayMesh:
	var st := _begin()
	var I := Transform3D.IDENTITY
	P.cylinder(st, Vector3.ZERO, 6.5, 6.5, 0.12, 28, MARBLE_SHADE.darkened(0.06), I)
	for i in 28:   # bordure en dalles alternées
		var a := i * TAU / 28.0
		P.box(st, Vector3(cos(a) * 6.3, 0.12, sin(a) * 6.3), Vector3(1.0, 0.04, 0.9), MARBLE_SHADE if i % 2 else MARBLE, I, Color.TRANSPARENT, -a + PI / 2.0)
	return _end(st)

# La Curie : petit temple du Sénat, porte vers +z (vers la fontaine).
static func curia() -> ArrayMesh:
	var st := _begin()
	var I := Transform3D.IDENTITY
	var xf := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)   # la façade (porte à -z dans le kit) regarde +z
	var h := 3.4
	P.box(st, Vector3(0, 0, 0.4), Vector3(5.0, h, 4.0), MARBLE, xf)
	P.box(st, Vector3(0, 0, 0.4), Vector3(5.1, 0.5, 4.1), MARBLE_SHADE, xf)
	for i in 6:
		P.column(st, Vector3(-2.1 + i * 0.84, 0, -2.2), h, 0.16, MARBLE, xf)
	P.box(st, Vector3(0, h, -0.5), Vector3(5.6, 0.35, 5.6), MARBLE_SHADE, xf)
	P.prism(st, Vector3(0, h + 0.35, -0.5), 6.0, 5.8, 1.4, TILE, xf, POMPEI, PI / 2.0)
	P.tiles(st, Vector3(0, h + 0.35, -0.5), 6.0, 5.8, 1.4, TILE_DARK, xf, PI / 2.0)
	P.box(st, Vector3(0, 0, -1.6), Vector3(1.2, 2.0, 0.1), DOOR, xf)
	P.stairs(st, Vector3(0, 0, -3.3), 4.4, 4, 0.14, 0.3, MARBLE_SHADE, xf)
	for x in [-3.2, 3.2]:
		P.box(st, Vector3(x, 0, -2.6), Vector3(0.6, 0.9, 0.6), MARBLE_SHADE, xf)
		_statuette(st, Vector3(x, 0.9, -2.6), 1.1, BRONZE, xf)
	P.pyramid(st, Vector3(0, h + 1.75, -3.3), 0.4, 0.4, 0.5, GOLD, xf)
	return _end(st)

# --- Monuments du Forum ---

static func monument(id: String) -> ArrayMesh:
	var key := "m|" + id
	if _cache.has(key):
		return _cache[key]
	var st := _begin()
	var I := Transform3D.IDENTITY
	match id:
		"jardins":
			for i in 12:
				var a := i * TAU / 12.0
				P.box(st, Vector3(cos(a) * 2.8, 0, sin(a) * 2.8), Vector3(1.3, 0.6, 0.4), IVY, I, IVY.lightened(0.15), -a + PI / 2.0)
			P.cylinder(st, Vector3.ZERO, 1.2, 1.2, 0.4, 12, MARBLE_SHADE, I)
			P.cylinder(st, Vector3(0, 0.4, 0), 1.0, 1.0, 0.02, 12, WATER, I)
			for a in [0.8, 2.9, 4.6]:   # cyprès
				P.cylinder(st, Vector3(cos(a) * 1.9, 0, sin(a) * 1.9), 0.35, 0.05, 2.6, 8, Color("2f4a2b"), I)
		"statue":
			P.box(st, Vector3.ZERO, Vector3(1.4, 0.4, 1.4), MARBLE_SHADE, I)
			P.column(st, Vector3(0, 0.4, 0), 2.2, 0.3, MARBLE, I)
			_statuette(st, Vector3(0, 2.6, 0), 2.0, GOLD, I)
		"colonnade":
			for i in 6:
				P.column(st, Vector3(-3.75 + i * 1.5, 0, 0), 3.0, 0.16, MARBLE, I)
			P.box(st, Vector3(0, 3.0, 0), Vector3(8.4, 0.35, 0.9), MARBLE_SHADE, I)
			P.prism(st, Vector3(0, 3.35, 0), 8.6, 1.1, 0.35, TILE, I)
		"temple":
			P.box(st, Vector3.ZERO, Vector3(5.4, 0.5, 4.2), MARBLE_SHADE, I)
			P.box(st, Vector3(0, 0.5, 0.3), Vector3(3.2, 3.0, 2.8), MARBLE, I)
			for row in [-1.6, 1.6]:
				for i in 4:
					P.column(st, Vector3(-2.25 + i * 1.5, 0.5, row), 3.0, 0.16, MARBLE, I)
			P.box(st, Vector3(0, 3.5, 0), Vector3(5.6, 0.35, 4.4), MARBLE_SHADE, I)
			P.prism(st, Vector3(0, 3.85, 0), 4.6, 5.8, 1.3, TILE, I, POMPEI, PI / 2.0)
			P.tiles(st, Vector3(0, 3.85, 0), 4.6, 5.8, 1.3, TILE_DARK, I, PI / 2.0)
			P.stairs(st, Vector3(0, 0, -2.1), 4.0, 3, 0.17, 0.3, MARBLE_SHADE, I)
		"arc":
			P.arch(st, Vector3.ZERO, 4.2, 3.6, 1.6, 0.8, MARBLE, I, 10)
			P.box(st, Vector3(0, 3.6 + 0.48, 0), Vector3(4.6, 1.0, 1.7), MARBLE_SHADE, I)
			P.box(st, Vector3(0, 4.1, -0.86), Vector3(2.6, 0.5, 0.06), PURPLE, I)
			for x in [-1.6, 1.6]:
				_statuette(st, Vector3(x, 5.1, 0), 1.2, GOLD, I)
		"aqueduc":
			for i in 5:
				P.arch(st, Vector3(-3.6 + i * 1.8, 0, 0), 1.8, 2.4, 1.0, 0.3, STONE, I, 6)
			P.box(st, Vector3(0, 2.6, 0), Vector3(9.2, 0.6, 1.1), STONE_DARK, I)
			P.box(st, Vector3(0, 3.2, 0), Vector3(9.0, 0.02, 0.6), WATER, I)
		"amphitheatre":
			var n := 18
			for i in n:
				var a := i * TAU / n
				var xf := Transform3D(Basis(Vector3.UP, -a), Vector3(cos(a) * 5.2, 0, sin(a) * 5.2 * 0.8))
				P.arch(st, Vector3.ZERO, 1.7, 2.2, 0.9, 0.3, STONE, xf, 6)
				P.box(st, Vector3(0, 2.2, 0), Vector3(1.7, 0.9, 0.9), STONE, xf, STONE_DARK)
			P.cylinder(st, Vector3.ZERO, 4.2, 4.2, 0.3, 24, OCHRE.lightened(0.2), I)
		"pantheon":
			P.cylinder(st, Vector3.ZERO, 3.2, 3.2, 3.0, 20, MARBLE, I)
			P.cylinder(st, Vector3(0, 3.0, 0), 3.3, 3.3, 0.3, 20, MARBLE_SHADE, I)
			P.dome(st, Vector3(0, 3.3, 0), 3.2, BRONZE.lightened(0.1), I, 6, 20)
			for i in 6:
				P.column(st, Vector3(-2.0 + i * 0.8, 0, -4.2), 3.0, 0.15, MARBLE, I)
			P.box(st, Vector3(0, 3.0, -3.6), Vector3(5.2, 0.35, 2.2), MARBLE_SHADE, I)
			P.prism(st, Vector3(0, 3.35, -3.6), 2.4, 5.4, 1.1, TILE, I, POMPEI, PI / 2.0)
			P.stairs(st, Vector3(0, 0, -5.4), 4.6, 3, 0.14, 0.3, MARBLE_SHADE, I)
	var mesh := _end(st)
	_cache[key] = mesh
	return mesh

# --- Arbres méditerranéens (couleurs par sommet, feuillage qui ondule) ---
# UV.x = hauteur du centre du houppier, UV.y = 1 sur le feuillage (normales arrondies), 0 sur le tronc.

static func _leaf_material() -> ShaderMaterial:
	if _mat_leaf == null:
		_mat_leaf = ShaderMaterial.new()
		_mat_leaf.shader = preload("res://shaders/rome_leaf.gdshader")
	return _mat_leaf

static func _foliage(st: SurfaceTool, crown_y: float) -> void:
	st.set_uv(Vector2(crown_y, 1.0))

static func _trunk(st: SurfaceTool) -> void:
	st.set_uv(Vector2(0.0, 0.0))

static func tree(kind: String, variant: int = 0) -> ArrayMesh:
	var key := "t|%s|%d" % [kind, variant % 3]
	if _cache.has(key):
		return _cache[key]
	var st := _begin()
	var I := Transform3D.IDENTITY
	var rng := RandomNumberGenerator.new()
	rng.seed = variant
	match kind:
		"cypres":   # fuseau sombre et étroit, en trois cônes empilés
			var h := rng.randf_range(4.2, 5.6)
			_trunk(st)
			P.cylinder(st, Vector3.ZERO, 0.14, 0.1, 0.5, 6, TRUNK, I)
			_foliage(st, h * 0.45)
			P.cylinder(st, Vector3(0, 0.4, 0), 0.55, 0.62, h * 0.35, 7, CYPRESS, I, 0.1)
			P.cylinder(st, Vector3(0, 0.4 + h * 0.35, 0), 0.62, 0.42, h * 0.35, 7, CYPRESS.lightened(0.06), I, 0.1)
			P.cylinder(st, Vector3(0, 0.4 + h * 0.7, 0), 0.42, 0.0, h * 0.3, 7, CYPRESS.lightened(0.1), I, 0.1)
		"pin":   # pin parasol : tronc haut légèrement penché, couronne aplatie en deux dômes
			var h := rng.randf_range(3.0, 4.0)
			var r := rng.randf_range(1.5, 1.9)
			_trunk(st)
			P.cylinder(st, Vector3.ZERO, 0.22, 0.15, h, 7, TRUNK, I)
			P.cylinder(st, Vector3(0.25, h * 0.55, 0.15), 0.1, 0.06, h * 0.4, 5, TRUNK, I)
			_foliage(st, h + 0.3)
			P.cylinder(st, Vector3(0, h - 0.25, 0), r * 0.55, r, 0.45, 10, PINE.darkened(0.12), I, 0.1, false)
			P.dome(st, Vector3(0, h + 0.2, 0), r, PINE, I, 4, 10, 0.62)
			P.dome(st, Vector3(r * 0.4, h + 0.1, r * 0.3), r * 0.55, PINE.lightened(0.08), I, 3, 8, 0.7)
		"olivier":   # tronc tordu, trois boules de feuillage gris-vert
			_trunk(st)
			P.cylinder(st, Vector3.ZERO, 0.3, 0.2, 1.3, 6, TRUNK.lightened(0.15), I, 0.3)
			P.cylinder(st, Vector3(0.25, 1.1, 0.1), 0.14, 0.08, 1.0, 5, TRUNK.lightened(0.15), I)
			P.cylinder(st, Vector3(-0.3, 1.0, -0.2), 0.14, 0.08, 0.9, 5, TRUNK.lightened(0.15), I)
			_foliage(st, 2.2)
			P.dome(st, Vector3(0, 1.5, 0), 1.3, OLIVE, I, 4, 9, 0.85)
			P.dome(st, Vector3(0.7, 1.7, 0.4), 0.9, OLIVE.lightened(0.08), I, 3, 8, 0.9)
			P.dome(st, Vector3(-0.6, 1.6, -0.5), 1.0, OLIVE.darkened(0.06), I, 3, 8, 0.9)
		"laurier":   # buisson dense
			_foliage(st, 0.7)
			P.dome(st, Vector3.ZERO, 0.9, LAUREL, I, 3, 8)
			P.dome(st, Vector3(0.5, 0.0, 0.3), 0.6, LAUREL.lightened(0.1), I, 2, 7)
		"lavande":
			_foliage(st, 0.3)
			P.dome(st, Vector3.ZERO, 0.5, Color("7a6a9a"), I, 2, 7)
			for i in 5:
				var a := i * TAU / 5.0
				P.cylinder(st, Vector3(cos(a) * 0.25, 0.3, sin(a) * 0.25), 0.05, 0.03, 0.4, 4, Color("8f6fc4"), I)
	var mesh := st.commit()
	mesh.surface_set_material(0, _leaf_material())
	_cache[key] = mesh
	return mesh

# --- Tenues romaines des personnages (en espace modèle Kenney, personnage d'environ 0,9 de haut) ---

static func garment(unit: String) -> ArrayMesh:
	var key := "g|" + unit
	if _cache.has(key):
		return _cache[key]
	var st := _begin()
	var I := Transform3D.IDENTITY
	match unit:
		"chevalier":   # Légat : toge blanche à bande pourpre, couronne de laurier
			P.cylinder(st, Vector3(0, 0.28, 0), 0.2, 0.17, 0.4, 8, MARBLE, I, 0.0, false, false)
			P.box(st, Vector3(0.09, 0.3, 0.17), Vector3(0.06, 0.36, 0.02), PURPLE, I)
			for i in 10:
				var a := i * TAU / 10.0
				P.box(st, Vector3(cos(a) * 0.17, 0.84, sin(a) * 0.17), Vector3(0.06, 0.04, 0.05), LAUREL, I, Color.TRANSPARENT, -a)
		"soldat":   # Légionnaire : cuirasse rouge, casque avec cimier
			P.cylinder(st, Vector3(0, 0.3, 0), 0.2, 0.18, 0.36, 8, POMPEI, I, 0.0, false, false)
			P.box(st, Vector3(0, 0.3, 0), Vector3(0.42, 0.06, 0.42), BRONZE, I)
			P.dome(st, Vector3(0, 0.8, 0), 0.19, BRONZE, I, 3, 8)
			P.box(st, Vector3(0, 0.92, 0), Vector3(0.05, 0.12, 0.3), POMPEI, I)
		"eclaireur":   # Vélite : tunique courte ocre, bandeau
			P.cylinder(st, Vector3(0, 0.32, 0), 0.19, 0.17, 0.3, 8, OCHRE, I, 0.0, false, false)
			P.cylinder(st, Vector3(0, 0.82, 0), 0.18, 0.18, 0.05, 8, POMPEI, I, 0.0, false, false)
		"mage":   # Augure : robe blanche, voile et lituus (bâton recourbé)
			P.cylinder(st, Vector3(0, 0.2, 0), 0.22, 0.17, 0.5, 8, MARBLE, I, 0.0, false, false)
			P.cylinder(st, Vector3(0, 0.72, 0), 0.22, 0.16, 0.22, 8, MARBLE_SHADE, I, 0.0, false, false)
			P.cylinder(st, Vector3(0.26, 0.0, 0.1), 0.02, 0.02, 1.0, 5, WOOD, I)
			P.dome(st, Vector3(0.26, 1.0, 0.1), 0.06, WOOD, I, 2, 6)
		_:   # Plébéien : tunique brute
			P.cylinder(st, Vector3(0, 0.3, 0), 0.19, 0.17, 0.34, 8, STUCCO.darkened(0.1), I, 0.0, false, false)
	var mesh := _end(st)
	_cache[key] = mesh
	return mesh
