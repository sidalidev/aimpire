extends SceneTree
# Caméra du téléphone en portrait (docs/MOBILE-PORTRAIT.md §3.3 et §5.1) : calculs de camera_math.gd, puis camera_rig.gd
# dans une vue de 411 × 891 dp (SubViewport, sans fenêtre) avec des villages factices. Le test appelle lui-même _process
# image par image (1/60 s).
# Lancer : godot --headless --path godot -s tests/test_camera_portrait.gd   (code de sortie 1 au premier écart)

const CM := preload("res://camera_math.gd")

var echecs := 0
var total := 0
var rig: Node3D
var main: Node

func verifie(cas: String, ok: bool, detail := "") -> void:
	total += 1
	if not ok:
		echecs += 1
		printerr("ÉCHEC ", cas, ("  " + detail) if detail != "" else "")

func proche(a: float, b: float, tol: float) -> bool:
	return absf(a - b) <= tol

func toucher(index: int, pos: Vector2, appui: bool, double := false) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = appui
	e.double_tap = double
	rig._unhandled_input(e)

func glisser(index: int, pos: Vector2, relatif := Vector2.ZERO) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = relatif
	rig._unhandled_input(e)

func image(n := 1, dt := 1.0 / 60.0) -> void:
	for i in n:
		rig._process(dt)

func sol(s: Vector2) -> Vector3:
	var g = CM.ground_point(rig.cam, s)
	return g if g != null else Vector3(INF, 0, INF)

# Attend la fin d'un mouvement (glissé, retour, vol) : au plus `max_images` images.
func jusqu_au_repos(max_images := 600) -> int:
	for i in max_images:
		if not rig.active:
			return i
		image()
	return max_images

func reinitialiser(pos := Vector3.ZERO, d := 60.0) -> void:
	rig.etat = rig.IDLE
	rig.position = pos
	rig.zoom = d
	rig.place()

func _initialize() -> void:
	_calculs()
	main = preload("res://tests/faux_main.gd").new()
	main.mobile = RefCounted.new()   # mode téléphone
	main.selected = ""
	root.add_child(main)
	var vue := SubViewport.new()
	vue.size = Vector2i(411, 891)
	vue.disable_3d = false
	root.add_child(vue)
	rig = preload("res://camera_rig.gd").new()
	rig.main = main
	vue.add_child(rig)
	await process_frame
	rig.setup()
	rig.set_process(false)
	_villages()
	_parametres()
	_glisser()
	_glisser_rapide()
	_lancer()
	_bornes()
	_pincer()
	_toucher()
	_double_toucher()
	_paysage(vue)
	print("test_camera_portrait : %d/%d" % [total - echecs, total])
	quit(1 if echecs else 0)

func _calculs() -> void:
	# D_FAR du tableau de §3.3
	for cas in [[24.0, 97.0], [36.0, 145.0], [54.0, 218.0], [72.0, 290.0], [90.0, 300.0]]:
		verifie("D_FAR pour R_occ %d" % int(cas[0]), proche(CM.d_far(cas[0]), cas[1], 1.0), str(CM.d_far(cas[0])))
	verifie("R_occ sans village", CM.r_occ([]) == 24.0)
	verifie("R_occ anneau 40", proche(CM.r_occ([{"x": 40.0, "z": 0.0}, {"x": -22.0, "z": 0.0}]), 54.0, 0.01))
	verifie("élastique inversé", proche(CM.rubber(CM.rubber_inverse(3.0, 5.0), 5.0), 3.0, 0.001) and CM.rubber_inverse(0.0, 5.0) == 0.0)
	verifie("élastique borné", CM.rubber(1000.0, 5.0) <= 5.0 and proche(CM.rubber(0.1, 5.0), 0.099, 0.001))
	var p := CM.pivot_borne(Vector3(100, 0, 0), 50.0, 4.0)
	verifie("pivot borné", p.x > 50.0 and p.x < 54.0, str(p))
	verifie("pivot dans les limites inchangé", CM.pivot_borne(Vector3(10, 0, 5), 50.0, 4.0) == Vector3(10, 0, 5))
	var z := CM.soft_zoom(log(400.0), log(18.0), log(97.0))
	verifie("zoom souple : au plus ×1,15", exp(z) < 97.0 * 1.15 and exp(z) > 97.0)
	# ressort amorti critique : 0,5 s ramène à moins de 1 % à 60 et à 30 images par seconde
	for fps in [60.0, 30.0]:
		var x := Vector2(10.0, 0.0)
		for i in int(fps * 0.5):
			x = CM.spring_step(x.x, x.y, CM.RESSORT_W, 1.0 / fps)
		verifie("ressort à %d FPS" % int(fps), absf(x.x) < 0.1, str(x))
	# vitesse sur les 100 dernières ms
	var ech := PackedVector3Array()
	ech.resize(8)
	for i in 8:
		ech[i] = Vector3(i * 0.02, i * 2.0, 0.0)   # 100 unités par seconde
	var v := CM.velocity_from_samples(ech, 8, 7, 0.14)
	verifie("vitesse mesurée", proche(v.x, 100.0, 0.5), str(v))
	verifie("vitesse : trop court", CM.velocity_from_samples(ech, 1, 0, 0.0) == Vector2.ZERO)
	verifie("durée de vol bornée", CM.duree_vol(0.0, 50.0) == 0.3 and CM.duree_vol(10000.0, 50.0) == 0.6)
	# rayon calculé = rayon de Godot (vérifié plus bas sur la caméra)
	verifie("cubique", CM.cubique(0.0) == 0.0 and CM.cubique(1.0) == 1.0 and proche(CM.cubique(0.5), 0.5, 0.001))

