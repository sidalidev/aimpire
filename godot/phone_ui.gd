extends Node
# Interface du téléphone (docs/MOBILE-PORTRAIT.md §3.4 à §3.6), possédée par mobile.gd : zones sûres et marges, voile
# derrière le bloc du haut, barre du bas (Cockpit, Villages, Senate, Settings) avec ses pastilles, la feuille et son
# contenu, la couche du toast, et l'état unique `feuille`.
# `feuille` ("", "village", "cockpit", "senate", "villages", "settings") et l'onglet du cockpit ("now", "today", "week",
# "journal") pilotent main.selected, main.selected_building, main.cockpit_open, hud.report_open et
# settings.menu.visible, pour que hud.refresh() dessine le bon contenu. Dans l'autre sens, _verifier() regarde à chaque
# image si l'un d'eux a changé ailleurs (toucher sur la carte, cockpit) et ouvre ou ferme la feuille dans la même image.
# Mise en page unique : en portrait la barre et la feuille prennent la largeur de l'écran ; dans une fenêtre large, elles
# sont plafonnées à 560 dp et centrées.

const UI := preload("res://ui_kit.gd")
const CM := preload("res://camera_math.gd")
const HAPTIQUE := preload("res://haptics.gd")
const SHEET := preload("res://sheet.gd")
const MINIMAP := preload("res://minimap.gd")

const ONGLETS := ["now", "today", "week", "journal"]
const BARRE := ["cockpit", "villages", "senate", "settings"]
const LIBELLES := {"cockpit": "Cockpit", "villages": "Villages", "senate": "Senate", "settings": "Settings"}
const TITRES := {"cockpit": "Cockpit", "senate": "Senate", "villages": "Villages", "settings": "Settings"}
const COULEURS_NIVEAU := {1: Color("c98f62"), 2: Color("9cbf5a"), 3: Color("5bb0d3"), 4: Color("e8c04a")}

var main: Node
var mobile: Node
var feuille := ""
var onglet := "now"
# Marges de la mise en page en dp (zone sûre comprise) : haut, bas, gauche, droite ; et les retraits bruts de la zone sûre.
var T := 12.0
var B := 16.0
var L := 12.0
var R := 12.0
var retraits := Vector4.ZERO      # haut, droite, bas, gauche (dp)
var vue := Vector2(411, 891)

var couche_feuilles: CanvasLayer
var couche_toast: CanvasLayer
var barre: HBoxContainer
var boutons := {}                 # nom -> Button de la barre
var pastilles := {}               # nom -> Label (nombre) de la barre
var feuille_ui: Control           # sheet.gd
var onglets_cockpit: HBoxContainer
var carte: Control                # mini-carte réduite de la feuille Villages
var liste_villages: VBoxContainer
var contenu_reglages: Control     # colonne des réglages (settings.gd)
var _cle_villages := ""
var _sel := ""
var _bat := ""
var _cockpit := false
var _reglages := false
var _n_etats_rapport := -1

func setup() -> void:
	couche_feuilles = CanvasLayer.new()
	couche_feuilles.layer = 3
	add_child(couche_feuilles)
	couche_toast = CanvasLayer.new()
	couche_toast.layer = 5
	add_child(couche_toast)
	# Plus de voile en dégradé en haut (charte à plat) : la barre des ressources et la ligne d'état ont leur propre fond.
	_construire_barre()
	feuille_ui = SHEET.new(main.ui)
	feuille_ui.theme = main.ui.theme
	feuille_ui.power = main.power
	feuille_ui.fermee_par_utilisateur.connect(_sur_fermeture)
	couche_feuilles.add_child(feuille_ui)
	onglets_cockpit = main.ui.segmente(["Now", "Today", "Week", "Journal"], 0, func(i): choisir_onglet(ONGLETS[i]))
	carte = MINIMAP.new()
	carte.main = main
	carte.hote = true
	carte.clip_contents = true
	carte.custom_minimum_size = Vector2(0, 180)
	carte.touchee.connect(_sur_carte)
	carte.resized.connect(func():   # largeur du contenu de la feuille, hauteur 0,55 de la largeur
		var h := floorf(carte.size.x * 0.55)
		if h > 0.0 and absf(carte.custom_minimum_size.y - h) > 0.5:
			carte.custom_minimum_size.y = h)
	liste_villages = VBoxContainer.new()
	liste_villages.add_theme_constant_override("separation", 0)
	# le toast passe au-dessus des feuilles
	var toast: Label = main.hud.toast
	toast.get_parent().remove_child(toast)
	couche_toast.add_child(toast)
	# fond plein : le toast reste lisible au-dessus d'une feuille pleine de texte, pas seulement sur la carte
	var fond_toast := StyleBoxFlat.new()
	fond_toast.bg_color = UI.TEXTE   # inversé (encre en clair, crème en sombre) : se détache de la feuille comme du monde
	fond_toast.set_corner_radius_all(int(UI.RAYON_CARTE))
	fond_toast.content_margin_left = 16
	fond_toast.content_margin_right = 16
	fond_toast.content_margin_top = 10
	fond_toast.content_margin_bottom = 10
	toast.add_theme_stylebox_override("normal", fond_toast)
	toast.add_theme_constant_override("outline_size", 0)
	toast.add_theme_color_override("font_color", UI.FOND)
	toast.add_theme_font_override("font", main.ui.bold_font)
	toast.add_theme_font_size_override("font_size", 18)
	_sel = ""   # une sélection faite avant le premier état (AIMPIRE_SELECT) ouvre sa feuille dès qu'il arrive
	_bat = ""

