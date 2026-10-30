extends Node
# Réglages du joueur (Échap) : volumes, voix, mises à jour, qualité graphique. Sauvegardés dans user://reglages.cfg.
# Interface en anglais seulement (la clé « langue » des anciens réglages est ignorée).
# Sur le téléphone, la colonne est logée dans la feuille Settings (docs/MOBILE-PORTRAIT.md §3.6) : mode discret en tête,
# fluidité, qualité en boutons radio, rendu, sons, voix, mises à jour, section Phone, About ; contrôles segmentés au lieu
# des menus déroulants, textes repliés, cibles de 48 dp, pas de bouton Fermer (la feuille a son « x »).

const UI := preload("res://ui_kit.gd")

var main: Node
var data := {"musique": 1.0, "voix": 1.0, "effets": 1.0, "voix_on": true, "voix_detaillees": false, "qualite": "auto", "maj_auto": true}
var menu: PanelContainer
var sync_panel: Control = null   # section « Chaîne de sync » (sync_panel.gd), sur le Mac seulement
var _layer: CanvasLayer

const T := {"titre": "Settings", "musique": "Music", "voix": "Villager voices", "effets": "Effects", "voix_on": "Villagers speak", "voix_detaillees": "Detailed voices (sends the sentence to ElevenLabs)", "autostart": "Start as overlay at login", "maj_auto": "Check for updates (at launch, then daily)", "qualite": "Quality", "apropos": "About AImpire", "fermer": "Esc to close"}
const QUALITY_KEYS := ["auto", "haute", "equilibree", "performance", "minimale"]

func load_saved() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://reglages.cfg") == OK:
		for k in data.keys():
			data[k] = cfg.get_value("jeu", k, data[k])
	apply()

func save() -> void:
	var cfg := ConfigFile.new()
	for k in data.keys():
		cfg.set_value("jeu", k, data[k])
	cfg.save("user://reglages.cfg")

func apply() -> void:
	for bus in ["Musique", "Voix", "Effets"]:
		var i := AudioServer.get_bus_index(bus)
		if i < 0:
			continue
		var lin: float = data[bus.to_lower()]
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(lin, 0.0001)))
		AudioServer.set_bus_mute(i, lin <= 0.001)
	var fixed := {"haute": 0, "equilibree": 1, "performance": 2, "minimale": 3}
	if fixed.has(data.qualite):
		main.world.apply_quality(fixed[data.qualite])

func toggle() -> void:
	menu.visible = not menu.visible

