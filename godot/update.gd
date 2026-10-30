extends Node
# Mises à jour : lit https://aimpire.sidali.dev/update.json au démarrage puis une fois par jour (réglage « maj_auto »,
# activé par défaut). Si la version publiée pour cette plateforme dépasse celle de l'app (application/config/version),
# un toast l'annonce et les boutons « Mettre à jour » (HUD et réglages) apparaissent.
#   - Mac : le jeu télécharge le zip lui-même, vérifie son SHA-256 contre le manifeste, puis le montre dans le Finder.
#     Un fichier dont l'empreinte ne correspond pas est supprimé, jamais montré.
#   - Android : le bouton ouvre l'URL de l'APK ; le navigateur la télécharge puis Android propose de l'installer.
#     Android refuse d'installer par-dessus l'app un APK signé par un autre certificat : un fichier modifié ne passe pas.
# Le manifeste (relay/server.js, écrit par tools/publier-maj.mjs) :
#   { "version": "0.5.0", "mac": { "url", "sha256", "version"? }, "android": { "url", "sha256", "version"? }, "notes": "…" }
# La version d'une plateforme l'emporte sur celle du haut (une plateforme peut avoir une version de retard).
# Seules les URL de la même origine que le manifeste sont ouvertes ; une entrée sans sha256 valide est ignorée. Variable d'essai : AIMPIRE_UPDATE_URL.

signal disponible_change
signal telechargement_fini(ok: bool, chemin: String)

const URL_PAR_DEFAUT := "https://aimpire.sidali.dev/update.json"
const JOUR_S := 86400.0
const REESSAI_S := 3600.0        # après un échec réseau, nouvel essai une heure plus tard
const DELAI_DEMARRAGE_S := 3.0   # laisser le jeu démarrer avant la première requête
const TAILLE_MAX := 64 * 1024
const TAILLE_MAX_PAQUET := 512 * 1024 * 1024
const DOSSIER_MAJ := "user://maj"

var main: Node = null
var url_manifeste := URL_PAR_DEFAUT
var active := true
var disponible := {}             # {"version", "url", "notes"} si une version plus récente existe, sinon vide
var derniere_erreur := ""
var _http := HTTPRequest.new()
var _http_paquet: HTTPRequest = null
var _minuteur := Timer.new()
var _boutons: Array = []         # boutons « Mettre à jour » à montrer ou cacher

# --- Fonctions pures (tests/test_update.gd) ---

# Compare deux versions « x.y.z » (un « v » initial et un suffixe « -beta » sont ignorés) : -1, 0 ou 1.
static func comparer_versions(a: String, b: String) -> int:
	var pa := _morceaux(a)
	var pb := _morceaux(b)
	for i in range(maxi(pa.size(), pb.size())):
		var x: int = pa[i] if i < pa.size() else 0
		var y: int = pb[i] if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0

static func _morceaux(v: String) -> Array:
	var t := v.strip_edges().to_lower().trim_prefix("v")
	t = t.get_slice("-", 0).get_slice("+", 0)
	var out := []
	for m in t.split("."):
		out.append(int(m) if m.is_valid_int() else 0)
	return out

static func version_valide(v: String) -> bool:
	return RegEx.create_from_string("^v?\\d{1,4}(\\.\\d{1,4}){0,3}$").search(v.strip_edges()) != null

static func version_installee() -> String:
	return String(ProjectSettings.get_setting("application/config/version", "0.0.0"))

# "android", "mac" ou "" (pas de paquet publié pour cette plateforme).
static func plateforme() -> String:
	match OS.get_name():
		"Android":
			return "android"
		"macOS":
			return "mac"
	return ""

# « https://hôte[:port]/ » d'une URL http(s), ou "".
static func origine(url: String) -> String:
	var t := url.strip_edges()
	for sc in ["https://", "http://"]:
		if t.to_lower().begins_with(sc):
			var hote := t.substr(sc.length()).get_slice("/", 0)
			if hote == "" or hote.contains("@") or hote.contains("?") or hote.contains("#"):
				return ""
			return sc + hote.to_lower() + "/"
	return ""