# --- Mise en page ---

# Retraits de la zone sûre (dp) : marges de la mise en page et placement de tout ce qui est à l'écran.
func mise_en_page(nouveaux_retraits: Vector4, taille_vue: Vector2) -> void:
	retraits = nouveaux_retraits
	vue = taille_vue
	T = maxf(retraits.x + 8.0, 12.0)
	B = retraits.z + 16.0
	L = retraits.w + 12.0
	R = retraits.y + 12.0
	var largeur := minf(vue.x - L - R, UI.LARGEUR_MAX)
	var x := maxf(L, floorf((vue.x - largeur) / 2.0))
	barre.position = Vector2(x, vue.y - B - UI.BARRE)
	barre.size = Vector2(largeur, UI.BARRE)
	feuille_ui.mise_en_page(T, B, vue)
	main.hud.placer_telephone(T, L, R, vue)
	placer_toast()

# Toast : sous la ligne d'état (et sous le bandeau s'il est là), largeur de l'écran moins 48 dp.
func placer_toast() -> void:
	var toast: Label = main.hud.toast
	var y := T + (124.0 if main.hud.fps_label.visible else 108.0)   # sous la mesure des FPS si elle est affichée
	var b: Control = mobile.bandeau
	if b and b.visible:
		y = maxf(y, b.position.y + b.get_combined_minimum_size().y + 8.0)
	toast.anchor_left = 0.0
	toast.anchor_right = 1.0
	toast.offset_left = 24
	toast.offset_right = -24
	toast.offset_top = y
	toast.offset_bottom = y

# Hauteur de l'écran au milieu de la zone libre entre le bloc du haut et une feuille d'aperçu (cadrage d'un village).
func centre_libre() -> float:
	var haut := T + UI.BARRE_HAUT + 4.0 + UI.STATUT
	var b: Control = mobile.bandeau
	if b and b.visible:
		haut = maxf(haut, b.position.y + b.get_combined_minimum_size().y)
	var bas: float = feuille_ui.y_apercu() if feuille == "village" else vue.y * (1.0 - SHEET.APERCU_PART)
	return (minf(haut, bas - 96.0) + bas) / 2.0

# --- Barre du bas ---

var _styles := {}

func _style_barre(actif: bool, presse := false) -> StyleBoxFlat:
	var cle := int(actif) * 2 + int(presse)
	if _styles.has(cle):
		return _styles[cle]
	var s := StyleBoxFlat.new()
	_styles[cle] = s
	if actif:
		s.bg_color = UI.OR_PRESSE if presse else UI.OR
	else:
		s.bg_color = UI.CARTE_PRESSEE if presse else UI.FOND
	s.set_corner_radius_all(int(UI.RAYON_BOUTON))
	s.content_margin_left = 4
	s.content_margin_right = 4
	return s

