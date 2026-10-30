extends Control
# Interface : barre de ressources et de nourriture en haut, journal, toasts d'événements, panneau d'un village.
# Positions par ancres (bord droit, bas) pour suivre la taille de la fenêtre. En mode téléphone (`compact`,
# docs/MOBILE-PORTRAIT.md §3.4) : barre des ressources compacte et ligne d'état placées par phone_ui.gd, contenus
# (village, cockpit, rapports, Forum) logés dans la feuille du bas, polices d'au moins 16, actions du Mac masquées.

const UI := preload("res://ui_kit.gd")
const LAC := Color("5bb0d3")       # jauge de l'hiver (lac de la charte)
const VERT_MOISSON := Color("4e9a6e")

var main: Node
var top := PanelContainer.new()
var res_labels := {}   # ressource -> Label (icône SVG à côté)
var food_bar := ProgressBar.new()
var winter_bar := ProgressBar.new()
var food_label := Label.new()
var title_label := Label.new()
var log_label := Label.new()
var toast := Label.new()
var panel := PanelContainer.new()
var panel_text := RichTextLabel.new()
var toast_until := 0
var forum := PanelContainer.new()
var forum_box := VBoxContainer.new()
var _forum_key := ""
var post := HTTPRequest.new()
var getter := HTTPRequest.new()   # GET /digest, /rapport, /journal
var _get_kind := ""
var report_open := false
var actions_row := HBoxContainer.new()
var goal_dialog := ConfirmationDialog.new()
var goal_box := VBoxContainer.new()
var goal_text := LineEdit.new()
var goal_target := SpinBox.new()
var goal_res := OptionButton.new()
var _goal_village := ""
var _actions_key := ""
var senat := PanelContainer.new()
var senat_box := VBoxContainer.new()
var _quest_key := ""
var cockpit := PanelContainer.new()
var cockpit_box := VBoxContainer.new()
var _cockpit_key := ""
var compact := false          # mode téléphone (main.mobile)
var haut_panneaux := 70       # bord haut des panneaux de droite, sous la barre du haut
var bas_panneaux := -20       # bord bas des panneaux (au-dessus des boutons tactiles en mode téléphone)
var _rempli_moisson := UI.fond(VERT_MOISSON, 4)   # créés une fois : refresh ne change que leur couleur
var _rempli_hiver := UI.fond(LAC, 4)
var bouton_maj: Button        # « Mettre à jour » en haut à droite (update.gd), caché sans nouvelle version
# Téléphone
var report_text := RichTextLabel.new()   # rapports et journal (onglets du cockpit), séparés du panneau du village
var statut := HBoxContainer.new()        # ligne d'état sous la barre des ressources
var pastille_attention: Button           # « ! 2 need you » : ouvre le cockpit
var pastille_discret: Button             # « Discreet » quand le mode discret est actif : ouvre les réglages
var fps_label := Label.new()             # « 60 FPS » sous la ligne d'état, avec « Measure FPS »

# Taille de police : inchangée sur le Mac, au moins 16 sur téléphone.
func _fs(n: int) -> int:
	return maxi(n, 16) if compact else n

# Place un Control ancré au bord droit : `gauche` est l'écart entre son bord gauche et le bord droit de l'écran.
static func _ancre_droite(c: Control, gauche: float, haut: float) -> void:
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.offset_left = -gauche
	c.offset_right = -gauche
	c.offset_top = haut
	c.offset_bottom = haut

# Panneau qui défile : PanelContainer > ScrollContainer > contenu. Sur le Mac, il prend la taille de son contenu
# comme avant (défilement vertical désactivé) ; sur téléphone, il descend jusqu'aux boutons et défile.
func _defilant(p: PanelContainer, contenu: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if compact else ScrollContainer.SCROLL_MODE_DISABLED
	contenu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(contenu)
	p.add_child(sc)
	if compact:
		p.anchor_bottom = 1.0
		p.offset_bottom = bas_panneaux
	return sc

func _ready() -> void:
	compact = main.mobile != null
	if compact:
		haut_panneaux = 112
		bas_panneaux = -76
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # couvre l'écran : les panneaux s'ancrent à ses bords
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if compact:
		_construire_haut_telephone()
	else:
		_construire_haut_mac()
	_construire_suite()

func _construire_haut_mac() -> void:
	top.position = Vector2(12, 8)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fond_haut := UI.fond(Color(UI.FOND, 0.94), 22)   # pilule à plat sur le monde
	fond_haut.content_margin_left = 18
	fond_haut.content_margin_right = 18
	fond_haut.content_margin_top = 8
	fond_haut.content_margin_bottom = 8
	top.add_theme_stylebox_override("panel", fond_haut)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	title_label.add_theme_color_override("font_color", UI.TEXTE)
	title_label.add_theme_font_override("font", main.title_font)
	title_label.add_theme_font_size_override("font_size", 20)
	top.add_child(row)
	row.add_child(title_label)
	for r in ["bois", "pierre", "parchemins", "or"]:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 5)
		var ic := TextureRect.new()
		ic.texture = load("res://assets/ui/icons/%s.svg" % r)
		ic.custom_minimum_size = Vector2(22, 22)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.add_child(ic)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", _fs(15))
		cell.add_child(l)
		res_labels[r] = l
		row.add_child(cell)
	var fwrap := HBoxContainer.new()
	fwrap.add_theme_constant_override("separation", 5)
	var ble := TextureRect.new()
	ble.texture = load("res://assets/ui/icons/ble.svg")
	ble.custom_minimum_size = Vector2(22, 22)
	ble.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ble.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fwrap.add_child(ble)
	row.add_child(fwrap)
	var fcol := VBoxContainer.new()
	fcol.custom_minimum_size = Vector2(220, 0)
	food_label.add_theme_font_size_override("font_size", _fs(12))
	fcol.add_child(food_label)
	for bar in [food_bar, winter_bar]:
		bar.min_value = 0
		bar.max_value = 1
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(220, 8 if bar == winter_bar else 12)
		fcol.add_child(bar)
	_rempli_hiver.bg_color = LAC
	food_bar.add_theme_stylebox_override("fill", _rempli_moisson)
	winter_bar.add_theme_stylebox_override("fill", _rempli_hiver)
	fwrap.add_child(fcol)
	add_child(top)

