extends Node3D
# Chef d'orchestre du client AImpire : reçoit l'état de l'Empire et met à jour la scène.
# Deux sources possibles pour l'état : le serveur local (net.gd, GET /state toutes les 0,5 s) sur le Mac,
# ou le relais chiffré en mode téléphone (mobile.gd, voir docs/SYNC.md §7). Les deux aboutissent à _apply_state().
# Modules : ui_kit.gd (polices, textes), world.gd (monde et look peint), audio.gd (son et voix), settings.gd (réglages),
# camera_rig.gd (caméra, PiP, clics), village.gd / building.gd / person.gd (entités), hud.gd, minimap.gd, batch.gd,
# update.gd (mises à jour), about.gd (À propos, ce qui quitte l'appareil, tout effacer). Téléphone : mobile.gd, phone_ui.gd,
# sheet.gd, camera_math.gd, haptics.gd, geste.gd (docs/MOBILE-PORTRAIT.md).

var net := preload("res://net.gd").new()
var power: Node
var poll_timer: Timer

var ui := preload("res://ui_kit.gd").new()
var world: Node3D
var audio: Node
var settings: Node
var rig: Node3D
var hud: Control
var minimap: Control
var mobile: Node = null   # mode téléphone (mobile.gd) ; null sur le Mac
var maj: Node             # mises à jour (update.gd) : manifeste du relais, boutons « Mettre à jour »
var about: CanvasLayer    # écran « About » (about.gd), ouvert depuis les réglages
var http := HTTPRequest.new()
var villages := {}        # id -> village.gd
var persons := {}         # id de session ou "sub-…" -> person.gd
var porteurs := []        # personnages temporaires qui livrent une ressource
var last_event_t := 0
var last_state := {}
var started := false
var selected := ""
var hovered := ""
var selected_building := ""
var discret := false         # H : mode discret (noms et titres floutés par le serveur)
var cockpit_open := false   # Tab : la liste « À traiter / En cours / À relancer »
var _focus_shown := {}
var senator: Node3D       # le Sénateur du Forum : « ! » s'il a des ordres, « ? » s'il a une récompense pour toi
var _warm := []           # scènes de personnages préchargées (évite les à-coups)

const MARKS := {"question": "?", "permission": "!!", "fini": "!", "erreur": "×", "silence": "…"}

# Raccourcis utilisés par les autres scripts.
var title_font: Font:
	get: return ui.title_font
var body_font: Font:
	get: return ui.body_font
var pivot: Node3D:
	get: return rig
var zoom: float:
	get: return rig.zoom

func _label(text: String, y: float, size: float = 0.02) -> Label3D:
	return ui.label(text, y, size)

func _tag(text: String, y: float, color: Color, big := false) -> Label3D:
	return ui.tag(text, y, color, big)

func _road_to(target: Vector2, stop_before: float = 2.0) -> MeshInstance3D:
	return world.road_to(target, stop_before)

