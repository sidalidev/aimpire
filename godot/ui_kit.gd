extends RefCounted
# Polices, thème de l'interface et textes dans le monde (Label3D lisibles à tout zoom, tags en pastille).
# Charte graphique : AImpire a pour couleur l'or romain (#B8892A), la même dans l'icône et dans l'interface.
# Interface à plat (ni dégradé ni reflet), tout arrondi (cartes 22, boutons 14 ou pilule), thème clair (crème) ou sombre
# (sapin nuit) d'après le système, choisi au lancement (AIMPIRE_THEME=light ou dark pour les captures).
# Polices : Bricolage Grotesque (titres de l'interface) et Figtree (texte), OFL. Le monde garde Cinzel (OFL) : ses
# capitales gravées sont celles des inscriptions romaines, et les noms des villages et du Forum appartiennent au monde.

# Couleurs fixes de la charte.
const OR_ROMAIN := Color("b8892a")    # couleur d'AImpire : action principale, interrupteurs, curseurs
const ENCRE := Color("1f2a22")        # encre sapin : texte sur l'or et sur le miel
const CREME := Color("fbf7ef")        # crème miel
const MIEL := Color("e9a23b")         # pastilles d'attention (texte encre, 6,9:1)

# Jetons qui changent avec le thème (contrastes AA calculés, voir CHANGELOG 0.8.0). Valeurs du thème clair par défaut.
static var sombre := false
static var FOND := Color("fbf7ef")           # feuilles, panneaux, écrans pleins
static var CARTE := Color("f3ecdd")          # rangées, champs, boutons secondaires, barre du haut
static var CARTE_PRESSEE := Color("e9dfcb")
static var TEXTE := Color("1f2a22")          # 13,9:1 sur FOND
static var TEXTE_DOUX := Color("4a5a4f")     # 6,9:1 sur FOND, 6,2:1 sur CARTE
static var ACCENT_TEXTE := Color("6b4a12")   # intertitres, liens : 7,5:1 sur FOND
static var OR := Color("b8892a")             # remplissage de l'action principale
static var OR_PRESSE := Color("9c7322")
static var SUR_OR := Color("1f2a22")         # 4,7:1 sur l'or romain
static var TEINTE := Color("f4e3c3")         # bouton secondaire teinté
static var TEINTE_TEXTE := Color("6b4a12")   # 6,4:1 sur TEINTE
static var FILET := Color(0.122, 0.165, 0.133, 0.14)
static var PISTE := Color(0.122, 0.165, 0.133, 0.16)   # piste d'un interrupteur éteint, d'un curseur, d'une jauge
static var VOILE := Color(0.071, 0.125, 0.102, 0.45)  # fond assombri derrière une feuille ou une page
static var DANGER := Color("b3261e")         # rouge sémantique : action destructrice (texte crème 6,1:1)
static var DANGER_PRESSE := Color("8c1d18")
static var DANGER_TEXTE := Color("b3261e")   # message d'erreur : 6,1:1 sur FOND
static var SUCCES := Color("2f5d46")         # ce qui tourne, ce qui est fait : 7,1:1
static var INFO := Color("2a6f8e")           # « You: » dans la feuille d'un village
static var ATTENTION := Color("8a5a0e")      # une session t'attend (texte)

static func palette(s: bool) -> void:
	sombre = s
	FOND = Color("12201a") if s else Color("fbf7ef")
	CARTE = Color("1c2e26") if s else Color("f3ecdd")
	CARTE_PRESSEE = Color("26392f") if s else Color("e9dfcb")
	TEXTE = Color("fbf7ef") if s else Color("1f2a22")
	TEXTE_DOUX = Color("9fb3a8") if s else Color("4a5a4f")
	ACCENT_TEXTE = Color("d9b45a") if s else Color("6b4a12")
	OR = OR_ROMAIN
	OR_PRESSE = Color("cfa041") if s else Color("9c7322")
	SUR_OR = ENCRE
	TEINTE = Color("33392a") if s else Color("f4e3c3")
	TEINTE_TEXTE = Color("e2c27a") if s else Color("6b4a12")
	FILET = Color(0.984, 0.969, 0.937, 0.12) if s else Color(0.122, 0.165, 0.133, 0.14)
	PISTE = Color(0.984, 0.969, 0.937, 0.16) if s else Color(0.122, 0.165, 0.133, 0.16)
	VOILE = Color(0.02, 0.05, 0.04, 0.6) if s else Color(0.071, 0.125, 0.102, 0.45)
	DANGER = Color("b3261e")
	DANGER_PRESSE = Color("8c1d18")
	DANGER_TEXTE = Color("f2a69e") if s else Color("b3261e")
	SUCCES = Color("7cc29a") if s else Color("2f5d46")
	INFO = Color("5bb0d3") if s else Color("2a6f8e")
	ATTENTION = MIEL if s else Color("8a5a0e")

