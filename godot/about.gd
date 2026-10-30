extends CanvasLayer
# Écran « About » (bouton des réglages, Mac et téléphone, et écran d'appairage) : nos principes, version et nouveautés,
# sécurité (dernière revue, empreinte du certificat de signature lue à l'exécution sur Android), liens, puis les pages
# « What leaves your device », politique de confidentialité, nouveautés et « Erase everything ».
# Les textes longs (CHANGELOG, PRIVACY, date de la revue, empreinte publiée) viennent de about_texts.gd, construit par
# tools/gen-about.mjs. Variable d'essai : AIMPIRE_APROPOS=about|leaves|privacy|changelog|erase ouvre la page au démarrage.

const TX := preload("res://about_texts.gd")
const UI := preload("res://ui_kit.gd")
const CONTACT := "mailto:contact@sidali.dev"
const DEPOT := "https://github.com/sidalidev/aimpire"
const MOT_EFFACER := "ERASE"
const MOIS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const PRINCIPES := [
	"Your data belongs to you.",
	"No account. No tracking. No ads.",
	"Nothing leaves your device unless you choose it.",
	"The code is open source, so anyone can check this.",
]
const PAGES := ["about", "leaves", "privacy", "changelog", "licenses", "erase"]

var main: Node
var page := ""              # page affichée, "" si fermé
var mobile := false
var _voile: ColorRect
var _cadre: PanelContainer
var _defile: ScrollContainer
var _col: VBoxContainer
var _http := HTTPRequest.new()
var _champ: LineEdit
var _bouton_effacer: Button
var _message: Label
var _empreinte := {}        # {"sha256", "lue"} : lue une fois, à la première ouverture
var _largeur := 560.0
var _dernier_retour_ms := -1000
var _marge_clavier: Control = null   # page Erase sur le téléphone : la hauteur du clavier virtuel sous le champ

# ---------------------------------------------------------------------------
# Fonctions pures (tests/test_about.gd)
# ---------------------------------------------------------------------------

# « 2026-10-24 » -> « 24 Oct 2026 » ; texte inchangé s'il n'a pas cette forme.
static func date_lisible(iso: String) -> String:
	var m := RegEx.create_from_string("^(\\d{4})-(\\d{2})-(\\d{2})$").search(iso.strip_edges())
	if m == null or int(m.get_string(2)) < 1 or int(m.get_string(2)) > 12:
		return iso
	return "%d %s %s" % [int(m.get_string(3)), MOIS[int(m.get_string(2)) - 1], m.get_string(1)]

# Empreinte SHA-256 en hexadécimal minuscule sans séparateurs, ou "" si ce n'en est pas une.
static func empreinte_normale(texte: String) -> String:
	var h := texte.strip_edges().to_lower().replace(":", "").replace(" ", "")
	return h if RegEx.create_from_string("^[0-9a-f]{64}$").search(h) != null else ""

# 8 premiers et 4 derniers caractères : « 79e37e06…9ea0 ».
static func empreinte_courte(texte: String) -> String:
	var h := empreinte_normale(texte)
	return "" if h == "" else h.left(8) + "…" + h.right(4)

