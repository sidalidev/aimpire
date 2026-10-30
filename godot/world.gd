extends Node3D
# Le monde : soleil, ciel peint, terrain peint avec relief, lac, herbe au vent, forêts, Forum, chemins,
# contours dessinés en post-traitement, et paliers de qualité (adaptatifs pour rester au-dessus de 100 FPS).

const LAKE := Vector2(48.0, 38.0)      # centre du lac, dans une couronne libre de villages
const LAKE_R := Vector2(15.0, 10.0)    # demi-axes de l'ellipse

const KIT := preload("res://rome/kit.gd")
var main: Node
var env: Environment
var sun: DirectionalLight3D
var grass: Node3D
var post: MeshInstance3D
var quality := 0
var _fps_acc := 0.0
var _fps_n := 0
var _toon_cache := {}                  # Material d'origine -> ShaderMaterial peint
var _noise_a: NoiseTexture2D
var _noise_b: NoiseTexture2D

func setup() -> void:
	_noise_a = _noise(3, 0.05)
	_noise_b = _noise(11, 0.09)
	_make_light_and_sky()
	var sol := _make_ground()
	add_child(sol)
	if main.mobile:   # vue d'ensemble du téléphone : le haut de l'écran voit au-delà du terrain
		add_child(_make_outer_ground(sol.material_override))
	_make_lake()
	_make_forum()
	_make_grass()
	_make_post()

# --- Matériaux peints ---
static func _noise(seed: int, freq: float) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	var t := NoiseTexture2D.new()
	t.noise = n
	t.seamless = true
	t.width = 512
	t.height = 512
	t.generate_mipmaps = true
	return t

# Version peinte d'un matériau Kenney : même texture et même couleur, éclairage toon. Mis en cache.
func toon_for(src: Material, ruin := false) -> ShaderMaterial:
	var key := [src, ruin]
	if _toon_cache.has(key):
		return _toon_cache[key]
	var m := ShaderMaterial.new()
	var leaf: bool = src is BaseMaterial3D and src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.shader = preload("res://shaders/toon_leaf.gdshader") if leaf else preload("res://shaders/toon_tex.gdshader")
	if src is BaseMaterial3D:
		m.set_shader_parameter("albedo_tex", src.albedo_texture)
		m.set_shader_parameter("tint", src.albedo_color)
	m.set_shader_parameter("ruin", 1.0 if ruin else 0.0)
	_toon_cache[key] = m
	return m

# Copie d'un maillage où chaque surface reçoit son matériau peint (un arbre = écorce + feuilles). Mise en cache.
var _mesh_cache := {}
func toon_mesh(mesh: Mesh, ruin := false) -> Mesh:
	var key := [mesh, ruin]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var copy: Mesh = mesh.duplicate()
	for i in copy.get_surface_count():
		var src: Material = mesh.surface_get_material(i)
		if src and not (src is ShaderMaterial):
			var tm := toon_for(src, ruin)
			# centre du houppier au tiers supérieur du maillage, pour l'ombrage en boule des feuilles
			if tm.shader == preload("res://shaders/toon_leaf.gdshader"):
				tm = tm.duplicate()
				var aabb := mesh.get_aabb()
				tm.set_shader_parameter("crown_y", aabb.position.y + aabb.size.y * 0.66)
			copy.surface_set_material(i, tm)
	_mesh_cache[key] = copy
	return copy