func _construire_barre() -> void:
	barre = HBoxContainer.new()
	barre.theme = main.ui.theme
	barre.add_theme_constant_override("separation", 8)
	for nom in BARRE:
		var b := Button.new()
		b.text = LIBELLES[nom]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = UI.BARRE
		b.clip_text = true
		b.add_theme_font_size_override("font_size", UI.POLICE)
		b.resized.connect(func(): b.pivot_offset = b.size / 2.0)
		b.button_down.connect(func(): b.scale = Vector2.ONE * 0.97)   # enfoncé dès la première image
		b.button_up.connect(func(): _ressort(b))
		b.pressed.connect(func():
			HAPTIQUE.press()
			_sur_barre(nom))
		var p := Label.new()   # pastille : nombre (Cockpit, Senate) ou point (Settings)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_theme_font_size_override("font_size", UI.POLICE_META)
		p.add_theme_color_override("font_color", UI.ENCRE)
		p.add_theme_constant_override("outline_size", 0)
		var fond := StyleBoxFlat.new()
		fond.bg_color = UI.MIEL
		fond.set_corner_radius_all(10)
		fond.content_margin_left = 5
		fond.content_margin_right = 5
		p.add_theme_stylebox_override("normal", fond)
		p.anchor_left = 1.0
		p.anchor_right = 1.0
		p.offset_left = -26
		p.offset_right = -4
		p.offset_top = 4
		p.offset_bottom = 24
		p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		p.visible = false
		b.add_child(p)
		pastilles[nom] = p
		boutons[nom] = b
		barre.add_child(b)
	mobile.couche.add_child(barre)
	mobile.couche.move_child(barre, 0)
	maj_barre({})

func _ressort(b: Button) -> void:
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)

# État des boutons (celui dont la feuille est ouverte est en or) et pastilles : sessions qui t'attendent, récompenses à
# réclamer, mise à jour disponible.
func maj_barre(s: Dictionary) -> void:
	for nom in BARRE:
		var b: Button = boutons[nom]
		var actif: bool = feuille == nom and feuille_ui != null and feuille_ui.est_ouverte()
		b.add_theme_stylebox_override("normal", _style_barre(actif))
		b.add_theme_stylebox_override("hover", _style_barre(actif))
		b.add_theme_stylebox_override("pressed", _style_barre(actif, true))
		b.add_theme_stylebox_override("hover_pressed", _style_barre(actif, true))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var c := UI.SUR_OR if actif else UI.TEXTE
		for etat in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(etat, c)
	if s.is_empty():
		return
	var e: Dictionary = s.get("empire", {})
	var att := int(e.get("attention", 0))
	var a_reclamer := 0
	for q in e.get("quests", []):
		if q.get("done", false) and not q.get("claimed", false):
			a_reclamer += 1
	_pastille("cockpit", str(att) if att < 100 else "99+", att > 0)
	_pastille("senate", str(a_reclamer), a_reclamer > 0)
	_pastille("settings", " ", main.maj != null and not main.maj.disponible.is_empty())

func _pastille(nom: String, texte: String, montrer: bool) -> void:
	var p: Label = pastilles[nom]
	p.visible = montrer
	if p.text != texte:
		p.text = texte

func _sur_barre(nom: String) -> void:
	if feuille == nom and feuille_ui.est_ouverte():
		fermer()
	else:
		ouvrir(nom)

# --- Feuilles ---

# Ouvre une feuille (barre, pastilles, AIMPIRE_FEUILLE). Une seule à la fois : celle qui était ouverte disparaît.
func ouvrir(nom: String, tab := "") -> void:
	if tab != "":
		onglet = tab
	var meme: bool = nom == feuille and feuille_ui.est_ouverte()
	if not meme and feuille_ui.visible:
		feuille_ui.fermer_tout_de_suite()
	feuille = nom
	_vers_main()
	if nom == "cockpit":
		_maj_onglets()
		_charger_onglet()
	_heberger()
	mobile.rafraichir_hud()
	feuille_ui.a_apercu = nom == "village"
	if not meme:
		var cran := "apercu" if nom == "village" else "pleine"
		if OS.get_environment("AIMPIRE_DETENTE") == "pleine":   # captures : la feuille du village dépliée
			cran = "pleine"
		feuille_ui.ouvrir(cran)
	maj_barre(main.last_state)

# Fermeture voulue par l'utilisateur (« x », glisser, retour, voile, bouton de la barre) : animée, puis l'état.
func fermer() -> void:
	if feuille == "":
		return
	feuille_ui.fermer()

func _sur_fermeture() -> void:
	feuille = ""
	_vers_main()
	maj_barre(main.last_state)
	mobile.rafraichir_hud()

# Fermeture causée par l'état (sélection retirée, cockpit fermé ailleurs) : immédiate.
func _fermer_tout_de_suite() -> void:
	feuille_ui.fermer_tout_de_suite()
	feuille = ""
	_vers_main()
	maj_barre(main.last_state)

# Geste retour : ferme la feuille ouverte (sans passer par l'aperçu). false s'il n'y en avait pas.
func retour() -> bool:
	if feuille == "" or not feuille_ui.visible:
		return false
	fermer()
	return true