var _V: GDScript

func _village(id: String, pos: Vector3, batiments: Array) -> Node3D:
	var v: Node3D = _V.new()
	v.position = pos
	rig.get_parent().add_child(v)
	for b in batiments:
		var n := Node3D.new()
		n.position = b[1]
		v.add_child(n)
		v.buildings[b[0]] = n
	main.villages[id] = v
	return v

func _villages() -> void:
	_V = GDScript.new()
	_V.source_code = "extends Node3D\nvar buildings := {}\n"
	_V.reload()
	_village("nord", Vector3(40, 0, 0), [["b1", Vector3(-1, 0, -3)], ["b2", Vector3(3, 0, 3)]])
	_village("sud", Vector3(-40, 0, 0), [["b3", Vector3(0, 0, 0)]])
	_village("ouest", Vector3(0, 0, 58), [])
	rig.set_world_extent([{"x": 40.0, "z": 0.0}, {"x": -40.0, "z": 0.0}, {"x": 0.0, "z": 58.0}])

func _parametres() -> void:
	verifie("portrait", rig.portrait and rig.cam.keep_aspect == Camera3D.KEEP_WIDTH and rig.cam.fov == 30.0)
	verifie("R_occ 72, D_FAR 290", proche(rig.r_occ, 72.0, 0.01) and proche(rig.d_far, 290.2, 0.5), "%f %f" % [rig.r_occ, rig.d_far])
	reinitialiser(Vector3.ZERO, 100.0)
	var a: float = rig.cam.global_transform.basis.z.angle_to(Vector3.UP)
	verifie("plongée de 55°", proche(rad_to_deg(a), 35.0, 0.1), str(rad_to_deg(a)))
	var s := Vector2(300, 700)
	var d := CM.rayon(rig.cam.global_transform.basis, 30.0, true, Vector2(411, 891), s)
	verifie("rayon calculé = rayon de Godot", d.distance_to(rig.cam.project_ray_normal(s)) < 0.001, "%s %s" % [d, rig.cam.project_ray_normal(s)])
	verifie("largeur visible 0,536 d", proche(rig._largeur(), 0.536 * 100.0, 0.1), str(rig._largeur()))
	verifie("au repos", not rig.active)

# Le sol sous le doigt reste sous le doigt, en haut comme en bas de l'écran.
func _glisser() -> void:
	for cas in [[Vector2(205, 150), Vector2(205, 330)], [Vector2(205, 760), Vector2(240, 560)]]:
		reinitialiser(Vector3.ZERO, 60.0)
		var a: Vector2 = cas[0]
		var b: Vector2 = cas[1]
		toucher(0, a, true)
		verifie("doigt posé : actif", rig.active)
		# le glissé commence au-delà de 12 dp, ancré là où le seuil est franchi (pas de saut) : on mesure à partir de là
		glisser(0, a.lerp(b, 1.0 / 12.0))
		image()
		verifie("seuil franchi : glissé", rig.nom_etat() == "PAN", rig.nom_etat())
		var g0 := sol(a.lerp(b, 1.0 / 12.0))
		for i in range(1, 12):
			glisser(0, a.lerp(b, (i + 1) / 12.0))
			image()
		var g1 := sol(b)
		verifie("sol sous le doigt (%d)" % int(a.y), g0.distance_to(g1) < 0.5, "%s %s" % [g0, g1])
		image(6)
		toucher(0, b, false)
		jusqu_au_repos()
		verifie("au repos après le glissé", not rig.active, rig.nom_etat())