# Thème du système (macOS, Android), ou AIMPIRE_THEME=light|dark.
static func theme_systeme_sombre() -> bool:
	var force := OS.get_environment("AIMPIRE_THEME")
	if force == "dark":
		return true
	if force == "light":
		return false
	return DisplayServer.is_dark_mode_supported() and DisplayServer.is_dark_mode()

# Couleur pour le BBCode d'un RichTextLabel : "#rrggbb".
static func hex(c: Color) -> String:
	return "#" + c.to_html(false)

# Jetons de mise en page du téléphone (docs/MOBILE-PORTRAIT.md §3.4), en dp : espacements, hauteurs, rayons, polices.
const ESPACE_XS := 4.0
const ESPACE_S := 8.0
const ESPACE_M := 12.0
const ESPACE_L := 16.0
const ESPACE_XL := 20.0
const ESPACE_XXL := 24.0
const BARRE := 56.0            # barre du bas
const BARRE_HAUT := 44.0       # barre des ressources
const STATUT := 48.0           # ligne d'état sous la barre des ressources
const RAYON_FEUILLE := 24.0    # feuilles et cartes (charte : 22 à 24)
const RAYON_CARTE := 22.0
const RAYON_BOUTON := 14.0
const CIBLE := 48.0            # cible tactile minimale
const POLICE_META := 14        # métadonnées seulement (âges, FPS)
const POLICE := 16             # tout texte à lire
const POLICE_TITRE := 22       # titre d'une feuille (Bricolage Grotesque)
const LARGEUR_MAX := 560.0     # barre et feuilles dans une fenêtre large : plafonnées et centrées

var title_font: Font   # Bricolage Grotesque 700 (OFL) : titres de l'interface
var big_title_font: Font   # la même, interlettrage -2 % (1 px) pour les grands titres (26 et plus)
var body_font: Font    # Figtree 500 (OFL) : texte
var bold_font: Font    # Figtree 700 : gras dans les textes
var world_font: Font   # Cinzel 700 (OFL) : noms du monde (villages, Forum, bulles)
var world_label_font: Font   # Figtree 600 : étiquettes du monde (bâtiments, personnages, tags)
var theme := Theme.new()
var label_scale := 1.0   # agrandit les textes 3D (mode téléphone : écran de 6 pouces, voir mobile.gd)
var label_range := 55.0  # distance au-delà de laquelle les petites étiquettes disparaissent (95 en portrait)

static func _variation(fichier: String, axes: Dictionary, espacement := 0) -> FontVariation:
	var ts := TextServerManager.get_primary_interface()
	var v := FontVariation.new()
	v.base_font = load(fichier)
	var o := {}
	for k in axes:
		o[ts.name_to_tag(k)] = axes[k]
	v.variation_opentype = o
	v.spacing_glyph = espacement
	return v

func _init() -> void:
	palette(theme_systeme_sombre())
	title_font = _variation("res://assets/fonts/BricolageGrotesque.ttf", {"wght": 700, "opsz": 24})
	big_title_font = _variation("res://assets/fonts/BricolageGrotesque.ttf", {"wght": 700, "opsz": 36}, -1)
	body_font = _variation("res://assets/fonts/Figtree.ttf", {"wght": 500})
	bold_font = _variation("res://assets/fonts/Figtree.ttf", {"wght": 700})
	world_font = _variation("res://assets/fonts/Cinzel.ttf", {"wght": 700})
	world_label_font = _variation("res://assets/fonts/Figtree.ttf", {"wght": 600})
	_construire_theme()