# Lit un manifeste : {"version", "url", "notes"} si la plateforme a une version plus récente que `installee`, sinon {}.
static func analyser(texte: String, installee: String, plat: String, origine_manifeste: String) -> Dictionary:
	if plat == "" or origine_manifeste == "":
		return {}
	var lecteur := JSON.new()   # parse() plutôt que parse_string() : pas d'erreur dans la console pour un fichier abîmé
	if lecteur.parse(texte) != OK:
		return {}
	var d = lecteur.data
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	var entree = d.get(plat)
	if typeof(entree) != TYPE_DICTIONARY:
		return {}
	var e: Dictionary = entree
	var version: String = String(e.get("version", d.get("version", "")))
	var url: String = String(e.get("url", ""))
	var sha: String = String(e.get("sha256", "")).strip_edges().to_lower()
	if not sha256_valide(sha):
		return {}
	if not version_valide(version) or comparer_versions(version, installee) <= 0:
		return {}
	# même origine que le manifeste, chemin /download/ : jamais une adresse arbitraire glissée dans le fichier
	if origine(url) != origine_manifeste or not url.substr(origine_manifeste.length() - 1).begins_with("/download/"):
		return {}
	if url.contains("?") or url.contains("#") or url.contains(" ") or url.contains(".."):
		return {}
	var notes: String = String(d.get("notes", "")) if typeof(d.get("notes", "")) == TYPE_STRING else ""
	return {"version": version.strip_edges().trim_prefix("v"), "url": url, "sha256": sha, "notes": notes.left(400)}

static func sha256_valide(h: String) -> bool:
	return RegEx.create_from_string("^[0-9a-f]{64}$").search(h) != null