func _ready() -> void:
	if OS.get_environment("AIMPIRE_FPS") != "":
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	var MOBILE := preload("res://mobile.gd")
	if MOBILE.doit_activer():
		mobile = MOBILE.new()
		mobile.main = self
		mobile.preparer()   # échelle de l'interface et des textes 3D, à faire avant de créer le monde
	Input.set_custom_mouse_cursor(load("res://assets/ui/curseur.png"), Input.CURSOR_ARROW, Vector2(4, 3))
	Input.set_custom_mouse_cursor(load("res://assets/ui/curseur-survol.png"), Input.CURSOR_POINTING_HAND, Vector2(4, 3))
	rig = preload("res://camera_rig.gd").new()
	rig.main = self
	add_child(rig)
	rig.setup()
	settings = preload("res://settings.gd").new()
	settings.main = self
	add_child(settings)
	world = preload("res://world.gd").new()
	world.main = self
	add_child(world)
	world.setup()
	audio = preload("res://audio.gd").new()
	audio.main = self
	add_child(audio)
	audio.setup()
	if mobile:
		settings.data.qualite = "performance"   # par défaut sur téléphone ; un choix enregistré l'emporte
	settings.load_saved()
	maj = preload("res://update.gd").new()
	maj.main = self
	maj.active = bool(settings.data.get("maj_auto", true))
	add_child(maj)
	for who in ["male-a", "female-a", "male-b", "female-b", "male-c", "female-c", "male-d", "female-d", "male-e", "female-e", "male-f", "female-f"]:
		_warm.append(load("res://assets/people/character-%s.glb" % who))
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = preload("res://hud.gd").new()
	hud.main = self
	hud.theme = ui.theme
	layer.add_child(hud)
	about = preload("res://about.gd").new()
	about.main = self
	add_child(about)
	minimap = preload("res://minimap.gd").new()   # avant les réglages : le panneau des réglages passe au-dessus
	minimap.main = self
	minimap.anchor_top = 1.0
	minimap.anchor_bottom = 1.0
	minimap.offset_left = 14
	minimap.offset_top = -244
	layer.add_child(minimap)
	settings.build_menu(layer)
	selected = OS.get_environment("AIMPIRE_SELECT")
	if selected != "":   # captures : bâtiment choisi au démarrage (feuille du village en aperçu sur le téléphone)
		selected_building = OS.get_environment("AIMPIRE_BATIMENT")
	cockpit_open = OS.get_environment("AIMPIRE_COCKPIT") != ""
	if "--pip" in OS.get_cmdline_user_args():
		get_tree().create_timer(0.3).timeout.connect(func(): rig.set_pip(true))
	add_child(http)
	http.request_completed.connect(_on_state)
	poll_timer = Timer.new()
	poll_timer.wait_time = 0.5
	poll_timer.autostart = true
	poll_timer.timeout.connect(_poll)
	add_child(poll_timer)
	power = preload("res://power.gd").new()
	power.main = self
	add_child(power)
	if mobile:
		add_child(mobile)
		mobile.setup()   # écran d'appairage ou réception depuis le relais, boutons tactiles

# Interroger le serveur local (Mac seulement : en mode téléphone, l'état arrive par mobile.gd).
func _poll() -> void:
	if OS.get_environment("AIMPIRE_FPS") != "":
		print("FPS ", Engine.get_frames_per_second(), " qualite ", world.quality, " draw ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), " prim ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), " fen ", get_window().size)
	if mobile:
		return
	if http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		http.request(net.url("/state"))

