extends Control
# Feuille qui monte du bas (docs/MOBILE-PORTRAIT.md §3.5), une seule à la fois : phone_ui.gd y loge le contenu de la
# feuille ouverte (village, cockpit, Sénat, villages, réglages). Pleine largeur (560 dp au plus, centrée), opaque, coins du haut
# arrondis, en-tête de 56 dp (poignée, titre, « x » de 48 dp), corps qui défile.
# Crans : pleine (haut à T + 48, voile qui bloque la carte), aperçu (village seulement, 240 dp à 45 % de la hauteur, la
# carte reste utilisable au-dessus), fermée. On la glisse par l'en-tête, 1:1 vers le bas, amorti ×0,3 au-dessus du cran
# haut ; au lâcher : vitesse au-delà de 700 dp/s ou plus de 30 % de la hauteur vers le bas, 25 % vers le haut. Les
# mouvements suivent un ressort amorti critique (ω = 2π / 0,35 s) qui part de la vitesse du doigt et qu'un nouveau geste
# interrompt.

signal fermee_par_utilisateur      # fermeture voulue (glisser, « x », retour, voile) : animation finie
signal detente_changee(nom: String)

const UI := preload("res://ui_kit.gd")
const CM := preload("res://camera_math.gd")
const HAPTIQUE := preload("res://haptics.gd")

const W_RESSORT := TAU / 0.35
const VITESSE_SEUIL := 700.0       # dp/s
const PART_FERMER := 0.30
const PART_MONTER := 0.25
const PART_APERCU := 0.60          # glissée de moins de 60 % depuis le cran plein, une feuille à aperçu s'y arrête
const AMORTI_HAUT := 0.3
const APERCU_MIN := 240.0
const APERCU_PART := 0.45
const EN_TETE := 56.0
# Feuille du village ouverte par un toucher sur la carte : pendant 400 ms elle ne prend aucun toucher, pour que le second
# toucher d'un double toucher aille à la carte (cadrer le village) au lieu de tomber sur la feuille qui monte.
const LIBRE_MS := 400

var ui: RefCounted                 # ui_kit de main (polices)
var a_apercu := false              # seule la feuille du village a un cran d'aperçu
var detente := "fermee"            # "pleine", "apercu" ou "fermee" : cran atteint (ou visé pendant une animation)
var voile: ColorRect
var panneau: PanelContainer
var en_tete: Control
var titre: Label
var bouton_fermer: Button
var collant: VBoxContainer         # au-dessus du défilement (onglets du cockpit)
var defile: ScrollContainer
var corps: VBoxContainer
var _marge_corps: MarginContainer
var _haut := 12.0                  # marges de l'écran (zone sûre comprise)
var _bas := 16.0
var _vue := Vector2(411, 891)
var _y := 891.0                    # bord haut actuel
var _v := 0.0                      # vitesse (dp/s, positive vers le bas)
var _anime := false
var _ferme_utilisateur := false
var _apres_glisse := false
var _glisse := false
var _prise := 0.0
var _ech := PackedVector2Array()   # échantillons (t, y) du glissé
var _t := 0.0
var power: Node = null             # main.power, pour 60 images par seconde pendant un mouvement
var _libre_jusqua := 0             # ticks (ms) : la feuille laisse passer les touchers jusque-là (LIBRE_MS)

