extends VBoxContainer
# Section « Chaîne de sync » du menu des réglages (Échap), côté Mac (docs/SYNC.md §5) : créer ou supprimer la chaîne,
# QR code du lien, lien copiable, 12 mots numérotés, état de la publication. Tout passe par GET /sync et POST /sync du
# serveur local (jeton local exigé : ces routes révèlent le secret de la chaîne).
# Le secret (QR, lien, mots) est caché par défaut derrière « Afficher le secret », se recache seul au bout de 60 s ou à la
# fermeture du menu, et n'est jamais servi en mode discret (partage d'écran, visio). Le lien copié est effacé du
# presse-papiers au bout de 30 s (presse-papiers universel, historiques).

const UI := preload("res://ui_kit.gd")
const SC := preload("res://sync_crypto.gd")

var main: Node

var _get := HTTPRequest.new()
var _post := HTTPRequest.new()
var _minuteur := Timer.new()
var _etat: Dictionary = {}
var _lien_qr := ""

var _statut := Label.new()
var _creer := Button.new()
var _relais := VBoxContainer.new()   # « Relay address » field, shown while there is no chain
var _champ_relais := LineEdit.new()
var _detail := VBoxContainer.new()
var _qr := TextureRect.new()
var _id := Label.new()
var _lien := LineEdit.new()
var _copier := Button.new()
var _mots := GridContainer.new()
var _envoi := Label.new()
var _supprimer := Button.new()
var _secret := VBoxContainer.new()   # QR, lien et mots : caché par défaut
var _afficher := Button.new()
var _masque := Label.new()
var _secret_jusqua := 0              # ticks : au-delà, le secret se recache
var _copie_jusqua := 0               # ticks : au-delà, le lien copié est retiré du presse-papiers

const SECRET_MS := 60000
const PRESSE_PAPIERS_MS := 30000
var _confirmation := ConfirmationDialog.new()

const LARGEUR := 420.0

const T := {
	"titre": "Sync chain",
	"intro": "Watch the Empire from your phone. The relay only sees encrypted data.",
	"creer": "Create a sync chain",
	"relais": "Relay address",
	"relais_aide": "The official relay is run by the author, without guarantee. You can host your own (relay/ folder).",
	"relais_invalide": "Invalid relay address: use https:// (http:// only on this machine).",
	"aucune": "No chain yet.",
	"lien": "Link to open in the phone app:",
	"copier": "Copy",
	"copie": "Copied",
	"mots": "Or these 12 words, in order:",
	"id": "Chain %s · relay %s",
	"jamais": "Not published to the relay yet.",
	"envoi": "Last sent %s ago, %s",
	"commandes": " · %d command(s) from the phone",
	"supprimer": "Delete the chain",
	"confirmer": "Delete the chain? The phone will no longer see the Empire and the published state will be erased from the relay. You will need to create a new one and pair again.",
	"oui": "Delete",
	"non": "Cancel",
	"injoignable": "Local server unreachable.",
	"secret": "Keep this QR code, link and words to yourself: they give access to the Empire.",
	"attente": "One moment…",
	"afficher": "Show the secret (QR, link, 12 words)",
	"cacher": "Hide the secret",
	"masque": "Secret hidden in discreet mode (H to turn it off).",
}

