extends Node3D
# Un village = un dossier de travail. Parcelle avec ses bâtiments (sessions), décor selon le niveau, nom et objectif.

# vicus = terre cuite, oppidum = vert olive, urbs = bleu égéen, métropole = or
const LEVEL_COLORS := {1: Color("c98f62"), 2: Color("9cbf5a"), 3: Color("5bb0d3"), 4: Color("e8c04a")}
const RES_NAMES := {"or": "gold", "bois": "wood", "pierre": "stone", "parchemins": "scrolls", "commits": "commits"}

var focused := false
var titre_au_loin := true   # faux sur la vue d'ensemble du téléphone : seuls les villages choisis ou qui t'attendent gardent leur nom

# Tags, objectif et noms des bâtiments n'apparaissent qu'au survol ou à la sélection du village : la carte reste propre.
func set_focus(on: bool) -> void:
	focused = on
	level_tag.visible = on
	goal.visible = on and goal.text != ""
	for b in buildings.values():
		b.set_focus(on)
	_maj_titre()

func montrer_titre_au_loin(on: bool) -> void:
	titre_au_loin = on
	_maj_titre()

func _maj_titre() -> void:
	if title:
		title.visible = titre_au_loin or focused or int(data.get("attention", 0)) > 0

func _exit_tree() -> void:
	if is_instance_valid(road):
		road.queue_free()

const KIT := preload("res://rome/kit.gd")
var main: Node
var data := {}
var buildings := {}
var decor: Node3D
var decor_key := ""
var title: Label3D
var level_tag: Label3D
var goal: Label3D
var road: Node3D
var ang := 0.0

func setup(m: Node, v: Dictionary) -> void:
	main = m
	ang = float(v.ang)
	position = Vector3(float(v.x), 0, float(v.z))
	title = main._label("", 7.6, 0.016)
	add_child(title)
	level_tag = main._tag("", 6.7, Color.WHITE, true)
	add_child(level_tag)
	goal = main._label("", 5.9, 0.01)
	goal.visibility_range_end = 0.0
	add_child(goal)
	road = main._road_to(Vector2(float(v.x), float(v.z)), 5.5)
	update(v)
	set_focus(false)

func update(v: Dictionary) -> void:
	data = v
	var key := "%d|%d" % [int(v.level), int(v.get("vitalite", 100)) / 25]
	if key != decor_key:
		decor_key = key
		_decor()
	var stars := ""
	for i in int(v.level):
		stars += "★"
	title.text = String(v.name).to_upper()
	_maj_titre()
	var vit := float(v.get("vitalite", 100)) / 100.0
	title.modulate = Color(0.62, 0.6, 0.56).lerp(Color("f7f1e3"), vit)
	level_tag.text = "  %s %s  " % [String(v.levelName).to_upper(), stars]
	level_tag.outline_modulate = LEVEL_COLORS.get(int(v.level), Color.WHITE)
	if v.get("objectif"):
		var o: Dictionary = v.objectif
		var n := int(round(float(o.progress) * 10.0))
		goal.text = "%s  %s%s  %d/%d %s" % [o.texte, "▰".repeat(n), "▱".repeat(10 - n), int(o.have), int(o.cible), String(RES_NAMES.get(o.res, o.res))]
		goal.modulate = Color("ffe08a") if o.done else Color("f7f1e3")
	else:
		goal.text = ""
	var seen := {}
	for b in v.buildings:
		if b.get("hidden", false):
			continue
		seen[b.id] = true
		var bd: Dictionary = b.duplicate()
		bd["village"] = v.id
		if not buildings.has(b.id):
			var node := preload("res://building.gd").new()
			node.position = to_local(Vector3(float(b.x), 0, float(b.z)))
			node.rotation.y = -ang + PI / 2.0   # la porte regarde vers le Town Center
			add_child(node)
			node.setup(main, bd)
			node.set_focus(focused)
			buildings[b.id] = node
		else:
			buildings[b.id].update(bd)
	for id in buildings.keys():
		if not seen.has(id):
			buildings[id].queue_free()
			buildings.erase(id)

var _batch: RefCounted

func _m(name: String, pos: Vector3, sc: float = 1.0, rot: float = 0.0) -> void:
	_batch.add(name, pos, sc, rot)

# Enceinte selon le niveau : haie (vicus), muret (oppidum), remparts et tourelles (urbs), colonnade, porte et statues (métropole).
func _decor() -> void:
	if decor:
		decor.queue_free()
	decor = Node3D.new()
	decor.rotation.y = -ang + PI / 2.0
	add_child(decor)
	var level := int(data.level)
	_batch = preload("res://batch.gd").new()
	for kind in ["muret", "rempart", "colonnade", "porte", "tourelle", "statue", "haie"]:
		_batch.register("rome/" + kind, KIT.wall_piece(kind))
	# abandon : plus la vitalité baisse, plus les herbes folles et les pierres envahissent la parcelle
	var neglect := 1.0 - float(data.get("vitalite", 100)) / 100.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(String(data.id).hash())
	for i in int(neglect * 26.0):
		_m("nature/Bush_Common" if i % 3 else "nature/Rock_Medium_1", Vector3(rng.randf_range(-6.0, 6.0), 0, rng.randf_range(-4.0, 13.0)), rng.randf_range(0.5, 0.9), rng.randf() * TAU)
	var w := 13.0
	var l := 18.0
	var zc := 4.0   # centre de la parcelle (les bâtiments sont décalés vers l'extérieur)
	var piece: String = {1: "rome/haie", 2: "rome/muret", 3: "rome/rempart", 4: "rome/colonnade"}[mini(level, 4)]
	var step := 2.0 if level >= 4 else 1.0   # la colonnade est faite de travées de 2 m
	var x := -w / 2.0
	while x <= w / 2.0:
		if absf(x) > 1.8:   # la porte du village est au milieu du mur qui regarde le Forum
			_m(piece, Vector3(x, 0, zc - l / 2.0), 1.0, 0.0)
		_m(piece, Vector3(x, 0, zc + l / 2.0), 1.0, PI)
		x += step
	var z := zc - l / 2.0 + 1.0
	while z < zc + l / 2.0:
		_m(piece, Vector3(-w / 2.0, 0, z), 1.0, PI / 2.0)
		_m(piece, Vector3(w / 2.0, 0, z), 1.0, -PI / 2.0)
		z += step
	if level >= 3:
		for c in [Vector3(-w / 2.0, 0, zc - l / 2.0), Vector3(w / 2.0, 0, zc - l / 2.0), Vector3(-w / 2.0, 0, zc + l / 2.0), Vector3(w / 2.0, 0, zc + l / 2.0)]:
			_m("rome/tourelle", c)
	if level >= 4:
		_m("rome/porte", Vector3(0, 0, zc - l / 2.0), 1.0, 0.0)
		for c in [Vector3(-2.6, 0, zc - l / 2.0 - 1.2), Vector3(2.6, 0, zc - l / 2.0 - 1.2)]:
			_m("rome/statue", c)
	_batch.build(decor, main.world)
