extends RefCounted
# Regroupe beaucoup d'objets Kenney identiques en un seul appel de dessin (MultiMesh), comme le font les jeux de stratégie :
# 900 arbres = quelques MultiMeshInstance3D au lieu de 900 nœuds. Les maillages de chaque modèle sont extraits une seule fois.

static var _parts := {}     # nom du modèle -> [[Mesh, Transform3D local], ...]
var groups := {}            # Mesh -> Array[Transform3D]

# Enregistre un maillage généré (kit romain) sous un nom, utilisable ensuite par `add()` comme un modèle Kenney.
static func register(model_name: String, mesh: Mesh) -> void:
	_parts[model_name] = [[mesh, Transform3D.IDENTITY]]

static func parts_of(model_name: String) -> Array:
	if _parts.has(model_name):
		return _parts[model_name]
	var out := []
	var path := ("res://assets/%s.gltf" % model_name) if "/" in model_name else ("res://assets/town/%s.glb" % model_name)
	var root: Node3D = load(path).instantiate()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != root and n is Node3D:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		out.append([mi.mesh, xf])
	root.free()
	_parts[model_name] = out
	return out

var chunk := 0.0            # > 0 : découpe en carrés de cette taille (culling par carré)

func add(model_name: String, pos: Vector3, sc: float = 1.0, rot: float = 0.0) -> void:
	var xf := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * sc), pos)
	var cell := Vector2i(floori(pos.x / chunk), floori(pos.z / chunk)) if chunk > 0.0 else Vector2i.ZERO
	for p in parts_of(model_name):
		var key := [p[0], cell]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(xf * p[1])

# `world` (world.gd) fournit le maillage peint ; `ruin` le passe en couleurs fanées ; `far` = distance d'affichage (0 = toujours).
func build(parent: Node, world: Node = null, shadows := true, ruin := false, far := 0.0) -> void:
	for key in groups:
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = key[0]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if world:
			mm.mesh = world.toon_mesh(key[0], ruin)   # copie du maillage avec un matériau peint par surface (écorce, feuilles…)
		if not shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if far > 0.0:
			mmi.visibility_range_end = far
			mmi.visibility_range_end_margin = 8.0
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mmi)
	groups.clear()