# Premier glissé reçu déjà loin du point de départ (entrées accumulées sur une image lente) : la carte rattrape le doigt
# au-delà du seuil de 12 dp, le sol reste sous le doigt.
func _glisser_rapide() -> void:
	reinitialiser(Vector3.ZERO, 120.0)
	var a := Vector2(205, 500)
	var b := Vector2(205, 620)
	var g_depart := sol(a.lerp(b, 12.0 / 120.0))   # sol sous le point où le seuil est franchi
	toucher(0, a, true)
	glisser(0, b)
	image()
	verifie("glissé rapide : rattrape le doigt", sol(b).distance_to(g_depart) < 0.5, "%s %s" % [sol(b), g_depart])
	toucher(0, b, false)
	jusqu_au_repos()

# Un lancer continue après le doigt levé, ralentit puis s'arrête.
func _lancer() -> void:
	reinitialiser(Vector3.ZERO, 120.0)
	toucher(0, Vector2(205, 600), true)
	for i in 6:
		glisser(0, Vector2(205, 600 - 40 * (i + 1)))
		image()
	toucher(0, Vector2(205, 360), false)
	verifie("lancer : glissé", rig.nom_etat() == "GLIDE", rig.nom_etat())
	var p0 := rig.position
	image(5)
	var d1 := rig.position.distance_to(p0)
	var p1 := rig.position
	image(5)
	var d2 := rig.position.distance_to(p1)
	verifie("lancer : continue après le lever", d1 > 0.1, str(d1))
	verifie("lancer : ralentit", d2 < d1, "%f %f" % [d1, d2])
	var n := jusqu_au_repos()
	verifie("lancer : s'arrête", not rig.active and n < 300, "%s après %d images" % [rig.nom_etat(), n])

# Bord du monde : le pivot ne dépasse jamais R_bound + O_MAX en glissant, et revient dans R_bound.
func _bornes() -> void:
	reinitialiser(Vector3(50, 0, 50).normalized() * 70.0, 60.0)
	var o_max: float = CM.ELASTIQUE_BORD * rig._largeur()
	toucher(0, Vector2(205, 800), true)   # le doigt monte : la vue part vers le bord du monde (lacet de 45°)
	var pire := 0.0
	for i in 40:
		glisser(0, Vector2(205, 800 - 15 * (i + 1)))
		image()
		pire = maxf(pire, Vector2(rig.position.x, rig.position.z).length())
	verifie("butée élastique", pire <= rig.r_occ + o_max + 0.01, "%f > %f" % [pire, rig.r_occ + o_max])
	verifie("butée atteinte", pire > rig.r_occ, str(pire))
	image(6)
	toucher(0, Vector2(205, 200), false)
	jusqu_au_repos()
	var r := Vector2(rig.position.x, rig.position.z).length()
	verifie("retour dans les limites", r <= rig.r_occ * 1.005, "%f > %f" % [r, rig.r_occ])
	# un toucher pendant le retour élastique ne laisse pas la caméra hors limites
	_hors_du_bord()
	image()
	toucher(0, Vector2(205, 450), true)
	toucher(0, Vector2(205, 450), false)
	jusqu_au_repos()
	r = Vector2(rig.position.x, rig.position.z).length()
	verifie("toucher pendant le retour : revient dans les limites", r <= rig.r_occ * 1.005, "%f > %f" % [r, rig.r_occ])
	# reprendre la carte pendant le retour : pas de saut (l'élastique n'est pas appliqué deux fois)
	_hors_du_bord()
	image(2)
	var avant: Vector3 = rig.position
	toucher(0, Vector2(205, 450), true)
	glisser(0, Vector2(205, 463))
	image()
	glisser(0, Vector2(205, 464))
	image()
	verifie("reprise pendant le retour : pas de saut", rig.position.distance_to(avant) < 0.5, "%f unités pour 14 dp" % rig.position.distance_to(avant))
	toucher(0, Vector2(205, 464), false)
	jusqu_au_repos()

