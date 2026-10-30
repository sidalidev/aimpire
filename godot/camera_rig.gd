extends Node3D
# Caméra de stratégie : ce nœud est le pivot au sol, la caméra est inclinée au-dessus, en diagonale, vue isométrique classique de jeu de stratégie.
# Molette = zoom, clic droit ou molette maintenue = déplacer, flèches = déplacer, P = PiP, survol et clic sur les villages.
# Tactile (téléphone), docs/MOBILE-PORTRAIT.md §3.3 : angle fixe, un doigt glisse la carte (le sol reste sous le doigt,
# inertie, butée élastique au bord du monde), deux doigts pincent autour du point entre les doigts, toucher = sélection
# (tolérance de 28 dp), double toucher = cadrer un village, le Forum ou tout l'Empire. Les événements tactiles ne font que
# noter la position des doigts : la caméra bouge une seule fois par image, dans _process.
# Téléphone en portrait (fenêtre plus haute que large) : champ horizontal de 30°, plongée de 55°, distance de 18 à la
# limite lointaine qui montre tout l'Empire. Ailleurs (Mac, téléphone en paysage) : 38° vertical, 41,35°, zoom de 14 à 110.

const CM := preload("res://camera_math.gd")
const HAPTIQUE := preload("res://haptics.gd")

var main: Node
var cam: Camera3D
var zoom := 46.0
var dragging := false
var pip := false
var pip_drag := false
var pip_off := Vector2i.ZERO

const ZOOM_MIN := 14.0
const ZOOM_MAX := 110.0
const FOV_PAYSAGE := 38.0
const SEUIL_TOUCHER := 12.0      # dp : au-delà, un toucher devient un glissé
const DUREE_TOUCHER := 0.45      # s : un toucher plus long n'est pas une sélection
const ECART_MIN := 24.0          # dp : écart des doigts sous lequel le pincement ne zoome pas
const RAYON_TAP := 28.0          # dp : un bâtiment à moins de cette distance du doigt est choisi
const RAYON_VILLAGE_TAP := 14.0  # unités du monde
const RAYON_VILLAGE_DOUBLE := 16.0
const RAYON_FORUM_DOUBLE := 10.0

enum { IDLE, PRESS, PAN, PINCH, GLIDE, SETTLE, FLY }
const NOMS_ETATS := ["IDLE", "PRESS", "PAN", "PINCH", "GLIDE", "SETTLE", "FLY"]
var etat := IDLE
var active: bool:   # la caméra bouge ou un doigt est posé : power.gd garde 60 images par seconde
	get: return etat != IDLE
var portrait := false
var r_occ := CM.R_MIN
var d_far := CM.d_far(CM.R_MIN)

var doigts := {}                 # index du doigt -> position courante (unités de la vue, des dp sur téléphone)
var _avant := {}                 # index du doigt -> position déjà appliquée à la caméra
var _t := 0.0                    # horloge de la caméra (s), avancée par _process
var _depart := Vector2.ZERO
var _depart_t := 0.0
var _bouge_t := 0.0              # dernier mouvement d'un doigt
var _sans_tap := false           # double toucher, deuxième doigt : pas de sélection au relâcher
var _brut := Vector3.ZERO        # pivot sans contrainte (le pivot affiché passe par la butée élastique)
var _z_brut := 0.0               # ln(distance) sans contrainte
var _vitesse := Vector3.ZERO     # glissé (unités du monde par seconde)
var _cible := Vector3.ZERO       # retour dans les limites : position visée
var _v_pos := Vector2.ZERO
var _v_z := 0.0
var _ech := PackedVector3Array() # tampon circulaire Vector3(t, x, z) du pivot brut pendant un glissé
var _ech_n := 0
var _ech_tete := -1
var _butee_signalee := false
var _limite_signalee := false
var _vol_de := Vector3.ZERO
var _vol_a := Vector3.ZERO
var _vol_z0 := 0.0
var _vol_z1 := 0.0
var _vol_t := 0.0
var _vol_duree := 0.3

func setup() -> void:
	rotation.y = deg_to_rad(45.0)
	cam = Camera3D.new()
	cam.fov = FOV_PAYSAGE
	add_child(cam)
	_ech.resize(32)
	if OS.get_environment("AIMPIRE_ZOOM") != "":
		zoom = float(OS.get_environment("AIMPIRE_ZOOM"))
	_parametres()
	get_viewport().size_changed.connect(_parametres)
	place()