# Applique le rendu peint à toutes les surfaces d'un modèle instancié (bâtiments du Forum, personnages).
func toonify(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var src: Material = mi.get_active_material(i)
			if src and not (src is ShaderMaterial):
				mi.set_surface_override_material(i, toon_for(src))

func model(model_name: String, pos: Vector3, sc: float = 1.0, rot_y: float = 0.0, parent: Node = null) -> Node3D:
	var n: Node3D = load("res://assets/town/%s.glb" % model_name).instantiate()
	n.position = pos
	n.scale = Vector3.ONE * sc
	n.rotation.y = rot_y
	(parent if parent else self).add_child(n)
	toonify(n)
	return n

# --- Lumière, ciel, environnement ---
func _make_light_and_sky() -> void:
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 38, 0)      # fin d'après-midi méditerranéenne : soleil bas, ombres longues
	sun.light_color = Color("ffd9a3")
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 90.0
	sun.shadow_blur = 1.5
	add_child(sun)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = preload("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("clouds", _noise_a)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Ni l'ambiante ni les reflets ne viennent du ciel : sa carte de radiance (6 faces et filtrage) n'est donc pas
	# recalculée à chaque image alors que le shader du ciel bouge (TIME). Presque tous les matériaux sont sans spéculaire.
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.ambient_light_color = Color("b4c0dc")      # lumière du ciel, bleutée : remplit les ombres sans les noircir
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.06
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4
	env.fog_enabled = true
	env.fog_light_color = Color("f0dcb8")
	env.fog_density = BRUME
	env.fog_sky_affect = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

# --- Terrain : plat là où vivent les villages, collines puis montagnes vers l'horizon, cuvette du lac ---
func height(x: float, z: float, noise: FastNoiseLite) -> float:
	var r := sqrt(x * x + z * z)
	var ramp := clampf((r - 92.0) / 60.0, 0.0, 1.0)
	var bump := (noise.get_noise_2d(x, z) + 0.5) * 14.0 * ramp * ramp
	var rim := clampf((r - 135.0) / 30.0, 0.0, 1.0) * 26.0 * (0.6 + 0.4 * noise.get_noise_2d(x * 3.0, z * 3.0))
	var e := Vector2((x - LAKE.x) / LAKE_R.x, (z - LAKE.y) / LAKE_R.y).length()
	var lake := -2.4 * (1.0 - smoothstep(0.55, 1.15, e))
	return bump + rim + lake + noise.get_noise_2d(x * 0.5, z * 0.5) * 0.12

func _make_ground() -> MeshInstance3D:
	var size := 340.0
	var n := 150
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.02
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts := []
	for j in range(n + 1):
		var row := []
		for i in range(n + 1):
			var x := -size / 2.0 + size * i / n
			var z := -size / 2.0 + size * j / n
			row.append(Vector3(x, height(x, z, noise), z))
		verts.append(row)
	for j in n:
		for i in n:
			var a: Vector3 = verts[j][i]
			var b: Vector3 = verts[j][i + 1]
			var c: Vector3 = verts[j + 1][i]
			var d: Vector3 = verts[j + 1][i + 1]
			for tri in [[a, b, c], [b, d, c]]:   # sens horaire vu du dessus : face avant pour Godot
				var nrm: Vector3 = (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
				for v in tri:
					st.set_normal(nrm)
					st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("noise_a", _noise_a)
	mat.set_shader_parameter("noise_b", _noise_b)
	# garrigue : herbes sèches jaune-vert, terre sableuse, affleurements calcaires, taches de genêt
	mat.set_shader_parameter("grass_dark", Color(0.30, 0.42, 0.17))
	mat.set_shader_parameter("grass_mid", Color(0.50, 0.57, 0.24))
	mat.set_shader_parameter("grass_light", Color(0.70, 0.70, 0.36))
	mat.set_shader_parameter("dirt", Color(0.70, 0.58, 0.40))
	mat.set_shader_parameter("rock", Color(0.72, 0.70, 0.64))
	mat.set_shader_parameter("flower", Color(0.95, 0.85, 0.40))
	mi.material_override = mat
	return mi

# Sol au-delà du terrain (340 unités de côté) : un anneau plat sous le niveau du lac, du bord du terrain à 1 200 unités,
# avec le même matériau peint. Il ne recouvre rien du terrain (trou au milieu) : un seul appel de dessin, pas de
# surdessin. Seulement sur le téléphone, dont la vue d'ensemble en portrait regarde loin (docs/MOBILE-PORTRAIT.md §3.3).
func _make_outer_ground(mat: Material) -> MeshInstance3D:
	var dedans := 165.0
	var dehors := 1200.0
	var y := -3.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var bords := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for i in 4:
		var a: Vector2 = bords[i]
		var b: Vector2 = bords[(i + 1) % 4]
		var ai := Vector3(a.x * dedans, y, a.y * dedans)
		var bi := Vector3(b.x * dedans, y, b.y * dedans)
		var ao := Vector3(a.x * dehors, y, a.y * dehors)
		var bo := Vector3(b.x * dehors, y, b.y * dehors)
		for v in [ai, ao, bo, ai, bo, bi]:   # sens horaire vu du dessus, comme le terrain
			st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _make_lake() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = LAKE_R * 2.3
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	mi.mesh = pm
	mi.position = Vector3(LAKE.x, -0.35, LAKE.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/water.gdshader")
	mat.set_shader_parameter("noise_tex", _noise_b)
	mi.material_override = mat
	add_child(mi)
	var b := preload("res://batch.gd").new()     # roseaux et pierres sur la berge
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 40:
		var a := rng.randf() * TAU
		var e := rng.randf_range(1.0, 1.25)
		var p := LAKE + Vector2(cos(a) * LAKE_R.x * e, sin(a) * LAKE_R.y * e)
		b.add("rock-small" if i % 3 == 0 else "hedge", Vector3(p.x, 0, p.y), rng.randf_range(0.7, 1.3), rng.randf() * TAU)
	b.build(self, self)

func _in_lake(p: Vector2, margin := 1.35) -> bool:
	return Vector2((p.x - LAKE.x) / LAKE_R.x, (p.y - LAKE.y) / LAKE_R.y).length() < margin

# --- Forum, décor, chemins ---
var monuments_node: Node3D
var _monuments_key := ""

func _make_forum() -> void:
	var f := MeshInstance3D.new()
	f.mesh = KIT.fountain()
	add_child(f)
	var curia := MeshInstance3D.new()
	curia.mesh = KIT.curia()
	curia.position = Vector3(0, 0, -11.0)
	add_child(curia)
	var body := StaticBody3D.new()       # le Forum se clique comme un village : il ouvre le panneau du Sénat et des monuments
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(7, 3, 7)
	shape.shape = bx
	body.add_child(shape)
	body.position.y = 1.5
	body.set_meta("village", "forum")
	add_child(body)
	add_child(main.ui.label("FORUM", 4.0, 0.016))
	# dallage du Forum : un disque de marbre légèrement surélevé
	var slab := MeshInstance3D.new()
	slab.mesh = KIT.forum_slab()
	add_child(slab)
	for i in 4:
		var a := i * PI / 2.0 + PI / 4.0
		var b := MeshInstance3D.new()
		b.mesh = KIT.wall_piece("statue")
		b.position = Vector3(cos(a) * 5.4, 0.1, sin(a) * 5.4)
		b.rotation.y = -a + PI / 2.0
		add_child(b)

# Forêts en bosquets, lisières de buissons, fleurs, fougères, champignons, rochers.
# Modèles Quaternius (CC0) : arbres de 3 500 à 6 000 triangles, regroupés par carrés de 30 m et masqués au loin.
var decor_node: Node3D
var _decor_key := ""
var _village_pos := []

# Appelé à chaque état : (re)plante les forêts quand l'ensemble des villages change de place.
func ensure_decor(villages: Array) -> void:
	var pts := []
	for v in villages:
		pts.append(Vector2(float(v.x), float(v.z)))
	var key := str(pts)
	if key == _decor_key:
		return
	_decor_key = key
	_village_pos = pts
	if decor_node:
		decor_node.queue_free()
	decor_node = Node3D.new()
	add_child(decor_node)
	_make_decor()

func _make_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var groves := FastNoiseLite.new()
	groves.seed = 21
	groves.frequency = 0.035
	var bt := preload("res://batch.gd").new()
	var bu := preload("res://batch.gd").new()
	var br := preload("res://batch.gd").new()
	for b in [bt, bu, br]:
		b.chunk = 30.0
	for kind in ["cypres", "pin", "olivier", "laurier", "lavande"]:
		for v in 3:
			bt.register("rome/%s_%d" % [kind, v], KIT.tree(kind, v))
	var under := ["nature/Bush_Common", "nature/Bush_Common_Flowers", "nature/Fern_1", "nature/Plant_1_Big", "nature/Plant_7_Big", "nature/Flower_3_Group", "nature/Flower_4_Group", "nature/Grass_Wispy_Tall", "nature/Grass_Common_Tall", "nature/Clover_1", "nature/Mushroom_Common"]
	var rocks := ["nature/Rock_Medium_1", "nature/Rock_Medium_2", "nature/Rock_Medium_3"]
	# forêts méditerranéennes en bosquets : pins parasols dominants, cyprès en bouquets, quelques feuillus
	var placed := 0
	var tries := 0
	while placed < 650 and tries < 40000:
		tries += 1
		var p := Vector2.from_angle(rng.randf() * TAU) * (9.0 + 125.0 * pow(rng.randf(), 1.25))
		if not _free_for_decor(p) or groves.get_noise_2d(p.x, p.y) < -0.08:
			continue
		var r := rng.randf()
		var t: String
		if r < 0.5:
			t = "rome/pin_%d" % (rng.randi() % 3)
		elif r < 0.72:
			t = "rome/cypres_%d" % (rng.randi() % 3)
		else:
			t = "nature/CommonTree_%d" % (1 + rng.randi() % 5)
		bt.add(t, Vector3(p.x, 0, p.y), rng.randf_range(0.8, 1.15) if t.begins_with("rome") else rng.randf_range(0.5, 0.75), rng.randf() * TAU)
		placed += 1
		if rng.randf() < 0.5:   # sous-bois : lauriers, lavande, buissons
			var q := p + Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
			var u := rng.randf()
			bu.add("rome/laurier_%d" % (rng.randi() % 3) if u < 0.4 else ("rome/lavande_%d" % (rng.randi() % 3) if u < 0.7 else under[rng.randi() % 4]), Vector3(q.x, 0, q.y), rng.randf_range(0.8, 1.3), rng.randf() * TAU)
	# oliveraies : une couronne d'oliviers en quinconce autour de chaque village, et deux cyprès à la porte
	for c0 in _village_pos:
		var c: Vector2 = c0
		var dir: Vector2 = c.normalized()
		var n := 10
		for i in n:
			var a := i * TAU / n + 0.3
			var p: Vector2 = c + Vector2(cos(a), sin(a)) * rng.randf_range(11.0, 13.5)
			if p.length() < 9.0 or _in_lake(p) or absf(Vector2(cos(a), sin(a)).dot(-dir)) > 0.85:   # pas devant la porte
				continue
			var ok := true
			for other in _village_pos:
				if other != c0 and p.distance_to(other) < 9.5:
					ok = false
			if ok:
				bt.add("rome/olivier_%d" % (rng.randi() % 3), Vector3(p.x, 0, p.y), rng.randf_range(0.8, 1.1), rng.randf() * TAU)
		var gate: Vector2 = c - dir * 9.8
		var perp := Vector2(-dir.y, dir.x)
		for sgn in [1.0, -1.0]:
			var g: Vector2 = gate + perp * sgn * 2.6
			bt.add("rome/cypres_%d" % (rng.randi() % 3), Vector3(g.x, 0, g.y), 0.85, rng.randf() * TAU)
	# allée de cyprès autour du Forum
	for i in 16:
		var a := i * TAU / 16.0 + PI / 16.0
		var p := Vector2(cos(a), sin(a)) * 9.0
		var near_road := false
		for c in _village_pos:
			var t := clampf(p.dot(c) / c.length_squared(), 0.0, 1.0)
			if p.distance_to(c * t) < 2.2:
				near_road = true
		if not near_road:
			bt.add("rome/cypres_%d" % (i % 3), Vector3(p.x, 0, p.y), 0.75, rng.randf() * TAU)
	for i in 1400:   # herbes sèches, fleurs, lavande éparse
		var p := Vector2(rng.randf_range(-100, 100), rng.randf_range(-100, 100))
		if p.length() < 7.0 or _in_lake(p, 1.05):
			continue
		var u := rng.randf()
		bu.add("rome/lavande_%d" % (rng.randi() % 3) if u < 0.15 else under[2 + rng.randi() % (under.size() - 2)], Vector3(p.x, 0, p.y), rng.randf_range(0.5, 0.9), rng.randf() * TAU)
	for i in 90:
		var p := Vector2(rng.randf_range(-130, 130), rng.randf_range(-130, 130))
		if _free_for_decor(p):
			br.add(rocks[rng.randi() % rocks.size()], Vector3(p.x, -0.2, p.y), rng.randf_range(0.5, 1.3), rng.randf() * TAU)
	if OS.get_environment("AIMPIRE_FPS") != "":
		print("DECOR arbres ", placed, " villages ", _village_pos.size())
	bt.build(decor_node, self, true, false, 160.0)
	bu.build(decor_node, self, false, false, 60.0)
	br.build(decor_node, self, true, false, 140.0)

# Emplacements possibles des villages : mêmes anneaux que le serveur (daemon/model.js, RINGS), deux premiers anneaux.
var _slots := []
func _village_slots() -> Array:
	if _slots.is_empty():
		for ring in [[8, 22.0, 0], [14, 40.0, 1]]:
			var n: int = ring[0]
			for i in n:
				var a := float(i) / n * TAU + (0.0 if ring[2] % 2 else PI / n)
				_slots.append(Vector2(cos(a), sin(a)) * float(ring[1]))
	return _slots

# Libre pour le décor : hors du Forum, du lac, des parcelles de village et des chemins qui y mènent.
func _free_for_decor(p: Vector2) -> bool:
	if p.length() < 9.0 or _in_lake(p):
		return false
	for c in _village_pos:
		if p.distance_to(c) < 9.5:
			return false
		var t := clampf(p.dot(c) / c.length_squared(), 0.0, 1.0)     # distance au chemin Forum → village
		if p.distance_to(c * t) < 2.6:
			return false
	return true

# Touffes d'herbe au vent : un petit maillage de 3 brins, répété par MultiMesh en carrés de 24 m (dessinés seulement s'ils sont visibles et proches).
func _make_grass() -> void:
	grass = Node3D.new()
	add_child(grass)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := k * TAU / 3.0 + 0.3
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x) * 0.16
		var tip := dir * 0.22 + Vector3(0, 0.42 + 0.08 * k, 0)
		for v in [[-side, 0.0], [side, 0.0], [tip, 1.0]]:
			st.set_uv(Vector2(0, v[1]))
			st.add_vertex(v[0])
	var tuft := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/grass.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var cells := {}
	for i in 9000:
		var p := Vector2(rng.randf_range(-95, 95), rng.randf_range(-95, 95))
		if p.length() < 6.0 or p.length() > 95.0 or _in_lake(p, 1.05):
			continue
		var c := Vector2i(floori(p.x / 24.0), floori(p.y / 24.0))
		if not cells.has(c):
			cells[c] = []
		cells[c].append(p)
	for c in cells:
		var pts: Array = cells[c]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = tuft
		mm.instance_count = pts.size()
		for i in pts.size():
			var p: Vector2 = pts[i]
			var s := rng.randf_range(0.7, 1.4)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), Vector3(p.x, 0, p.y)))
			mm.set_instance_color(i, Color(1, 1, 1).lerp(Color(1.1, 1.0, 0.75), rng.randf() * 0.5))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 75.0
		mmi.visibility_range_end_margin = 10.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		grass.add_child(mmi)