# Données qui peuvent quitter l'appareil, par plateforme : [[titre, texte], …]. Mêmes faits que PRIVACY.md.
static func fuites(plateforme: String) -> Array:
	var maj := ["Update check", "At launch, then once a day, AImpire asks aimpire.sidali.dev over HTTPS whether a newer version exists. It sends nothing about you. The server sees your IP address. You can turn it off in Settings."]
	var relais_voit := "The relay sees: a random chain id, message sizes, times, and your IP address while connected. It never sees the content."
	if plateforme == "android":
		return [
			["Sync chain", "This phone reads the state of your Empire from the relay of its sync chain (aimpire.sidali.dev unless the Mac chose another) and sends it a few commands (claim, build, discreet mode), end-to-end encrypted. " + relais_voit],
			maj,
			["Nothing else", "No analytics, no crash reports, no ads. Settings and the chain key stay on this phone."],
		]
	return [
		["Your session logs", "Nowhere. The local server reads them on this Mac, read-only, and never sends them anywhere."],
		maj,
		["Sync chain (only if you create one)", "The state of your Empire goes to the relay you chose (aimpire.sidali.dev by default), end-to-end encrypted, every few seconds while AImpire runs. In discreet mode, names, paths and titles are removed before encryption. " + relais_voit],
		["Detailed voices (off by default)", "Only if you turn them on and set your own ElevenLabs key: the start of a session's latest request or reply (120 characters at most) goes to ElevenLabs over HTTPS, with your key, so a villager can say it. A sentence already spoken is cached on this Mac and not sent again."],
		["Nothing else", "No analytics, no crash reports, no ads. Notifications are shown by macOS on this Mac only."],
	]

# Third-party notices shown in the app: Godot Engine and its components (read from the engine itself), then Bun, which
# runs the local server inside the Mac app. Plain text, one block per component.
const BUN_LICENSE := """Bun (Mac app only: it runs the local server)
https://bun.sh

Bun itself is MIT-licensed.

MIT License

Copyright (c) Oven and Bun contributors

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Bun statically links JavaScriptCore and parts of WebKit (LGPL-2), and other libraries under their own licenses. The patched WebKit used by Bun is at https://github.com/oven-sh/webkit and the full list is at https://github.com/oven-sh/bun/blob/main/LICENSE.md"""

static func licences_tierces() -> String:
	var out := PackedStringArray()
	out.append("Godot Engine\nhttps://godotengine.org\n\n" + Engine.get_license_text().strip_edges())
	var composants := PackedStringArray()
	for c in Engine.get_copyright_info():
		var lignes := PackedStringArray()
		for part in c.get("parts", []):
			for cr in part.get("copyright", []):
				lignes.append("  © " + String(cr))
			lignes.append("  License: " + String(part.get("license", "")))
		composants.append(String(c.get("name", "")) + "\n" + "\n".join(lignes))
	out.append("Components of Godot Engine\n\n" + "\n\n".join(composants))
	var textes := Engine.get_license_info()
	for nom in textes:
		out.append("License: %s\n\n%s" % [nom, String(textes[nom]).strip_edges()])
	out.append(BUN_LICENSE)
	return "\n\n\n".join(out)

# Ce que « Erase everything » efface, par plateforme.
static func texte_effacement(plateforme: String) -> String:
	if plateforme == "android":
		return "This erases everything AImpire keeps on this phone: settings, the sync chain key and downloaded updates. This phone leaves the sync chain. The chain itself belongs to your Mac: delete it there to erase it from the relay right away, otherwise the relay erases it 30 days after the Mac stops publishing. AImpire then starts as on the first launch."
	return "This erases everything AImpire keeps on this Mac: the data folder (progress, saves, settings, voice cache, sync chain keys, your ElevenLabs key file), the game settings and the start at login. If you have a sync chain, the relay is asked to delete it and your phone stops seeing the Empire. Your session logs in ~/.claude are never touched. AImpire then quits and starts as on the first launch."

# Un dossier qu'on accepte de vider : absolu, propre à AImpire, ni la racine, ni le dossier personnel, ni ~/.claude.
static func peut_effacer(chemin: String, maison: String = "") -> bool:
	var c := chemin.strip_edges().simplify_path().trim_suffix("/")
	if c.length() < 8 or not c.is_absolute_path() or c.contains(".."):
		return false
	if not c.to_lower().contains("aimpire"):
		return false
	if c.contains("/.claude") or c.ends_with("/.claude"):
		return false
	var m := maison.strip_edges().simplify_path().trim_suffix("/")
	if m != "" and (c == m or m.begins_with(c + "/")):
		return false
	return true