func _t(cle: String) -> String:
	return String(T.get(cle, cle))

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	custom_minimum_size = Vector2(LARGEUR, 0)
	var titre := Label.new()
	titre.text = _t("titre")
	if main and main.ui:
		titre.add_theme_font_override("font", main.ui.title_font)
	titre.add_theme_font_size_override("font_size", 22)
	titre.add_theme_color_override("font_color", UI.TEXTE)
	add_child(titre)
	var intro := Label.new()
	intro.text = _t("intro")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(LARGEUR, 0)   # largeur fixe : un texte replié mesuré à 0 px gonflerait le menu
	intro.add_theme_font_size_override("font_size", 13)
	intro.add_theme_color_override("font_color", UI.TEXTE_DOUX)
	add_child(intro)
	_statut.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_statut.custom_minimum_size = Vector2(LARGEUR, 0)
	_statut.add_theme_font_size_override("font_size", 13)
	add_child(_statut)
	# Relay address: the official relay by default, replaceable by any relay you host (relay/ in the repository)
	_relais.add_theme_constant_override("separation", 4)
	add_child(_relais)
	var lr := Label.new()
	lr.text = _t("relais")
	lr.add_theme_font_size_override("font_size", 13)
	_relais.add_child(lr)
	_champ_relais.text = SC.RELAIS_PAR_DEFAUT
	_champ_relais.placeholder_text = SC.RELAIS_PAR_DEFAUT
	_champ_relais.custom_minimum_size = Vector2(LARGEUR, 0)
	_champ_relais.add_theme_font_size_override("font_size", 12)
	_champ_relais.text_submitted.connect(func(_t): _on_creer())
	_relais.add_child(_champ_relais)
	var ar := Label.new()
	ar.text = _t("relais_aide")
	ar.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ar.custom_minimum_size = Vector2(LARGEUR, 0)
	ar.add_theme_font_size_override("font_size", 12)
	ar.add_theme_color_override("font_color", UI.TEXTE_DOUX)
	_relais.add_child(ar)
	_creer.text = _t("creer")
	UI.habiller(_creer, true)
	_creer.custom_minimum_size.y = 40
	if main and main.ui:
		_creer.add_theme_font_override("font", main.ui.bold_font)
	_creer.pressed.connect(_on_creer)
	add_child(_creer)

	# Détail d'une chaîne existante
	_detail.add_theme_constant_override("separation", 8)
	add_child(_detail)
	_qr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_qr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_afficher.text = _t("afficher")
	_afficher.pressed.connect(basculer_secret)
	_detail.add_child(_afficher)
	_masque.text = _t("masque")
	_masque.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_masque.custom_minimum_size = Vector2(LARGEUR, 0)
	_masque.add_theme_font_size_override("font_size", 13)
	_masque.visible = false
	_detail.add_child(_masque)
	_secret.add_theme_constant_override("separation", 8)
	_secret.visible = false
	_detail.add_child(_secret)
	# QR à gauche, 12 mots à droite
	var haut := HBoxContainer.new()
	haut.add_theme_constant_override("separation", 16)
	_secret.add_child(haut)
	haut.add_child(_qr)
	var droite := VBoxContainer.new()
	droite.add_theme_constant_override("separation", 4)
	haut.add_child(droite)
	var l1 := Label.new()
	l1.text = _t("lien")
	l1.add_theme_font_size_override("font_size", 13)
	_secret.add_child(l1)
	var ligne := HBoxContainer.new()
	_lien.editable = false
	_lien.select_all_on_focus = true
	_lien.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lien.add_theme_font_size_override("font_size", 12)
	ligne.add_child(_lien)
	_copier.text = _t("copier")
	_copier.pressed.connect(_on_copier)
	ligne.add_child(_copier)
	_secret.add_child(ligne)
	var l2 := Label.new()
	l2.text = _t("mots")
	l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l2.custom_minimum_size = Vector2(200, 0)
	l2.add_theme_font_size_override("font_size", 13)
	droite.add_child(l2)
	_mots.columns = 2
	_mots.add_theme_constant_override("h_separation", 14)
	_mots.add_theme_constant_override("v_separation", 1)
	droite.add_child(_mots)
	_id.add_theme_font_size_override("font_size", 12)
	_id.add_theme_color_override("font_color", UI.TEXTE_DOUX)
	_detail.add_child(_id)
	_detail.move_child(_id, 0)   # en tête, toujours visible : sert à vérifier l'appairage sans montrer le secret
	var avertissement := Label.new()
	avertissement.text = _t("secret")
	avertissement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	avertissement.custom_minimum_size = Vector2(LARGEUR, 0)
	avertissement.add_theme_font_size_override("font_size", 12)
	avertissement.add_theme_color_override("font_color", UI.ATTENTION)
	_secret.add_child(avertissement)
	_envoi.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_envoi.custom_minimum_size = Vector2(LARGEUR, 0)
	_envoi.add_theme_font_size_override("font_size", 12)
	_detail.add_child(_envoi)
	_supprimer.text = _t("supprimer")
	_supprimer.pressed.connect(func(): _confirmation.popup_centered(Vector2i(420, 0)))
	_detail.add_child(_supprimer)

	_confirmation.title = _t("titre")
	_confirmation.dialog_text = _t("confirmer")
	_confirmation.dialog_autowrap = true
	_confirmation.ok_button_text = _t("oui")
	_confirmation.cancel_button_text = _t("non")
	_confirmation.confirmed.connect(_on_supprimer)
	add_child(_confirmation)

	add_child(_get)
	_get.request_completed.connect(_on_etat)
	add_child(_post)
	_post.request_completed.connect(_on_action)
	_minuteur.wait_time = 3.0
	_minuteur.autostart = true
	_minuteur.timeout.connect(func():
		_echeances()
		if is_visible_in_tree():
			rafraichir())
	add_child(_minuteur)
	appliquer_etat({})
	_statut.text = _t("attente")

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree():
		if is_visible_in_tree():
			rafraichir()
		else:
			cacher_secret()   # menu fermé : le secret ne réapparaîtra pas tout seul à la prochaine ouverture