# Empreinte SHA-256 d'un fichier, lue par blocs (le zip Mac fait près de 100 Mo).
static func sha256_fichier(chemin: String) -> String:
	var f := FileAccess.open(chemin, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while not f.eof_reached():
		ctx.update(f.get_buffer(1024 * 1024))
	f.close()
	return ctx.finish().hex_encode()

# Texte du bouton : sur Android, il dit que l'installation passe par le navigateur.
static func texte_bouton(version: String, plat: String) -> String:
	if plat == "android":
		return "Update to %s\nDownload and install through the browser" % version
	return "Update to %s" % version

# --- Nœud ---

func _ready() -> void:
	var env := OS.get_environment("AIMPIRE_UPDATE_URL")
	if env != "":
		url_manifeste = env
	_http.timeout = 20.0
	_http.body_size_limit = TAILLE_MAX
	_http.request_completed.connect(_sur_reponse)
	add_child(_http)
	_minuteur.one_shot = true
	_minuteur.timeout.connect(verifier)
	add_child(_minuteur)
	if active:
		_planifier(DELAI_DEMARRAGE_S)

func _planifier(secondes: float) -> void:
	_minuteur.stop()
	if active:
		_minuteur.start(secondes)

# Active ou coupe la vérification (réglages). Réactivée : vérifie tout de suite.
func set_active(on: bool) -> void:
	active = on
	if on:
		_planifier(0.5)
	else:
		_minuteur.stop()
		_http.cancel_request()

func verifier() -> void:
	if not active or _plateforme_effective() == "":
		return
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	var err := _http.request(url_manifeste, PackedStringArray(["Accept: application/json"]))
	if err != OK:
		derniere_erreur = "request failed (%s)" % error_string(err)
		_planifier(REESSAI_S)

func _plateforme_effective() -> String:
	var p := OS.get_environment("AIMPIRE_UPDATE_PLATEFORME")   # essais : « android » sur le Mac
	return p if p != "" else plateforme()

func _sur_reponse(resultat: int, code: int, _entetes: PackedStringArray, corps: PackedByteArray) -> void:
	if resultat != HTTPRequest.RESULT_SUCCESS or code != 200:
		derniere_erreur = "manifest unreachable (result %d, HTTP %d)" % [resultat, code]
		_planifier(REESSAI_S)
		return
	derniere_erreur = ""
	_planifier(JOUR_S)
	var avant: String = String(disponible.get("version", ""))
	disponible = analyser(corps.get_string_from_utf8(), version_installee(), _plateforme_effective(), origine(url_manifeste))
	_maj_boutons()
	disponible_change.emit()
	var v: String = String(disponible.get("version", ""))
	if v != "" and v != avant and main != null and main.get("hud") != null:
		main.hud.show_toast("Update available: AImpire %s" % v, 6000)

func ouvrir() -> void:
	if disponible.is_empty():
		return
	if _plateforme_effective() == "android":
		OS.shell_open(String(disponible.url))
		_toast("Downloading in the browser: open the APK and Android will offer to install it")
		return
	if not telechargement_fini.is_connected(_montrer_paquet):
		telechargement_fini.connect(_montrer_paquet)
	if telecharger():
		_toast("Downloading the update…")

# Télécharge le paquet annoncé dans user://maj puis vérifie son SHA-256. Émet telechargement_fini(ok, chemin).
func telecharger() -> bool:
	if disponible.is_empty() or (_http_paquet != null and _http_paquet.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED):
		return false
	DirAccess.make_dir_recursive_absolute(DOSSIER_MAJ)
	var chemin := DOSSIER_MAJ.path_join(String(disponible.url).get_file())
	if _http_paquet == null:
		_http_paquet = HTTPRequest.new()
		_http_paquet.timeout = 600.0
		_http_paquet.use_threads = true
		_http_paquet.body_size_limit = TAILLE_MAX_PAQUET
		add_child(_http_paquet)
	_http_paquet.download_file = chemin
	var attendu: String = String(disponible.sha256)
	var fini := func(resultat: int, code: int, _h: PackedStringArray, _c: PackedByteArray) -> void:
		var ok := resultat == HTTPRequest.RESULT_SUCCESS and code == 200 and sha256_fichier(chemin) == attendu
		if not ok:
			DirAccess.remove_absolute(chemin)
			derniere_erreur = "package refused (result %d, HTTP %d, checksum mismatch or incomplete download)" % [resultat, code]
		telechargement_fini.emit(ok, chemin if ok else "")
	_http_paquet.request_completed.connect(fini, CONNECT_ONE_SHOT)
	if _http_paquet.request(String(disponible.url)) != OK:
		_http_paquet.request_completed.disconnect(fini)
		return false
	return true

func _montrer_paquet(ok: bool, chemin: String) -> void:
	if ok:
		OS.shell_show_in_file_manager(ProjectSettings.globalize_path(chemin))
		_toast("Update verified: unzip it and replace AImpire in Applications")
	else:
		_toast("Update refused: the downloaded file does not match the published checksum")

func _toast(texte: String) -> void:
	if main != null and main.get("hud") != null:
		main.hud.show_toast(texte, 6000)

# Un bouton « Mettre à jour » relié à ce module, caché tant qu'aucune version plus récente n'est connue. `court` : une
# seule ligne « Update 0.7.1 » (ligne d'état du téléphone) ; sinon le texte complet, replié s'il le faut.
func creer_bouton(taille_police := 14, court := false) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("court", court)
	b.add_theme_font_size_override("font_size", taille_police)
	var UI := preload("res://ui_kit.gd")
	b.add_theme_color_override("font_color", UI.ENCRE)
	b.add_theme_color_override("font_hover_color", UI.ENCRE)
	b.add_theme_color_override("font_pressed_color", UI.ENCRE)
	for etat in ["normal", "hover", "pressed"]:   # or romain plein, texte encre (4,7:1) : se voit sur le monde comme dans le menu
		var fond := StyleBoxFlat.new()
		fond.bg_color = UI.OR_ROMAIN.lightened(0.08) if etat == "hover" else (UI.OR_ROMAIN.darkened(0.12) if etat == "pressed" else UI.OR_ROMAIN)
		fond.set_corner_radius_all(int(UI.RAYON_BOUTON))
		fond.content_margin_left = 12
		fond.content_margin_right = 12
		fond.content_margin_top = 5
		fond.content_margin_bottom = 5
		b.add_theme_stylebox_override(etat, fond)
	b.pressed.connect(ouvrir)
	b.tree_exiting.connect(func(): _boutons.erase(b))
	_boutons.append(b)
	_maj_bouton(b)
	return b

func _maj_boutons() -> void:
	for b in _boutons:
		if is_instance_valid(b):
			_maj_bouton(b)

func _maj_bouton(b: Button) -> void:
	b.visible = not disponible.is_empty()
	if b.visible:
		var court: bool = b.get_meta("court", false)
		b.text = ("Update %s" % String(disponible.version)) if court else texte_bouton(String(disponible.version), _plateforme_effective())
		b.tooltip_text = String(disponible.get("notes", ""))