# Vide un dossier (fichiers et sous-dossiers), sans suivre les liens symboliques. Renvoie le nombre d'éléments effacés.
static func vider_dossier(chemin: String) -> int:
	var d := DirAccess.open(chemin)
	if d == null:
		return 0
	d.include_hidden = true
	var n := 0
	for nom in d.get_directories():
		var sous := chemin.path_join(nom)
		if d.is_link(nom):
			if DirAccess.remove_absolute(sous) == OK:
				n += 1
			continue
		n += vider_dossier(sous)
		if DirAccess.remove_absolute(sous) == OK:
			n += 1
	for nom in d.get_files():
		if DirAccess.remove_absolute(chemin.path_join(nom)) == OK:
			n += 1
	return n

# Markdown très simple vers BBCode : titres, puces, gras, code, crochets échappés.
static func markdown_bbcode(md: String) -> String:
	var out := PackedStringArray()
	var gras := RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	var suite := false   # la ligne précédente est un paragraphe ou une puce qu'une ligne repliée peut prolonger
	for ligne in md.replace("\r", "").split("\n"):
		var l := ligne.replace("[", "[lb]").replace("`", "")
		l = gras.sub(l, "[b]$1[/b]", true)
		if l.begins_with("# "):
			suite = false
			continue   # le titre du document est celui de la page
		if l.begins_with("## ") or l.begins_with("### "):
			out.append("[b]" + l.substr(l.find(" ") + 1).strip_edges() + "[/b]")
			suite = false
		elif l.begins_with("- "):
			out.append("  •  " + l.substr(2))
			suite = true
		elif l.strip_edges() == "":
			out.append("")
			suite = false
		elif suite and out.size():
			out[out.size() - 1] += " " + l.strip_edges()   # ligne repliée dans le fichier : même paragraphe
		else:
			out.append(l.strip_edges())
			suite = true
	return "\n".join(out).strip_edges()

# Premier certificat (X.509 DER) du bloc de signature APK v3 ou v2, ou vide. `lire(position, longueur)` renvoie des
# octets du fichier, `taille` sa longueur : on ne lit que la fin du répertoire central (EOCD) puis le bloc
# « APK Sig Block 42 » juste avant le répertoire central.
static func certificat_apk(lire: Callable, taille: int) -> PackedByteArray:
	if taille < 22:
		return PackedByteArray()
	var eocd := -1
	var queue := PackedByteArray()
	for queue_lg in [22, mini(taille, 65557)]:   # d'abord sans commentaire d'archive, le cas courant
		queue = lire.call(taille - queue_lg, queue_lg)
		if queue.size() != queue_lg:
			return PackedByteArray()
		for i in range(queue_lg - 22, -1, -1):
			if queue.decode_u32(i) == 0x06054b50:
				eocd = i
				break
		if eocd >= 0:
			break
	if eocd < 0:
		return PackedByteArray()
	var debut_rc := queue.decode_u32(eocd + 16)
	if debut_rc < 32 or debut_rc > taille:
		return PackedByteArray()
	var pied: PackedByteArray = lire.call(debut_rc - 24, 24)
	if pied.size() != 24 or pied.slice(8).get_string_from_ascii() != "APK Sig Block 42":
		return PackedByteArray()
	var taille_bloc := pied.decode_u64(0)
	if taille_bloc < 24 or taille_bloc > debut_rc - 8 or taille_bloc > 16 * 1024 * 1024:
		return PackedByteArray()
	var bloc: PackedByteArray = lire.call(debut_rc - taille_bloc - 8, taille_bloc + 8)
	if bloc.size() != taille_bloc + 8:
		return PackedByteArray()
	var paires := {}
	var i := 8
	var fin := bloc.size() - 24
	while i + 12 <= fin:
		var lg := bloc.decode_u64(i)
		if lg < 4 or i + 8 + lg > fin:
			break
		paires[bloc.decode_u32(i + 8)] = bloc.slice(i + 12, i + 8 + lg)
		i += 8 + lg
	for id in [0xf05368c0, 0x7109871a]:   # v3, puis v2
		if paires.has(id):
			var c := _premier_certificat(paires[id])
			if not c.is_empty():
				return c
	return PackedByteArray()