# Affiche ou recache le QR, le lien et les mots. Public pour les tests.
func basculer_secret() -> void:
	if _secret.visible:
		cacher_secret()
		return
	_secret.visible = true
	_secret_jusqua = Time.get_ticks_msec() + SECRET_MS
	_afficher.text = _t("cacher")

func cacher_secret() -> void:
	_secret.visible = false
	_secret_jusqua = 0
	_afficher.text = _t("afficher")

# Secret affiché depuis 60 s : recaché. Lien copié depuis 30 s et toujours dans le presse-papiers : retiré.
func _echeances() -> void:
	var t := Time.get_ticks_msec()
	if _secret.visible and t > _secret_jusqua:
		cacher_secret()
	if _copie_jusqua > 0 and t > _copie_jusqua:
		_copie_jusqua = 0
		if _lien_qr != "" and DisplayServer.clipboard_get() == _lien_qr:
			DisplayServer.clipboard_set("")

func rafraichir() -> void:
	if main == null or not _get.is_inside_tree() or _get.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_get.request(main.net.url("/sync"), main.net.headers())

func _on_etat(_r: int, code: int, _h: PackedStringArray, corps: PackedByteArray) -> void:
	if code != 200:
		_statut.text = _t("injoignable")
		_statut.visible = true
		_statut.add_theme_color_override("font_color", UI.DANGER_TEXTE)
		return
	var lu = JSON.parse_string(corps.get_string_from_utf8())
	if typeof(lu) == TYPE_DICTIONARY:
		appliquer_etat(lu)

func _poster(action: String, params := "") -> void:
	if main == null or _post.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	_creer.disabled = true
	_supprimer.disabled = true
	_statut.text = _t("attente")
	_statut.visible = true
	_statut.remove_theme_color_override("font_color")
	_post.request(main.net.url("/sync?action=" + action + params), main.net.headers(), HTTPClient.METHOD_POST)

# Relay typed by the user, normalised to « https://host[:port]/path/ », or "" if refused: https everywhere, http only
# on this machine (tests), no credentials, query or fragment (so never the pairing link pasted by mistake).
# Same rule as relaisValide() in daemon/sync.js, which checks it again. Public for the tests.
static func relais_saisi(texte: String) -> String:
	var t := texte.strip_edges()
	if t == "":
		return SC.RELAIS_PAR_DEFAUT
	var bas := t.to_lower()
	var schema := "https://" if bas.begins_with("https://") else ("http://" if bas.begins_with("http://") else "")
	if schema == "" or t.contains("#") or t.contains("?") or t.contains("@") or t.contains(" "):
		return ""
	var reste := t.substr(schema.length())
	var coupe := reste.find("/")
	var hote_port := (reste if coupe < 0 else reste.substr(0, coupe)).to_lower()
	var chemin := "/" if coupe < 0 else reste.substr(coupe)
	var m := RegEx.create_from_string("^([a-z0-9.-]+|\\[::1\\])(:[0-9]{1,5})?$").search(hote_port)
	if m == null or m.get_string(1).begins_with(".") or m.get_string(1).ends_with("."):
		return ""
	if schema == "http://" and not (m.get_string(1) in ["127.0.0.1", "localhost", "[::1]"]):
		return ""
	if not chemin.ends_with("/"):
		chemin += "/"
	return schema + hote_port + chemin

func _on_creer() -> void:
	var r := relais_saisi(_champ_relais.text)
	if r == "":
		_erreur(_t("relais_invalide"))
		return
	_champ_relais.text = r
	# the official relay is not sent: the local server then keeps AIMPIRE_RELAIS if it is set (tests, self-hosting)
	_poster("creer", "" if r == SC.RELAIS_PAR_DEFAUT else "&relais=" + r.uri_encode())

func _erreur(texte: String) -> void:
	_statut.text = texte
	_statut.visible = true
	_statut.add_theme_color_override("font_color", UI.DANGER_TEXTE)

func _on_supprimer() -> void:
	_poster("supprimer")