func _construire_suite() -> void:
	log_label.position = Vector2(12, haut_panneaux)
	log_label.add_theme_color_override("font_color", UI.CREME)   # texte du monde : crème et contour encre
	log_label.add_theme_color_override("font_outline_color", UI.ENCRE)
	log_label.add_theme_constant_override("outline_size", 6)
	log_label.add_theme_font_size_override("font_size", _fs(14))
	log_label.add_theme_constant_override("outline_size", 7)
	add_child(log_label)
	toast.anchor_left = 0.0
	toast.anchor_right = 1.0
	toast.offset_left = 40
	toast.offset_right = -40
	toast.offset_top = 90
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_theme_font_override("font", main.ui.bold_font)
	toast.add_theme_font_size_override("font_size", 18 if compact else 20)
	toast.add_theme_color_override("font_color", UI.FOND)   # carte inversée : encre en clair, crème en sombre
	toast.add_theme_constant_override("outline_size", 0)
	var fond_toast := UI.fond(UI.TEXTE, 22)
	fond_toast.content_margin_left = 20
	fond_toast.content_margin_right = 20
	fond_toast.content_margin_top = 10
	fond_toast.content_margin_bottom = 10
	toast.add_theme_stylebox_override("normal", fond_toast)
	if not compact:   # Mac : la carte prend la largeur du texte, centrée
		toast.anchor_left = 0.5
		toast.anchor_right = 0.5
		toast.offset_left = 0
		toast.offset_right = 0
		toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
		toast.autowrap_mode = TextServer.AUTOWRAP_OFF
	toast.visible = false
	add_child(toast)
	panel_text.add_theme_font_override("normal_font", main.body_font)
	panel_text.add_theme_font_override("bold_font", main.title_font)
	# panneau de droite (village, rapport, journal) : 420 de large, du haut jusqu'en bas, ancré au bord droit
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -440
	panel.offset_right = -20
	panel.offset_top = haut_panneaux
	panel.offset_bottom = bas_panneaux
	panel_text.bbcode_enabled = true
	panel_text.fit_content = true     # c'est le ScrollContainer qui défile (au doigt comme à la molette)
	panel_text.scroll_active = false
	panel_text.add_theme_font_size_override("normal_font_size", _fs(14))
	panel_text.add_theme_font_size_override("bold_font_size", _fs(15))
	panel_text.meta_clicked.connect(_on_panel_link)
	if compact:   # le doigt qui glisse sur le texte fait défiler la feuille
		panel_text.mouse_filter = Control.MOUSE_FILTER_PASS
		for t in [report_text]:
			t.bbcode_enabled = true
			t.fit_content = true
			t.scroll_active = false
			t.mouse_filter = Control.MOUSE_FILTER_PASS
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			t.add_theme_font_override("normal_font", main.body_font)
			t.add_theme_font_override("bold_font", main.title_font)
			t.add_theme_font_size_override("normal_font_size", 16)
			t.add_theme_font_size_override("bold_font_size", 16)
		food_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		food_label.add_theme_font_size_override("font_size", 16)
	var defile := ScrollContainer.new()
	defile.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	defile.add_child(panel_text)
	panel.add_child(defile)
	add_child(goal_dialog)
	goal_dialog.title = "Village goal"
	goal_dialog.ok_button_text = "Set"
	var box := VBoxContainer.new()
	goal_text.placeholder_text = "Ship v1.3"
	goal_box.add_child(goal_text)
	goal_target.min_value = 1
	goal_target.max_value = 10000
	goal_target.value = 20
	goal_box.add_child(goal_target)
	for r in ["or", "commits", "bois", "parchemins"]:   # libellé anglais affiché, clé envoyée au serveur
		goal_res.add_item(RES_NAMES[r])
		goal_res.set_item_metadata(goal_res.item_count - 1, r)
	goal_box.add_child(goal_res)
	goal_dialog.add_child(goal_box)
	goal_dialog.confirmed.connect(_submit_goal)
	panel.visible = false
	add_child(panel)
	_ancre_droite(senat, 280, haut_panneaux)
	senat.custom_minimum_size = Vector2(268, 0)
	senat.mouse_filter = Control.MOUSE_FILTER_PASS
	senat_box.add_theme_constant_override("separation", 4)
	senat.add_child(senat_box)
	add_child(senat)
	_ancre_droite(forum, 420, haut_panneaux)
	forum.custom_minimum_size = Vector2(400, 0)
	forum_box.add_theme_constant_override("separation", 6)
	_defilant(forum, forum_box)
	forum.visible = false
	add_child(forum)
	cockpit.position = Vector2(12, haut_panneaux if compact else 96)
	cockpit.custom_minimum_size = Vector2(440, 0)
	cockpit.mouse_filter = Control.MOUSE_FILTER_PASS
	cockpit_box.add_theme_constant_override("separation", 3)
	_defilant(cockpit, cockpit_box)
	cockpit.visible = false
	add_child(cockpit)
	add_child(post)
	add_child(getter)
	getter.request_completed.connect(_on_get)
	actions_row.add_theme_constant_override("separation", 6)
	_ancre_droite(actions_row, 440, 36)
	actions_row.visible = false
	add_child(actions_row)
	# Téléphone : pas de bouton dans la ligne d'état (il la faisait déborder sur 360 dp) ;
	# la mise à jour passe par le point sur Settings et le bouton de la feuille Settings.
	if main.maj and not compact:
		bouton_maj = main.maj.creer_bouton(13)
		bouton_maj.anchor_left = 1.0
		bouton_maj.anchor_right = 1.0
		bouton_maj.offset_left = -12
		bouton_maj.offset_right = -12
		bouton_maj.offset_top = 4
		bouton_maj.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		add_child(bouton_maj)
	if compact:   # ce que le téléphone ne montre pas : tout passe par la barre du bas et les feuilles
		for c in [panel, forum, cockpit, senat, actions_row, log_label]:
			c.visible = false