# Glissé lent au-delà du bord du monde, doigt immobile avant le lever (pas de lancer) : retour élastique en cours.
func _hors_du_bord() -> void:
	reinitialiser(Vector3(50, 0, 50).normalized() * 70.0, 60.0)
	toucher(0, Vector2(205, 800), true)
	for i in 30:
		glisser(0, Vector2(205, 800 - 20 * (i + 1)))
		image()
	image(8)
	toucher(0, Vector2(205, 200), false)

# Pincer : le point sous le milieu des doigts reste en place ; le zoom finit dans [D_NEAR, D_FAR].
func _pincer() -> void:
	reinitialiser(Vector3.ZERO, 80.0)
	var c := Vector2(230, 500)
	var g0 := sol(c)
	toucher(0, c + Vector2(-60, -60), true)
	toucher(1, c + Vector2(60, 60), true)
	for i in 10:
		var e := 60.0 + 8.0 * (i + 1)
		glisser(0, c + Vector2(-e, -e))
		glisser(1, c + Vector2(e, e))
		image()
	var g1 := sol(c)
	verifie("pincer : le point reste sous les doigts", g0.distance_to(g1) < 0.5, "%s %s" % [g0, g1])
	verifie("écarter rapproche", rig.zoom < 80.0 * 0.6, str(rig.zoom))
	verifie("pincer : actif", rig.active and rig.nom_etat() == "PINCH")
	# au-delà de la limite proche, puis lever : retour au-dessus de D_NEAR
	for i in 20:
		var e := 140.0 + 8.0 * (i + 1)
		glisser(0, c + Vector2(-e, -e))
		glisser(1, c + Vector2(e, e))
		image()
	verifie("élastique sous D_NEAR", rig.zoom < CM.D_NEAR and rig.zoom > CM.D_NEAR / 1.15, str(rig.zoom))
	toucher(1, c + Vector2(300, 300), false)
	toucher(0, c + Vector2(-300, -300), false)
	jusqu_au_repos()
	verifie("zoom dans [D_NEAR, D_FAR]", rig.zoom >= CM.D_NEAR * 0.999 and rig.zoom <= rig.d_far * 1.001, str(rig.zoom))
	# dézoom au-delà de la limite lointaine
	reinitialiser(Vector3.ZERO, 250.0)
	toucher(0, c + Vector2(-150, -150), true)
	toucher(1, c + Vector2(150, 150), true)
	for i in 10:
		var e := 150.0 - 12.0 * (i + 1)
		glisser(0, c + Vector2(-e, -e))
		glisser(1, c + Vector2(e, e))
		image()
	toucher(0, c, false)
	toucher(1, c, false)
	jusqu_au_repos()
	verifie("zoom ramené à D_FAR", proche(rig.zoom, rig.d_far, rig.d_far * 0.006), str(rig.zoom))
	# pincer de nouveau pendant le retour du zoom : pas de saut
	reinitialiser(Vector3.ZERO, rig.d_far)
	toucher(0, c + Vector2(-50, 0), true)
	toucher(1, c + Vector2(50, 0), true)
	for i in 10:
		glisser(0, c + Vector2(-50 + 4 * (i + 1), 0))
		glisser(1, c + Vector2(50 - 4 * (i + 1), 0))
		image()
	toucher(0, c, false)
	toucher(1, c, false)
	image(2)
	var z0: float = rig.zoom
	toucher(0, c + Vector2(-50, 0), true)
	toucher(1, c + Vector2(50, 0), true)
	glisser(0, c + Vector2(-50.001, 0))
	glisser(1, c + Vector2(50.001, 0))
	image()
	verifie("reprise du pincement pendant le retour : pas de saut", absf(rig.zoom / z0 - 1.0) < 0.005, "%f puis %f" % [z0, rig.zoom])
	toucher(0, c, false)
	toucher(1, c, false)
	jusqu_au_repos()