func _vue() -> Vector2:
	return get_viewport().get_visible_rect().size

# Paramètres de la caméra selon la forme de la vue : portrait seulement en mode téléphone et vue plus haute que large.
func _parametres() -> void:
	var v := _vue()
	var p: bool = main != null and main.get("mobile") != null and v.y > v.x
	var garde := Camera3D.KEEP_WIDTH if p else Camera3D.KEEP_HEIGHT
	if p == portrait and cam.keep_aspect == garde:
		return
	portrait = p
	cam.keep_aspect = garde
	cam.fov = CM.HFOV if p else FOV_PAYSAGE
	zoom = clampf(zoom, d_min(), d_max())
	place()

func d_min() -> float:
	return CM.D_NEAR if portrait else ZOOM_MIN

func d_max() -> float:
	return d_far if portrait else ZOOM_MAX

func nom_etat() -> String:
	return NOMS_ETATS[etat]

func place() -> void:
	if portrait:
		var a := deg_to_rad(CM.PITCH)
		cam.position = Vector3(0, zoom * sin(a), zoom * cos(a))
	else:
		cam.position = Vector3(0, zoom * 0.66, zoom * 0.75)
	cam.look_at(global_position)
	var monde = main.get("world") if main else null
	if monde != null:   # brouillard du Mac au cadrage habituel ; plus léger quand le portrait recule (world.brume_pour)
		monde.brume_pour(zoom if portrait else 46.0)

# Étendue de l'Empire (main._apply_state) : bord du monde pour les gestes et limite lointaine du portrait.
func set_world_extent(villages: Array) -> void:
	r_occ = CM.r_occ(villages)
	d_far = CM.d_far(r_occ)
	if etat == IDLE and zoom > d_max():
		zoom = d_max()
		place()

# Vue d'ensemble : le Forum au centre, à la limite lointaine.
func vue_ensemble(instantane := false) -> void:
	if instantane:
		etat = IDLE
		position = Vector3.ZERO
		zoom = d_max()
		place()
		_brut = position
		_z_brut = log(zoom)
	else:
		fly_to(Vector3.ZERO, d_max())

# Largeur visible au pivot (unités du monde) et unités du monde par dp.
func _largeur() -> float:
	return CM.largeur_visible(zoom, cam.fov, portrait, _vue())

func _k_dp() -> float:
	return _largeur() / maxf(_vue().x, 1.0)

# PiP : petite fenêtre sans bordure, toujours au-dessus, en bas à droite (480 × 300 points sur Retina).
func set_pip(on: bool) -> void:
	pip = on
	var w := get_window()
	w.borderless = on
	w.always_on_top = on
	if on:
		var area := DisplayServer.screen_get_usable_rect(w.current_screen)
		w.size = Vector2i(960, 600)
		w.position = area.position + area.size - w.size - Vector2i(24, 24)
		main.selected = ""
		zoom = 50.0
	else:
		w.size = Vector2i(1280, 720)
		w.move_to_center()
		zoom = 46.0
	main.hud.visible = not on
	main.minimap.visible = not on
	place()

func _hit_under(screen_pos: Vector2) -> Dictionary:
	var from := cam.project_ray_origin(screen_pos)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(screen_pos) * 400.0))
	if not hit or not hit.collider.has_meta("village"):
		return {"village": "", "building": ""}
	return {"village": String(hit.collider.get_meta("village")), "building": String(hit.collider.get_meta("building")) if hit.collider.has_meta("building") else ""}