# Le même, pour un fichier lisible avec FileAccess (tests sur le Mac).
static func certificat_fichier(chemin: String) -> PackedByteArray:
	var f := FileAccess.open(chemin, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var lire := func(pos: int, lg: int) -> PackedByteArray:
		f.seek(pos)
		return f.get_buffer(lg)
	return certificat_apk(lire, f.get_length())

# Signataires (suite préfixée) > premier signataire > données signées > condensés, puis certificats > premier certificat.
static func _premier_certificat(v: PackedByteArray) -> PackedByteArray:
	var signataires := _prefixe(v, 0)
	var signataire := _prefixe(signataires, 0)
	var donnees := _prefixe(signataire, 0)
	var condenses := _prefixe(donnees, 0)
	if donnees.size() < condenses.size() + 8:
		return PackedByteArray()
	var certificats := _prefixe(donnees, 4 + condenses.size())
	return _prefixe(certificats, 0)

# Valeur préfixée par sa longueur (uint32, petit-boutiste) à la position `pos`, ou vide si elle déborde.
static func _prefixe(o: PackedByteArray, pos: int) -> PackedByteArray:
	if pos + 4 > o.size():
		return PackedByteArray()
	var lg := o.decode_u32(pos)
	if pos + 4 + lg > o.size():
		return PackedByteArray()
	return o.slice(pos + 4, pos + 4 + lg)

static func sha256_hex(o: PackedByteArray) -> String:
	if o.is_empty():
		return ""
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(o)
	return h.finish().hex_encode()

# Empreinte du certificat qui a signé l'APK installé : lue dans le bloc de signature de l'APK (le fichier de l'app,
# lu par java.nio : FileAccess de Godot n'ouvre pas /data/app), puis confirmée par Android
# (PackageManager.hasSigningCertificate, Android 9 et plus). "" si l'une des deux étapes échoue.
static func empreinte_android() -> String:
	if OS.get_name() != "Android" or not Engine.has_singleton("AndroidRuntime"):
		return ""
	var ctx = Engine.get_singleton("AndroidRuntime").getApplicationContext()
	if ctx == null:
		return ""
	var chemin = JavaClassWrapper.wrap("java.nio.file.Path").of(String(ctx.getPackageCodePath()), PackedStringArray())
	var canal = JavaClassWrapper.wrap("java.nio.file.Files").newByteChannel(chemin, []) if chemin else null
	if canal == null:
		return ""
	var tampons := JavaClassWrapper.wrap("java.nio.ByteBuffer")
	var lire := func(pos: int, lg: int) -> PackedByteArray:
		var t = tampons.allocate(lg)
		canal.position(pos)
		var lu := 0
		while lu < lg:
			var n := int(canal.read(t))
			if n <= 0:
				break
			lu += n
		if lu != lg or lg < 8:
			return PackedByteArray()
		# array() revient comme objet Java opaque : on relit le tampon 8 octets à la fois (getLong, gros-boutiste).
		var out := PackedByteArray()
		out.resize(lg)
		var mot := PackedByteArray()
		mot.resize(8)
		for i in range(0, lg, 8):
			var j := mini(i, lg - 8)
			mot.encode_s64(0, int(t.getLong(j)))
			for k in 8:
				out[j + k] = mot[7 - k]
		return out
	var cert := certificat_apk(lire, int(canal.size()))
	canal.close()
	if cert.is_empty():
		return ""
	var empreinte := sha256_hex(cert)
	var pm = ctx.getPackageManager()
	if pm == null or not bool(pm.hasSigningCertificate(String(ctx.getPackageName()), empreinte.hex_decode(), 1)):   # CERT_INPUT_SHA256
		return ""
	return empreinte

# ---------------------------------------------------------------------------
# Nœud
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 6
	mobile = main != null and main.get("mobile") != null
	_voile = ColorRect.new()
	_voile.color = UI.VOILE
	_voile.set_anchors_preset(Control.PRESET_FULL_RECT)
	_voile.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_voile)
	_cadre = PanelContainer.new()
	if main:
		_cadre.theme = main.ui.theme
	var fond := StyleBoxFlat.new()
	fond.bg_color = UI.FOND   # opaque : rien de l'écran du dessous ne transparaît
	fond.set_corner_radius_all(int(UI.RAYON_FEUILLE) if mobile else int(UI.RAYON_CARTE))
	fond.set_content_margin_all(16 if mobile else 22)
	_cadre.add_theme_stylebox_override("panel", fond)
	_largeur = 560.0
	_cadre.anchor_left = 0.5
	_cadre.anchor_right = 0.5
	_cadre.anchor_bottom = 1.0
	_cadre.offset_left = -_largeur / 2.0
	_cadre.offset_right = _largeur / 2.0
	_cadre.offset_top = 40
	_cadre.offset_bottom = -40
	add_child(_cadre)
	_defile = ScrollContainer.new()
	_defile.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_defile.scroll_deadzone = 8
	_cadre.add_child(_defile)
	_col = VBoxContainer.new()
	_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col.add_theme_constant_override("separation", 10)
	_defile.add_child(_col)
	_http.timeout = 15.0
	add_child(_http)
	visible = false
	if mobile:   # rotation, fenêtre partagée : la page ouverte reprend la largeur de l'écran
		get_viewport().size_changed.connect(func():
			if visible:
				_mise_en_page()
				_construire())
	var demande := OS.get_environment("AIMPIRE_APROPOS")
	if demande in PAGES:
		open.call_deferred(demande)