func _init(kit: RefCounted = null) -> void:
	ui = kit

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	voile = ColorRect.new()
	voile.color = UI.VOILE
	voile.set_anchors_preset(Control.PRESET_FULL_RECT)
	voile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	voile.gui_input.connect(_sur_voile)
	add_child(voile)
	panneau = PanelContainer.new()
	var fond := StyleBoxFlat.new()
	fond.bg_color = UI.FOND   # opaque : la barre du bas ne transparaît pas sous une feuille pleine
	fond.corner_radius_top_left = int(UI.RAYON_FEUILLE)
	fond.corner_radius_top_right = int(UI.RAYON_FEUILLE)
	panneau.add_theme_stylebox_override("panel", fond)
	panneau.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panneau)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panneau.add_child(col)
	en_tete = Control.new()
	en_tete.custom_minimum_size.y = EN_TETE
	en_tete.mouse_filter = Control.MOUSE_FILTER_STOP
	en_tete.gui_input.connect(_sur_en_tete)
	col.add_child(en_tete)
	var poignee := Panel.new()   # poignée en pilule
	poignee.add_theme_stylebox_override("panel", UI.fond(Color(UI.TEXTE_DOUX, 0.45), 3))
	poignee.mouse_filter = Control.MOUSE_FILTER_IGNORE
	poignee.anchor_left = 0.5
	poignee.anchor_right = 0.5
	poignee.offset_left = -18
	poignee.offset_right = 18
	poignee.offset_top = 8
	poignee.offset_bottom = 13
	en_tete.add_child(poignee)
	titre = Label.new()
	titre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titre.anchor_right = 1.0
	titre.anchor_bottom = 1.0
	titre.offset_left = 20
	titre.offset_right = -56
	titre.offset_top = 10
	titre.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	titre.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titre.add_theme_font_size_override("font_size", UI.POLICE_TITRE)
	titre.add_theme_color_override("font_color", UI.TEXTE)
	if ui:
		titre.add_theme_font_override("font", ui.title_font)
	en_tete.add_child(titre)
	bouton_fermer = Button.new()
	bouton_fermer.icon = UI.icone_fermer()
	bouton_fermer.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bouton_fermer.flat = true
	bouton_fermer.focus_mode = Control.FOCUS_NONE
	bouton_fermer.tooltip_text = "Close"
	bouton_fermer.add_theme_font_size_override("font_size", 28)
	for etat in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		bouton_fermer.add_theme_color_override(etat, UI.TEXTE_DOUX)
	bouton_fermer.anchor_left = 1.0
	bouton_fermer.anchor_right = 1.0
	bouton_fermer.offset_left = -52
	bouton_fermer.offset_right = -4
	bouton_fermer.offset_top = 6
	bouton_fermer.offset_bottom = 54
	bouton_fermer.pressed.connect(func():
		HAPTIQUE.press()
		fermer())
	en_tete.add_child(bouton_fermer)
	collant = VBoxContainer.new()
	collant.add_theme_constant_override("separation", 0)
	var marge_collant := MarginContainer.new()
	for c in ["margin_left", "margin_right"]:
		marge_collant.add_theme_constant_override(c, 20)
	marge_collant.add_theme_constant_override("margin_bottom", 8)
	marge_collant.add_child(collant)
	col.add_child(marge_collant)
	defile = ScrollContainer.new()
	defile.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	defile.scroll_deadzone = 8
	defile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(defile)
	_marge_corps = MarginContainer.new()
	_marge_corps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for c in ["margin_left", "margin_right"]:
		_marge_corps.add_theme_constant_override(c, 20)
	defile.add_child(_marge_corps)
	corps = VBoxContainer.new()
	corps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	corps.add_theme_constant_override("separation", 8)
	_marge_corps.add_child(corps)
	visible = false
	_placer()

# Marges de l'écran (zone sûre comprise) et taille de la vue : recalculées au changement de taille.
func mise_en_page(haut: float, bas: float, vue: Vector2) -> void:
	_haut = haut
	_bas = bas
	_vue = vue
	_marge_corps.add_theme_constant_override("margin_bottom", int(bas))
	if not _anime and not _glisse:
		_y = y_de(detente)
	_placer()

# --- Crans ---

func y_plein() -> float:
	return _haut + UI.STATUT

func y_apercu() -> float:
	var contenu := EN_TETE + collant.get_combined_minimum_size().y + corps.get_combined_minimum_size().y + 8.0
	return _vue.y - clampf(contenu, APERCU_MIN, APERCU_PART * _vue.y)

func y_de(d: String) -> float:
	match d:
		"pleine":
			return y_plein()
		"apercu":
			return y_apercu() if a_apercu else y_plein()
	return _vue.y

# Cran choisi au lâcher (fonction pure, tests/test_sheet.gd). `deplacement` : distance parcourue depuis le cran de départ,
# positive vers le bas ; `vitesse` en dp/s, positive vers le bas ; `hauteur` : hauteur de la feuille à ce cran.
static func choisir_detente(depart: String, a_un_apercu: bool, deplacement: float, vitesse: float, hauteur: float) -> String:
	var h := maxf(hauteur, 1.0)
	if vitesse > VITESSE_SEUIL or deplacement > PART_FERMER * h:
		if depart == "pleine" and a_un_apercu and deplacement < PART_APERCU * h:
			return "apercu"
		return "fermee"
	if depart == "apercu" and (vitesse < -VITESSE_SEUIL or deplacement < -PART_MONTER * h):
		return "pleine"
	return depart

# --- Ouverture et fermeture ---

func est_ouverte() -> bool:
	return visible and detente != "fermee"

# Ouvre au cran donné en montant du bas de l'écran (ou depuis la position actuelle si elle est déjà ouverte).
func ouvrir(d: String) -> void:
	if not visible:
		_y = _vue.y
		_v = 0.0
		if a_apercu:
			_libre_jusqua = Time.get_ticks_msec() + LIBRE_MS
			panneau.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	visible = true
	_ferme_utilisateur = false
	_aller(d, _v, false)

# Fermeture voulue par l'utilisateur : animée, puis le signal fermee_par_utilisateur.
func fermer() -> void:
	if not visible:
		return
	_ferme_utilisateur = true
	_aller("fermee", _v, false)