func _on_action(_r: int, code: int, _h: PackedStringArray, corps: PackedByteArray) -> void:
	_creer.disabled = false
	_supprimer.disabled = false
	var lu = JSON.parse_string(corps.get_string_from_utf8())
	if code == 200 and typeof(lu) == TYPE_DICTIONARY and lu.has("enabled"):
		appliquer_etat(lu)
	elif code == 400 and typeof(lu) == TYPE_DICTIONARY and String(lu.get("error", "")) != "":
		_erreur(String(lu.error))   # the server explains (invalid relay, chain already there)
	else:
		rafraichir()

func _on_copier() -> void:
	DisplayServer.clipboard_set(_lien.text)
	_copie_jusqua = Time.get_ticks_msec() + PRESSE_PAPIERS_MS
	_copier.text = _t("copie")
	get_tree().create_timer(1.5).timeout.connect(func(): _copier.text = _t("copier"))

# Met l'affichage à jour depuis la réponse de GET /sync. Public pour les tests.
func appliquer_etat(e: Dictionary) -> void:
	_etat = e
	var active: bool = bool(e.get("enabled", false))
	_creer.visible = not active
	_relais.visible = not active
	_detail.visible = active
	_statut.remove_theme_color_override("font_color")
	if not active:
		_statut.text = _t("aucune")
		_statut.visible = true
		_lien_qr = ""
		cacher_secret()
		return
	# Mode discret : le serveur ne sert ni lien, ni mots, ni QR (masque = true).
	var masque: bool = bool(e.get("masque", false))
	_masque.visible = masque
	_afficher.visible = not masque
	if masque:
		cacher_secret()
		_lien_qr = ""
		_lien.text = ""
		_qr.texture = null
		for enfant in _mots.get_children():
			enfant.queue_free()
	var lien: String = String(e.get("lien", ""))
	if not masque and lien != _lien_qr:
		var qr: Dictionary = e.get("qr", {})
		_qr.texture = texture_qr(qr)
		var n: int = int(qr.get("taille", 0)) + 8
		var echelle: int = maxi(2, 170 / maxi(n, 1))
		_qr.custom_minimum_size = Vector2(n * echelle, n * echelle)
		_lien.text = lien
		for enfant in _mots.get_children():
			enfant.queue_free()
		var i := 1
		for mot in e.get("mots", []):
			var l := Label.new()
			l.text = "%d. %s" % [i, String(mot)]
			l.add_theme_font_size_override("font_size", 14)
			_mots.add_child(l)
			i += 1
		_lien_qr = lien
	_id.text = _t("id") % [String(e.get("id_court", "")), String(e.get("relay", ""))]
	var erreur: String = String(e.get("erreur", ""))
	var dernier: int = int(e.get("dernier_envoi", 0))
	var texte := _t("jamais")
	if dernier > 0:
		var ecart: int = maxi(0, int(Time.get_unix_time_from_system() * 1000.0) - dernier)
		texte = _t("envoi") % [_duree(ecart), _taille(int(e.get("octets", 0)))]
	var nb: int = int(e.get("commandes", 0))
	if nb > 0:
		texte += _t("commandes") % nb
	_statut.text = erreur if erreur != "" else ""
	_statut.visible = erreur != ""
	if erreur != "":
		_statut.add_theme_color_override("font_color", UI.DANGER_TEXTE)
	_envoi.text = texte

static func _duree(ms: int) -> String:
	var s: int = ms / 1000
	if s < 60:
		return "%d s" % s
	if s < 3600:
		return "%d min" % (s / 60)
	return "%d h" % (s / 3600)

static func _taille(octets: int) -> String:
	if octets < 1024:
		return "%d B" % octets
	return "%d KB" % int(round(octets / 1024.0))

# Image du QR : un pixel par module, 4 modules clairs tout autour (zone de silence), agrandie sans lissage à l'affichage.
static func texture_qr(qr: Dictionary) -> ImageTexture:
	var n: int = int(qr.get("taille", 0))
	var lignes: Array = qr.get("modules", [])
	if n <= 0 or lignes.size() != n:
		return null
	var marge := 4
	var img := Image.create_empty(n + 2 * marge, n + 2 * marge, false, Image.FORMAT_L8)
	img.fill(Color.WHITE)
	for y in n:
		var ligne: String = String(lignes[y])
		for x in mini(n, ligne.length()):
			if ligne.unicode_at(x) == 49:   # « 1 » : module sombre
				img.set_pixel(x + marge, y + marge, Color.BLACK)
	return ImageTexture.create_from_image(img)
