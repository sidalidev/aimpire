extends Node3D
# Un personnage Kenney animé. Son unité dépend du modèle Claude : chevalier (Opus), soldat (Sonnet), éclaireur (Haiku), mage (Fable), paysan.
# Contremaître (une session) : plus grand, cercle de couleur. Villageois (sous-agent) ou porteur (ressource) : plus petit.

const PEOPLE := ["male-a", "female-a", "male-b", "female-b", "male-c", "female-c", "male-d", "female-d", "male-e", "female-e", "male-f", "female-f"]
const UNITS := {
	"chevalier": {"scale": 2.6, "color": Color("e8b64c"), "name": "Legate"},
	"soldat": {"scale": 2.2, "color": Color("b8332a"), "name": "Legionary"},
	"eclaireur": {"scale": 1.8, "color": Color("7fae5a"), "name": "Velite"},
	"mage": {"scale": 2.4, "color": Color("7a3b8f"), "name": "Augur"},
	"paysan": {"scale": 2.0, "color": Color("b9b0a0"), "name": "Plebeian"},
}
const RES_COLORS := {"bois": Color("a0622d"), "pierre": Color("9aa0a6"), "parchemins": Color("f1e3b5"), "or": Color("ffd23f")}

const KIT := preload("res://rome/kit.gd")
var main: Node
var unit := "paysan"
var hero := false
var model: Node3D
var anim: AnimationPlayer
var label: Label3D
var bubble: Label3D
var mark: Label3D
var target := Vector3.ZERO
var working := false
var sleeping := false
var voice := 0
var act := ""
var speed := 3.5
var carry: MeshInstance3D
var on_arrive: Callable

func setup(m: Node, id: String, u: String, is_hero: bool) -> void:
	main = m
	unit = u if UNITS.has(u) else "paysan"
	hero = is_hero
	var h := absi(id.hash())
	voice = h % 5
	var info: Dictionary = UNITS[unit]
	var sc: float = info.scale * (1.0 if hero else 0.62)
	model = load("res://assets/people/character-%s.glb" % PEOPLE[h % PEOPLE.size()]).instantiate()
	model.scale = Vector3.ONE * sc
	add_child(model)
	main.world.toonify(model)
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	for a in ["walk", "idle", "interact-right", "sit", "sprint"]:
		if anim.has_animation(a):
			anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	anim.play("idle")
	speed = 3.2 if unit == "chevalier" else (5.5 if unit == "eclaireur" else 4.0)
	var top: float = 0.72 * sc + 0.3
	label = main._label("", top, 0.012)
	add_child(label)
	bubble = main._tag("", top + 0.55, Color.WHITE, true)   # bulle : le contour épais clair sert de fond
	bubble.visibility_range_end = 0.0
	bubble.visible = false
	add_child(bubble)
	mark = main._label("!", top + 0.35, 0.04)
	mark.modulate = Color("ffd23f")
	mark.visible = false
	add_child(mark)
	if hero:
		var ring := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.26 * sc
		disc.bottom_radius = 0.26 * sc
		disc.height = 0.02
		ring.mesh = disc
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(info.color, 0.75)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = info.color
		ring.material_override = mat
		add_child(ring)
	# tenue romaine selon l'unité (toge et laurier, cuirasse et casque, tunique, voile d'augure)
	var garment := MeshInstance3D.new()
	garment.mesh = KIT.garment(unit)
	model.add_child(garment)

func set_carry(res: String) -> void:
	if carry:
		carry.queue_free()
		carry = null
	if res == "":
		return
	carry = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.22, 0.22) if res != "parchemins" else Vector3(0.1, 0.3, 0.1)
	carry.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = RES_COLORS.get(res, Color.WHITE)
	if res == "or":
		mat.emission_enabled = true
		mat.emission = Color("ffd23f")
		mat.emission_energy_multiplier = 0.6
	carry.material_override = mat
	carry.position = Vector3(0.25, 0.55, 0.15)
	model.add_child(carry)

func set_state(w: bool, s: bool, text: String, show_mark: bool, mark_text: String = "!") -> void:
	working = w
	sleeping = s
	label.text = text
	label.visible = text != ""
	label.modulate = Color.WHITE if w else Color(1, 1, 1, 0.7)
	mark.visible = show_mark
	mark.text = mark_text
	mark.scale = Vector3.ONE
	match mark_text:
		"z":
			mark.modulate = Color(0.85, 0.9, 1, 0.55)
			mark.scale = Vector3.ONE * 0.45
		"!!":       # permission : rouge, c'est bloquant
			mark.modulate = Color("ff5a4a")
		"×":        # erreur API
			mark.modulate = Color("ff8a6a")
		"?":        # question posée
			mark.modulate = Color("ffd23f")
		"…":        # silence suspect
			mark.modulate = Color(0.9, 0.9, 0.9, 0.7)
		_:          # tour terminé
			mark.modulate = Color("f7f1e3")

# « dit » : bulle blanche ; « pense » : bulle bleutée entre parenthèses, comme une pensée de bande dessinée.
func say_text(t: String, kind: String = "dit") -> void:
	if kind == "pense":
		bubble.text = "  ( %s )  " % t
		bubble.outline_modulate = Color("d6e4f5")
		bubble.modulate = Color("2c3d55")
	else:
		bubble.text = "  “%s”  " % t
		bubble.outline_modulate = Color("fffdf6")
		bubble.modulate = Color("1d120a")
	bubble.visible = true
	get_tree().create_timer(2.8).timeout.connect(func(): if is_instance_valid(bubble): bubble.visible = false)

func _process(delta: float) -> void:
	var to := target - position
	to.y = 0
	var a := "idle"
	if to.length() > 0.15:
		position = position.move_toward(target, speed * delta)
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), 10.0 * delta)
		a = "sprint" if unit == "eclaireur" and anim.has_animation("sprint") else "walk"
	else:
		if on_arrive.is_valid():
			var cb := on_arrive
			on_arrive = Callable()
			cb.call()
			return
		if working:
			a = "interact-right"
		elif sleeping:
			a = "sit"
	if a != act:
		anim.play(a, 0.2)
		act = a