# Réponse de GET /state : contrôle HTTP et JSON, puis le rendu commun.
func _on_state(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		hud.log_label.text = "Server unreachable (%s), retrying…" % net.base
		net.on_failure()
		return
	net.on_success()
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_apply_state(parsed)

# Recevoir un état (celui de /state, ou celui que le Mac a publié sur le relais) et mettre la scène à jour.
func _apply_state(parsed: Dictionary) -> void:
	if not parsed.has("villages"):
		if parsed.has("scanning"):   # premier recensement : le serveur lit tous les journaux
			var sc: Dictionary = parsed.scanning
			hud.log_label.text = "Taking the census of the Empire… %d / %d logs" % [int(sc.get("done", 0)), int(sc.get("total", 0))]
		return
	var s: Dictionary = parsed
	last_state = s
	discret = s.get("privacy", "") == "flou"
	var seen_v := {}
	var seen_p := {}
	for v in s.villages:
		seen_v[v.id] = true
		# un village dont le rang change est reconstruit à sa nouvelle place
		if villages.has(v.id) and villages[v.id].position.distance_to(Vector3(float(v.x), 0, float(v.z))) > 0.5:
			villages[v.id].queue_free()
			villages.erase(v.id)
			_focus_shown.erase(v.id)
		if not villages.has(v.id):
			var node := preload("res://village.gd").new()
			add_child(node)
			node.setup(self, v)
			villages[v.id] = node
		else:
			villages[v.id].update(v)
		var toward := -Vector3(float(v.x), 0, float(v.z)).normalized()
		var side := Vector3(-toward.z, 0, toward.x)
		for b in v.buildings:
			if b.get("hidden", false) or b.ruin:
				continue
			_update_foreman(b, v, toward, side)
			seen_p[b.id] = true
			var k := 0
			for sub in b.get("subs", []):
				_update_sub(sub, b, k)
				seen_p["sub-" + String(sub.id)] = true
				k += 1
	for id in persons.keys():
		if not seen_p.has(id):
			persons[id].queue_free()
			persons.erase(id)
	for id in villages.keys():
		if not seen_v.has(id):
			villages[id].queue_free()
			villages.erase(id)
	world.ensure_decor(s.villages)
	rig.set_world_extent(s.villages)
	world.set_season(String(s.empire.get("calendrier", {}).get("saison", "ete")), s.empire.get("fete") != null)
	_update_senator(s.empire)
	world.build_monuments(s.empire.get("monuments", []).filter(func(m): return m.bati).map(func(m): return m.id))
	_handle_events(s.get("events", []))
	if not started:
		hud.fetch_digest()
	var focus_env := OS.get_environment("AIMPIRE_FOCUS")   # cadrer un village au démarrage sans ouvrir son panneau (captures)
	if not started and focus_env != "" and villages.has(focus_env):
		focus_village(focus_env, false)
	elif not started and rig.portrait and OS.get_environment("AIMPIRE_ZOOM") == "":
		rig.vue_ensemble(true)   # tout l'Empire au lancement (et chaque matériau rendu une fois avant le premier geste)
		if selected != "" and villages.has(selected):
			rig.fly_to(villages[selected].position, preload("res://camera_math.gd").D_VILLAGE, mobile.ui.centre_libre())
	started = true
	hud.refresh(s, selected, Engine.get_frames_per_second())

func _update_senator(e: Dictionary) -> void:
	if senator == null:
		senator = _new_person("senateur", "chevalier", true, Vector3(-3.0, 0, 3.6))
		senator.target = Vector3(-3.0, 0, 3.6)
	var quests: Array = e.get("quests", [])
	var claim := quests.any(func(q): return q.done and not q.get("claimed", false))
	var todo := quests.any(func(q): return not q.done)
	senator.set_state(false, false, "SENATOR", claim or todo, "?" if claim else "!")

# Centre la caméra sur un village et l'ouvre (depuis les ordres du Sénat). Téléphone en portrait : cadrage du village
# (D_VILLAGE), placé au milieu de la zone libre au-dessus de sa feuille d'aperçu.
func focus_village(id: String, open := true) -> void:
	if villages.has(id):
		if open:
			selected = id
		if rig.portrait:
			if open and mobile.ui:
				mobile.ui._process(0.0)   # la feuille du village s'ouvre dans cette image
			rig.fly_to(villages[id].position, preload("res://camera_math.gd").D_VILLAGE, mobile.ui.centre_libre() if open else -1.0)
		else:
			rig.fly_to(villages[id].position, rig.zoom)

# Cadre la caméra sur une session (depuis le cockpit) et ouvre son village (sur le téléphone, la session en tête de la
# feuille d'aperçu, D_BUILDING).
func focus_building(village: String, building: String) -> void:
	if mobile:
		selected_building = building
	focus_village(village)
	for v in last_state.get("villages", []):
		if v.id == village:
			for b in v.buildings:
				if b.id == building:
					var cible := Vector3(float(b.x), 0, float(b.z))
					if rig.portrait:
						rig.fly_to(cible, preload("res://camera_math.gd").D_BUILDING, mobile.ui.centre_libre())
					else:
						rig.fly_to(cible, rig.zoom)

func _new_person(id: String, unit: String, hero: bool, at: Vector3) -> Node3D:
	var p := preload("res://person.gd").new()
	p.position = at
	add_child(p)
	p.setup(self, id, unit, hero)
	return p

# Le contremaître d'une session : au bâtiment s'il travaille, assis s'il dort, à la fontaine avec « ! » s'il t'attend.
func _update_foreman(b: Dictionary, v: Dictionary, toward: Vector3, side: Vector3) -> void:
	var bpos := Vector3(float(b.x), 0, float(b.z))
	if not persons.has(b.id):
		var np := _new_person(b.id, b.unit, true, bpos)
		np.set_meta("subs", 0)
		persons[b.id] = np
		audio.say("nouveau", np)
	var p: Node3D = persons[b.id]
	var w: bool = b.working
	if w != p.working and started:
		if w and String(b.asked) != "":
			audio.say("travail", p, "Right… " + audio.short(String(b.asked), 60))
		elif not w and String(b.said) != "":
			audio.say("fini", p, "Done: " + audio.short(String(b.said), 70))
		else:
			audio.say("travail" if w else "fini", p)
	var n_subs: int = b.get("subs", []).size()
	if n_subs > int(p.get_meta("subs", 0)):
		audio.say("renfort", p)
	p.set_meta("subs", n_subs)
	if w:
		p.target = bpos + toward * 2.6
	elif b.sleeping:
		p.target = bpos + side * 2.4
	else:
		var h := absi(int(String(b.id).hash())) % 12
		p.target = Vector3(cos(h / 12.0 * TAU) * 3.4, 0, sin(h / 12.0 * TAU) * 3.4)
	var text := ""
	if w:
		text = "%s · %s\n%s%s" % [b.model, String(b.title).left(26), b.state, (" · %d villager%s" % [n_subs, "s" if n_subs > 1 else ""]) if n_subs else ""]
	elif not b.sleeping:
		text = "%s · %s" % [v.name, String(b.title).left(22)]
	# marque au-dessus de la tête : seulement si quelque chose mérite ton attention (ou « z » s'il dort)
	var att := String(b.get("attention", ""))
	var mark: String = MARKS.get(att, "")
	if mark == "" and b.sleeping:
		mark = "z"
	p.set_state(w, bool(b.sleeping), text, mark != "", mark)

# Un sous-agent : petit villageois qui travaille autour du bâtiment de sa session.
func _update_sub(sub: Dictionary, b: Dictionary, k: int) -> void:
	var id := "sub-" + String(sub.id)
	var bpos := Vector3(float(b.x), 0, float(b.z))
	if not persons.has(id):
		persons[id] = _new_person(String(sub.id), String(sub.unit), false, bpos)
	var p: Node3D = persons[id]
	var ang := float(k) * 0.9 + 0.6
	p.target = bpos + Vector3(cos(ang), 0, sin(ang)) * (2.4 + 0.4 * (k % 3))
	var tool_text: String = String(sub.tool) if (sub.working and sub.tool) else ("done" if not sub.working else "…")
	p.set_state(bool(sub.working), false, "%s\n%s" % [String(sub.title).left(24), tool_text], false)

# Événements du serveur : livraisons de ressources (porteurs), niveaux, objectifs, succès, famine.
func _handle_events(events: Array) -> void:
	if last_event_t == 0:
		last_event_t = int(Time.get_unix_time_from_system() * 1000.0) - 5000
	for e in events:
		if int(e.t) <= last_event_t:
			continue
		match String(e.type):
			"bois", "pierre", "parchemins", "or":
				_spawn_porteur(e)
			"niveau", "objectif", "succes", "reprise", "recompense", "monument":
				hud.show_toast(String(e.text))
				audio.play_sfx("fanfare")
			"senat":
				hud.show_toast(String(e.text))
				audio.play_sfx("cor")
			"famine":
				hud.show_toast(String(e.text))
				audio.play_sfx("cor")
			"faim":
				audio.play_sfx("cloche")
	if events.size():
		last_event_t = maxi(last_event_t, int(events[-1].t))

func _spawn_porteur(e: Dictionary) -> void:
	if porteurs.size() >= 8:
		return
	var from := Vector3.ZERO
	var unit := "paysan"
	for v in last_state.villages:
		if v.id == e.village:
			for b in v.buildings:
				if b.id == e.building:
					from = Vector3(float(b.x), 0, float(b.z))
					unit = String(b.unit)
	if from == Vector3.ZERO:
		return
	var p := _new_person("p-" + String(e.building) + str(randi()), unit, false, from)
	p.set_carry(String(e.type))
	p.target = Vector3(randf_range(-2.5, 2.5), 0, randf_range(2.8, 3.6))
	p.set_state(false, false, "", false)
	porteurs.append(p)
	p.on_arrive = func():
		audio.play_sfx("livraison")
		porteurs.erase(p)
		p.queue_free()

# Tags, objectifs et noms des bâtiments : seulement pour le village survolé ou sélectionné. Téléphone en portrait, au-delà
# de D_TITRES : seuls les noms des villages choisis ou qui t'attendent restent (ils se chevauchent sur la vue d'ensemble).
const D_TITRES := 150.0
var _titres_au_loin := true

func _update_focus() -> void:
	var titres: bool = not rig.portrait or rig.zoom <= D_TITRES
	var tous := titres != _titres_au_loin
	_titres_au_loin = titres
	for id in villages:
		var on: bool = id == hovered or id == selected
		if _focus_shown.get(id, null) != on:
			villages[id].set_focus(on)
			_focus_shown[id] = on
		if tous or villages[id].titre_au_loin != titres:
			villages[id].montrer_titre_au_loin(titres)

func _process(delta: float) -> void:
	_update_focus()
	if started:
		# pas de changement de qualité pendant un geste ou une feuille qui bouge (saccade au pincement)
		if rig.active or (power and power.interactif):
			world.adapt_suspendre()
		else:
			world.adapt(delta)