func _village_under(screen_pos: Vector2) -> String:
	return String(_hit_under(screen_pos).village)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_M:
				main.audio.toggle_music()
				return
			KEY_ESCAPE:
				if main.about and main.about.retour():
					return
				if main.selected != "":
					main.selected = ""
				else:
					main.settings.toggle()
				return
			KEY_P:
				set_pip(not pip)
				return
			KEY_TAB:
				main.cockpit_open = not main.cockpit_open
				return
			KEY_R:
				main.hud.show_report("jour")
				return
			KEY_W:
				main.hud.show_report("semaine")
				return
			KEY_J:
				main.hud.show_journal()
				return
			KEY_H:   # mode discret : titres et noms remplacés côté serveur (partage d'écran, visio)
				main.discret = not main.discret
				main.hud._post("/reglage?cle=privacy&val=" + ("flou" if main.discret else "normal"))
				main.hud.show_toast("Discreet mode " + ("on" if main.discret else "off"))
				return
	if pip:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.double_click:
				set_pip(false)
				return
			pip_drag = event.pressed
			pip_off = DisplayServer.mouse_get_position() - get_window().position
			return
		if event is InputEventMouseMotion and pip_drag:
			get_window().position = DisplayServer.mouse_get_position() - pip_off
			return
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_tactile(event)
		return
	# Sur écran tactile, Godot double chaque toucher d'un faux événement souris (utile aux boutons de l'interface) :
	# la caméra l'ignore, les gestes ci-dessus suffisent.
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMagnifyGesture and doigts.size() < 2:   # pavé tactile du Mac (sur téléphone : calcul à deux doigts)
		zoom = clampf(zoom / maxf(event.factor, 0.01), ZOOM_MIN, ZOOM_MAX)
		place()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom = clampf(zoom + (-3.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 3.0), ZOOM_MIN, ZOOM_MAX)
		place()
		return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		dragging = event.pressed
		return
	if event is InputEventMouseMotion:
		if dragging:
			position += basis * Vector3(-event.relative.x, 0, -event.relative.y) * zoom * 0.0022
			return
		main.hovered = _village_under(event.position)
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if main.hovered != "" else Input.CURSOR_ARROW)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var h := _hit_under(event.position)
		main.selected = String(h.village)
		main.selected_building = String(h.building)

# ---------------------------------------------------------------------------
# Gestes tactiles (machine à états de docs/MOBILE-PORTRAIT.md §3.3)
# ---------------------------------------------------------------------------