# Fermeture causée par l'état (une autre feuille s'ouvre, sélection changée) : immédiate.
func fermer_tout_de_suite() -> void:
	visible = false
	_libre_jusqua = 0
	panneau.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED
	_anime = false
	_glisse = false
	_ferme_utilisateur = false
	detente = "fermee"
	_y = _vue.y
	_v = 0.0
	_placer()

func _aller(d: String, vitesse: float, apres_glisse: bool) -> void:
	detente = d
	_v = vitesse
	_anime = true
	_apres_glisse = apres_glisse
	detente_changee.emit(d)
	if power:
		power.poke()

# --- Gestes ---

func _sur_en_tete(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_glisse = true
			_anime = false
			_prise = e.global_position.y - _y
			_ech.clear()
			_ech.append(Vector2(_t, _y))
		elif _glisse:
			_glisse = false
			_lacher()
		en_tete.accept_event()
	elif e is InputEventMouseMotion and _glisse:
		var y: float = e.global_position.y - _prise
		var haut := y_plein()
		if y < haut:
			y = haut - (haut - y) * AMORTI_HAUT
		_y = y
		_ech.append(Vector2(_t, _y))
		if _ech.size() > 16:
			_ech.remove_at(0)
		_placer()
		if power:
			power.poke()
		en_tete.accept_event()

func _vitesse_glisse() -> float:
	if _ech.size() < 2:
		return 0.0
	var dernier := _ech[_ech.size() - 1]
	var premier := dernier
	for i in range(_ech.size() - 2, -1, -1):
		if dernier.x - _ech[i].x > 0.1:
			break
		premier = _ech[i]
	var dt := dernier.x - premier.x
	return (dernier.y - premier.y) / dt if dt > 0.016 else 0.0

func _lacher() -> void:
	var v := _vitesse_glisse()
	var depart := detente
	var y0 := y_de(depart)
	var choix := choisir_detente(depart, a_apercu, _y - y0, v, _vue.y - y0)
	if choix == "fermee":
		_ferme_utilisateur = true
	_aller(choix, v, true)

func _sur_voile(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		fermer()
		voile.accept_event()

# --- Animation ---

# Un pas du ressort vers le cran visé (fonction testable : tests/test_sheet.gd l'appelle à 60 et à 30 images par seconde).
func pas(dt: float) -> void:
	_t += dt
	if not _anime:
		return
	var cible := y_de(detente)
	var s := CM.spring_step(_y - cible, _v, W_RESSORT, dt)
	_y = cible + s.x
	_v = s.y
	if absf(s.x) < 1.5 and absf(s.y) < 30.0:   # la fin de la course (moins de 1,5 dp) se pose d'un coup : 0,5 s au plus
		_y = cible
		_v = 0.0
		_anime = false
		if _apres_glisse:
			HAPTIQUE.snap()
			_apres_glisse = false
		if detente == "fermee":
			visible = false
			if _ferme_utilisateur:
				_ferme_utilisateur = false
				fermee_par_utilisateur.emit()
	elif power:
		power.poke()
	_placer()

func _process(dt: float) -> void:
	if _anime:
		pas(dt)
	else:
		_t += dt
	if _libre_jusqua > 0 and Time.get_ticks_msec() >= _libre_jusqua:
		_libre_jusqua = 0
		panneau.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED

func en_mouvement() -> bool:
	return _anime or _glisse

func _placer() -> void:
	if panneau == null:
		return
	var largeur := minf(_vue.x, UI.LARGEUR_MAX)
	panneau.position = Vector2(floorf((_vue.x - largeur) / 2.0), _y)
	panneau.size = Vector2(largeur, maxf(_vue.y - y_plein(), 1.0))
	var haut := y_plein()
	var part := clampf(1.0 - (_y - haut) / maxf(0.3 * _vue.y, 1.0), 0.0, 1.0)
	voile.color = Color(UI.VOILE, UI.VOILE.a * part)
	voile.visible = part > 0.0
	voile.mouse_filter = Control.MOUSE_FILTER_STOP if detente == "pleine" and part > 0.5 else Control.MOUSE_FILTER_IGNORE

# Contenu : `noeuds` remplacent ce que la feuille hébergeait (ils sont détachés de leur ancien parent).
func heberger(t: String, noeuds: Array, en_haut: Array = []) -> void:
	titre.text = t
	for parent in [corps, collant]:
		for c in parent.get_children():
			parent.remove_child(c)
	for n in noeuds:
		_rattacher(n, corps)
	for n in en_haut:
		_rattacher(n, collant)
	defile.scroll_vertical = 0

static func _rattacher(n: Node, parent: Node) -> void:
	if n.get_parent() == parent:
		return
	if n.get_parent():
		n.get_parent().remove_child(n)
	parent.add_child(n)