func _plateforme() -> String:
	return "android" if OS.get_name() == "Android" else "mac"

func open(nom := "about") -> void:
	page = nom if nom in PAGES else "about"
	visible = true
	_mise_en_page()
	_construire()

# Téléphone : la page prend la largeur de l'écran entre les marges (zone sûre comprise), 640 dp au plus, du haut (T) au
# bas (B). Mac : 560 de large, 40 du haut et du bas, comme avant.
func _mise_en_page() -> void:
	if not mobile or _cadre == null:
		return
	var vue := _cadre.get_viewport_rect().size
	var t := 12.0
	var b := 12.0
	var l := 12.0
	var r := 12.0
	var ui = main.mobile.get("ui") if main else null
	if ui:
		t = ui.T
		b = ui.B
		l = ui.L
		r = ui.R
	_largeur = minf(640.0, vue.x - l - r)
	var gauche := maxf(l, floorf((vue.x - _largeur) / 2.0))
	_cadre.anchor_left = 0.0
	_cadre.anchor_right = 0.0
	_cadre.offset_left = gauche
	_cadre.offset_right = gauche + _largeur
	_cadre.offset_top = t
	_cadre.offset_bottom = -b

func close() -> void:
	page = ""
	visible = false
	_vider()

# Retour (Échap, geste retour d'Android) : une sous-page revient à About, About se ferme. false si rien n'était ouvert.
func retour() -> bool:
	if not visible:
		return false
	# Sur Android, un seul geste retour peut arriver deux fois (notification et touche) : on ne recule qu'une page.
	var t := Time.get_ticks_msec()
	if t - _dernier_retour_ms < 300:
		return true
	_dernier_retour_ms = t
	if page != "about":
		open("about")
	else:
		close()
	return true

func _vider() -> void:
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	_champ = null
	_bouton_effacer = null
	_message = null
	_marge_clavier = null

func _construire() -> void:
	_vider()
	_defile.scroll_vertical = 0
	match page:
		"leaves":
			_page_fuites()
		"privacy":
			_page_texte("Privacy policy", TX.PRIVACY)
		"changelog":
			_page_texte("What's new", TX.CHANGELOG)
		"licenses":
			_page_licences()
		"erase":
			_page_effacer()
		_:
			_page_about()

# --- Éléments ---

