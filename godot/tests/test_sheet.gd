extends SceneTree
# Feuille du bas (sheet.gd, docs/MOBILE-PORTRAIT.md §3.5) : cran choisi au lâcher selon la distance et la vitesse,
# ouverture et fermeture par le ressort en moins de 0,5 s à 60 et à 30 images par seconde, glisser l'en-tête, fermeture
# voulue (signal), fermeture immédiate. Lancer : godot --headless --path godot -s tests/test_sheet.gd

const SHEET := preload("res://sheet.gd")

var echecs := 0
var total := 0
var fermee := 0

func egal(cas: String, obtenu: Variant, attendu: Variant) -> void:
	total += 1
	if str(obtenu) != str(attendu):
		echecs += 1
		printerr("ÉCHEC ", cas, "  obtenu ", str(obtenu), ", attendu ", str(attendu))

func _initialize() -> void:
	# Cran choisi au lâcher : depart, aperçu possible, déplacement (dp, vers le bas > 0), vitesse (dp/s), hauteur
	var H := 800.0
	for cas in [
		["pleine", false, 0.0, 0.0, "pleine"],          # rien ne bouge
		["pleine", false, 100.0, 200.0, "pleine"],      # 12 % et lent : on revient
		["pleine", false, 260.0, 100.0, "fermee"],      # plus de 30 %
		["pleine", false, 40.0, 900.0, "fermee"],       # lancer vers le bas
		["pleine", true, 260.0, 100.0, "apercu"],       # feuille à aperçu glissée de moins de 60 %
		["pleine", true, 520.0, 100.0, "fermee"],       # plus de 60 % : fermée
		["pleine", true, 40.0, 900.0, "apercu"],        # lancer vers le bas depuis le cran plein : l'aperçu
		["apercu", true, 80.0, 100.0, "apercu"],        # 10 % : on revient
		["apercu", true, 260.0, 0.0, "fermee"],
		["apercu", true, 10.0, 1200.0, "fermee"],
		["apercu", true, -220.0, -100.0, "pleine"],     # 25 % vers le haut
		["apercu", true, -30.0, -900.0, "pleine"],      # lancer vers le haut
		["apercu", true, -100.0, -300.0, "apercu"],
	]:
		egal("cran %s %s %d %d" % [cas[0], cas[1], int(cas[2]), int(cas[3])], SHEET.choisir_detente(cas[0], cas[1], cas[2], cas[3], H), cas[4])

	var f: Control = SHEET.new()
	root.add_child(f)
	await process_frame
	f.set_process(false)
	f.fermee_par_utilisateur.connect(func(): fermee += 1)
	var vue := Vector2(411, 891)
	f.mise_en_page(12.0, 16.0, vue)
	egal("cran plein sous la barre des ressources", f.y_plein(), 60.0)
	# Ressort : ouvert et posé en moins de 0,5 s, à 60 puis à 30 images par seconde
	for fps in [60, 30]:
		f.fermer_tout_de_suite()
		f.a_apercu = false
		f.ouvrir("pleine")
		egal("ouverture part du bas (%d FPS)" % fps, f._y, vue.y)
		for i in fps / 2:
			f.pas(1.0 / fps)
		egal("ouverte en 0,5 s (%d FPS)" % fps, [absf(f._y - f.y_plein()) < 0.5, f.en_mouvement()], [true, false])
		# fermeture voulue (« x », geste retour) : animée, puis le signal
		var avant := fermee
		f.fermer()
		egal("fermeture animée", f.visible, true)
		for i in fps / 2:
			f.pas(1.0 / fps)
		egal("fermée en 0,5 s (%d FPS)" % fps, [f.visible, f.detente, fermee - avant], [false, "fermee", 1])
	# Aperçu : 240 dp au moins (contenu court), carte libre au-dessus ; glisser l'en-tête vers le haut : cran plein
	f.a_apercu = true
	f.fermer_tout_de_suite()
	f.ouvrir("apercu")
	# feuille du village ouverte depuis la carte : le second toucher d'un double toucher passe à la carte pendant 400 ms
	egal("aperçu : touchers laissés à la carte", f.panneau.mouse_behavior_recursive, Control.MOUSE_BEHAVIOR_DISABLED)
	f._libre_jusqua = 1
	f._process(0.0)
	egal("aperçu : touchers rendus après 400 ms", f.panneau.mouse_behavior_recursive, Control.MOUSE_BEHAVIOR_INHERITED)
	for i in 30:
		f.pas(1.0 / 60.0)
	egal("aperçu de 240 dp", f._y, vue.y - 240.0)
	egal("pas de voile en aperçu", f.voile.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	_glisser(f, f._y + 20.0, [f._y + 20.0 - 60.0, f._y + 20.0 - 120.0, f._y + 20.0 - 200.0])
	for i in 30:
		f.pas(1.0 / 60.0)
	egal("glissé vers le haut : plein", [f.detente, absf(f._y - f.y_plein()) < 0.5], ["pleine", true])
	egal("voile en plein : bloque la carte", f.voile.mouse_filter, Control.MOUSE_FILTER_STOP)
	# au-dessus du cran haut, le mouvement est amorti ×0,3
	_appuyer(f, f._y + 20.0, true)
	_bouger(f, f._y + 20.0 - 100.0)
	egal("amorti au-dessus du cran haut", snappedf(f._y, 0.01), snappedf(f.y_plein() - 30.0, 0.01))
	_appuyer(f, f._y + 20.0, false)
	for i in 30:
		f.pas(1.0 / 60.0)
	egal("revient au cran plein", absf(f._y - f.y_plein()) < 0.5, true)
	# glissé lent de 35 % vers le bas : l'aperçu (feuille du village)
	var y0: float = f._y
	_glisser(f, y0 + 20.0, [y0 + 20.0 + 100.0, y0 + 20.0 + 200.0, y0 + 20.0 + 290.0], 0.2)
	for i in 30:
		f.pas(1.0 / 60.0)
	egal("glissé de 35 % : aperçu", f.detente, "apercu")
	# fermeture causée par l'état : immédiate, sans signal
	var avant2 := fermee
	f.fermer_tout_de_suite()
	egal("fermeture immédiate", [f.visible, fermee - avant2], [false, 0])
	print("test_sheet : %d/%d" % [total - echecs, total])
	quit(1 if echecs else 0)

func _appuyer(f: Control, y: float, appui: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = appui
	e.global_position = Vector2(200, y)
	f._sur_en_tete(e)

func _bouger(f: Control, y: float) -> void:
	var e := InputEventMouseMotion.new()
	e.global_position = Vector2(200, y)
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	f._sur_en_tete(e)

# Appui sur l'en-tête, mouvements (une image de `dt` entre chacun), puis lâcher.
func _glisser(f: Control, depart: float, points: Array, dt := 1.0 / 60.0) -> void:
	_appuyer(f, depart, true)
	for y in points:
		f.pas(dt)
		_bouger(f, y)
	_appuyer(f, points[-1], false)
