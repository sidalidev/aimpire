extends Node3D
# Un bâtiment = une session. Construit avec les pièces Kenney selon son type, son niveau et son état (travaille, dort, ruine).

const KIT := preload("res://rome/kit.gd")
var main: Node
var data := {}
var built_key := ""
var label: Label3D
var tag: Label3D
var smoke: GPUParticles3D
var body: StaticBody3D
var parts: Node3D

func setup(m: Node, d: Dictionary) -> void:
	main = m
	label = main._label("", 5.1, 0.011)
	add_child(label)
	tag = main._tag("", 4.4, Color.WHITE)
	add_child(tag)
	body = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(3.6, 5, 3.6)
	shape.shape = bx
	body.add_child(shape)
	body.position.y = 2.5
	add_child(body)
	update(d)

func set_focus(on: bool) -> void:
	label.visible = on
	tag.visible = on

func update(d: Dictionary) -> void:
	data = d
	body.set_meta("village", d.get("village", ""))
	body.set_meta("building", d.id)
	var key := "%s|%d|%s" % [d.type, int(d.level), "ruine" if d.ruin else "ok"]
	if key != built_key:
		var rebuild := built_key != ""
		built_key = key
		_build()
		if rebuild:
			_dust()
	if smoke:
		smoke.emitting = bool(d.working)
		smoke.visible = bool(d.working) or smoke.emitting
	_hammer = bool(d.working) and String(d.type) in ["forge", "atelier"]
	var stars := ""
	for i in int(d.level):
		stars += "★"
	label.text = String(d.title).left(28)
	label.modulate = Color(0.75, 0.75, 0.75, 0.6) if d.ruin else (Color(1, 1, 1, 0.75) if d.sleeping else Color.WHITE)
	tag.text = " %s %s " % [("ruin" if d.ruin else TYPE_NAMES.get(d.type, d.type)), stars]
	var col: Color = Color("8a8a80") if d.ruin else TYPE_COLORS.get(d.type, Color.WHITE)
	if d.sleeping and not d.ruin:
		col = col.lerp(Color("8a8a80"), 0.45)
	tag.outline_modulate = col

const TYPE_NAMES := {"cabane": "hut", "atelier": "workshop", "forge": "forge", "bibliotheque": "library", "tour": "watchtower", "chateau": "palace"}
const TYPE_COLORS := {"cabane": Color("d8c7a3"), "atelier": Color("c98f62"), "forge": Color("d0694b"), "bibliotheque": Color("e3cf8f"), "tour": Color("8fb6c9"), "chateau": Color("b58ad6")}

var _batch: RefCounted
var _hammer := false       # coups de marteau quand une forge ou un atelier travaille
var _hammer_t := 0.0

func _process(delta: float) -> void:
	if not _hammer:
		return
	_hammer_t -= delta
	if _hammer_t <= 0.0:
		_hammer_t = randf_range(4.0, 9.0)
		if main.audio and main.rig.position.distance_to(global_position) < 40.0:
			main.audio.play_sfx("forge" if String(data.type) == "forge" else "chantier2", -10.0)

func _m(name: String, pos: Vector3, sc: float = 1.0, rot: float = 0.0) -> void:
	_batch.add(name, pos, sc, rot)

func _build() -> void:
	if parts:
		parts.queue_free()
	parts = Node3D.new()
	add_child(parts)
	smoke = null
	var d := data
	var ruin: bool = d.ruin
	var level := int(d.level)
	var mi := MeshInstance3D.new()
	mi.mesh = KIT.building(String(d.type), level, ruin, int(String(d.id).md5_text().left(8).hex_to_int()))
	parts.add_child(mi)
	if not ruin and String(d.type) == "forge":
		_smoke(Vector3(0.9, 2.2 + (0.6 if level >= 3 else 0.0) + 1.3, -0.6))

# Nuage de poussière de chantier : une bouffée quand le bâtiment change de type, de niveau ou d'état.
func _dust() -> void:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.9
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, -2.0, 0)
	pm.scale_min = 0.3
	pm.scale_max = 0.7
	pm.color = Color(0.85, 0.75, 0.55, 0.7)
	p.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = 0.25
	mesh.height = 0.5
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.75, 0.55, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	p.draw_pass_1 = mesh
	p.position.y = 0.5
	add_child(p)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(func(): if is_instance_valid(p): p.queue_free())
	if main.audio:
		main.audio.play_sfx("chantier")

func _smoke(pos: Vector3) -> void:
	smoke = GPUParticles3D.new()
	smoke.position = pos
	smoke.amount = 24
	smoke.lifetime = 2.6
	smoke.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.2, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.3
	pm.gravity = Vector3(0.3, 0.2, 0)
	pm.scale_min = 0.25
	pm.scale_max = 0.6
	pm.color = Color(0.9, 0.9, 0.9, 0.55)
	smoke.process_material = pm
	var mesh := SphereMesh.new()     # sphère très simple : 48 triangles au lieu de 4 000 par défaut
	mesh.radius = 0.25
	mesh.height = 0.5
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.85, 0.85, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	smoke.draw_pass_1 = mesh
	parts.add_child(smoke)