# La feuille pilote l'état de main et du HUD.
func _vers_main() -> void:
	main.cockpit_open = feuille == "cockpit"
	main.hud.report_open = feuille == "cockpit" and onglet != "now"
	main.settings.menu.visible = feuille == "settings"
	if feuille == "senate":
		main.selected = "forum"
		main.selected_building = ""
	elif feuille != "village":
		main.selected = ""
		main.selected_building = ""
	_sel = main.selected
	_bat = main.selected_building
	_cockpit = main.cockpit_open
	_reglages = main.settings.menu.visible

# À chaque image : un changement venu d'ailleurs (toucher sur la carte, cockpit) ouvre ou ferme la feuille tout de suite.
func _process(_dt: float) -> void:
	if main == null or not main.started or not is_instance_valid(main.settings.menu):
		return
	var change := false
	if main.selected != _sel or main.selected_building != _bat:
		var village_avant := _sel
		_sel = main.selected
		_bat = main.selected_building
		change = true
		if _sel == "forum":
			if feuille != "senate":
				ouvrir("senate")
		elif _sel != "":
			if feuille != "village":
				ouvrir("village")
			else:
				feuille_ui.titre.text = _nom_village(_sel)
				if village_avant != _sel or feuille_ui.detente == "apercu":
					feuille_ui.defile.scroll_vertical = 0
		elif feuille in ["village", "senate"]:
			_fermer_tout_de_suite()
	if main.cockpit_open != _cockpit:
		_cockpit = main.cockpit_open
		change = true
		if _cockpit and feuille != "cockpit":
			ouvrir("cockpit")
		elif not _cockpit and feuille == "cockpit":
			_fermer_tout_de_suite()
	if main.settings.menu.visible != _reglages:
		_reglages = main.settings.menu.visible
		change = true
		if _reglages and feuille != "settings":
			ouvrir("settings")
		elif not _reglages and feuille == "settings":
			_fermer_tout_de_suite()
	if change:
		maj_barre(main.last_state)
		mobile.rafraichir_hud()
	if feuille_ui.en_mouvement():
		main.power.poke()

func _nom_village(id: String) -> String:
	for v in main.last_state.get("villages", []):
		if v.id == id:
			return nom_affiche(String(v.name))
	return "Village"

# Nom d'un village dans l'interface : première lettre en capitale (« harbor » devient « Harbor »), le reste tel quel. Le
# monde l'écrit en capitales romaines (Cinzel).
static func nom_affiche(n: String) -> String:
	return n.left(1).to_upper() + n.substr(1) if n != "" else n

# Ce que la feuille ouverte héberge.
func _heberger() -> void:
	var h: Control = main.hud
	match feuille:
		"village":
			feuille_ui.heberger(_nom_village(main.selected), [h.panel_text])
		"cockpit":
			feuille_ui.heberger("Cockpit", [h.cockpit_box if onglet == "now" else h.report_text], [onglets_cockpit])
		"senate":
			feuille_ui.heberger("Senate", [h.forum_box, h.food_label])
		"villages":
			feuille_ui.heberger("Villages", [carte, liste_villages])
		"settings":
			if contenu_reglages:
				feuille_ui.heberger("Settings", [contenu_reglages])

# settings.gd a reconstruit sa colonne (appairage, oubli de la chaîne) : la feuille la reprend si elle est ouverte.
func reglages_reconstruits(col: Control) -> void:
	if contenu_reglages and contenu_reglages != col and is_instance_valid(contenu_reglages):
		if contenu_reglages.get_parent():
			contenu_reglages.get_parent().remove_child(contenu_reglages)
		contenu_reglages.queue_free()
	contenu_reglages = col
	if feuille == "settings":
		_heberger()

# --- Cockpit : onglets Now / Today / Week / Journal ---

func choisir_onglet(t: String) -> void:
	if t == onglet and feuille == "cockpit":
		return
	onglet = t
	main.hud.report_open = t != "now"
	_charger_onglet()
	_heberger()
	mobile.rafraichir_hud()

func _maj_onglets() -> void:
	var i := ONGLETS.find(onglet)
	for k in onglets_cockpit.get_child_count():
		(onglets_cockpit.get_child(k) as Button).set_pressed_no_signal(k == i)

func _charger_onglet() -> void:
	_n_etats_rapport = mobile.n_etats
	match onglet:
		"today":
			main.hud.show_report("jour")
		"week":
			main.hud.show_report("semaine")
		"journal":
			main.hud.show_journal()