# Téléphone : barre des ressources (quatre jetons, nombres sur 4 caractères au plus, moisson et hiver), ligne d'état
# (titre, pastilles), mesure des FPS. phone_ui.gd les place (placer_telephone) selon les marges de l'écran.
func _construire_haut_telephone() -> void:
	var fond := StyleBoxFlat.new()
	fond.bg_color = Color(UI.FOND, 0.96)   # pilule à plat sur le monde
	fond.set_corner_radius_all(22)
	fond.content_margin_left = 14
	fond.content_margin_right = 14
	fond.content_margin_top = 4
	fond.content_margin_bottom = 4
	top.add_theme_stylebox_override("panel", fond)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.custom_minimum_size.y = UI.BARRE_HAUT
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(row)
	for r in ["bois", "pierre", "parchemins", "or"]:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		cell.add_child(_icone(r))
		var l := Label.new()
		l.add_theme_font_size_override("font_size", UI.POLICE)
		l.add_theme_constant_override("outline_size", 0)
		cell.add_child(l)
		res_labels[r] = l
		row.add_child(cell)
	var fwrap := HBoxContainer.new()
	fwrap.add_theme_constant_override("separation", 4)
	fwrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fwrap.add_child(_icone("ble"))
	var fcol := VBoxContainer.new()
	fcol.add_theme_constant_override("separation", 2)
	fcol.alignment = BoxContainer.ALIGNMENT_CENTER
	fcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fcol.custom_minimum_size.x = 40
	for bar in [food_bar, winter_bar]:
		bar.min_value = 0
		bar.max_value = 1
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(40, 4 if bar == winter_bar else 8)
		fcol.add_child(bar)
	_rempli_hiver.bg_color = LAC
	food_bar.add_theme_stylebox_override("fill", _rempli_moisson)
	winter_bar.add_theme_stylebox_override("fill", _rempli_hiver)
	fwrap.add_child(fcol)
	row.add_child(fwrap)
	add_child(top)
	statut.add_theme_constant_override("separation", 8)
	statut.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.add_theme_color_override("font_color", UI.TEXTE)
	title_label.add_theme_constant_override("outline_size", 0)
	title_label.add_theme_font_size_override("font_size", UI.POLICE)
	var fond_titre := UI.fond(Color(UI.FOND, 0.96), 20)   # même pilule que la barre des ressources
	fond_titre.content_margin_left = 14
	fond_titre.content_margin_right = 14
	fond_titre.expand_margin_top = -4
	fond_titre.expand_margin_bottom = -4
	title_label.add_theme_stylebox_override("normal", fond_titre)
	title_label.visible = false   # montré avec le premier état : pas de pilule vide
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.custom_minimum_size.y = UI.STATUT
	statut.add_child(title_label)
	pastille_attention = _pastille_statut(UI.MIEL, UI.ENCRE, func(): main.mobile.ui.ouvrir("cockpit", "now"))
	pastille_discret = _pastille_statut(Color(UI.FOND, 0.96), UI.TEXTE, func(): main.mobile.ui.ouvrir("settings"))
	pastille_discret.text = "Discreet"
	add_child(statut)
	fps_label.add_theme_font_size_override("font_size", UI.POLICE_META)
	fps_label.add_theme_color_override("font_color", UI.CREME)
	fps_label.add_theme_color_override("font_outline_color", UI.ENCRE)
	fps_label.add_theme_constant_override("outline_size", 6)
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fps_label.visible = false
	add_child(fps_label)

func _icone(nom: String) -> TextureRect:
	var ic := TextureRect.new()
	ic.texture = load("res://assets/ui/icons/%s.svg" % nom)
	ic.custom_minimum_size = Vector2(20, 20)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return ic