# Thème par défaut de tous les contrôles : boutons, champs, cases, curseurs, menus, barres de défilement, panneaux.
func _construire_theme() -> void:
	var t := theme
	t.default_font = body_font
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXTE)
	t.set_color("font_outline_color", "Label", ENCRE)
	t.set_constant("outline_size", "Label", 0)
	t.set_color("default_color", "RichTextLabel", TEXTE)
	t.set_font("bold_font", "RichTextLabel", bold_font)
	t.set_color("selection_color", "RichTextLabel", Color(OR_ROMAIN, 0.35))
	var panneau := fond(FOND, RAYON_CARTE)
	panneau.set_content_margin_all(16)
	t.set_stylebox("panel", "PanelContainer", panneau)
	t.set_stylebox("panel", "Panel", fond(FOND, RAYON_CARTE))
	t.set_stylebox("panel", "TooltipPanel", fond(FOND, RAYON_BOUTON, FILET, 1))
	t.set_color("font_color", "TooltipLabel", TEXTE)
	# boutons : carte claire (ou sombre), rayon 14, texte encre (ou crème)
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, fond(CARTE, RAYON_BOUTON))
		t.set_stylebox("hover", type, fond(CARTE_PRESSEE, RAYON_BOUTON))
		t.set_stylebox("pressed", type, fond(CARTE_PRESSEE, RAYON_BOUTON))
		t.set_stylebox("hover_pressed", type, fond(CARTE_PRESSEE, RAYON_BOUTON))
		t.set_stylebox("disabled", type, fond(Color(CARTE, 0.5), RAYON_BOUTON))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		for etat in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			t.set_color(etat, type, TEXTE)
		t.set_color("font_disabled_color", type, Color(TEXTE, 0.45))
	t.set_icon("arrow", "OptionButton", _icone_svg(_svg_chevron(), 16))
	# cases et boutons radio du Mac : rond ou carré arrondi, or quand c'est coché
	for type in ["CheckBox", "CheckButton"]:
		for etat in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			t.set_stylebox(etat, type, StyleBoxEmpty.new())
		for etat in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			t.set_color(etat, type, TEXTE)
	t.set_icon("checked", "CheckBox", _icone_svg(_svg_case(true), 20))
	t.set_icon("unchecked", "CheckBox", _icone_svg(_svg_case(false), 20))
	t.set_icon("radio_checked", "CheckBox", _icone_svg(_svg_radio(true), 20))
	t.set_icon("radio_unchecked", "CheckBox", _icone_svg(_svg_radio(false), 20))
	# champs de saisie
	var champ := fond(CARTE, RAYON_BOUTON, FILET, 1)
	champ.content_margin_left = 14
	champ.content_margin_right = 14
	t.set_stylebox("normal", "LineEdit", champ)
	var champ_actif := fond(CARTE, RAYON_BOUTON, OR_ROMAIN, 2)
	champ_actif.content_margin_left = 14
	champ_actif.content_margin_right = 14
	t.set_stylebox("focus", "LineEdit", champ_actif)
	t.set_stylebox("read_only", "LineEdit", fond(Color(CARTE, 0.6), RAYON_BOUTON, FILET, 1))
	t.set_color("font_color", "LineEdit", TEXTE)
	t.set_color("font_uneditable_color", "LineEdit", TEXTE_DOUX)
	t.set_color("font_placeholder_color", "LineEdit", Color(TEXTE_DOUX, 0.8))
	t.set_color("caret_color", "LineEdit", TEXTE)
	t.set_color("selection_color", "LineEdit", Color(OR_ROMAIN, 0.35))
	t.set_color("font_selected_color", "LineEdit", TEXTE)
	# curseurs : piste fine arrondie, partie remplie en or, rond plein
	var piste := fond(PISTE, 3)
	piste.content_margin_top = 3
	piste.content_margin_bottom = 3
	var rempli := fond(OR_ROMAIN, 3)
	rempli.content_margin_top = 3
	rempli.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", piste)
	t.set_stylebox("grabber_area", "HSlider", rempli)
	t.set_stylebox("grabber_area_highlight", "HSlider", rempli)
	var rond := _icone_svg(_svg_rond(), 22)
	t.set_icon("grabber", "HSlider", rond)
	t.set_icon("grabber_highlight", "HSlider", rond)
	t.set_icon("grabber_disabled", "HSlider", rond)
	# jauges (moisson, hiver)
	t.set_stylebox("background", "ProgressBar", fond(PISTE, 4))
	t.set_stylebox("fill", "ProgressBar", fond(OR_ROMAIN, 4))
	# menus déroulants
	var menu := fond(FOND, RAYON_BOUTON, FILET, 1)
	menu.set_content_margin_all(6)
	t.set_stylebox("panel", "PopupMenu", menu)
	t.set_stylebox("hover", "PopupMenu", fond(CARTE_PRESSEE, 10))
	t.set_color("font_color", "PopupMenu", TEXTE)
	t.set_color("font_hover_color", "PopupMenu", TEXTE)
	t.set_icon("radio_checked", "PopupMenu", _icone_svg(_svg_radio(true), 16))
	t.set_icon("radio_unchecked", "PopupMenu", _icone_svg(_svg_radio(false), 16))
	t.set_icon("checked", "PopupMenu", _icone_svg(_svg_case(true), 16))
	t.set_icon("unchecked", "PopupMenu", _icone_svg(_svg_case(false), 16))
	# barres de défilement : un trait arrondi discret
	for type in ["VScrollBar", "HScrollBar"]:
		var poignee := fond(Color(TEXTE_DOUX, 0.45), 4)
		poignee.set_content_margin_all(3)
		t.set_stylebox("grabber", type, poignee)
		t.set_stylebox("grabber_highlight", type, fond(Color(TEXTE_DOUX, 0.7), 4))
		t.set_stylebox("grabber_pressed", type, fond(Color(TEXTE_DOUX, 0.85), 4))
		t.set_stylebox("scroll", type, StyleBoxEmpty.new())
		t.set_stylebox("scroll_focus", type, StyleBoxEmpty.new())
	# séparateurs
	var ligne := StyleBoxLine.new()
	ligne.color = FILET
	ligne.thickness = 1
	t.set_stylebox("separator", "HSeparator", ligne)
	var ligne_v := StyleBoxLine.new()
	ligne_v.color = FILET
	ligne_v.thickness = 1
	ligne_v.vertical = true
	t.set_stylebox("separator", "VSeparator", ligne_v)
	# dialogues (Mac : objectif d'un village, supprimer la chaîne)
	var dialogue := fond(FOND, RAYON_CARTE)
	dialogue.set_content_margin_all(16)
	t.set_stylebox("panel", "AcceptDialog", dialogue)
	var cadre := fond(FOND, RAYON_CARTE, FILET, 1)
	cadre.expand_margin_top = 32
	cadre.expand_margin_left = 2
	cadre.expand_margin_right = 2
	cadre.expand_margin_bottom = 2
	t.set_stylebox("embedded_border", "Window", cadre)
	t.set_stylebox("embedded_unfocused_border", "Window", cadre)
	t.set_color("title_color", "Window", TEXTE)
	t.set_font("title_font", "Window", title_font)