func _titre(texte: String) -> Label:
	var l := Label.new()
	l.text = texte
	if main:
		l.add_theme_font_override("font", main.ui.big_title_font)
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", UI.TEXTE)
	_replier(l)
	_col.add_child(l)
	return l

# Téléphone étroit (360 dp) : un titre ne doit pas élargir la colonne au-delà de l'écran.
func _replier(l: Label) -> void:
	if mobile:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = _largeur_texte()

func _intertitre(texte: String) -> Label:
	var l := Label.new()
	l.text = texte
	if main:
		l.add_theme_font_override("font", main.ui.title_font)
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", UI.ACCENT_TEXTE)
	_replier(l)
	_col.add_child(l)
	return l

func _texte(texte: String, doux := false, parent: Control = null) -> Label:
	var l := Label.new()
	l.text = texte
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = _largeur_texte()   # largeur fixe : un texte replié mesuré à 0 px gonflerait le panneau
	l.add_theme_font_size_override("font_size", 16 if mobile else 15)
	if doux:
		l.add_theme_color_override("font_color", UI.TEXTE_DOUX)
	(parent if parent else _col).add_child(l)
	return l

# Largeur des textes : le cadre moins ses marges intérieures (et la barre de défilement sur le Mac).
func _largeur_texte() -> float:
	return _largeur - (40.0 if mobile else 64.0)