# Rapport ou journal ouvert : relu quand un nouvel état arrive (ses annexes ont pu changer).
func rafraichir_rapport() -> void:
	if feuille == "cockpit" and onglet != "now" and mobile.n_etats != _n_etats_rapport:
		_charger_onglet()

# --- Villages : mini-carte réduite, puis la liste ---

func maj_villages(s: Dictionary) -> void:
	var vs: Array = s.get("villages", [])
	var lignes := []
	for v in vs:
		var actifs := 0
		for b in v.get("buildings", []):
			if b.get("working", false) and not b.get("hidden", false):
				actifs += 1
		lignes.append({"id": String(v.id), "nom": String(v.name), "niveau": int(v.get("level", 1)), "actifs": actifs,
			"attention": int(v.get("attention", 0)), "repos": float(v.get("idleDays", 0.0))})
	lignes.sort_custom(func(a, b):
		if (a.attention > 0) != (b.attention > 0):
			return a.attention > 0
		if (a.actifs > 0) != (b.actifs > 0):
			return a.actifs > 0
		return a.nom.naturalnocasecmp_to(b.nom) < 0)
	var cle := JSON.stringify(lignes)
	if cle == _cle_villages:
		return
	_cle_villages = cle
	for c in liste_villages.get_children():
		c.queue_free()
	if lignes.is_empty():
		liste_villages.add_child(main.ui.texte("No village yet: the Empire appears once the Mac has published.", UI.POLICE, UI.TEXTE_DOUX))
	for l in lignes:
		liste_villages.add_child(_ligne_village(l))

static func activite(actifs: int, repos: float) -> String:
	if actifs > 0:
		return "%d active" % actifs
	if repos < 1.0:
		return "resting"
	var j := int(floor(repos))
	return "asleep %d d" % j

func _ligne_village(l: Dictionary) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.custom_minimum_size.y = 56
	var vide := StyleBoxEmpty.new()
	var presse := StyleBoxFlat.new()
	presse.bg_color = UI.CARTE_PRESSEE
	presse.set_corner_radius_all(int(UI.RAYON_BOUTON))
	for etat in ["normal", "hover", "focus", "disabled"]:
		b.add_theme_stylebox_override(etat, vide)
	b.add_theme_stylebox_override("pressed", presse)
	b.add_theme_stylebox_override("hover_pressed", presse)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var point := Panel.new()
	var fp := StyleBoxFlat.new()
	fp.bg_color = COULEURS_NIVEAU.get(int(l.niveau), Color.WHITE)
	fp.set_corner_radius_all(6)
	point.add_theme_stylebox_override("panel", fp)
	point.custom_minimum_size = Vector2(12, 12)
	point.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	point.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(point)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nom := Label.new()
	nom.text = nom_affiche(String(l.nom))
	nom.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nom.add_theme_font_size_override("font_size", UI.POLICE)
	nom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nom)
	var act := Label.new()
	act.text = activite(int(l.actifs), float(l.repos))
	act.add_theme_font_size_override("font_size", UI.POLICE_META)
	act.add_theme_color_override("font_color", UI.SUCCES if int(l.actifs) > 0 else UI.TEXTE_DOUX)
	act.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(act)
	h.add_child(col)
	if int(l.attention) > 0:
		var m := Label.new()
		m.text = "!"
		m.add_theme_font_override("font", main.ui.title_font)
		m.add_theme_font_size_override("font_size", 22)
		m.add_theme_color_override("font_color", UI.ATTENTION)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(m)
	b.add_child(h)
	var id := String(l.id)
	UI.garde_defilement(b, func():
		HAPTIQUE.press()
		aller_au_village(id))
	return b

# Une ligne de la liste ou la mini-carte : la feuille se ferme, la caméra vole au village (D_VILLAGE) et sa feuille
# s'ouvre en aperçu.
func aller_au_village(id: String) -> void:
	if not main.villages.has(id):
		return
	_fermer_tout_de_suite()
	main.selected = id
	main.selected_building = ""
	_process(0.0)   # ouvre la feuille du village en aperçu dans cette image
	main.rig.fly_to(main.villages[id].position, CM.D_VILLAGE, centre_libre())

func _sur_carte(point: Vector3) -> void:
	var id: String = main.rig.village_proche(point, 14.0)
	if id != "":
		aller_au_village(id)
		return
	_fermer_tout_de_suite()
	main.rig.fly_to(point, main.rig.zoom)