# Icônes du thème dessinées en SVG (traits arrondis), tramées à 3x pour rester nettes une fois agrandies par l'échelle de
# l'interface, affichées à `taille` unités.
static func _icone_svg(svg: String, taille: int) -> ImageTexture:
	var img := Image.new()
	img.load_svg_from_string(svg, 3.0 * taille / 24.0)
	var tex := ImageTexture.create_from_image(img)
	tex.set_size_override(Vector2i(taille, taille))
	return tex

# Croix de fermeture (feuilles, pages) : deux traits à bouts ronds, 2,1 sur la grille de 24.
static func icone_fermer() -> ImageTexture:
	return _icone_svg('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M7 7l10 10M17 7 7 17" fill="none" stroke="%s" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"/></svg>' % hex(TEXTE_DOUX), 24)

static func _svg_case(cochee: bool) -> String:
	if cochee:
		return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect x="2" y="2" width="20" height="20" rx="6" fill="%s"/><path d="M7 12.4l3.2 3.1L17 8.7" fill="none" stroke="%s" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>' % [hex(OR_ROMAIN), hex(ENCRE)]
	return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="5.5" fill="none" stroke="%s" stroke-width="2"/></svg>' % hex(TEXTE_DOUX)

static func _svg_radio(choisi: bool) -> String:
	if choisi:
		return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9.5" fill="none" stroke="%s" stroke-width="2.2"/><circle cx="12" cy="12" r="5" fill="%s"/></svg>' % [hex(OR_ROMAIN), hex(OR_ROMAIN)]
	return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9.5" fill="none" stroke="%s" stroke-width="2"/></svg>' % hex(TEXTE_DOUX)