# Pastille de la ligne d'état : 40 dp de haut dans une ligne de 48, zone de toucher de 48.
func _pastille_statut(fond_c: Color, texte_c: Color, action: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(48, 48)
	b.add_theme_font_size_override("font_size", 16)
	var fond := StyleBoxFlat.new()
	fond.bg_color = fond_c
	fond.set_corner_radius_all(20)
	fond.content_margin_left = 12
	fond.content_margin_right = 12
	fond.expand_margin_top = -4
	fond.expand_margin_bottom = -4
	for etat in ["normal", "hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(etat, fond)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for etat in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(etat, texte_c)
	b.pressed.connect(func():
		preload("res://haptics.gd").press()
		action.call())
	b.visible = false
	statut.add_child(b)
	return b

# Place la barre des ressources (en T), la ligne d'état (T + 48) et la mesure des FPS (T + 96) entre les marges L et R.
func placer_telephone(t: float, l: float, r: float, vue: Vector2) -> void:
	var largeur := vue.x - l - r
	top.position = Vector2(l, t)
	top.size = Vector2(largeur, 44)
	statut.position = Vector2(l, t + 48)
	statut.size = Vector2(largeur, 48)
	fps_label.position = Vector2(l, t + 96)

# Nombre en 4 caractères au plus : 999, 1.2k, 12k, 1.2M (tronqué, jamais arrondi vers le haut).
static func court(n: int) -> String:
	if n < 0:
		return "-" + court(-n)
	if n < 1000:
		return str(n)
	if n < 10000:
		return "%d.%dk" % [n / 1000, (n % 1000) / 100]
	if n < 1000000:
		return "%dk" % (n / 1000)
	if n < 10000000:
		return "%d.%dM" % [n / 1000000, (n % 1000000) / 100000]
	if n < 1000000000:
		return "%dM" % (n / 1000000)
	return "%dG" % (n / 1000000000)

func show_toast(t: String, ms: int = 4000) -> void:
	toast.text = t
	toast.visible = true
	toast_until = Time.get_ticks_msec() + ms
	if compact and main.mobile and main.mobile.ui:
		main.mobile.ui.placer_toast()

func _process(_d: float) -> void:
	if toast.visible and Time.get_ticks_msec() > toast_until:
		toast.visible = false

func _ago(sec) -> String:
	if sec == null:
		return "?"
	if sec < 60:
		return "%d s" % sec
	if sec < 3600:
		return "%d min" % int(sec / 60)
	if sec < 86400:
		return "%d h" % int(sec / 3600)
	return "%d d" % int(sec / 86400)

func _esc(t) -> String:
	return String(t).replace("[", "[lb]")

# Ordres du Sénat : les villages endormis à relancer aujourd'hui, avec la récompense. Clic = aller au village.
func _refresh_senat(quests: Array, panel_open: bool) -> void:
	senat.visible = not quests.is_empty() and not panel_open
	var key := JSON.stringify(quests)
	if key == _quest_key:
		return
	_quest_key = key
	for c in senat_box.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = "SENATE ORDERS"
	title.add_theme_font_override("font", main.title_font)
	title.add_theme_font_size_override("font_size", _fs(15))
	title.add_theme_color_override("font_color", UI.ACCENT_TEXTE)
	senat_box.add_child(title)
	for q in quests:
		var b := Button.new()
		b.flat = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", _fs(13))
		_coupe(b)
		if q.done and not q.get("claimed", false):
			b.text = "🎁 Claim +%d 🪙  (%s)" % [int(q.reward), q.name]
			b.add_theme_color_override("font_color", UI.ATTENTION)
			b.pressed.connect(func(): _post("/reclamer?village=" + String(q.village).uri_encode()))
		elif q.done:
			b.text = "✔ %s is alive again" % q.name
			b.add_theme_color_override("font_color", UI.SUCCES)
		else:
			b.text = "☐ Revive %s (%d d)  +%d 🪙" % [q.name, int(q.idle), int(q.reward)]
			b.pressed.connect(func(): main.focus_village(String(q.village)))
		senat_box.add_child(b)

func _fetch(path: String, kind: String) -> void:
	if main.mobile:   # téléphone : le rapport, le journal et le digest voyagent avec l'état (annexes)
		var d = main.mobile.annexe(kind, path)
		if d is Dictionary:
			_apply_get(kind, d)
		elif kind != "digest":   # pourquoi c'est indisponible (mode discret, rien reçu encore), dans l'onglet ouvert
			report_text.text = "[color=%s]%s[/color]" % [UI.hex(UI.TEXTE_DOUX), _esc(String(d))]
			report_open = true
		return
	if getter.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		_get_kind = kind
		getter.request(main.net.url(path), main.net.headers())

func fetch_digest() -> void:
	_fetch("/digest", "digest")

func show_report(periode: String) -> void:
	_fetch("/rapport?periode=" + periode, "rapport")

func show_journal() -> void:
	_fetch("/journal", "journal")

func _on_get(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if typeof(d) != TYPE_DICTIONARY:
		return
	_apply_get(_get_kind, d)

# Afficher le digest, un rapport ou le journal, qu'il vienne du serveur local ou des annexes du relais.
func _apply_get(kind: String, d: Dictionary) -> void:
	match kind:
		"digest":
			var since := float(d.get("since", 0)) / 1000.0
			var ago := Time.get_unix_time_from_system() - since
			if ago > 1800.0:   # au moins une demi-heure d'absence : sinon il n'y a rien à raconter
				var parts := []
				if int(d.get("attention", 0)):
					parts.append("%d session(s) waiting for you (Tab)" % int(d.attention))
				if int(d.get("commits", 0)):
					parts.append("%d commits" % int(d.commits))
				if int(d.get("testsOk", 0)):
					parts.append("%d green tests" % int(d.testsOk))
				if d.get("villages", []).size():
					parts.append("%d active villages" % d.villages.size())
				show_toast("Since your last visit (%s): %s" % [_ago(int(ago)), " · ".join(parts) if parts.size() else "nothing new"], 6000)
			_post("/vu")
		"rapport":
			_show_markdown(String(d.get("texte", "")))
		"journal":
			var out := "[font_size=22][b]Empire journal[/b][/font_size]  [color=%s]%s[/color]\n\n" % [UI.hex(UI.TEXTE_DOUX), _fermer()]
			var entries: Array = d.get("entrees", [])
			entries.reverse()
			for e in entries:
				var t := Time.get_datetime_dict_from_unix_time(int(float(e.t) / 1000.0) + Time.get_time_zone_from_system().bias * 60)
				out += "[color=%s]%02d/%02d %02d:%02d[/color]  %s\n" % [UI.hex(UI.TEXTE_DOUX), t.day, t.month, t.hour, t.minute, _esc(e.text)]
			if compact:   # la feuille a déjà son titre et son « x »
				out = out.substr(out.find("\n\n") + 2)
				if entries.is_empty():
					out = "[color=%s]Nothing in the journal yet.[/color]" % UI.hex(UI.TEXTE_DOUX)
			_cible_rapport().text = out
			report_open = true

# Téléphone : rapports et journal dans leur propre texte (onglets du cockpit) ; Mac : le panneau de droite.
func _cible_rapport() -> RichTextLabel:
	return report_text if compact else panel_text

# Comment fermer un panneau : Échap sur le Mac ; sur téléphone la feuille a son « x » et le geste retour.
func _fermer() -> String:
	return "" if compact else "Esc to close"

# Rendu simple du Markdown des rapports (titres, puces) dans le panneau.
func _show_markdown(md: String) -> void:
	var out := ""
	for line in md.split("\n"):
		if line.begins_with("# "):
			if compact:
				out += "[color=%s][b]%s[/b][/color]\n" % [UI.hex(UI.ACCENT_TEXTE), _esc(line.substr(2))]
			else:
				out += "[font_size=22][b]%s[/b][/font_size]  [color=%s]%s[/color]\n" % [_esc(line.substr(2)), UI.hex(UI.TEXTE_DOUX), _fermer()]
		elif line.begins_with("## "):
			out += "\n[color=%s][b]%s[/b][/color]\n" % [UI.hex(UI.ACCENT_TEXTE), _esc(line.substr(3))]
		elif line.begins_with("- "):
			out += "  • %s\n" % _esc(line.substr(2))
		else:
			out += _esc(line) + "\n"
	_cible_rapport().text = out
	report_open = true

# Liens du panneau village : accepter la proposition du Sénat, fixer ou retirer un objectif.
func _on_panel_link(meta) -> void:
	var v = null
	for x in main.last_state.get("villages", []):
		if x.id == main.selected:
			v = x
	if v == null:
		return
	match String(meta):
		"accepter":
			for sug in main.last_state.empire.get("suggestions", []):
				if sug.id == v.id:
					_post("/objectif?village=%s&texte=%s&res=%s&cible=%d" % [String(v.name).uri_encode(), String(sug.texte).uri_encode(), String(sug.res), int(sug.cible)])
		"retirer":
			_post("/objectif?village=%s&retirer=1" % String(v.name).uri_encode())
		"objectif":
			_goal_village = String(v.name)
			goal_dialog.popup_centered(Vector2i(360, 180))

func _submit_goal() -> void:
	if _goal_village == "" or goal_text.text.strip_edges() == "":
		return
	_post("/objectif?village=%s&texte=%s&res=%s&cible=%d" % [_goal_village.uri_encode(), goal_text.text.strip_edges().uri_encode(), String(goal_res.get_item_metadata(goal_res.selected)), int(goal_target.value)])

func _post(path: String) -> void:
	if main.mobile:   # téléphone : commande chiffrée déposée sur le relais (réclamer, construire, mode discret)
		main.mobile.poster(path)
		return
	if post.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		post.request(main.net.url(path), main.net.headers(), HTTPClient.METHOD_POST)

# Panneau du Forum : trésor, ordres du Sénat (réclamer), monuments à bâtir avec l'or.
func _refresh_forum(e: Dictionary) -> void:
	var key := JSON.stringify([e.get("tresor", 0), e.get("quests", []), e.get("monuments", []), e.get("fete", null)])
	if key == _forum_key:
		return
	_forum_key = key
	for c in forum_box.get_children():
		c.queue_free()
	if not compact:   # sur téléphone, le titre est celui de la feuille
		var t := Label.new()
		t.text = "THE FORUM"
		t.add_theme_font_override("font", main.title_font)
		t.add_theme_font_size_override("font_size", 24)
		t.add_theme_color_override("font_color", UI.ACCENT_TEXTE)
		forum_box.add_child(t)
	var tr := Label.new()
	tr.text = "Treasury: %d gold  ·  %s%s" % [int(e.get("tresor", 0)), String(e.get("calendrier", {}).get("jour", "")), "" if compact else "  ·  Esc to close"]
	tr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if compact:
		tr.add_theme_font_size_override("font_size", 16)
		var res := e
		tr.text += "\nWood %d · Stone %d · Scrolls %d" % [int(res.get("bois", 0)), int(res.get("pierre", 0)), int(res.get("parchemins", 0))]
	forum_box.add_child(tr)
	var fete := Button.new()
	fete.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_coupe(fete)
	if e.get("fete"):
		fete.text = "Festival under way: fireworks until tomorrow"
		fete.disabled = true
	elif compact:   # la fête reste réservée au Mac (docs/SYNC.md §6)
		fete.text = "Throw a festival: from the Mac"
		fete.disabled = true
	else:
		fete.text = "Throw a festival for the Empire (a day of fireworks)"
		fete.pressed.connect(func(): _post("/fete"))
	forum_box.add_child(fete)
	var h1 := Label.new()
	h1.text = "Senate orders"
	h1.add_theme_font_override("font", main.title_font)
	h1.add_theme_color_override("font_color", UI.ACCENT_TEXTE)
	if compact:
		h1.add_theme_font_size_override("font_size", 18)
	forum_box.add_child(h1)
	if compact and e.get("quests", []).is_empty():
		forum_box.add_child(_texte_doux("No orders today."))
	for q in e.get("quests", []):
		var b := _bouton_forum(q.done and not q.get("claimed", false))
		if q.done and not q.get("claimed", false):
			b.text = "🎁 Claim +%d 🪙: %s is alive again" % [int(q.reward), q.name]
			_relier(b, func(): _post("/reclamer?village=" + String(q.village).uri_encode()))
		elif q.done:
			b.text = "✔ %s: reward received" % q.name
			b.disabled = true
		else:
			b.text = "☐ Revive %s (asleep for %d d): +%d 🪙" % [q.name, int(q.idle), int(q.reward)]
			_relier(b, func(): main.focus_village(String(q.village)))
		forum_box.add_child(b)
	var h2 := Label.new()
	h2.text = "Monuments"
	h2.add_theme_font_override("font", main.title_font)
	h2.add_theme_color_override("font_color", UI.ACCENT_TEXTE)
	if compact:
		h2.add_theme_font_size_override("font_size", 18)
	forum_box.add_child(h2)
	for m in e.get("monuments", []):
		var b := _bouton_forum(false)
		if m.bati:
			b.text = "🏛 %s: built" % m.nom
			b.disabled = true
		else:
			b.text = "Build %s: %d 🪙" % [m.nom, int(m.cout)]
			b.disabled = int(e.get("tresor", 0)) < int(m.cout)
			_relier(b, func(): _post("/construire?id=" + String(m.id)))
		forum_box.add_child(b)

# Bouton du Forum : sur le Mac comme avant ; sur téléphone 48 dp, texte replié, or plein pour « Claim » (l'action
# principale), défilement de la feuille préservé.
func _bouton_forum(principal: bool) -> Button:
	if compact:
		var b: Button = main.ui.bouton("", principal)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		return b
	var mac := Button.new()
	mac.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_coupe(mac)
	return mac

func _relier(b: Button, action: Callable) -> void:
	if compact:
		preload("res://ui_kit.gd").garde_defilement(b, action)
	else:
		b.pressed.connect(action)

func _texte_doux(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", UI.TEXTE_DOUX)
	return l

const KIND_NAMES := {"question": "is asking you a question", "permission": "waiting for permission", "fini": "done", "erreur": "repeated API error", "silence": "suspicious silence"}
# Couleur d'un signal d'attention (thème clair ou sombre).
static func couleur_signal(kind: String) -> Color:
	match kind:
		"question":
			return UI.ATTENTION
		"permission", "erreur":
			return UI.DANGER_TEXTE
		"silence":
			return UI.TEXTE_DOUX
	return UI.TEXTE

func _h(text: String, color: Color = Color(0, 0, 0, 0), size: int = 15) -> Label:
	if color.a == 0.0:
		color = UI.ACCENT_TEXTE
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", main.title_font)
	l.add_theme_font_size_override("font_size", _fs(size))
	l.add_theme_color_override("font_color", color)
	if compact:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _row(text: String, color: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = text
	b.add_theme_font_size_override("font_size", _fs(13))
	b.add_theme_color_override("font_color", color)
	if compact:   # les lignes passent sur deux lignes au lieu d'être coupées ; le doigt qui glisse fait défiler
		b.add_theme_color_override("font_hover_color", color)
		b.add_theme_color_override("font_pressed_color", color.darkened(0.2))
		b.add_theme_color_override("font_focus_color", color)
		b.focus_mode = Control.FOCUS_NONE
		_relier(b, cb)
	else:
		b.pressed.connect(cb)
	_coupe(b)
	return b

# Téléphone : texte replié sur plusieurs lignes et cible tactile de 48 dp, au lieu d'élargir la feuille hors de l'écran.
func _coupe(b: Button) -> void:
	if compact:
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.y = 48

# Cockpit (Tab) : ce qui mérite ton attention, ce qui tourne, ce que le Sénat veut voir relancé. Clic = cadrer la session.
func _refresh_cockpit(s: Dictionary) -> void:
	var att: Array = s.get("attention", [])
	var working := []
	for v in s.villages:
		for b in v.buildings:
			if b.working:
				working.append([v, b])
	var key := JSON.stringify([att, working.map(func(x): return [x[1].id, x[1].state]), s.empire.get("quests", [])])
	if key == _cockpit_key:
		return
	_cockpit_key = key
	for c in cockpit_box.get_children():
		c.queue_free()
	cockpit_box.add_child(_h("NEEDS YOU  (%d)" % att.size()))
	if att.is_empty():
		cockpit_box.add_child(_row("Nothing is waiting for you", UI.TEXTE_DOUX, func(): pass))
	for a in att:
		var since := _ago(int(Time.get_unix_time_from_system() - float(a.since) / 1000.0))
		var txt := "%s  %s · %s  (%s)" % [main.MARKS.get(a.kind, "!"), a.villageName, String(a.title).left(30), KIND_NAMES.get(a.kind, a.kind)]
		if a.kind == "permission" and a.get("tool", ""):
			txt += " · " + String(a.tool)
		txt += "  " + since + " ago"
		cockpit_box.add_child(_row(txt, couleur_signal(String(a.kind)), func(): main.focus_building(String(a.village), String(a.session))))
	cockpit_box.add_child(_h("RUNNING  (%d)" % working.size(), UI.SUCCES))
	for x in working:
		var v: Dictionary = x[0]
		var b: Dictionary = x[1]
		cockpit_box.add_child(_row("● %s · %s · %s" % [v.name, String(b.title).left(30), b.state], UI.SUCCES, func(): main.focus_building(String(v.id), String(b.id))))
	var quests: Array = s.empire.get("quests", [])
	if not quests.is_empty():
		cockpit_box.add_child(_h("TO REVIVE"))
		for q in quests:
			if not q.done:
				cockpit_box.add_child(_row("☐ %s (asleep for %d d)  +%d 🪙" % [q.name, int(q.idle), int(q.reward)], UI.TEXTE, func(): main.focus_village(String(q.village))))
	var a2: Dictionary = s.empire.get("aujourdhui", {})
	cockpit_box.add_child(_h("TODAY", UI.TEXTE_DOUX, 13))
	cockpit_box.add_child(_row("%d commits · %d green tests · %d h %02d active · $%.1f" % [int(a2.get("commits", 0)), int(a2.get("testsOk", 0)), int(a2.get("min", 0)) / 60, int(a2.get("min", 0)) % 60, float(a2.get("usd", 0))], UI.TEXTE_DOUX, func(): pass))
	if not compact:   # sur téléphone : « x », glisser ou geste retour
		cockpit_box.add_child(_row("Tab to close", UI.TEXTE_DOUX, func(): main.cockpit_open = false))

# Téléphone : la barre des ressources, la ligne d'état, puis le contenu de la feuille ouverte (phone_ui.feuille).
func _refresh_telephone(s: Dictionary, selected: String, fps: int) -> void:
	var e: Dictionary = s.empire
	var n_att := int(e.get("attention", 0))
	var cal: Dictionary = e.get("calendrier", {})
	var fete_txt := ""
	if cal.get("fete"):
		fete_txt = " · " + String(cal.fete.nom)
	elif e.get("rare"):
		fete_txt = " · " + String(e.rare.nom)
	# le nombre de sessions actives avant la série : sur 360 à 411 dp la ligne est coupée à la fin, pas sur l'essentiel
	title_label.text = "%s · %d/%d active · %d-day streak%s" % [e.titre, int(e.actives), int(e.sessions), int(e.get("serie", 0)), fete_txt]
	title_label.visible = true
	pastille_attention.visible = n_att > 0
	pastille_attention.text = "! %d need you" % n_att
	pastille_discret.visible = main.discret
	for r in ["bois", "pierre", "parchemins"]:
		res_labels[r].text = court(int(e[r]))
	res_labels["or"].text = court(int(e.get("tresor", e.or)))
	var f: Dictionary = s.food
	food_bar.value = 1.0 - float(f.saison)
	winter_bar.value = 1.0 - float(f.hiver)
	var teinte := UI.DANGER if f.famine else (UI.MIEL if float(f.saison) > 0.8 else VERT_MOISSON)
	if _rempli_moisson.bg_color != teinte:
		_rempli_moisson.bg_color = teinte
	_texte_moisson(f)
	fps_label.visible = main.mobile.journal_fps
	if fps_label.visible:
		fps_label.text = "%d FPS" % fps
	var ui = main.mobile.ui
	if ui == null:
		return
	match ui.feuille:
		"senate":
			_refresh_forum(e)
		"cockpit":
			if ui.onglet == "now":
				_refresh_cockpit(s)
			else:
				ui.rafraichir_rapport()
		"village":
			if selected != "" and selected != "forum":
				_panel(s, selected)
				ui.feuille_ui.titre.text = ui._nom_village(selected)
		"villages":
			ui.maj_villages(s)
	ui.maj_barre(s)

func _texte_moisson(f: Dictionary) -> void:
	if f.famine and f.retourA != null:
		var left := int((float(f.retourA) - Time.get_unix_time_from_system() * 1000.0) / 1000.0)
		food_label.text = "Famine! Harvest in %s" % _ago(maxi(left, 0))
	else:
		var parts := []
		for u in ["chevalier", "soldat", "eclaireur", "mage"]:
			if f.parUnite.has(u) and float(f.parUnite[u]) > 0.02:
				parts.append("%s %d%%" % [UNIT_NAMES[u], int(float(f.parUnite[u]) * 100)])
		food_label.text = "Harvest: %d%%  (%s)" % [int((1.0 - float(f.saison)) * 100), " · ".join(parts)]

func refresh(s: Dictionary, selected: String, fps: int) -> void:
	if compact:
		_refresh_telephone(s, selected, fps)
		return
	forum.visible = selected == "forum"
	if forum.visible:
		_refresh_forum(s.empire)
	cockpit.visible = main.cockpit_open and not forum.visible
	if cockpit.visible:
		_refresh_cockpit(s)
	log_label.visible = not cockpit.visible
	var e: Dictionary = s.empire
	var n_att := int(e.get("attention", 0))
	var cal: Dictionary = e.get("calendrier", {})
	var fete_txt := ""
	if cal.get("fete"):
		fete_txt = " · " + String(cal.fete.nom)
	elif e.get("rare"):
		fete_txt = " · " + String(e.rare.nom)
	title_label.text = "%s · %d-day streak · %d/%d active%s%s" % [e.titre, int(e.get("serie", 0)), int(e.actives), int(e.sessions), ("  ·  %d need you%s" % [n_att, "" if compact else " (Tab)"]) if n_att else "", fete_txt]
	_refresh_senat(e.get("quests", []), selected != "" or cockpit.visible or (is_instance_valid(main.settings.menu) and main.settings.menu.visible))
	for r in ["bois", "pierre", "parchemins"]:
		res_labels[r].text = str(int(e[r]))
	res_labels["or"].text = str(int(e.get("tresor", e.or)))
	var f: Dictionary = s.food
	food_bar.value = 1.0 - float(f.saison)
	winter_bar.value = 1.0 - float(f.hiver)
	var teinte := UI.DANGER if f.famine else (UI.MIEL if float(f.saison) > 0.8 else VERT_MOISSON)
	if _rempli_moisson.bg_color != teinte:
		_rempli_moisson.bg_color = teinte
	if f.famine and f.retourA != null:
		var left := int((float(f.retourA) - Time.get_unix_time_from_system() * 1000.0) / 1000.0)
		food_label.text = "Famine! Harvest in %s" % _ago(maxi(left, 0))
	else:
		var parts := []
		for u in ["chevalier", "soldat", "eclaireur", "mage"]:
			if f.parUnite.has(u) and float(f.parUnite[u]) > 0.02:
				parts.append("%s %d%%" % [UNIT_NAMES[u], int(float(f.parUnite[u]) * 100)])
		food_label.text = "Harvest: %d%%  (%s)" % [int((1.0 - float(f.saison)) * 100), " · ".join(parts)]
	log_label.text = ("%d FPS\n" % fps) + "\n".join(s.log.slice(0, 3 if compact else 7))
	if compact:
		log_label.visible = log_label.visible and not panel.visible and not forum.visible
	if report_open and (selected != "" or cockpit.visible):
		report_open = false
	panel.visible = (selected != "" and selected != "forum") or report_open
	if panel.visible and not report_open:
		_panel(s, selected)
	_refresh_actions(s, selected)

const TYPE_NAMES := {"cabane": "hut", "atelier": "workshop", "forge": "forge", "bibliotheque": "library", "tour": "watchtower", "chateau": "palace"}
const UNIT_NAMES := {"chevalier": "Legate", "soldat": "Legionary", "eclaireur": "Velite", "mage": "Augur", "paysan": "Plebeian"}
const RES_NAMES := {"or": "gold", "bois": "wood", "pierre": "stone", "parchemins": "scrolls", "commits": "commits"}

# Boutons d'action pour la session cliquée : rien ne consomme de tokens (ouvrir l'app Claude, le dossier, un terminal, la PR, copier la commande de reprise).
func _refresh_actions(s: Dictionary, selected: String) -> void:
	var bid: String = main.selected_building
	# ces actions exécutent quelque chose sur le Mac : jamais depuis le téléphone
	actions_row.visible = bid != "" and selected != "" and selected != "forum" and not report_open and not compact
	if not actions_row.visible:
		_actions_key = ""
		return
	if _actions_key == bid:
		return
	_actions_key = bid
	for c in actions_row.get_children():
		c.queue_free()
	for a in [["Claude", "claude"], ["Folder", "dossier"], ["Terminal", "terminal"], ["PR", "pr"], ["Log", "journal"]]:
		var b := Button.new()
		b.text = a[0]
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func(): _post("/action?kind=%s&session=%s" % [a[1], bid.uri_encode()]))
		actions_row.add_child(b)
	var cp := Button.new()
	cp.text = "Copy --resume"
	cp.add_theme_font_size_override("font_size", 12)
	cp.pressed.connect(func(): DisplayServer.clipboard_set("claude --resume " + bid); show_toast("Command copied"))
	actions_row.add_child(cp)

# Couleurs sémantiques du BBCode ([color=doux], texte, accent, succes, info) remplacées par celles du thème.
static func teinter(bb: String) -> String:
	var teintes := {"doux": UI.TEXTE_DOUX, "texte": UI.TEXTE, "accent": UI.ACCENT_TEXTE, "succes": UI.SUCCES, "info": UI.INFO}
	for nom in teintes:
		bb = bb.replace("[color=%s]" % nom, "[color=%s]" % UI.hex(teintes[nom]))
	return bb

func _panel(s: Dictionary, selected: String) -> void:
	var v = null
	for x in s.villages:
		if x.id == selected:
			v = x
	if v == null:
		panel.visible = false
		return
	var out := ""
	if compact:   # le nom est le titre de la feuille
		out += "[color=doux]%s · XP %d[/color]\n" % [_esc(String(v.levelName).capitalize()), int(v.xp)]
		out += "[color=texte]🪵 %d  🪨 %d  📜 %d  🪙 %d[/color]\n" % [int(v.res.bois), int(v.res.pierre), int(v.res.parchemins), int(v.res.or)]
	else:
		out += "[font_size=22][b]%s[/b][/font_size]  [color=doux]%s[/color]\n" % [_esc(v.name), _esc(String(v.levelName).capitalize())]
		out += "[color=texte]🪵 %d  🪨 %d  📜 %d  🪙 %d  ·  XP %d  ·  %s[/color]\n" % [int(v.res.bois), int(v.res.pierre), int(v.res.parchemins), int(v.res.or), int(v.xp), _fermer()]
	if v.get("objectif"):
		var o: Dictionary = v.objectif
		out += "[color=accent]Goal: %s  %d/%d %s[/color]%s\n" % [_esc(o.texte), int(o.have), int(o.cible), "✔" if o.done else "", "" if compact else "  [url=retirer]remove[/url]"]
	elif compact:   # les objectifs se fixent depuis le Mac
		pass
	else:
		var sug = null
		for x in s.empire.get("suggestions", []):
			if x.id == v.id:
				sug = x
		if sug:
			out += "[color=succes]The Senate suggests: %s (%d %s)[/color]  [url=accepter]accept[/url]  [url=objectif]other…[/url]\n" % [_esc(sug.texte), int(sug.cible), _esc(RES_NAMES.get(sug.res, sug.res))]
		else:
			out += "[color=doux][url=objectif]Set a goal[/url][/color]\n"
	out += "\n"
	var ordered: Array = v.buildings.duplicate()
	ordered.sort_custom(func(a, b): return a.id == main.selected_building and b.id != main.selected_building)
	for b in ordered:
		var col := UI.hex(UI.SUCCES) if b.working else (UI.hex(UI.TEXTE_DOUX) if b.ruin else UI.hex(UI.OR))
		if b.id == main.selected_building:
			out += "[color=accent]▶ selected session%s[/color]\n" % ("" if compact else " · actions at the top right")
		out += "[color=%s]●[/color] [b]%s[/b]  [color=doux]%s lvl %d[/color]\n" % [col, _esc(String(b.title).left(34)), _esc(TYPE_NAMES.get(b.type, b.type)), int(b.level)]
		out += "[color=texte]%s %s · %s · %s ago · %d tools · %d commits · $%.2f[/color]\n" % [UNIT_NAMES.get(b.unit, "?"), _esc(b.model), _esc(b.armure), _ago(b.ago), int(b.res.pierre + b.res.bois + b.res.parchemins), int(b.commits), float(b.usd)]
		out += "[color=doux]%s[/color]\n" % _esc(b.state)
		if b.asked:
			out += "[color=info]You:[/color] %s\n" % _esc(String(b.asked).left(120))
		if b.said:
			out += "[color=accent]Claude:[/color] %s\n" % _esc(String(b.said).left(160))
		for sub in b.get("subs", []):
			out += "   [color=succes]↳ villager %s · %s[/color]\n" % [_esc(String(sub.title).left(30)), _esc(sub.tool if sub.working else "done")]
		out += "\n"
	panel_text.text = teinter(out)