func _style(couleur: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = couleur
	s.set_corner_radius_all(int(UI.RAYON_BOUTON))
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

# Bouton du jeu (teinté, ou rouge pour « danger »), à plat, rayon 14 : enfoncé tout de suite, petit ressort au toucher.
func _bouton(texte: String, action: Callable, danger := false, parent: Control = null) -> Button:
	var b := Button.new()
	b.text = texte
	b.custom_minimum_size.y = 48 if mobile else 36
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_size_override("font_size", 16 if mobile else 15)
	var normal := UI.DANGER if danger else UI.TEINTE
	var presse := UI.DANGER_PRESSE if danger else UI.TEINTE.darkened(0.08)
	var survol := UI.DANGER.lightened(0.06) if danger else UI.TEINTE.darkened(0.04)
	b.add_theme_stylebox_override("normal", _style(normal))
	b.add_theme_stylebox_override("hover", _style(survol))
	b.add_theme_stylebox_override("pressed", _style(presse))
	b.add_theme_stylebox_override("hover_pressed", _style(presse))
	b.add_theme_stylebox_override("disabled", _style(Color(normal, 0.45)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var texte_c := UI.CREME if danger else UI.TEINTE_TEXTE
	for etat in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(etat, texte_c)
	b.add_theme_color_override("font_disabled_color", Color(texte_c, 0.5))
	if mobile:
		b.focus_mode = Control.FOCUS_NONE
	b.resized.connect(func(): b.pivot_offset = b.size / 2.0)
	b.button_down.connect(func(): _ressort(b, 0.97))
	b.button_up.connect(func(): _ressort(b, 1.0))
	b.pressed.connect(action)
	(parent if parent else _col).add_child(b)
	return b

func _ressort(b: Button, echelle: float) -> void:
	if not is_instance_valid(b):
		return
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2.ONE * echelle, 0.22).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)

# Rangée de boutons : sur le téléphone elle passe à la ligne si l'écran est étroit.
func _ligne() -> Container:
	var h: Container = HFlowContainer.new() if mobile else HBoxContainer.new()
	h.add_theme_constant_override("h_separation" if mobile else "separation", 10)
	if mobile:
		h.add_theme_constant_override("v_separation", 10)
	_col.add_child(h)
	return h

func _espace(h := 6) -> void:
	var c := Control.new()
	c.custom_minimum_size.y = h
	_col.add_child(c)

func _fermer_ou_retour(principal: bool) -> void:
	_espace(4)
	if principal:
		_bouton("Close", close)
	else:
		_bouton("Back", func(): open("about"))

# --- Pages ---

func _page_about() -> void:
	_titre("About AImpire")
	_intertitre("Our principles")
	for p in PRINCIPES:
		_texte(p)
	_bouton("What leaves your device", func(): open("leaves"))
	_espace()
	_intertitre("Version")
	var v := _ligne()
	var lv := Label.new()
	lv.text = "Version %s" % String(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	lv.add_theme_font_size_override("font_size", 16 if mobile else 15)
	v.add_child(lv)
	_bouton("What's new", func(): open("changelog"), false, v)
	_espace()
	_intertitre("Security")
	_texte("Last security review: %s" % date_lisible(TX.SECURITY_REVIEW))
	_texte("Internal review. No external audit yet.", true)
	if _plateforme() == "android":
		_ligne_empreinte()
	_bouton("Report a security issue", func(): OS.shell_open(CONTACT + "?subject=AImpire%20security"))
	_espace()
	_intertitre("Links")
	var liens := _ligne()
	_bouton("Privacy policy", func(): open("privacy"), false, liens)
	_bouton("Source code", func(): OS.shell_open(DEPOT), false, liens)
	_bouton("Third-party licenses", func(): open("licenses"), false, liens)
	_bouton("Contact", func(): OS.shell_open(CONTACT), false, liens)
	_espace()
	_bouton("Erase everything", func(): open("erase"), true)
	_espace()
	var pied := _texte("Made by Sid · sidali.dev", true)
	pied.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var code := _texte("Open source: the app under the MIT license, the relay under AGPL-3.0. Community project, not affiliated with Anthropic.", true)
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fermer_ou_retour(true)

# Android : empreinte lue dans l'APK installé, comparée à celle publiée dans SECURITY.md.
func _ligne_empreinte() -> void:
	if _empreinte.is_empty():
		var lue := empreinte_android()
		_empreinte = {"sha256": lue if lue != "" else TX.SIGNING_SHA256_ANDROID, "lue": lue != ""}
	var publiee: String = TX.SIGNING_SHA256_ANDROID
	_texte("Signing certificate: %s" % empreinte_courte(_empreinte.sha256))
	if not _empreinte.lue:
		_texte("Published value from SECURITY.md. It could not be read from this install.", true)
	elif _empreinte.sha256 != publiee:
		var l := _texte("This does not match the fingerprint in SECURITY.md (%s). Do not trust this install." % empreinte_courte(publiee))
		l.add_theme_color_override("font_color", UI.DANGER_TEXTE)
	else:
		_texte("Read from this install. Matches SECURITY.md.", true)

func _page_fuites() -> void:
	_titre("What leaves your device")
	for f in fuites(_plateforme()):
		_intertitre(String(f[0]))
		_texte(String(f[1]))
	_fermer_ou_retour(false)

func _page_texte(titre: String, md: String) -> void:
	_titre(titre)
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.selection_enabled = not mobile
	r.mouse_filter = Control.MOUSE_FILTER_PASS   # le doigt qui glisse dessus fait défiler la page
	r.custom_minimum_size.x = _largeur_texte()
	r.add_theme_font_size_override("normal_font_size", 16 if mobile else 14)
	r.add_theme_font_size_override("bold_font_size", 17 if mobile else 15)
	r.add_theme_color_override("default_color", UI.TEXTE)
	r.text = markdown_bbcode(md)
	_col.add_child(r)
	_fermer_ou_retour(false)

# Godot and Bun notices, as plain text (no BBCode: license texts hold brackets).
func _page_licences() -> void:
	_titre("Third-party licenses")
	_texte("AImpire is built with Godot Engine and, on the Mac, Bun. Their licenses ask that these notices travel with the app.", true)
	var r := RichTextLabel.new()
	r.bbcode_enabled = false
	r.fit_content = true
	r.scroll_active = false
	r.selection_enabled = not mobile
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.custom_minimum_size.x = _largeur_texte()
	r.add_theme_font_size_override("normal_font_size", 13 if mobile else 12)
	r.add_theme_color_override("default_color", UI.TEXTE)
	r.text = licences_tierces()
	_col.add_child(r)
	_fermer_ou_retour(false)

func _page_effacer() -> void:
	_titre("Erase everything")
	_texte(texte_effacement(_plateforme()))
	_texte("This cannot be undone. Type %s to confirm." % MOT_EFFACER)
	_champ = LineEdit.new()
	_champ.placeholder_text = MOT_EFFACER
	_champ.custom_minimum_size = Vector2(220, 48 if mobile else 36)
	_champ.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_champ.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	_champ.text_changed.connect(func(_t): _maj_confirmation())
	_champ.text_submitted.connect(func(_t): if _confirme(): _effacer())
	if mobile:
		_champ.add_theme_font_size_override("font_size", 16)
		_champ.focus_entered.connect(_montrer_champ)
	_col.add_child(_champ)
	var h := _ligne()
	_bouton_effacer = _bouton("Erase everything", _effacer, true, h)
	_bouton("Cancel", func(): open("about"), false, h)
	_message = _texte("", true)
	_message.visible = false
	_maj_confirmation()
	_marge_clavier = Control.new()
	_col.add_child(_marge_clavier)

# Téléphone : le clavier virtuel ne cache pas le champ ERASE (marge de sa hauteur sous la page, puis défilement).
func _montrer_champ() -> void:
	await get_tree().create_timer(0.4).timeout
	if _marge_clavier == null or _champ == null or main == null or main.get("mobile") == null:
		return
	var m = main.mobile
	_marge_clavier.custom_minimum_size.y = maxf(0.0, m.hauteur_clavier() - (m.ui.B if m.ui else 0.0))
	await get_tree().process_frame
	if _champ:
		_defile.ensure_control_visible(_champ)

func _confirme() -> bool:
	return _champ != null and _champ.text.strip_edges() == MOT_EFFACER

func _maj_confirmation() -> void:
	if _bouton_effacer:
		_bouton_effacer.disabled = not _confirme()

func _dire(texte: String, erreur := false) -> void:
	if _message == null:
		return
	_message.text = texte
	_message.visible = true
	if erreur:
		_message.add_theme_color_override("font_color", UI.DANGER_TEXTE)
	else:
		_message.remove_theme_color_override("font_color")

# --- Effacement ---

func _effacer() -> void:
	if not _confirme():
		return
	_bouton_effacer.disabled = true
	_champ.editable = false
	if _plateforme() == "android" or main == null or main.get("mobile") != null:
		_effacer_local()
		return
	# Mac : le serveur local efface son dossier de données (et la chaîne sur le relais), puis s'arrête.
	_dire("Erasing…")
	if _http.request_completed.is_connected(_sur_effacement):
		_http.request_completed.disconnect(_sur_effacement)
	_http.request_completed.connect(_sur_effacement, CONNECT_ONE_SHOT)
	if _http.request(main.net.url("/effacer"), main.net.headers(), HTTPClient.METHOD_POST) != OK:
		_sur_effacement(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())

func _sur_effacement(_r: int, code: int, _h: PackedStringArray, _corps: PackedByteArray) -> void:
	if code != 200:
		_dire("The local server could not erase its data (%s). Nothing was erased. Try again once AImpire is running normally." % ("unreachable" if code == 0 else "HTTP %d" % code), true)
		_champ.editable = true
		_maj_confirmation()
		return
	_effacer_local()

# Données du jeu lui-même (user://) : réglages, chaîne du téléphone, mises à jour téléchargées, journaux du moteur.
func _effacer_local() -> void:
	if main and main.settings and OS.get_name() == "macOS" and main.settings._autostart_installed():
		main.settings._set_autostart(false)
	var dossier := OS.get_user_data_dir()
	if peut_effacer(dossier, OS.get_environment("HOME")):
		vider_dossier(dossier)
	if _plateforme() == "android" or (main and main.get("mobile") != null):
		get_tree().reload_current_scene()   # comme au premier lancement : écran d'appairage
	else:
		get_tree().quit()