static func _svg_rond() -> String:
	return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="%s"/><circle cx="12" cy="12" r="4" fill="%s"/></svg>' % [hex(OR_ROMAIN), hex(CREME)]

static func _svg_chevron() -> String:
	return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M7 10l5 5 5-5" fill="none" stroke="%s" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"/></svg>' % hex(TEXTE_DOUX)

# Texte dans le monde : taille fixe à l'écran, contour sombre. `size` donne le rôle : grand = titre ou marque, petit = étiquette.
func label(text: String, y: float, size: float = 0.02) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.position.y = y
	l.no_depth_test = true
	l.outline_modulate = Color(0.1, 0.06, 0.03, 0.95)
	l.modulate = Color("f7f1e3")
	l.render_priority = 2
	l.outline_render_priority = 1
	if size >= 0.03:          # « ! » et « z »
		l.font = world_font
		l.font_size = 64
		l.outline_size = 14
		l.pixel_size = 0.00045 * label_scale
	elif size >= 0.015:       # titres de village, bulles
		l.font = world_font
		l.font_size = 40
		l.outline_size = 12
		l.pixel_size = 0.00042 * label_scale
	else:                     # étiquettes de bâtiment et de personnage
		l.font = world_label_font
		l.font_size = 30
		l.outline_size = 10
		l.pixel_size = 0.00034 * label_scale
		l.visibility_range_end = label_range
	return l

