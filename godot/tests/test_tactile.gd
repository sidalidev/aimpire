extends SceneTree
# Gestes tactiles de camera_rig.gd sur le Mac (vue 1280 × 720, pas de mode téléphone) : glisser, pincer, toucher, double
# toucher, et faux clics souris ignorés. Les doigts ne font que noter leur position : la caméra bouge dans _process, que
# le test appelle lui-même image par image (1/60 s) pour rester déterministe.
# Lancer : godot --headless --path godot -s tests/test_tactile.gd   (code de sortie 1 au premier écart)

var echecs := 0
var total := 0

func verifie(cas: String, ok: bool, detail := "") -> void:
	total += 1
	if not ok:
		echecs += 1
		printerr("ÉCHEC ", cas, ("  " + detail) if detail != "" else "")

func toucher(rig: Node3D, index: int, pos: Vector2, appui: bool, double := false) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = appui
	e.double_tap = double
	rig._unhandled_input(e)

func glisser(rig: Node3D, index: int, pos: Vector2, relatif: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = relatif
	rig._unhandled_input(e)

func image(rig: Node3D, n := 1) -> void:
	for i in n:
		rig._process(1.0 / 60.0)

func _initialize() -> void:
	var main: Node = preload("res://tests/faux_main.gd").new()
	root.add_child(main)
	var rig: Node3D = preload("res://camera_rig.gd").new()
	rig.main = main
	main.add_child(rig)
	await process_frame
	rig.setup()
	rig.set_process(false)
	verifie("Mac : pas de portrait", not rig.portrait and rig.cam.keep_aspect == Camera3D.KEEP_HEIGHT and rig.cam.fov == 38.0)

	# Un doigt qui glisse : la vue se déplace, et ce n'est pas une sélection
	var avant: Vector3 = rig.position
	toucher(rig, 0, Vector2(400, 300), true)
	for i in 10:
		glisser(rig, 0, Vector2(400 + 10 * (i + 1), 300), Vector2(10, 0))
		image(rig)
	image(rig, 6)   # doigt immobile avant de se lever : pas de lancer
	toucher(rig, 0, Vector2(500, 300), false)
	verifie("glisser déplace la vue", rig.position.distance_to(avant) > 1.0, str(rig.position))
	verifie("glisser ne sélectionne pas", main.selected == "village-de-depart", main.selected)
	verifie("au repos après un glissé lent", not rig.active, rig.nom_etat())

	# Petit tremblement sous le seuil puis relâcher : c'est un toucher, il sélectionne (ici : rien sous le doigt)
	var pos_toucher: Vector3 = rig.position
	toucher(rig, 0, Vector2(300, 200), true)
	glisser(rig, 0, Vector2(304, 202), Vector2(4, 2))
	image(rig)
	toucher(rig, 0, Vector2(304, 202), false)
	verifie("toucher bref sélectionne", main.selected == "", main.selected)
	verifie("tremblement ne déplace pas", rig.position == pos_toucher)

	# Pincer : deux doigts qui s'écartent rapprochent la caméra (zoom plus petit), qui se resserrent l'éloignent
	var z0: float = rig.zoom
	toucher(rig, 0, Vector2(300, 300), true)
	toucher(rig, 1, Vector2(500, 300), true)
	glisser(rig, 1, Vector2(600, 300), Vector2(100, 0))
	image(rig)
	verifie("écarter rapproche", rig.zoom < z0 * 0.8, "%f -> %f" % [z0, rig.zoom])
	var z1: float = rig.zoom
	glisser(rig, 1, Vector2(400, 300), Vector2(-200, 0))
	image(rig)
	verifie("resserrer éloigne", rig.zoom > z1 * 1.5, "%f -> %f" % [z1, rig.zoom])
	glisser(rig, 1, Vector2(302, 300), Vector2(-98, 0))
	image(rig)
	verifie("zoom borné à 110", rig.zoom <= 110.0, str(rig.zoom))
	main.selected = "garde"
	toucher(rig, 1, Vector2(300.5, 300), false)
	toucher(rig, 0, Vector2(300, 300), false)
	verifie("pincer ne sélectionne pas", main.selected == "garde", main.selected)
	image(rig, 60)
	verifie("zoom dans [14, 110] après le geste", rig.zoom >= 14.0 and rig.zoom <= 110.0, str(rig.zoom))

	# Faux clic souris émis par Godot pour un toucher : ignoré par la caméra
	var clic := InputEventMouseButton.new()
	clic.device = InputEvent.DEVICE_ID_EMULATION
	clic.button_index = MOUSE_BUTTON_LEFT
	clic.pressed = true
	clic.position = Vector2(10, 10)
	rig._unhandled_input(clic)
	verifie("faux clic ignoré", main.selected == "garde", main.selected)

	# Double toucher hors d'un village : vue d'ensemble (le Forum au centre)
	rig.position = Vector3(20, 0, -15)
	toucher(rig, 0, Vector2(200, 200), true, true)
	toucher(rig, 0, Vector2(200, 200), false)
	image(rig, 48)   # 0,8 s
	verifie("double toucher : Forum", rig.position.length() < 0.05, str(rig.position))
	# le premier toucher du double avait sélectionné le village dessous : le Forum ne garde pas ce panneau ouvert
	verifie("double toucher ferme la sélection du premier toucher", main.selected == "" and main.selected_building == "", main.selected)
	verifie("Mac : bornes du zoom inchangées", rig.d_min() == 14.0 and rig.d_max() == 110.0)

	if echecs:
		printerr("%d / %d vérifications en échec" % [echecs, total])
		quit(1)
	else:
		print("%d vérifications, tout est vert" % total)
		quit(0)
