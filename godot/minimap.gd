extends Control
# Mini-carte en losange : villages (couleur = niveau), personnages, cadre de la vue. Un clic y déplace la caméra.
# Sur le Mac : 230 × 230 en bas à gauche. Sur le téléphone, une copie réduite vit dans la feuille Villages (`hote`) : sa
# taille vient de la feuille, le cadre de la vue est l'empreinte au sol des 4 coins de l'écran, un toucher émet `touchee`.

signal touchee(point: Vector3)

const CM := preload("res://camera_math.gd")
const WORLD := 75.0
const LEVEL_COLORS := {1: Color("c98f62"), 2: Color("9cbf5a"), 3: Color("5bb0d3"), 4: Color("e8c04a")}
var main: Node
var hote := false            # logée dans une feuille du téléphone : taille donnée par la feuille
var _appui := Vector2.ZERO
var _bouge := false

func _ready() -> void:
	if not hote:
		custom_minimum_size = Vector2(230, 230)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		mouse_filter = Control.MOUSE_FILTER_PASS   # un doigt qui glisse dessus fait défiler la feuille

# Demi-largeur du losange : il tient dans la boîte (hauteur 0,62 de la largeur).
func _rayon() -> float:
	return minf(size.x * 0.5, size.y * 0.5 / 0.62)

func to_map(x: float, z: float) -> Vector2:
	var v := Vector2(x, z).rotated(deg_to_rad(45.0)) / WORLD
	return size / 2.0 + Vector2(v.x, v.y * 0.62) * _rayon()

func to_world(p: Vector2) -> Vector3:
	var v := (p - size / 2.0) / _rayon()
	v.y /= 0.62
	var w := v.rotated(deg_to_rad(-45.0)) * WORLD
	return Vector3(w.x, 0, w.y)

func _process(_d: float) -> void:
	if is_visible_in_tree():
		queue_redraw()

func _draw() -> void:
	var c := size / 2.0
	var r := _rayon()
	var diamond := _arrondi(PackedVector2Array([c + Vector2(0, -r * 0.62), c + Vector2(r, 0), c + Vector2(0, r * 0.62), c + Vector2(-r, 0)]), r * 0.12)
	draw_colored_polygon(diamond, Color("4d7a33"))
	draw_polyline(diamond + PackedVector2Array([diamond[0]]), Color("d9b77a"), 3.0, true)   # charte : aucune pointe
	if main == null or main.last_state.is_empty():
		return
	var tc := to_map(0, 0)
	draw_circle(tc, 5.5, Color("e8d7a8"))   # le Forum (charte : aucun coin dur)
	for v in main.last_state.villages:
		var m: Vector2 = to_map(float(v.x), float(v.z))
		draw_line(tc, m, Color(0.85, 0.85, 0.95, 0.3), 1.5)
		var sz := 6.0 + int(v.level) * 2.0
		draw_circle(m, sz / 2.0 + 0.5, LEVEL_COLORS.get(int(v.level), Color.WHITE))
	for id in main.persons:
		var p: Node3D = main.persons[id]
		var m: Vector2 = to_map(p.position.x, p.position.z)
		draw_circle(m, 2.6, Color("7CFC9A") if p.working else (Color(1, 1, 1, 0.35) if p.sleeping else Color("f6f6f6")))
	if hote:
		_cadre_projete()
		return
	var v3: Vector3 = main.pivot.position
	var half: float = 0.45 * main.zoom
	var corners := PackedVector2Array()
	for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
		var w: Vector3 = v3 + main.pivot.basis * Vector3(d.x * half * 1.4, 0, d.y * half * 0.8)
		corners.append(to_map(w.x, w.z))
	_cadre(corners)

# Cadre de la vue : trait fin, coins arrondis (un point rond à chaque coin).
func _cadre(coins: PackedVector2Array) -> void:
	draw_polyline(coins, Color.WHITE, 1.5, true)
	for q in coins:
		draw_circle(q, 0.75, Color.WHITE, true, -1.0, true)

# Polygone fermé aux coins arrondis : chaque coin devient une courbe (Bézier quadratique) de `rayon` px le long des côtés.
static func _arrondi(pts: PackedVector2Array, rayon: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var p := pts[i]
		var a := p + (pts[(i - 1 + n) % n] - p).limit_length(rayon)
		var b := p + (pts[(i + 1) % n] - p).limit_length(rayon)
		for k in 9:
			var t := k / 8.0
			out.append(a.lerp(p, t).lerp(p.lerp(b, t), t))
	return out

# Empreinte au sol de l'écran : les 4 coins projetés sur le sol (un coin au-dessus de l'horizon est ramené au bord du monde).
func _cadre_projete() -> void:
	var cam: Camera3D = main.rig.cam
	var vue: Vector2 = main.rig.get_viewport().get_visible_rect().size
	var coins := PackedVector2Array()
	for s in [Vector2(0, 0), Vector2(vue.x, 0), Vector2(vue.x, vue.y), Vector2(0, vue.y), Vector2(0, 0)]:
		var g = CM.ground_point(cam, s)
		if g == null:
			var o := cam.project_ray_origin(s)
			var n := cam.project_ray_normal(s)
			g = o + Vector3(n.x, 0, n.z).normalized() * 300.0
		coins.append(_dans_losange(to_map(main.rig.position.x, main.rig.position.z), to_map(g.x, g.z)))
	_cadre(coins)

# Vue de loin : les coins du haut de l'écran tombent très loin. Le coin est ramené sur le bord du losange, le long du
# segment qui part du pivot, pour que le cadre reste dans la carte au lieu de la traverser de grands traits.
func _dans_losange(depuis: Vector2, m: Vector2) -> Vector2:
	var c := size / 2.0
	var r := _rayon()
	var dehors := func(q: Vector2) -> bool: return absf(q.x - c.x) / r + absf(q.y - c.y) / (0.62 * r) > 1.0
	if not dehors.call(m) or dehors.call(depuis):
		return m
	var a := 0.0
	var b := 1.0
	for i in 12:
		var t := (a + b) / 2.0
		if dehors.call(depuis.lerp(m, t)):
			b = t
		else:
			a = t
	return depuis.lerp(m, a)

func _gui_input(event: InputEvent) -> void:
	if hote:   # toucher bref (sans glisser) : envoyé à la feuille, qui fait voler la caméra
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_appui = event.position
				_bouge = false
			elif not _bouge:
				touchee.emit(to_world(event.position))
		elif event is InputEventMouseMotion and event.position.distance_to(_appui) > 8.0:
			_bouge = true
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		main.pivot.position = to_world(event.position)
		accept_event()
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		main.pivot.position = to_world(event.position)
		accept_event()