func _tactile(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_poser(event.index, event.position, event.double_tap)
		else:
			_lever(event.index, event.position)
		return
	if not doigts.has(event.index):   # InputEventScreenDrag d'un doigt posé avant (sur l'interface)
		return
	doigts[event.index] = event.position
	_bouge_t = _t
	if etat == PRESS and doigts.size() == 1 and event.position.distance_to(_depart) > SEUIL_TOUCHER:
		etat = PAN
		# ancré au point où le seuil de 12 dp est franchi : la carte ne saute pas de 12 dp, mais rattrape le doigt s'il
		# est déjà plus loin (entrées accumulées sur une image, première image au plafond de 30 au repos)
		_avant[event.index] = _depart + (event.position - _depart).normalized() * SEUIL_TOUCHER
		_ech_n = 0
		_echantillon()
	_poke()

func _poser(i: int, pos: Vector2, double: bool) -> void:
	_appliquer()
	doigts[i] = pos
	_avant[i] = pos
	_poke()
	if doigts.size() == 1:   # glissé, retour et vol s'arrêtent là où ils sont
		etat = PRESS
		_brut = _brut_depuis(position)
		_z_brut = _z_brut_depuis(zoom)
		_vitesse = Vector3.ZERO
		_depart = pos
		_depart_t = _t
		_bouge_t = _t
		_sans_tap = false
		_butee_signalee = false
		_limite_signalee = false
		if double:
			_sans_tap = true
			_double_toucher(pos)
	else:
		etat = PINCH
		_sans_tap = true
		for k in doigts:
			_avant[k] = doigts[k]

func _lever(i: int, pos: Vector2) -> void:
	if not doigts.has(i):
		return
	doigts[i] = pos
	_appliquer()
	doigts.erase(i)
	_avant.erase(i)
	match etat:
		PRESS:
			if doigts.is_empty():
				var tap := not _sans_tap and _t - _depart_t < DUREE_TOUCHER
				_fin_geste()   # un toucher pendant un retour élastique ou un glissé : la caméra revient dans les limites
				if tap:
					selectionner(pos)
		PAN:
			if doigts.is_empty():
				_fin_glisser()
		PINCH:
			if doigts.size() == 1:   # un doigt reste : il reprend le glissé, ancré là où il est
				etat = PAN
				for k in doigts:
					_avant[k] = doigts[k]
				_ech_n = 0
			elif doigts.size() >= 2:
				for k in doigts:
					_avant[k] = doigts[k]
			else:
				_fin_geste()
	_poke()

# Applique à la caméra le mouvement des doigts depuis le dernier calcul (une fois par image, et avant tout changement d'état).
func _appliquer() -> void:
	if etat == PAN:
		for i in doigts:
			var a: Vector2 = _avant[i]
			var b: Vector2 = doigts[i]
			if a != b:
				_deplacer_sol(a, b)
				_avant[i] = b
			return
	elif etat == PINCH and doigts.size() >= 2:
		var i0 := -1
		var i1 := -1
		for i in doigts:
			if i0 < 0:
				i0 = i
			else:
				i1 = i
				break
		var a0: Vector2 = _avant[i0]
		var a1: Vector2 = _avant[i1]
		var b0: Vector2 = doigts[i0]
		var b1: Vector2 = doigts[i1]
		if a0 != b0 or a1 != b1:
			_pincer(a0, a1, b0, b1)
			_avant[i0] = b0
			_avant[i1] = b1

# Le sol sous le doigt reste sous le doigt, à toute hauteur de l'écran.
func _deplacer_sol(a: Vector2, b: Vector2) -> void:
	var ga = CM.ground_point(cam, a)
	var gb = CM.ground_point(cam, b)
	if ga == null or gb == null:   # près de l'horizon : formule linéaire
		var k := _k_dp()
		_brut += basis * Vector3(-(b.x - a.x) * k, 0, -(b.y - a.y) * k * 1.5)
	else:
		_brut += ga - gb
	_poser_pivot()

# Zoom en espace logarithmique autour du point entre les doigts ; ce point reste sous les doigts, le milieu déplace la vue.
func _pincer(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> void:
	var s0 := a0.distance_to(a1)
	var s1 := b0.distance_to(b1)
	var m0 := (a0 + a1) * 0.5
	var m1 := (b0 + b1) * 0.5
	if s0 < ECART_MIN or s1 < ECART_MIN:
		_deplacer_sol(m0, m1)
		return
	var g0 = CM.ground_point(cam, m0)
	_z_brut += log(s0 / s1)
	var z_min := log(d_min())
	var z_max := log(d_max())
	zoom = exp(CM.soft_zoom(_z_brut, z_min, z_max))
	place()
	var g1 = CM.ground_point(cam, m1)
	if g0 != null and g1 != null:
		_brut += g0 - g1
	_poser_pivot()
	var dehors := _z_brut > z_max or _z_brut < z_min
	if dehors and not _limite_signalee:
		HAPTIQUE.tick()
	_limite_signalee = dehors

func _poser_pivot() -> void:
	var p := CM.pivot_borne(_brut, r_occ, CM.ELASTIQUE_BORD * _largeur())
	if not _butee_signalee and Vector2(_brut.x, _brut.z).length() > r_occ:
		_butee_signalee = true
		HAPTIQUE.tick()
	position = p

# Pivot et ln(distance) bruts qui redonnent ce qui est affiché : un doigt posé pendant un retour élastique reprend de
# là sans saut (l'élastique n'est pas appliqué deux fois).
func _brut_depuis(p: Vector3) -> Vector3:
	var r := Vector2(p.x, p.z).length()
	if r <= r_occ:
		return Vector3(p.x, 0, p.z)
	var m := CM.ELASTIQUE_BORD * _largeur()
	return Vector3(p.x, 0, p.z) * ((r_occ + CM.rubber_inverse(r - r_occ, m)) / r)

func _z_brut_depuis(d: float) -> float:
	var z := log(d)
	var z_min := log(d_min())
	var z_max := log(d_max())
	if z > z_max:
		return z_max + CM.rubber_inverse(z - z_max, CM.ELASTIQUE_ZOOM)
	if z < z_min:
		return z_min - CM.rubber_inverse(z_min - z, CM.ELASTIQUE_ZOOM)
	return z

func _echantillon() -> void:
	_ech_tete = (_ech_tete + 1) % _ech.size()
	_ech[_ech_tete] = Vector3(_t, _brut.x, _brut.z)
	_ech_n = mini(_ech_n + 1, _ech.size())

# Doigt levé après un glissé : lancer si la vitesse des 100 dernières ms le justifie.
func _fin_glisser() -> void:
	var v := Vector2.ZERO
	if _t - _bouge_t < CM.REPOS_AVANT_LEVER:
		_echantillon()
		v = CM.velocity_from_samples(_ech, _ech_n, _ech_tete, _t)
	var k := _k_dp()
	var dp_s := v.length() / k
	if dp_s > CM.VITESSE_MAX:
		v *= CM.VITESSE_MAX / dp_s
		dp_s = CM.VITESSE_MAX
	if dp_s >= CM.LANCER_MIN:
		_vitesse = Vector3(v.x, 0, v.y)
		etat = GLIDE
	else:
		_fin_geste()

func _hors_limites() -> bool:
	var r := Vector2(position.x, position.z).length()
	return r > r_occ * 1.005 or zoom > d_max() * 1.005 or zoom < d_min() * 0.995

func _fin_geste() -> void:
	_brut = position
	_z_brut = log(zoom)
	if _hors_limites():
		etat = SETTLE
		var r := Vector2(position.x, position.z).length()
		_cible = Vector3(position.x, 0, position.z) * (r_occ / r) if r > r_occ else Vector3(position.x, 0, position.z)
		_v_pos = Vector2(_vitesse.x, _vitesse.z)
		_v_z = 0.0
	else:
		etat = IDLE
		_vitesse = Vector3.ZERO

func _process(delta: float) -> void:
	_t += delta
	var move := Vector3(Input.get_axis("ui_left", "ui_right"), 0, Input.get_axis("ui_up", "ui_down"))
	if move != Vector3.ZERO:
		position += basis * move * zoom * 0.9 * delta
	match etat:
		IDLE:
			return
		PAN:
			_appliquer()
			_echantillon()
		PINCH:
			_appliquer()
		GLIDE:
			_glisser(delta)
		SETTLE:
			_ressort(delta)
		FLY:
			_voler(delta)
	_poke()

func _glisser(dt: float) -> void:
	var r := Vector2(_brut.x, _brut.z).length()
	var dehors := Vector3(_brut.x, 0, _brut.z) / r if r > r_occ else Vector3.ZERO
	_vitesse = CM.glide_step(_vitesse, dt, dehors)
	_brut += _vitesse * dt
	_poser_pivot()
	if _vitesse.length() < CM.ARRET * _k_dp():
		_fin_geste()

# Retour dans les limites : ressort amorti critique sur la position et sur ln(distance).
func _ressort(dt: float) -> void:
	var w := CM.RESSORT_W
	var sx := CM.spring_step(position.x - _cible.x, _v_pos.x, w, dt)
	var sz := CM.spring_step(position.z - _cible.z, _v_pos.y, w, dt)
	position = Vector3(_cible.x + sx.x, 0, _cible.z + sz.x)
	_v_pos = Vector2(sx.y, sz.y)
	var zc := clampf(log(zoom), log(d_min()), log(d_max()))
	var sl := CM.spring_step(log(zoom) - zc, _v_z, w, dt)
	zoom = exp(zc + sl.x)
	_v_z = sl.y
	place()
	if position.distance_to(_cible) < 0.005 * maxf(r_occ, 1.0) and absf(sl.x) < 0.005:
		position = _cible
		zoom = exp(zc)
		place()
		_brut = position
		_z_brut = log(zoom)
		_vitesse = Vector3.ZERO
		etat = IDLE

# Vol vers un point (double toucher, cockpit, liste des villages, mini-carte), interrompu par tout toucher.
# `centre_y` >= 0 : la cible doit apparaître à cette hauteur de l'écran (milieu de la zone libre au-dessus d'une feuille).
func fly_to(cible: Vector3, d: float, centre_y := -1.0) -> void:
	d = clampf(d, d_min(), d_max())
	cible.y = 0.0
	if centre_y >= 0.0:
		var p0 := position
		var z0 := zoom
		position = cible
		zoom = d
		place()
		var g = CM.ground_point(cam, Vector2(_vue().x / 2.0, centre_y))
		position = p0
		zoom = z0
		place()
		if g != null:
			cible += cible - g
			cible.y = 0.0
	_vol_de = position
	_vol_a = cible
	_vol_z0 = log(zoom)
	_vol_z1 = log(d)
	_vol_t = 0.0
	_vol_duree = CM.duree_vol(position.distance_to(cible), _largeur())
	etat = FLY
	_poke()

func _voler(dt: float) -> void:
	_vol_t += dt
	var u := CM.cubique(_vol_t / _vol_duree)
	position = _vol_de.lerp(_vol_a, u)
	zoom = exp(lerpf(_vol_z0, _vol_z1, u))
	place()
	if _vol_t >= _vol_duree:
		_brut = position
		_z_brut = log(zoom)
		etat = IDLE

# ---------------------------------------------------------------------------
# Toucher et double toucher
# ---------------------------------------------------------------------------

# Toucher : le bâtiment (ou le Forum) le plus proche du doigt à moins de 28 dp, sinon le rayon physique, sinon le village
# dont le centre est à moins de 14 unités du sol touché, sinon rien (la feuille d'aperçu se ferme).
func selectionner(screen_pos: Vector2) -> void:
	var avant_v := String(main.selected)
	var avant_b := String(main.selected_building)
	var choix := choisir(screen_pos)
	main.selected = choix[0]
	main.selected_building = choix[1]
	if choix[0] != avant_v or choix[1] != avant_b:
		HAPTIQUE.tick()

func choisir(s: Vector2) -> PackedStringArray:
	var meilleur := RAYON_TAP
	var v_choisi := ""
	var b_choisi := ""
	var vs = main.get("villages")
	if vs is Dictionary:
		for vid in vs:
			var v = vs[vid]
			if not is_instance_valid(v):
				continue
			for bid in v.buildings:
				var b: Node3D = v.buildings[bid]
				var p := b.global_position + Vector3(0, 2.5, 0)
				if cam.is_position_behind(p):
					continue
				var d := cam.unproject_position(p).distance_to(s)
				if d < meilleur:
					meilleur = d
					v_choisi = String(vid)
					b_choisi = String(bid)
	var forum := Vector3(0, 1.5, 0)
	if not cam.is_position_behind(forum) and cam.unproject_position(forum).distance_to(s) < meilleur:
		v_choisi = "forum"
		b_choisi = ""
	if v_choisi != "":
		return PackedStringArray([v_choisi, b_choisi])
	var h := _hit_under(s)
	if String(h.village) != "":
		return PackedStringArray([String(h.village), String(h.building)])
	var g = CM.ground_point(cam, s)
	if g != null:
		var proche := village_proche(g, RAYON_VILLAGE_TAP)
		if proche != "":
			return PackedStringArray([proche, ""])
	return PackedStringArray(["", ""])

func village_proche(g: Vector3, rayon: float) -> String:
	var meilleur := rayon
	var choisi := ""
	var vs = main.get("villages")
	if vs is Dictionary:
		for vid in vs:
			var v = vs[vid]
			if not is_instance_valid(v):
				continue
			var d := Vector2(v.position.x - g.x, v.position.z - g.z).length()
			if d < meilleur:
				meilleur = d
				choisi = String(vid)
	return choisi

# Double toucher : sur un village, le cadrer (D_VILLAGE) et le garder choisi (feuille d'aperçu) ; sur le Forum, le cadrer
# sans feuille ; ailleurs, vue d'ensemble sans sélection. Le premier toucher de la paire est remplacé.
func _double_toucher(pos: Vector2) -> void:
	var g = CM.ground_point(cam, pos)
	var vid := village_proche(g, RAYON_VILLAGE_DOUBLE) if g != null else ""
	main.selected_building = ""
	if vid != "":
		main.selected = vid
		var v: Node3D = main.villages[vid]
		fly_to(v.position, CM.D_VILLAGE, _centre_apercu())
	elif g != null and Vector2(g.x, g.z).length() < RAYON_FORUM_DOUBLE:
		main.selected = ""
		fly_to(Vector3.ZERO, CM.D_VILLAGE)
	else:
		main.selected = ""
		fly_to(Vector3.ZERO, d_max())
	HAPTIQUE.tick()

# Hauteur de l'écran où poser un village quand une feuille d'aperçu couvre le bas (-1 sans interface de téléphone).
func _centre_apercu() -> float:
	var m = main.get("mobile")
	if m == null or m.get("ui") == null:
		return -1.0
	return m.ui.centre_libre()

func _poke() -> void:
	var p = main.get("power") if main else null
	if p != null:
		p.poke()