# Contours à l'encre et vignetage : un quad plein écran attaché à la caméra.
func _make_post() -> void:
	# les contours lisent la texture normal_roughness, réservée au rendu Forward+ (pas au rendu Mobile du téléphone)
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return
	post = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	post.mesh = q
	post.extra_cull_margin = 16384.0
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/post.gdshader")
	mat.render_priority = -128
	post.material_override = mat
	main.rig.cam.add_child(post)

# Un chemin de terre qui serpente du Forum jusqu'à l'entrée du village (courbe de Bézier, ruban de triangles).
func road_to(target: Vector2, stop_before: float = 2.0) -> MeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(target.x * 131 + target.y * 17)
	var dir := target.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var p0 := dir * 4.6
	var p2 := target - dir * stop_before
	var p1 := (p0 + p2) / 2.0 + perp * rng.randf_range(-0.22, 0.22) * target.length()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var steps := int(target.length() / 1.2) + 4
	for i in range(steps + 1):
		var t := float(i) / steps
		var pt: Vector2 = p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
		var tg: Vector2 = (p1 - p0).lerp(p2 - p1, t).normalized()
		var side: Vector2 = Vector2(-tg.y, tg.x) * 0.85
		var wob := sin(t * 23.0 + rng.randf() * 0.4) * 0.12
		for sgn in [1.0, -1.0]:
			var q: Vector2 = pt + side * (sgn + wob)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(sgn, t * steps))
			st.add_vertex(Vector3(q.x, 0.04, q.y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("c9a97a")   # sable et poussière des voies
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	main.add_child(mi)
	return mi

# Monuments achetés avec l'or : construits autour du Forum avec les pièces Kenney (colonnes, toits, arches),
# la statue est un personnage en marbre sur un piédestal.
const MONUMENT_SPOTS := {"jardins": Vector3(-8.5, 0, -1.5), "statue": Vector3(0, 0, -7.0), "colonnade": Vector3(8.5, 0, -1.5), "temple": Vector3(-7.0, 0, 7.5), "arc": Vector3(7.0, 0, 7.5),
	"aqueduc": Vector3(0, 0, 13.0), "amphitheatre": Vector3(10.5, 0, -10.5), "pantheon": Vector3(-10.5, 0, -10.5)}

func build_monuments(built: Array) -> void:
	var key := ",".join(built)
	if key == _monuments_key:
		return
	_monuments_key = key
	if monuments_node:
		monuments_node.queue_free()
	monuments_node = Node3D.new()
	add_child(monuments_node)
	for id in built:
		var c: Vector3 = MONUMENT_SPOTS.get(id, Vector3.ZERO)
		var mi := MeshInstance3D.new()
		mi.mesh = KIT.monument(id)
		mi.position = c
		mi.rotation.y = atan2(-c.x, -c.z) + PI      # la façade (porte à -z) regarde la fontaine
		if id == "aqueduc" or id == "colonnade":
			mi.rotation.y = atan2(-c.x, -c.z) + PI / 2.0
		monuments_node.add_child(mi)

# --- Qualité : 0 haute, 1 équilibrée (FSR 85 %, sans SSAO), 2 performance (FSR 70 %, sans MSAA ni herbe lointaine),
# 3 minimale (sans ombres ni halo : les ombres directionnelles sont le premier poste d'un GPU de téléphone) ---
func apply_quality(q: int) -> void:
	quality = clampi(q, 0, 3)
	var vp := get_viewport()
	var fsr := quality > 0 and RenderingServer.get_current_rendering_method() == "forward_plus"   # FSR : Forward+ seulement
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if fsr else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = [1.0, 0.85, 0.7, 0.6][quality]
	vp.msaa_3d = Viewport.MSAA_2X if quality <= 1 else Viewport.MSAA_DISABLED
	env.ssao_enabled = quality == 0
	env.glow_enabled = quality <= 2
	sun.shadow_enabled = quality <= 2
	sun.shadow_blur = 1.5 if quality <= 2 else 0.0
	sun.directional_shadow_max_distance = [90.0, 80.0, 65.0, 50.0][quality]
	if grass:
		grass.visible = quality <= 2
		for g in grass.get_children():
			g.visibility_range_end = [75.0, 65.0, 45.0, 0.0][quality]
	if post:
		post.visible = quality <= 2

# Brouillard : densité choisie pour le cadrage du Mac (zoom 46). Le téléphone en portrait recule jusqu'à 300 unités pour
# montrer tout l'Empire : à densité fixe, le voile couvrirait toute la vue d'ensemble (20 % à 220 unités). La densité suit
# donc la distance au-delà de 46, et ne change que si l'écart dépasse 2 % (rien à chaque image pendant un pincement lent).
const BRUME := 0.001

func brume_pour(d: float) -> void:
	if env == null:
		return
	var densite := BRUME * minf(1.0, 46.0 / maxf(d, 1.0))
	if absf(densite - env.fog_density) > densite * 0.02:
		env.fog_density = densite

# Pendant l'interaction : la mesure repart de zéro (les images d'un geste ne jugent pas la qualité).
func adapt_suspendre() -> void:
	_fps_acc = 0.0
	_fps_n = 0

func adapt(delta: float) -> void:
	if main.settings.data.qualite != "auto":
		return
	_fps_acc += delta
	_fps_n += 1
	if _fps_acc < 2.0:
		return
	var fps := _fps_n / _fps_acc
	_fps_acc = 0.0
	_fps_n = 0
	# sous un plafond (power.gd), on juge par rapport au plafond : 30 FPS plafonnés à 30 n'est pas une baisse de régime
	var cap := float(Engine.max_fps) if Engine.max_fps > 0 else 1000.0
	if fps < minf(100.0, cap * 0.9) and quality < 3:
		apply_quality(quality + 1)
	elif fps > minf(150.0, cap * 0.97) and quality > 0:
		apply_quality(quality - 1)

# --- Feux d'artifice au-dessus du Forum (objectif atteint, fête, événement rare) et saison cosmétique ---
var _fete := false
var _fete_t := 0.0

func fireworks(n: int = 1) -> void:
	for i in n:
		var p := GPUParticles3D.new()
		p.position = Vector3(randf_range(-6, 6), randf_range(8, 13), randf_range(-6, 6))
		p.amount = 90
		p.lifetime = 1.6
		p.one_shot = true
		p.explosiveness = 1.0
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.2
		pm.direction = Vector3.ZERO
		pm.spread = 180.0
		pm.initial_velocity_min = 5.0
		pm.initial_velocity_max = 8.0
		pm.gravity = Vector3(0, -3.0, 0)
		pm.damping_min = 1.5
		pm.damping_max = 2.5
		pm.scale_min = 0.08
		pm.scale_max = 0.16
		pm.color = [Color("ffd23f"), Color("ff5a4a"), Color("7fb3ff"), Color("f7f1e3")][i % 4]
		p.process_material = pm
		var mesh := SphereMesh.new()
		mesh.radius = 0.5
		mesh.height = 1.0
		mesh.radial_segments = 6
		mesh.rings = 3
		var mat := StandardMaterial3D.new()
		mat.albedo_color = pm.color
		mat.emission_enabled = true
		mat.emission = pm.color
		mat.emission_energy_multiplier = 3.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = mat
		p.draw_pass_1 = mesh
		add_child(p)
		get_tree().create_timer(0.4 * i).timeout.connect(func(): if is_instance_valid(p): p.emitting = true)
		get_tree().create_timer(3.0 + 0.4 * i).timeout.connect(func(): if is_instance_valid(p): p.queue_free())

# Saison : la lumière suit le calendrier (été blanc et chaud, automne doré, hiver pâle et bleuté, printemps frais).
func set_season(saison: String, fete: bool) -> void:
	_fete = fete
	match saison:
		"ete":
			sun.light_color = Color("fff0d0")
			sun.light_energy = 1.55
		"automne":
			sun.light_color = Color("ffd9a3")
			sun.light_energy = 1.5
		"hiver":
			sun.light_color = Color("e8ecff")
			sun.light_energy = 1.25
		"printemps":
			sun.light_color = Color("fff6e0")
			sun.light_energy = 1.45

func _process(delta: float) -> void:
	if not _fete:
		return
	_fete_t -= delta
	if _fete_t <= 0.0:
		_fete_t = randf_range(6.0, 12.0)
		fireworks(1)