func build_menu(layer: CanvasLayer) -> void:
	_layer = layer
	if main.mobile:
		_construire_telephone(layer)
		return
	menu = PanelContainer.new()
	menu.theme = main.ui.theme
	var box := StyleBoxFlat.new()
	box.bg_color = UI.FOND
	box.set_corner_radius_all(int(UI.RAYON_CARTE))
	box.set_content_margin_all(24)
	menu.add_theme_stylebox_override("panel", box)
	menu.position = Vector2(440, 160)
	menu.custom_minimum_size = Vector2(400, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	var cols: HBoxContainer = null   # Mac : réglages à gauche, chaîne de sync à droite
	if main.mobile:   # téléphone : menu centré qui défile (écran bas en paysage)
		main.mobile.habiller_menu(menu, col)
	else:
		cols = HBoxContainer.new()
		cols.add_theme_constant_override("separation", 22)
		col.custom_minimum_size = Vector2(380, 0)
		cols.add_child(col)
		menu.add_child(cols)
	var tr: Dictionary = T
	var title := Label.new()
	title.text = tr.titre
	title.add_theme_font_override("font", main.ui.big_title_font)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", UI.TEXTE)
	col.add_child(title)
	for key in ["musique", "voix", "effets"]:
		var lab := Label.new()
		lab.text = tr[key]
		col.add_child(lab)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.5
		sl.step = 0.05
		sl.value = data[key]
		sl.value_changed.connect(func(val): data[key] = val; apply(); save())
		col.add_child(sl)
	for key in ["voix_on", "voix_detaillees"]:
		var cb := CheckBox.new()
		cb.text = tr[key]
		cb.button_pressed = data[key]
		cb.toggled.connect(func(on): data[key] = on; save())
		col.add_child(cb)
	if OS.get_name() == "macOS" and OS.has_feature("template"):   # seulement depuis l'app exportée
		var auto := CheckBox.new()
		auto.text = tr.autostart
		auto.button_pressed = _autostart_installed()
		auto.toggled.connect(func(on): _set_autostart(on))
		col.add_child(auto)
	var maj_cb := CheckBox.new()
	maj_cb.text = tr.maj_auto
	maj_cb.button_pressed = bool(data.maj_auto)
	maj_cb.toggled.connect(func(on):
		data.maj_auto = on
		save()
		if main.maj:
			main.maj.set_active(on))
	col.add_child(maj_cb)
	if main.maj:   # caché tant qu'aucune version plus récente n'est connue
		var maj_bouton: Button = main.maj.creer_bouton(16 if main.mobile else 14)
		maj_bouton.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		col.add_child(maj_bouton)
	var qrow := HBoxContainer.new()
	var ql := Label.new()
	ql.text = tr.qualite + " "
	qrow.add_child(ql)
	var qopt := OptionButton.new()
	for k in ["Auto (100 FPS min.)", "High", "Balanced", "Performance", "Minimal (no shadows)"]:
		qopt.add_item(k)
	qopt.selected = maxi(0, QUALITY_KEYS.find(data.qualite))
	qopt.item_selected.connect(func(i):
		data.qualite = QUALITY_KEYS[i]
		save()
		if i > 0:
			main.world.apply_quality(i - 1))
	qrow.add_child(qopt)
	col.add_child(qrow)
	var apropos := Button.new()
	apropos.text = tr.apropos
	apropos.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if main.mobile:
		apropos.custom_minimum_size.y = 48
	apropos.pressed.connect(func(): main.about.open())
	col.add_child(apropos)
	if main.mobile:   # images par seconde, chaîne de sync, « Oublier cette chaîne », bouton Fermer
		main.mobile.ajoute_reglages(col)
	else:
		var hint := Label.new()
		hint.text = tr.fermer
		hint.add_theme_color_override("font_color", UI.TEXTE_DOUX)
		col.add_child(hint)
	if cols:   # la chaîne se crée sur le Mac, qui a le serveur local
		cols.add_child(VSeparator.new())
		sync_panel = preload("res://sync_panel.gd").new()
		sync_panel.main = main
		cols.add_child(sync_panel)
	menu.visible = OS.get_environment("AIMPIRE_REGLAGES") != ""   # ouvert au démarrage (captures)
	layer.add_child(menu)
	if cols:   # centré, et réduit à son contenu quand la section de sync change (QR affiché ou retiré)
		menu.minimum_size_changed.connect(_centrer_menu, CONNECT_DEFERRED)
		menu.get_viewport().size_changed.connect(_centrer_menu)
		_centrer_menu.call_deferred()

const QUALITY_LABELS := ["Auto", "High", "Balanced", "Performance", "Minimal (no shadows)"]

func _construire_telephone(layer: CanvasLayer) -> void:
	var ui = main.ui
	var tr: Dictionary = T
	menu = PanelContainer.new()
	menu.theme = ui.theme
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.theme = ui.theme
	main.mobile.reglage_discret(col)
	main.mobile.reglage_fluidite(col)
	col.add_child(ui.texte(tr.qualite))
	col.add_child(ui.choix_radio(QUALITY_LABELS, maxi(0, QUALITY_KEYS.find(data.qualite)), func(k):
		data.qualite = QUALITY_KEYS[k]
		save()
		if k > 0:
			main.world.apply_quality(k - 1)))
	main.mobile.reglage_moteur(col)
	for key in ["musique", "voix", "effets"]:
		col.add_child(ui.texte(tr[key]))
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.5
		sl.step = 0.05
		sl.value = data[key]
		UI.habiller_curseur(sl)
		sl.value_changed.connect(func(val): data[key] = val; apply(); save())
		col.add_child(sl)
	for key in ["voix_on", "voix_detaillees", "maj_auto"]:
		var cle: String = key
		col.add_child(ui.interrupteur(tr[key], bool(data[key]), func(on):
			data[cle] = on
			save()
			if cle == "maj_auto" and main.maj:
				main.maj.set_active(on)))
	if main.maj:   # caché tant qu'aucune version plus récente n'est connue
		var maj_bouton: Button = main.maj.creer_bouton(16)
		maj_bouton.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		maj_bouton.custom_minimum_size.y = UI.CIBLE
		col.add_child(maj_bouton)
	main.mobile.ajoute_reglages(col)
	var apropos: Button = ui.bouton(tr.apropos)
	apropos.pressed.connect(func(): main.about.open())
	col.add_child(apropos)
	menu.add_child(col)
	menu.visible = false
	layer.add_child(menu)
	main.mobile.habiller_menu(menu, col)

func _centrer_menu() -> void:
	if not is_instance_valid(menu) or not menu.is_inside_tree():
		return
	menu.reset_size()
	menu.position = ((menu.get_viewport_rect().size - menu.size) / 2.0).floor()

# Lancement à l'ouverture de session (macOS) : un LaunchAgent qui ouvre l'app en incrustation. Opt-in, retirable ici même.
const AGENT_ID := "dev.sidali.aimpire"

func _agent_path() -> String:
	return OS.get_environment("HOME") + "/Library/LaunchAgents/" + AGENT_ID + ".plist"

func _autostart_installed() -> bool:
	return FileAccess.file_exists(_agent_path())

func _set_autostart(on: bool) -> void:
	var path := _agent_path()
	var uid := []
	OS.execute("id", ["-u"], uid)
	var domain := "gui/" + String(uid[0]).strip_edges() if uid.size() else "gui/501"
	if on:
		var app := OS.get_executable_path().get_base_dir().path_join("../..").simplify_path()
		var plist := """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>%s</string>
<key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-a</string><string>%s</string><string>--args</string><string>--pip</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
""" % [AGENT_ID, app]
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string(plist)
			f.close()
			OS.execute("launchctl", ["bootstrap", domain, path])
	else:
		OS.execute("launchctl", ["bootout", domain + "/" + AGENT_ID])
		DirAccess.remove_absolute(path)