# Toucher : un bâtiment à 20 dp du doigt est choisi, à 40 dp il ne l'est pas.
func _toucher() -> void:
	reinitialiser(Vector3(40, 0, 0), 40.0)
	image()
	var b: Node3D = main.villages["nord"].buildings["b1"]
	var p: Vector2 = rig.cam.unproject_position(b.global_position + Vector3(0, 2.5, 0))
	var autre: Node3D = main.villages["nord"].buildings["b2"]
	var p2: Vector2 = rig.cam.unproject_position(autre.global_position + Vector3(0, 2.5, 0))
	var dir: Vector2 = (p - p2).normalized()   # s'éloigner de l'autre bâtiment
	main.selected = ""
	toucher(0, p + dir * 20.0, true)
	toucher(0, p + dir * 20.0, false)
	verifie("toucher à 20 dp : bâtiment choisi", main.selected == "nord" and main.selected_building == "b1", "%s %s" % [main.selected, main.selected_building])
	toucher(0, p + dir * 40.0, true)
	toucher(0, p + dir * 40.0, false)
	verifie("toucher à 40 dp : pas ce bâtiment", main.selected_building != "b1", "%s %s" % [main.selected, main.selected_building])
	# sol vide loin de tout : rien
	toucher(0, Vector2(20, 870), true)
	toucher(0, Vector2(20, 870), false)
	verifie("toucher dans le vide : rien", main.selected == "" and main.selected_building == "", main.selected)

func _ecran(g: Vector3) -> Vector2:
	return rig.cam.unproject_position(g)

# Double toucher : un village (cadré à D_VILLAGE, gardé), le Forum (D_VILLAGE, rien), ailleurs (vue d'ensemble).
func _double_toucher() -> void:
	reinitialiser(Vector3(20, 0, 0), 120.0)
	var s := _ecran(Vector3(38, 0, 2))
	toucher(0, s, true)
	toucher(0, s, false)
	toucher(0, s, true, true)
	verifie("double toucher : vol", rig.nom_etat() == "FLY", rig.nom_etat())
	toucher(0, s, false)
	jusqu_au_repos()
	verifie("double toucher : village gardé", main.selected == "nord" and main.selected_building == "", main.selected)
	verifie("double toucher : village cadré", rig.position.distance_to(Vector3(40, 0, 0)) < 0.05 and proche(rig.zoom, CM.D_VILLAGE, 0.1), "%s %f" % [rig.position, rig.zoom])
	reinitialiser(Vector3(5, 0, 5), 100.0)
	s = _ecran(Vector3(2, 0, -3))
	toucher(0, s, true, true)
	toucher(0, s, false)
	jusqu_au_repos()
	verifie("double toucher : Forum", rig.position.length() < 0.05 and proche(rig.zoom, CM.D_VILLAGE, 0.1) and main.selected == "", "%s %f %s" % [rig.position, rig.zoom, main.selected])
	reinitialiser(Vector3(-20, 0, -30), 60.0)
	s = _ecran(Vector3(-25, 0, -38))
	toucher(0, s, true, true)
	toucher(0, s, false)
	jusqu_au_repos()
	verifie("double toucher ailleurs : vue d'ensemble", rig.position.length() < 0.05 and proche(rig.zoom, rig.d_far, 0.5), "%s %f" % [rig.position, rig.zoom])
	# un doigt posé pendant le vol l'arrête là où il est
	reinitialiser(Vector3(-20, 0, -30), 60.0)
	rig.fly_to(Vector3.ZERO, 200.0)
	image(5)
	var pendant := rig.position
	toucher(0, Vector2(200, 400), true)
	image(3)
	verifie("vol interrompu par un doigt", rig.position == pendant and rig.nom_etat() == "PRESS", rig.nom_etat())
	toucher(0, Vector2(200, 400), false)
	main.selected = ""
	main.selected_building = ""

# Fenêtre plus large que haute : réglages du Mac (38° vertical, zoom de 14 à 110).
func _paysage(vue: SubViewport) -> void:
	vue.size = Vector2i(891, 411)
	rig._parametres()
	verifie("paysage : réglages du Mac", not rig.portrait and rig.cam.fov == 38.0 and rig.cam.keep_aspect == Camera3D.KEEP_HEIGHT)
	verifie("paysage : bornes 14 à 110", rig.d_min() == 14.0 and rig.d_max() == 110.0 and rig.zoom <= 110.0)