# Pastille : le contour épais coloré sert de fond, le texte est sombre. Pour les tags (niveau, type) et les bulles.
func tag(text: String, y: float, color: Color, big := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.position.y = y
	l.no_depth_test = true
	l.font = world_label_font
	l.font_size = 30 if big else 22
	l.outline_size = 34 if big else 28
	l.outline_modulate = color
	l.modulate = Color("1d120a")
	l.pixel_size = (0.00036 if big else 0.00032) * label_scale
	l.render_priority = 4
	l.outline_render_priority = 3
	if not big:
		l.visibility_range_end = label_range
	return l

# --- Contrôles du téléphone (feuilles, réglages) ---

static func fond(couleur: Color, rayon: float, bord := Color(0, 0, 0, 0), epaisseur := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = couleur
	s.set_corner_radius_all(int(rayon))
	if epaisseur > 0:
		s.border_color = bord
		s.set_border_width_all(epaisseur)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

# Bouton du téléphone, à plat et sans filet, rayon 14, 48 dp, texte replié : or romain plein et texte encre pour
# l'action principale, teinté (crème miel ou sapin) pour les autres.
func bouton(t: String, principal := false) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = CIBLE
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", POLICE)
	habiller(b, principal)
	if principal:
		b.add_theme_font_override("font", bold_font)
	return b

# Habille un bouton existant : or romain plein et texte encre en gras (action principale), sinon teinté.
static func habiller(b: Button, principal := false) -> void:
	var normal := OR if principal else TEINTE
	var presse := OR_PRESSE if principal else TEINTE.darkened(0.08)
	b.add_theme_stylebox_override("normal", fond(normal, RAYON_BOUTON))
	b.add_theme_stylebox_override("hover", fond(normal, RAYON_BOUTON))
	b.add_theme_stylebox_override("pressed", fond(presse, RAYON_BOUTON))
	b.add_theme_stylebox_override("hover_pressed", fond(presse, RAYON_BOUTON))
	b.add_theme_stylebox_override("disabled", fond(Color(normal, 0.45), RAYON_BOUTON))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var texte_c := SUR_OR if principal else TEINTE_TEXTE
	for etat in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(etat, texte_c)
	b.add_theme_color_override("font_disabled_color", Color(texte_c, 0.5))

# Bouton en lien (texte seul, aligné sur le texte voisin) : or foncé en clair, or clair en sombre, 48 dp de haut.
static func lien(b: Button) -> void:
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, CIBLE)
	for etat in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(etat, StyleBoxEmpty.new())
	for etat in ["font_color", "font_hover_color", "font_focus_color"]:
		b.add_theme_color_override(etat, ACCENT_TEXTE)
	b.add_theme_color_override("font_pressed_color", Color(ACCENT_TEXTE, 0.6))
	b.add_theme_color_override("font_hover_pressed_color", Color(ACCENT_TEXTE, 0.6))

# Contrôle segmenté : boutons à bascule de même largeur, un seul enfoncé. `au_choix(i)` à chaque changement.
func segmente(options: Array, choisi: int, au_choix: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	var groupe := ButtonGroup.new()
	for i in options.size():
		var b := Button.new()
		b.text = String(options[i])
		b.toggle_mode = true
		b.button_group = groupe
		b.button_pressed = i == choisi
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = CIBLE
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", POLICE)
		var g := int(RAYON_BOUTON) if i == 0 else 0
		var d := int(RAYON_BOUTON) if i == options.size() - 1 else 0
		for etat in ["normal", "hover", "pressed", "hover_pressed"]:
			var s := fond(OR if etat.contains("pressed") else CARTE, 0)
			s.corner_radius_top_left = g
			s.corner_radius_bottom_left = g
			s.corner_radius_top_right = d
			s.corner_radius_bottom_right = d
			s.content_margin_left = 6
			s.content_margin_right = 6
			b.add_theme_stylebox_override(etat, s)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		for etat in ["font_color", "font_hover_color", "font_focus_color"]:
			b.add_theme_color_override(etat, TEXTE)
		b.add_theme_color_override("font_pressed_color", SUR_OR)
		b.add_theme_color_override("font_hover_pressed_color", SUR_OR)
		var k := i
		b.toggled.connect(func(on):
			if on:
				preload("res://haptics.gd").press()
				au_choix.call(k))
		h.add_child(b)
	return h

# Un bouton dans une liste qui défile : le doigt qui glisse fait défiler (MOUSE_FILTER_PASS) et, s'il a bougé de plus de
# 8 dp depuis l'appui, le relâcher sur le bouton ne déclenche rien.
static func garde_defilement(b: BaseButton, action: Callable) -> void:
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			b.set_meta("appui", e.global_position)
			b.set_meta("bouge", false)
		elif e is InputEventMouseMotion and b.has_meta("appui") and e.global_position.distance_to(b.get_meta("appui")) > 8.0:
			b.set_meta("bouge", true))
	b.pressed.connect(func():
		if not bool(b.get_meta("bouge", false)):
			action.call())

# Rangée tactile : le contenu (texte replié, indicateur) et, par-dessus, un bouton transparent de toute la rangée. Le
# PanelContainer donne à ses enfants le même rectangle : la rangée grandit avec un texte sur deux lignes, et toute la
# rangée (48 dp au moins) répond au doigt.
static func _rangee(contenu: Control, bouton: BaseButton) -> PanelContainer:
	var r := PanelContainer.new()
	r.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	contenu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(contenu)
	bouton.flat = true
	bouton.focus_mode = Control.FOCUS_NONE
	bouton.custom_minimum_size.y = CIBLE
	for etat in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		bouton.add_theme_stylebox_override(etat, StyleBoxEmpty.new())
	r.add_child(bouton)
	return r

func _libelle_rangee(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", POLICE)
	l.add_theme_color_override("font_color", TEXTE)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# Interrupteur (réglage oui ou non) : le texte à gauche, une piste ronde de 52 × 32 dp à droite, or romain quand il est
# actif (rond encre), cerclée quand il est éteint (rond doux), avec un rond qui glisse. Toute la rangée se touche. `au_change(actif)` à chaque bascule.
func interrupteur(t: String, actif: bool, au_change: Callable) -> PanelContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.add_child(_libelle_rangee(t))
	var piste := Panel.new()
	piste.custom_minimum_size = Vector2(52, 32)
	piste.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	piste.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fond_piste := StyleBoxFlat.new()
	fond_piste.set_corner_radius_all(16)
	fond_piste.set_border_width_all(2)
	piste.add_theme_stylebox_override("panel", fond_piste)
	var rond := Panel.new()
	rond.size = Vector2(26, 26)
	rond.position = Vector2(3, 3)
	rond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fond_rond := StyleBoxFlat.new()
	fond_rond.set_corner_radius_all(13)
	rond.add_theme_stylebox_override("panel", fond_rond)
	piste.add_child(rond)
	h.add_child(piste)
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = actif
	b.set_meta("piste", piste)
	var peindre := func(on: bool, anime: bool):
		fond_piste.bg_color = OR if on else PISTE
		fond_piste.border_color = OR if on else TEXTE_DOUX
		fond_rond.bg_color = SUR_OR if on else TEXTE_DOUX
		var x := 23.0 if on else 3.0
		if anime:
			rond.create_tween().tween_property(rond, "position:x", x, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			rond.position.x = x
	peindre.call(actif, false)
	b.set_meta("peindre", peindre)
	b.toggled.connect(func(on):
		preload("res://haptics.gd").press()
		peindre.call(on, true)
		au_change.call(on))
	return _rangee(h, b)

# Remet un interrupteur sur l'état réel (changé ailleurs, par exemple par le Mac) sans déclencher son action.
static func regler_interrupteur(r: Control, on: bool) -> void:
	var b := r.get_child(1) as Button
	if b != null and b.button_pressed != on:
		b.set_pressed_no_signal(on)
		(b.get_meta("peindre") as Callable).call(on, true)

# Choix exclusif en rangées de 48 dp (qualité) : un rond cerclé à gauche, or plein pour l'option choisie.
func choix_radio(options: Array, choisi: int, au_choix: Callable) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	var groupe := ButtonGroup.new()
	for i in options.size():
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		var cercle := Panel.new()
		cercle.custom_minimum_size = Vector2(22, 22)
		cercle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cercle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fond_cercle := StyleBoxFlat.new()
		fond_cercle.bg_color = Color(0, 0, 0, 0)
		fond_cercle.set_corner_radius_all(11)
		fond_cercle.set_border_width_all(2)
		cercle.add_theme_stylebox_override("panel", fond_cercle)
		var point := Panel.new()
		point.size = Vector2(10, 10)
		point.position = Vector2(6, 6)
		point.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fond_point := StyleBoxFlat.new()
		fond_point.bg_color = OR
		fond_point.set_corner_radius_all(5)
		point.add_theme_stylebox_override("panel", fond_point)
		cercle.add_child(point)
		h.add_child(cercle)
		h.add_child(_libelle_rangee(String(options[i])))
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = groupe
		b.button_pressed = i == choisi
		var peindre := func(on: bool):
			fond_cercle.border_color = OR if on else TEXTE_DOUX
			point.visible = on
		peindre.call(i == choisi)
		var k := i
		b.toggled.connect(func(on):
			peindre.call(on)
			if on:
				preload("res://haptics.gd").press()
				au_choix.call(k))
		col.add_child(_rangee(h, b))
	return col

# Curseur du téléphone : piste de 6 dp, partie remplie en or romain, rond plein, 48 dp de haut pour le doigt.
static func habiller_curseur(sl: HSlider) -> void:
	sl.custom_minimum_size.y = CIBLE
	sl.focus_mode = Control.FOCUS_NONE
	var piste := StyleBoxFlat.new()
	piste.bg_color = PISTE
	piste.set_corner_radius_all(3)
	piste.content_margin_top = 3
	piste.content_margin_bottom = 3
	var rempli := StyleBoxFlat.new()
	rempli.bg_color = OR
	rempli.set_corner_radius_all(3)
	rempli.content_margin_top = 3
	rempli.content_margin_bottom = 3
	sl.add_theme_stylebox_override("slider", piste)
	sl.add_theme_stylebox_override("grabber_area", rempli)
	sl.add_theme_stylebox_override("grabber_area_highlight", rempli)

# Intertitre d'une section de feuille (Bricolage Grotesque, or foncé en clair, or clair en sombre).
func intertitre(t: String, taille := 18) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", title_font)
	l.add_theme_font_size_override("font_size", taille)
	l.add_theme_color_override("font_color", ACCENT_TEXTE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

# Texte replié d'au moins 16 sp (14 pour les métadonnées).
func texte(t: String, taille := POLICE, couleur := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", taille)
	if couleur.a > 0.0:
		l.add_theme_color_override("font_color", couleur)
	return l
