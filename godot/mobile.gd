extends Node
# Mode téléphone (docs/SYNC.md §7) : le jeu observe l'Empire à travers le relais chiffré au lieu du serveur local.
#   - chaîne de sync : user://chaine.cfg (secret S en hex et relais), écran d'appairage si elle manque ;
#   - réception : GET <relais>blob?wait=25 en boucle (long-poll, If-None-Match), déchiffrement, puis main._apply_state()
#     exactement comme une réponse de /state ; rapport, journal et digest viennent des annexes de l'enveloppe ;
#   - commandes : réclamer, construire et mode discret sont chiffrées et déposées par POST <relais>cmd ;
#   - interface tactile en portrait (docs/MOBILE-PORTRAIT.md) : barre du bas et feuilles (phone_ui.gd, sheet.gd), échelle
#     de l'interface (une unité = un dp), zones sûres sur les quatre bords, plafond d'images (power.gd), haptique.
# Actif si OS.has_feature("mobile"), si AIMPIRE_MOBILE=1 (essais sur le Mac), avec --chaine=<lien>, ou si chaine.cfg existe.
# Variables d'essai (Mac) : AIMPIRE_CHAINE (chemin de chaine.cfg), AIMPIRE_ECHELLE (échelle de l'interface),
# AIMPIRE_DENSITE (dp par pixel, remplace dpi / 160), AIMPIRE_ZONE_SURE (« haut,droite,bas,gauche » en dp),
# AIMPIRE_FEUILLE (cockpit, today, week, journal, villages, senate, settings : feuille ouverte au démarrage),
# AIMPIRE_BATIMENT (bâtiment choisi au démarrage, avec AIMPIRE_SELECT ; AIMPIRE_DETENTE=pleine ouvre sa feuille dépliée),
# AIMPIRE_GESTE (pan, fling, pinch-in, pinch-out,
# double-tap : gestes simulés, geste.gd ; aussi l'argument --geste= sur le téléphone),
# AIMPIRE_RELAIS (relais imposé, remplace celui du lien), AIMPIRE_MOTS (12 mots saisis puis « Rejoindre » pressé tout seul),
# AIMPIRE_TEST_COMMANDE (route envoyée une fois au premier état, par exemple /reglage?cle=privacy&val=flou).

const SC := preload("res://sync_crypto.gd")
const UI := preload("res://ui_kit.gd")
const HAPTIQUE := preload("res://haptics.gd")
const CHEMIN_CHAINE := "user://chaine.cfg"
const CHEMIN_REGLAGES := "user://telephone.cfg"
# Surcharge des réglages du projet lue au démarrage (application/config/project_settings_override dans project.godot) :
# présente avec rendering_method.mobile="mobile", elle fait tourner le jeu en Vulkan au lieu d'OpenGL ES 3 (par défaut).
const CHEMIN_MOTEUR := "user://moteur.cfg"
const ATTENTES := [1.0, 2.0, 5.0, 15.0]   # secondes avant de réessayer après une erreur réseau
const ATTENTES_RAPIDES := [1.0, 2.0, 5.0] # secondes après une réponse inutile trop rapide (304 immédiat, état déjà vu)
const REPONSE_RAPIDE_MS := 2000           # un long-poll qui revient plus vite que ça n'a pas vraiment attendu
const SILENCE_MS := 120000                # état du Mac plus vieux que ça (le Mac republie au moins chaque minute) : bandeau
const CONTACT_MS := 40000                 # sans réponse du relais depuis ce délai, c'est le téléphone qui n'est plus à jour
const DELAI_REPONSE_MS := 30000           # au-delà, « Le Mac n'a pas répondu »
const AGE_MAX_CMD_MS := 60000             # une commande pas encore déposée après ce délai est abandonnée
const ECRITURE_TS_MS := 30000             # dernier_ts est écrit dans chaine.cfg au plus toutes les 30 s (et à la mise en pause)
const VERSION_ENVELOPPE := 1              # champ v de l'enveloppe d'état (daemon/sync.js)
const TAILLE_MAX_BLOB := 256 * 1024 + 1024   # maxBlob du relais (256 Kio) et une marge : rien de plus n'est lu en mémoire
const TAILLE_MAX_REPONSE_CMD := 64 * 1024

var main: Node
var echelle := 1.0          # unités d'interface par pixel de base : 1 unité = 1 dp sur téléphone
var fluidite := "adaptive"  # « Smoothness » : "adaptive" (60 pendant l'interaction, 30 au repos) ou "battery"
var journal_fps := false    # « FPS … » dans le journal (logcat, étiquette godot) toutes les 2 s ; vrai par défaut en debug
var _mesure := 0.0          # prochaine ligne « FPS » (s, ticks)
var _durees := PackedFloat32Array()   # durées des images (ms) depuis la dernière ligne « FPS »
var _n_durees := 0
var _etats_vus := {}        # états de la caméra vus depuis la dernière ligne « FPS »
var n_etats := 0            # états reçus depuis le lancement (les onglets du cockpit relisent alors les annexes)
var ui: Node                # phone_ui.gd : barre du bas, feuilles, marges

# Chaîne courante
var secret := PackedByteArray()
var relais := ""
var id := ""
var cles := {}

# Réception
var etag := ""
# Horloge du Mac (ms) du dernier état accepté, authentifiée par le mac de l'enveloppe et gardée dans chaine.cfg : un état
# plus ancien est refusé, même après un redémarrage de l'app. C'est elle qui mesure la fraîcheur de ce qu'on affiche.
var dernier_ts := 0
var maj_relais := 0         # X-AImpire-Maj : dernier PUT d'après le relais (non authentifié : sert seulement à aggraver l'alerte)
var annexes := {}
var _http := HTTPRequest.new()
var _en_cours := false
var _debut_ms := 0          # début de la requête en cours (ticks)
var _contact_ms := 0        # dernière réponse 200 ou 304 du relais (ticks) : le téléphone est-il à jour ?
var _relance := 0.0         # heure (s, ticks) avant laquelle on ne réinterroge pas
var _echecs := 0
var _rapides := 0           # réponses inutiles trop rapides d'affilée
var _affiche := false       # un état a été affiché depuis le lancement
var _ts_ecrit_ms := 0       # dernière écriture de dernier_ts dans chaine.cfg (ticks)
var _ts_ecrit := 0
var _pause := false
var _erreur := ""           # passagère : réseau, relais saturé
var _alerte := ""           # durable : chaîne invalide, supprimée, version du Mac plus récente

# Commandes
var _http_cmd := HTTPRequest.new()
var _cmd_en_cours := false
var _file_cmd: Array = []   # [{blob, nonce}] en attente d'envoi
var _attendues := {}        # nonce -> {t, texte} : envoyées, en attente du résultat dans annexes.commandes
var _cmd_relance := 0.0
var _test_commande := ""

# Interface
var couche: CanvasLayer     # couche 2 : barre du bas, bandeau, écran d'appairage
var bandeau: PanelContainer
var _bandeau_texte: Label
var _rafraichi := 0.0
var _cle_hud := ""          # ce qui était ouvert au dernier dessin du HUD
var _hud_prochain := 0.0    # prochain dessin du HUD sans changement (âges « il y a … »), en s (ticks)
var _toucher_ms := 0        # dernier contact du doigt (ticks) : en « Battery saver », 20 s sans toucher donne 15 images/s
var en_veille := false      # lu par power.gd
var _retour_ms := -10000    # premier geste retour sans rien d'ouvert : un second dans les 2 s quitte
var _retour_image := -1     # image et heure (ms) du dernier geste retour traité (doublons filtrés)
var _retour_t := -10000
var retraits := Vector4.ZERO   # zone sûre (poinçon, coins, barre de gestes) : haut, droite, bas, gauche, en dp
var ecran: Control          # écran d'appairage
var _cadre_ecran: PanelContainer
var _defile_ecran: ScrollContainer
var _marge_clavier: Control # sous le contenu de l'appairage : hauteur du clavier virtuel
var _champ_lien: LineEdit
var _champ_mots: LineEdit
var _apercu_mots: RichTextLabel
var _suggestions: HFlowContainer
var _champ_relais: LineEdit
var _bouton_relais: Button
var _erreur_appairage: Label
var _oubli_confirme := false
var _col_reglages: Control = null   # colonne des réglages construite par settings.gd (logée dans la feuille Settings)
var _feuille_demandee := ""         # AIMPIRE_FEUILLE : ouverte au premier état reçu
var _interrupteur_discret: Control = null
var _discret_touche_ms := -100000

# ---------------------------------------------------------------------------
# Activation et chaîne enregistrée
# ---------------------------------------------------------------------------

static func doit_activer() -> bool:
	if OS.has_feature("mobile") or OS.get_environment("AIMPIRE_MOBILE") == "1":
		return true
	if _lien_en_argument() != "":
		return true
	return bool(lire_chaine().get("ok", false))

static func _lien_en_argument() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--chaine="):
			return a.substr(9)
	return ""

static func chemin_chaine() -> String:
	var p := OS.get_environment("AIMPIRE_CHAINE")
	return p if p != "" else CHEMIN_CHAINE

# {"ok": true, "secret": PackedByteArray, "relais": String, "dernier_ts": int} ou {"ok": false}
static func lire_chaine() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(chemin_chaine()) != OK:
		return {"ok": false}
	var hexa := String(cfg.get_value("chaine", "secret", "")).to_lower()
	var r := normaliser_relais(String(cfg.get_value("chaine", "relais", SC.RELAIS_PAR_DEFAUT)))
	if RegEx.create_from_string("^[0-9a-f]{32}$").search(hexa) == null or r == "":
		return {"ok": false}
	return {"ok": true, "secret": hexa.hex_decode(), "relais": r, "dernier_ts": int(cfg.get_value("reception", "dernier_ts", 0))}

# Adresse de relais propre « schéma://hôte[:port]/chemin/ », ou "" si elle ne convient pas : ni fragment (#), ni requête (?),
# ni identifiants (@), donc jamais le lien d'appairage collé par erreur. https partout ; http seulement vers un hôte local
# ou privé (127.0.0.1, localhost, 10.0.2.2 de l'émulateur, réseaux 10/8, 172.16/12, 192.168/16), car l'id et le trafic y
# passent en clair.
static func normaliser_relais(texte: String) -> String:
	var t := texte.strip_edges()
	var schema := ""
	for sc in ["https://", "http://"]:
		if t.to_lower().begins_with(sc):
			schema = sc
	if schema == "" or t.contains("#") or t.contains("?") or t.contains("@") or t.contains(" "):
		return ""
	var reste := t.substr(schema.length())
	var coupe := reste.find("/")
	var hote_port := (reste if coupe < 0 else reste.substr(0, coupe)).to_lower()
	var chemin := "/" if coupe < 0 else reste.substr(coupe)
	var m := RegEx.create_from_string("^([a-z0-9.-]+|\\[::1\\])(:[0-9]{1,5})?$").search(hote_port)
	if m == null:
		return ""
	if schema == "http://" and not hote_local(m.get_string(1)):
		return ""
	if not chemin.ends_with("/"):
		chemin += "/"
	return schema + hote_port + chemin

static func hote_local(hote: String) -> bool:
	if hote in ["127.0.0.1", "localhost", "[::1]", "10.0.2.2"]:
		return true
	var o := hote.split(".")
	if o.size() != 4:
		return false
	for x in o:
		if not x.is_valid_int():
			return false
	var a := int(o[0])
	var b := int(o[1])
	return a == 10 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168)

# Relais joint en http (réseau local) : affiché avec un avertissement.
static func relais_en_clair(r: String) -> bool:
	return r.begins_with("http://")

func _enregistrer_chaine() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("chaine", "secret", secret.hex_encode())
	cfg.set_value("chaine", "relais", relais)
	cfg.set_value("chaine", "appairee_le", int(Time.get_unix_time_from_system()))
	cfg.set_value("reception", "dernier_ts", dernier_ts)
	var err := cfg.save(chemin_chaine())
	if err != OK:
		push_error("sync chain not saved (%s): error %d" % [chemin_chaine(), err])

# Garde dernier_ts dans chaine.cfg : au prochain lancement, le relais ne pourra pas servir un état plus ancien.
func _noter_dernier_ts(forcer := false) -> void:
	if secret.is_empty() or dernier_ts <= _ts_ecrit:
		return
	if not forcer and Time.get_ticks_msec() - _ts_ecrit_ms < ECRITURE_TS_MS:
		return
	var cfg := ConfigFile.new()
	if cfg.load(chemin_chaine()) != OK or String(cfg.get_value("chaine", "secret", "")).to_lower() != secret.hex_encode():
		return   # chaîne oubliée ou remplacée entre-temps
	cfg.set_value("reception", "dernier_ts", dernier_ts)
	if cfg.save(chemin_chaine()) == OK:
		_ts_ecrit = dernier_ts
		_ts_ecrit_ms = Time.get_ticks_msec()

func _adopter(s: PackedByteArray, r: String, ts := 0) -> void:
	secret = s
	relais = r
	id = SC.derive_id(s)
	cles = SC.derive_keys(s)
	etag = ""
	dernier_ts = ts
	_ts_ecrit = ts
	maj_relais = 0
	annexes = {}
	_affiche = false
	_contact_ms = 0
	_erreur = ""
	_alerte = ""
	_echecs = 0
	_rapides = 0
	_relance = 0.0

# ---------------------------------------------------------------------------
# Mise en place (appelée par main.gd)
# ---------------------------------------------------------------------------

# Avant la création du monde : échelle de l'interface, taille des textes 3D, orientation (portrait, comme le manifeste :
# window/handheld/orientation=5 donne USER_PORTRAIT ; l'appel ici n'est là que pour la cohérence).
func preparer() -> void:
	_charger_reglages()
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_PORTRAIT)
	echelle = _calcul_echelle()
	main.get_window().content_scale_factor = echelle
	var fen := main.get_window().size
	main.ui.label_scale = echelle_textes_3d(densite(), fen)
	main.ui.label_range = 95.0 if fen.y > fen.x else 55.0   # les étiquettes restent visibles au cadrage d'un village
	main.ui.theme.default_font_size = 16

# Rendu choisi dans les réglages du téléphone. Par défaut OpenGL ES 3 (rendu Compatibilité, project.godot) : un pilote
# Vulkan qui échoue bloque Godot sur un écran noir avant le premier script (vu avec le Vulkan logiciel de l'émulateur),
# donc sans aucun moyen d'atteindre ce réglage. Vulkan (rendu Mobile) reste proposé, à essayer une fois l'app lancée ;
# s'il bloque, effacer les données de l'app revient à OpenGL. Visuellement rien ne change : les contours (post.gdshader)
# sont coupés sur le rendu Mobile comme sur Compatibilité.
static func moteur_vulkan() -> bool:
	return FileAccess.file_exists(CHEMIN_MOTEUR) and FileAccess.get_file_as_string(CHEMIN_MOTEUR).contains('"mobile"')

# true : rendu Mobile (Vulkan) ; false : rendu Compatibilité (OpenGL ES 3, par défaut). Pris en compte au prochain lancement.
static func choisir_moteur(vulkan: bool) -> void:
	if vulkan:
		var f := FileAccess.open(CHEMIN_MOTEUR, FileAccess.WRITE)
		if f:
			f.store_string('[rendering]\nrenderer/rendering_method.mobile="mobile"\n')
	elif FileAccess.file_exists(CHEMIN_MOTEUR):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CHEMIN_MOTEUR))

# Pixels par dp : AIMPIRE_DENSITE (captures sur le Mac), sinon dpi / 160 borné entre 1 et 3.
static func densite() -> float:
	var forcee := OS.get_environment("AIMPIRE_DENSITE")
	if forcee.is_valid_float() and float(forcee) > 0.0:
		return float(forcee)
	return clampf(DisplayServer.screen_get_dpi() / 160.0, 1.0, 3.0)

# Unités d'interface par unité de base (Window.content_scale_factor) pour qu'une unité vaille un dp dans toutes les
# orientations. L'étirement « canvas_items » + « expand » met la base de 1280 × 720 à l'échelle min(l / 1280, h / 720) :
# en paysage c'est la hauteur qui limite, en portrait la largeur. 1080 × 2340 à 420 dpi : 2,625 / 0,84375 = 3,111.
static func calcul_echelle(dp: float, fen: Vector2i) -> float:
	var base := minf(fen.x / 1280.0, fen.y / 720.0)
	if base <= 0.0:
		return 1.0
	return clampf(dp / base, 0.5, 6.0)

# Textes 3D à taille fixe : leur hauteur à l'écran suit hauteur de la vue / tan(champ vertical / 2). On garde la taille
# physique qu'ils avaient sur le téléphone en paysage (1,75 sur l'émulateur), soit 1,36 en portrait.
static func echelle_textes_3d(dp: float, fen: Vector2i) -> float:
	if fen.x <= 0 or fen.y <= 0:
		return 1.0
	var t := tan(deg_to_rad(19.0))
	if fen.y > fen.x:   # champ horizontal de 30° (camera_math.gd) : champ vertical selon la forme de l'écran
		t = tan(deg_to_rad(15.0)) * fen.y / fen.x
	return clampf(dp * (720.0 / fen.y) * t / tan(deg_to_rad(19.0)), 0.75, 2.5)

func _calcul_echelle() -> float:
	var forcee := OS.get_environment("AIMPIRE_ECHELLE")
	if forcee.is_valid_float():
		return clampf(float(forcee), 0.5, 6.0)
	return calcul_echelle(densite(), main.get_window().size)

# Après la création du HUD : boutons, bandeau, écran d'appairage, puis réception si une chaîne est connue.
func setup() -> void:
	_http.timeout = 40.0
	_http.use_threads = true
	_http.body_size_limit = TAILLE_MAX_BLOB   # un relais malveillant ne peut pas faire lire des centaines de Mo avant le mac
	_http.request_completed.connect(_sur_blob)
	add_child(_http)
	_http_cmd.timeout = 15.0
	_http_cmd.body_size_limit = TAILLE_MAX_REPONSE_CMD
	_http_cmd.request_completed.connect(_sur_cmd)
	add_child(_http_cmd)
	_test_commande = OS.get_environment("AIMPIRE_TEST_COMMANDE")
	main.minimap.visible = false   # jamais à l'écran sur le téléphone : une copie réduite vit dans la feuille Villages
	_durees.resize(256)
	couche = CanvasLayer.new()
	couche.layer = 2
	add_child(couche)
	_construire_bandeau()
	ui = preload("res://phone_ui.gd").new()
	ui.main = main
	ui.mobile = self
	add_child(ui)
	ui.setup()
	if _col_reglages:
		ui.reglages_reconstruits(_col_reglages)
	_construire_ecran()
	_toucher_ms = Time.get_ticks_msec()
	main.get_window().size_changed.connect(_sur_taille)
	_sur_taille()
	_sur_taille.call_deferred()
	var geste := _geste_demande()
	if geste != "":
		var g := preload("res://geste.gd").new()
		g.main = main
		g.nom = geste
		add_child(g)
	var lien := _lien_en_argument()
	var c := lire_chaine()
	if lien != "":
		var r: Dictionary = SC.from_link(lien)
		var rl := normaliser_relais(String(r.get("relais", "")))
		if r.ok and rl != "":
			var s: PackedByteArray = r.secret
			_adopter(s, rl, int(c.dernier_ts) if c.ok and c.secret == s else 0)
		else:
			_erreur_appairage.text = String(r.get("erreur", "The link's relay was refused (https, or http on a local network)"))
	if secret.is_empty() and c.ok:
		var s: PackedByteArray = c.secret
		_adopter(s, String(c.relais), int(c.dernier_ts))
	ecran.visible = secret.is_empty()
	ui.barre.visible = not ecran.visible
	if not secret.is_empty():   # le menu a été construit avant que la chaîne soit lue (main._ready)
		_reconstruire_reglages()
	var feuille := OS.get_environment("AIMPIRE_FEUILLE")   # captures : feuille ouverte au démarrage
	if feuille != "" and not ecran.visible:
		_feuille_demandee = feuille
	var mots_test := OS.get_environment("AIMPIRE_MOTS")
	if ecran.visible and mots_test != "":
		_champ_mots.text = mots_test
		_sur_mots(mots_test)
		get_tree().create_timer(0.5).timeout.connect(_rejoindre)

# ---------------------------------------------------------------------------
# Réception de l'état (long-poll sur le relais)
# ---------------------------------------------------------------------------

func _maintenant() -> float:
	return Time.get_ticks_msec() / 1000.0

func _process(delta: float) -> void:
	if not secret.is_empty() and not _pause and not _en_cours and _maintenant() >= _relance:
		_interroger()
	if not _cmd_en_cours and not _file_cmd.is_empty() and _maintenant() >= _cmd_relance:
		_envoyer_suivante()
	if journal_fps:   # durée de chaque image, pour p50, p95 et les images lentes de la ligne « FPS »
		if _n_durees < _durees.size():
			_durees[_n_durees] = delta * 1000.0
			_n_durees += 1
		if main.rig:
			_etats_vus[main.rig.etat] = true
	_rafraichi -= delta
	if _rafraichi <= 0.0:
		_rafraichi = 0.25
		_verifier_commandes()
		if journal_fps and _maintenant() >= _mesure:
			_mesure = _maintenant() + 2.0
			_journaliser_fps()
		_maj_bandeau()
		_maj_veille()
		_maj_interrupteur_discret()
		if ecran.visible and _marge_clavier:   # clavier refermé : la marge du bas disparaît
			var m := maxf(0.0, hauteur_clavier() - ui.B)
			if m < _marge_clavier.custom_minimum_size.y:
				_marge_clavier.custom_minimum_size.y = m
		# L'état n'arrive que quand il change (main._apply_state redessine alors le HUD). Entre deux, on ne redessine que si
		# ce qui est ouvert a changé (toucher, feuilles) ou toutes les 5 s pour les âges : pas 4 fois par seconde pour rien,
		# et jamais pendant un geste (pas de saccade au pincement).
		var geste: bool = main.rig != null and main.rig.active
		if main.started and not geste and (_cle_interface() != _cle_hud or _maintenant() >= _hud_prochain):
			rafraichir_hud()

func _cle_interface() -> String:
	return "%s|%s|%s|%s|%s|%s|%s" % [main.selected, main.selected_building, main.cockpit_open, main.hud.report_open,
		main.settings.menu.visible, ui.feuille if ui else "", ui.onglet if ui else ""]

func rafraichir_hud() -> void:
	if not main.started:
		return
	main.hud.refresh(main.last_state, main.selected, int(Engine.get_frames_per_second()))
	_cle_hud = _cle_interface()
	_hud_prochain = _maintenant() + 5.0

# Tout contact : 60 images par seconde tout de suite (power.poke, avant la première image du glissé). En « Battery saver »,
# 20 s sans toucher descendent à 15 images par seconde ; le premier contact rend le plafond.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton or event is InputEventKey:
		_toucher_ms = Time.get_ticks_msec()
		if main.power:
			main.power.poke()
		if en_veille:
			_maj_veille()

func _maj_veille() -> void:
	var veille := Time.get_ticks_msec() - _toucher_ms > 20000
	if veille != en_veille:
		en_veille = veille
		if main.power:
			main.power._apply(main.power.state)

func _interroger() -> void:
	var h := PackedStringArray(["X-AImpire-Id: " + id])
	if etag != "":
		h.append("If-None-Match: " + etag)
	var err := _http.request(relais + "blob?wait=25", h)
	if err == OK:
		_en_cours = true
		_debut_ms = Time.get_ticks_msec()
	else:
		_echec("Invalid relay address")

func _echec(message: String) -> void:
	_erreur = message
	_echecs += 1
	_relance = _maintenant() + float(ATTENTES[mini(_echecs - 1, ATTENTES.size() - 1)])

# Réponse inutile (304 ou état déjà vu) revenue sans vraie attente : les attentes du relais sont prises (4 par id, 200 au
# total) ou un proxy coupe le long-poll. On patiente 1, 2 puis 5 s au lieu de boucler à la vitesse du réseau, ce qui
# viderait la batterie et le quota de 600 requêtes par IP (partagé avec le Mac sur le même Wi-Fi).
func _reponse_inutile(duree_ms: int) -> void:
	if duree_ms >= REPONSE_RAPIDE_MS:
		_rapides = 0
		return
	_rapides += 1
	_relance = _maintenant() + float(ATTENTES_RAPIDES[mini(_rapides - 1, ATTENTES_RAPIDES.size() - 1)])

static func _en_tete(entetes: PackedStringArray, nom: String) -> String:
	var prefixe := nom.to_lower() + ":"
	for l in entetes:
		if l.to_lower().begins_with(prefixe):
			return l.substr(prefixe.length()).strip_edges()
	return ""

func _sur_blob(resultat: int, code: int, entetes: PackedStringArray, corps: PackedByteArray) -> void:
	_en_cours = false
	if _pause:
		return
	var duree := Time.get_ticks_msec() - _debut_ms
	if resultat == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		_echec("Relay response too large, ignored")
		return
	if resultat != HTTPRequest.RESULT_SUCCESS:
		_echec("Relay unreachable, retrying…")
		return
	var maj := _en_tete(entetes, "X-AImpire-Maj")
	if maj.is_valid_int():
		maj_relais = int(maj)
	match code:
		304:   # rien de neuf pendant l'attente : on relance tout de suite, sauf si le relais n'a pas vraiment attendu
			_contact_ms = Time.get_ticks_msec()
			_echecs = 0
			_erreur = ""
			_reponse_inutile(duree)
		200:
			_contact_ms = Time.get_ticks_msec()
			_echecs = 0
			_erreur = ""
			var nouvel := _en_tete(entetes, "ETag")
			if nouvel != "":
				etag = nouvel   # même si le blob est refusé : on attendra le suivant au lieu de boucler
			if _recevoir(corps):
				_rapides = 0
			else:
				_reponse_inutile(duree)
			if nouvel == "":   # sans ETag (proxy), chaque tour renverrait tout l'état : au moins 2 s entre deux requêtes
				_relance = maxf(_relance, _maintenant() + 2.0)
		404:
			_echecs = 0
			_erreur = ""
			if dernier_ts > 0:   # on a déjà vu un état de cette chaîne : elle a été supprimée sur le Mac ou purgée
				_alerte = "Sync chain deleted on the Mac or expired: join your Empire again (Settings, Forget this sync chain)"
				_relance = _maintenant() + 60.0
			else:
				_erreur = "The Mac has not published anything to this relay yet"
				_relance = _maintenant() + 5.0
		429:
			var apres := _en_tete(entetes, "Retry-After")
			_erreur = "Relay busy, please wait…"
			_relance = _maintenant() + clampf(float(apres) if apres.is_valid_float() else 10.0, 1.0, 300.0)
		_:
			_echec("The relay replied %d" % code)

# Un blob reçu : déchiffrer, vérifier l'enveloppe, puis le même rendu que /state. Renvoie true si l'état est affiché.
func _recevoir(blob: PackedByteArray) -> bool:
	var r: Dictionary = SC.decrypt_json(cles, blob)
	if not r.ok:
		_alerte = "Invalid sync chain: this relay serves a state that cannot be decrypted (%s)" % String(r.erreur)
		return false
	var env = r.objet
	if not (env is Dictionary) or String(env.get("type", "")) != "etat" or not (env.get("etat") is Dictionary):
		_alerte = "Invalid sync chain: unexpected envelope"
		return false
	var v := int(env.get("v", 0))
	if v != VERSION_ENVELOPPE:   # schéma de l'état inconnu : mieux vaut ne rien afficher qu'une scène à moitié à jour
		_alerte = "The Mac runs a newer version: update the app" if v > VERSION_ENVELOPPE else "Unknown envelope version (%d)" % v
		return false
	var ts := int(env.get("ts", 0))
	# Le relais ne peut pas faire revenir un état plus ancien que le dernier accepté, même d'un lancement précédent
	# (dernier_ts vient de chaine.cfg). Le même ts n'est repris qu'une fois, au lancement, pour avoir quelque chose à l'écran.
	if ts <= 0 or ts < dernier_ts or (ts == dernier_ts and _affiche):
		return false
	dernier_ts = ts
	_affiche = true
	_alerte = ""
	_noter_dernier_ts()
	var a = env.get("annexes")
	annexes = a if a is Dictionary else {}
	var etat: Dictionary = env.etat
	n_etats += 1
	main._apply_state(etat)   # redessine aussi le HUD
	_hud_prochain = _maintenant() + 5.0
	if _feuille_demandee != "" and main.started:
		var f := _feuille_demandee
		_feuille_demandee = ""
		if f in ["today", "week", "journal", "now"]:
			ui.ouvrir("cockpit", f)
		else:
			ui.ouvrir(f)
	if _test_commande != "" and main.started:
		var route := _test_commande
		_test_commande = ""
		poster(route)
	return true

static func _maintenant_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)

# Âge de l'état affiché, mesuré avec le ts authentifié du Mac ; X-AImpire-Maj (non authentifié) peut seulement l'aggraver.
func age_etat_ms() -> int:
	if dernier_ts <= 0:
		return -1
	var age := _maintenant_ms() - dernier_ts
	if maj_relais > 0:
		age = maxi(age, _maintenant_ms() - maj_relais)
	return maxi(age, 0)

# Le Mac publie-t-il encore ? Faux tant qu'on n'a pas de réponse fraîche du relais (c'est alors le téléphone qui ne sait pas).
func mac_silencieux() -> bool:
	return dernier_ts > 0 and _contact_ms > 0 and Time.get_ticks_msec() - _contact_ms < CONTACT_MS and age_etat_ms() > SILENCE_MS

# « 14:32 », « hier 18:42 » ou « le 17/10 18:42 » (heure locale du téléphone).
static func heure(ms: int) -> String:
	var biais: int = int(Time.get_time_zone_from_system().bias) * 60
	var t := Time.get_datetime_dict_from_unix_time(int(ms / 1000) + biais)
	var aujourdhui := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) + biais)
	var hier := Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_system()) - 86400 + biais)
	var hm := "%02d:%02d" % [t.hour, t.minute]
	if t.day == aujourdhui.day and t.month == aujourdhui.month and t.year == aujourdhui.year:
		return hm
	if t.day == hier.day and t.month == hier.month and t.year == hier.year:
		return "yesterday " + hm
	return "%02d/%02d %s" % [t.day, t.month, hm]

# Bandeau : alerte durable, attente du premier état, téléphone pas à jour (hors ligne, retour de veille), Mac silencieux.
# Deux horloges : la dernière réponse du relais (côté téléphone) et le ts de l'état (côté Mac).
func texte_bandeau() -> String:
	if secret.is_empty():
		return ""
	if _alerte != "":
		return _alerte
	if dernier_ts == 0:
		return _erreur if _erreur != "" else "Sync chain %s: waiting for the Mac…" % id.left(6)
	var de := "Mac state from " + heure(dernier_ts)
	var a_jour := _contact_ms > 0 and Time.get_ticks_msec() - _contact_ms < CONTACT_MS
	if _erreur != "":
		return "%s · %s" % [_erreur, de]
	if not a_jour:
		return "Updating… · " + de
	if mac_silencieux():
		return "The Mac has not published for %s (AImpire closed, Mac asleep or off) · %s" % [_duree(age_etat_ms() / 1000), de]
	return ""

func _maj_bandeau() -> void:
	var msg := texte_bandeau()
	if _bandeau_texte.text != msg:
		_bandeau_texte.text = msg
		bandeau.size = Vector2(bandeau.custom_minimum_size.x, 0)   # le bandeau reprend la hauteur de son texte
	if bandeau.visible != (msg != ""):
		bandeau.visible = msg != ""
		if ui:
			ui.placer_toast()

# Zone sûre d'Android (poinçon, coins arrondis, barre de gestes) en dp : Vector4(haut, droite, bas, gauche). `sur` : la
# zone sûre de l'écran en pixels (le poinçon n'y apparaît qu'en mode immersif), `fen` : la fenêtre en pixels, `k` : dp par
# pixel. Zéro si la zone sûre est vide.
static func calcul_retraits(sur: Rect2i, fen: Vector2i, k: float) -> Vector4:
	if sur.size.x <= 0 or sur.size.y <= 0 or fen.x <= 0 or fen.y <= 0:
		return Vector4.ZERO
	return Vector4(maxf(0.0, sur.position.y) * k, maxf(0.0, float(fen.x - sur.end.x)) * k,
		maxf(0.0, float(fen.y - sur.end.y)) * k, maxf(0.0, sur.position.x) * k)

# AIMPIRE_ZONE_SURE="haut,droite,bas,gauche" (dp, captures sur le Mac), sinon la zone sûre d'Android (zéro sur le Mac).
func _calcul_retraits() -> Vector4:
	var forcee := OS.get_environment("AIMPIRE_ZONE_SURE").split(",")
	if forcee.size() == 4:
		return Vector4(float(forcee[0]), float(forcee[1]), float(forcee[2]), float(forcee[3]))
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var fen := main.get_window().size
	if fen.x <= 0:
		return Vector4.ZERO
	var k := main.get_viewport().get_visible_rect().size.x / float(fen.x)
	return calcul_retraits(DisplayServer.get_display_safe_area(), fen, k)

# Taille de la fenêtre changée (rotation, multi-fenêtre) : échelle de l'interface, zones sûres, toute la mise en page.
func _sur_taille() -> void:
	var e := _calcul_echelle()
	if absf(e - echelle) > 0.01:
		echelle = e
		main.get_window().content_scale_factor = echelle
	retraits = _calcul_retraits()
	var vue := main.get_viewport().get_visible_rect().size
	ui.mise_en_page(retraits, vue)
	bandeau.position = Vector2(ui.L, ui.T + 100.0)
	bandeau.size = Vector2(vue.x - ui.L - ui.R, 0)
	bandeau.custom_minimum_size.x = vue.x - ui.L - ui.R
	# largeur du texte connue d'avance : sinon, avant la première mise en page, le texte replié se mesure à 0 de large et
	# le bandeau se croit haut de 600 dp (cadrage d'un village et toast placés trop bas)
	_bandeau_texte.custom_minimum_size.x = maxf(0.0, vue.x - ui.L - ui.R - 20.0)
	_placer_ecran()

static func _duree(s: int) -> String:
	if s < 3600:
		return "%d min" % maxi(1, s / 60)
	if s < 86400:
		return "%d h %02d min" % [s / 3600, (s % 3600) / 60]
	return ("%d day" if s < 2 * 86400 else "%d days") % (s / 86400)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:   # arrière-plan : on coupe le long-poll (pas de notifications en v1)
			_pause = true
			_http.cancel_request()
			_en_cours = false
			_noter_dernier_ts(true)
		NOTIFICATION_APPLICATION_RESUMED:
			_pause = false
			_relance = 0.0
			_contact_ms = 0   # « Mise à jour… » jusqu'à la première réponse, au lieu d'accuser le Mac
			_toucher_ms = Time.get_ticks_msec()
		NOTIFICATION_WM_GO_BACK_REQUEST:   # geste retour d'Android (quit_on_go_back est désactivé)
			# la même notification arrive deux fois pour un seul geste (par la fenêtre et par l'arbre) : sans ce filtre, le
			# second retour fermait aussitôt ce que le premier venait de dégager, et « Back again to quit » quittait l'app
			var t := Time.get_ticks_msec()
			if Engine.get_process_frames() != _retour_image and t - _retour_t > 250:
				_retour_image = Engine.get_process_frames()
				_retour_t = t
				retour(true)
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE:
			_noter_dernier_ts(true)

# ---------------------------------------------------------------------------
# Rapport, journal, digest : depuis les annexes de l'enveloppe (hud._fetch)
# ---------------------------------------------------------------------------

# Dictionary comme la réponse de la route locale, ou String qui explique pourquoi c'est indisponible.
func annexe(kind: String, path: String) -> Variant:
	if annexes.is_empty():
		return "Nothing received from the Mac yet"
	match kind:
		"digest":
			var d = annexes.get("digest")
			return d if d is Dictionary else "Unavailable in discreet mode"
		"rapport":
			var r = annexes.get("rapport")
			if not (r is Dictionary):
				return "Report unavailable in discreet mode"
			var periode := "semaine" if path.contains("semaine") else "jour"
			return {"texte": String(r.get(periode, ""))}
		"journal":
			var j = annexes.get("journal")
			if not (j is Array):
				return "Journal unavailable in discreet mode"
			return {"entrees": j}
	return "Unavailable from the phone"

# ---------------------------------------------------------------------------
# Commandes vers le Mac (docs/SYNC.md §6)
# ---------------------------------------------------------------------------

# Route locale (celle que hud._post utiliserait sur le Mac) vers commande : {"action": …, champs…} ou {} si interdite.
static func commande_de_route(path: String) -> Dictionary:
	var morceaux := path.split("?", true, 1)
	var p := {}
	if morceaux.size() > 1:
		for kv in morceaux[1].split("&", false):
			var paire := kv.split("=", true, 1)
			p[paire[0]] = paire[1].uri_decode() if paire.size() > 1 else ""
	match morceaux[0]:
		"/reclamer":
			if String(p.get("village", "")) != "":
				return {"action": "reclamer", "village": String(p.village)}
		"/construire":
			if String(p.get("id", "")) != "":
				return {"action": "construire", "id": String(p.id)}
		"/reglage":
			if p.get("cle", "") == "privacy" and p.get("val", "") in ["normal", "flou"]:
				return {"action": "reglage", "cle": "privacy", "val": String(p.val)}
	return {}

# Remplace hud._post en mode téléphone.
func poster(path: String) -> void:
	if path.begins_with("/vu"):   # « vu » ne concerne que l'écran du Mac
		return
	var c := commande_de_route(path)
	if c.is_empty():
		main.hud.show_toast("Mac only")
		return
	envoyer(c)

func _libelle(c: Dictionary) -> String:
	match String(c.action):
		"reclamer":
			return "reward claimed"
		"construire":
			return "monument built"
		"reglage":
			return "discreet mode " + ("on" if c.get("val") == "flou" else "off")
	return String(c.action)

# Chiffre {"type": "cmd", ts, nonce, action, champs…} et le met dans la file d'envoi.
func envoyer(c: Dictionary) -> void:
	if cles.is_empty():
		main.hud.show_toast("No sync chain: join your Empire first")
		HAPTIQUE.reject()
		return
	if mac_silencieux():   # personne pour l'appliquer : mieux vaut le dire tout de suite qu'attendre 30 s
		main.hud.show_toast("Mac offline: command not sent")
		HAPTIQUE.reject()
		return
	var nonce := SC.octets_aleatoires(16).hex_encode()
	var cmd := {"type": "cmd", "ts": _maintenant_ms(), "nonce": nonce}
	cmd.merge(c)
	_file_cmd.append({"blob": SC.encrypt_json(cles, cmd), "nonce": nonce, "cree": Time.get_ticks_msec()})
	_attendues[nonce] = {"t": Time.get_ticks_msec(), "texte": _libelle(c)}
	main.hud.show_toast("Sent to the Mac…", 2500)

# Retire une commande pas encore déposée sur le relais (et coupe son envoi s'il est en cours).
func _abandonner(nonce: String) -> void:
	for i in range(_file_cmd.size() - 1, -1, -1):
		if String(_file_cmd[i].nonce) == nonce:
			if i == 0 and _cmd_en_cours:
				_http_cmd.cancel_request()
				_cmd_en_cours = false
			_file_cmd.remove_at(i)

func _envoyer_suivante() -> void:
	# Une commande restée en file plus d'une minute (réseau coupé) ne part plus : appliquée bien plus tard, elle
	# changerait l'Empire « tout seul », sans retour visible.
	while not _file_cmd.is_empty() and Time.get_ticks_msec() - int(_file_cmd[0].cree) > AGE_MAX_CMD_MS:
		var vieille: Dictionary = _file_cmd.pop_front()
		if _attendues.has(String(vieille.nonce)):
			_attendues.erase(String(vieille.nonce))
			main.hud.show_toast("Command dropped: relay unreachable")
			HAPTIQUE.reject()
	if _file_cmd.is_empty():
		return
	var c: Dictionary = _file_cmd[0]
	var h := PackedStringArray(["X-AImpire-Id: " + id, "Content-Type: application/octet-stream"])
	var blob: PackedByteArray = c.blob
	if _http_cmd.request_raw(relais + "cmd", h, HTTPClient.METHOD_POST, blob) == OK:
		_cmd_en_cours = true
	else:
		_file_cmd.pop_front()

func _sur_cmd(resultat: int, code: int, _entetes: PackedStringArray, _corps: PackedByteArray) -> void:
	_cmd_en_cours = false
	if _file_cmd.is_empty():
		return
	if resultat != HTTPRequest.RESULT_SUCCESS:   # réseau : on retente dans 3 s (la commande garde son nonce et son ts)
		_cmd_relance = _maintenant() + 3.0
		return
	var c: Dictionary = _file_cmd.pop_front()
	match code:
		200, 202:
			pass
		429:   # file pleine ou débit : on la remet en tête et on patiente
			_file_cmd.push_front(c)
			_cmd_relance = _maintenant() + 10.0
		404:
			_attendues.erase(String(c.nonce))
			main.hud.show_toast("The Mac has not published anything yet: command not sent")
			HAPTIQUE.reject()
		_:
			_attendues.erase(String(c.nonce))
			main.hud.show_toast("Command refused by the relay (%d)" % code)
			HAPTIQUE.reject()

# Le Mac renvoie le résultat des dernières commandes dans annexes.commandes : on les rapproche par nonce.
func _verifier_commandes() -> void:
	if _attendues.is_empty():
		return
	var faites = annexes.get("commandes", [])
	if faites is Array:
		for f in faites:
			if not (f is Dictionary):
				continue
			var nonce := String(f.get("nonce", ""))
			if _attendues.has(nonce):
				var texte := String(_attendues[nonce].texte)
				_attendues.erase(nonce)
				if f.get("ok", false):
					main.hud.show_toast("Applied by the Mac: " + texte)
					HAPTIQUE.confirm()
				else:
					main.hud.show_toast("Refused by the Mac: " + String(f.get("erreur", texte)))
					HAPTIQUE.reject()
	for nonce in _attendues.keys():
		if Time.get_ticks_msec() - int(_attendues[nonce].t) > DELAI_REPONSE_MS:
			_attendues.erase(nonce)
			_abandonner(String(nonce))   # pas encore partie : elle ne partira plus
			main.hud.show_toast("The Mac did not answer")
			HAPTIQUE.reject()

# ---------------------------------------------------------------------------
# Bandeau et geste retour
# ---------------------------------------------------------------------------

# Bandeau sous la ligne d'état (T + 100), toute la largeur entre les marges : le texte passe à la ligne et le bandeau
# grandit vers le bas. Il ne prend aucun toucher.
func _construire_bandeau() -> void:
	bandeau = PanelContainer.new()
	bandeau.theme = main.ui.theme
	var fond := StyleBoxFlat.new()
	fond.bg_color = UI.MIEL   # alerte : miel plein, texte encre (6,9:1)
	fond.set_corner_radius_all(int(UI.RAYON_BOUTON))
	fond.content_margin_left = 14
	fond.content_margin_right = 14
	fond.content_margin_top = 10
	fond.content_margin_bottom = 10
	bandeau.add_theme_stylebox_override("panel", fond)
	bandeau.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bandeau_texte = Label.new()
	_bandeau_texte.add_theme_font_size_override("font_size", UI.POLICE)
	_bandeau_texte.add_theme_color_override("font_color", UI.ENCRE)
	_bandeau_texte.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bandeau.add_child(_bandeau_texte)
	bandeau.visible = false
	couche.add_child(bandeau)

# Geste retour d'Android et Échap : la page About, puis l'écran d'appairage, puis la feuille ouverte (fermée, pas ramenée
# à l'aperçu), puis la sélection ; rien d'ouvert, `quitter` demande un second geste pour quitter l'app.
func retour(quitter: bool) -> void:
	if main.about and main.about.retour():
		return
	if ecran.visible:
		if not secret.is_empty():
			ecran.visible = false
			ui.barre.visible = true
		elif quitter:
			_quitter()
		return
	if ui.retour():
		return
	if main.selected != "":
		main.selected = ""
		main.selected_building = ""
	elif quitter:
		_quitter()

# Rien d'ouvert : un glissé depuis le bord (pour déplacer la caméra) déclenche vite le retour d'Android. On demande donc
# un second geste dans les 2 s avant de quitter.
func _quitter() -> void:
	if Time.get_ticks_msec() - _retour_ms < 2000:
		_noter_dernier_ts(true)
		get_tree().quit()
		return
	_retour_ms = Time.get_ticks_msec()
	main.hud.show_toast("Back again to quit", 2000)

# ---------------------------------------------------------------------------
# Écran d'appairage : coller le lien ou taper les 12 mots
# ---------------------------------------------------------------------------

func _titre(texte: String, taille: int) -> Label:
	var l := Label.new()
	l.text = texte
	l.add_theme_font_override("font", main.ui.big_title_font if taille >= 26 else main.ui.title_font)
	l.add_theme_font_size_override("font_size", taille)
	l.add_theme_color_override("font_color", UI.TEXTE if taille >= 26 else UI.ACCENT_TEXTE)
	return l

func _texte(texte: String) -> Label:
	var l := Label.new()
	l.text = texte
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 200
	return l

# Écran d'appairage, pleine page sur la couche 2 : un cadre aux marges de l'écran (zone sûre comprise) qui défile, les
# suggestions de mots qui passent à la ligne, une marge en bas de la hauteur du clavier virtuel.
func _construire_ecran() -> void:
	ecran = Control.new()
	ecran.theme = main.ui.theme
	ecran.set_anchors_preset(Control.PRESET_FULL_RECT)
	var fond := ColorRect.new()
	fond.color = UI.FOND
	fond.set_anchors_preset(Control.PRESET_FULL_RECT)
	ecran.add_child(fond)
	_cadre_ecran = PanelContainer.new()
	_cadre_ecran.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = UI.FOND
	style.set_corner_radius_all(int(UI.RAYON_FEUILLE))
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 8
	_cadre_ecran.add_theme_stylebox_override("panel", style)
	ecran.add_child(_cadre_ecran)
	_defile_ecran = ScrollContainer.new()
	_defile_ecran.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_defile_ecran.scroll_deadzone = 8
	_cadre_ecran.add_child(_defile_ecran)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)
	_defile_ecran.add_child(col)
	var titre := _titre("Join your Empire", 30)
	titre.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(titre)
	col.add_child(_texte("On the Mac: Esc, then \"Create a sync chain\". Paste the link it shows, or type its 12 words."))

	col.add_child(_titre("The link", 18))
	var ligne := HBoxContainer.new()
	_champ_lien = LineEdit.new()
	_champ_lien.placeholder_text = "https://aimpire.sidali.dev/#s=…"
	_champ_lien.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_champ_lien.custom_minimum_size = Vector2(120, 48)
	_champ_lien.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	_champ_lien.add_theme_font_size_override("font_size", UI.POLICE)
	_champ_lien.text_submitted.connect(func(_t): _rejoindre())
	_champ_lien.focus_entered.connect(func(): _montrer_champ(_champ_lien))
	ligne.add_child(_champ_lien)
	var coller := Button.new()
	coller.text = "Paste"
	coller.custom_minimum_size = Vector2(88, 48)
	coller.add_theme_font_size_override("font_size", UI.POLICE)
	coller.pressed.connect(func():
		_champ_lien.text = DisplayServer.clipboard_get().strip_edges()
		_erreur_appairage.text = "")
	ligne.add_child(coller)
	col.add_child(ligne)

	col.add_child(_titre("Or the 12 words", 18))
	_champ_mots = LineEdit.new()
	_champ_mots.placeholder_text = "abandon amount liar …"
	_champ_mots.custom_minimum_size = Vector2(120, 48)
	_champ_mots.add_theme_font_size_override("font_size", UI.POLICE)
	_champ_mots.text_changed.connect(_sur_mots)
	_champ_mots.text_submitted.connect(func(_t): _rejoindre())
	_champ_mots.focus_entered.connect(func(): _montrer_champ(_champ_mots))
	col.add_child(_champ_mots)
	_suggestions = HFlowContainer.new()
	_suggestions.add_theme_constant_override("h_separation", 6)
	_suggestions.add_theme_constant_override("v_separation", 6)
	col.add_child(_suggestions)
	_apercu_mots = RichTextLabel.new()
	_apercu_mots.bbcode_enabled = true
	_apercu_mots.fit_content = true
	_apercu_mots.scroll_active = false
	_apercu_mots.mouse_filter = Control.MOUSE_FILTER_PASS   # le doigt qui glisse dessus fait défiler l'écran
	_apercu_mots.add_theme_font_size_override("normal_font_size", 16)
	col.add_child(_apercu_mots)

	_bouton_relais = Button.new()
	_bouton_relais.flat = true
	_bouton_relais.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_bouton_relais.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bouton_relais.custom_minimum_size.y = 48
	_bouton_relais.add_theme_font_size_override("font_size", 16)
	UI.lien(_bouton_relais)
	col.add_child(_bouton_relais)
	# Relais imposé : vide = celui du lien (ou le relais par défaut avec les mots). Rempli, il remplace les deux : utile
	# quand le lien du Mac désigne un relais local (http://127.0.0.1:7701/) que le téléphone joint par une autre adresse
	# (http://10.0.2.2:7701/ depuis l'émulateur Android, l'IP du Mac sur le Wi-Fi depuis un vrai téléphone).
	_champ_relais = LineEdit.new()
	_champ_relais.text = OS.get_environment("AIMPIRE_RELAIS")
	_champ_relais.placeholder_text = "empty: the link's relay"
	_champ_relais.custom_minimum_size = Vector2(120, 48)
	_champ_relais.add_theme_font_size_override("font_size", UI.POLICE)
	_champ_relais.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	_champ_relais.visible = false
	_champ_relais.text_changed.connect(func(_t): _maj_bouton_relais())
	_champ_relais.focus_entered.connect(func(): _montrer_champ(_champ_relais))
	col.add_child(_champ_relais)
	_bouton_relais.pressed.connect(func():
		_champ_relais.visible = not _champ_relais.visible
		_maj_bouton_relais())
	_maj_bouton_relais()

	var rejoindre: Button = main.ui.bouton("Join", true)
	rejoindre.custom_minimum_size.y = 56
	rejoindre.add_theme_font_override("font", main.ui.title_font)
	rejoindre.add_theme_font_size_override("font_size", 22)
	rejoindre.pressed.connect(_rejoindre)
	col.add_child(rejoindre)
	_erreur_appairage = Label.new()
	_erreur_appairage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_erreur_appairage.add_theme_font_size_override("font_size", UI.POLICE)
	_erreur_appairage.add_theme_color_override("font_color", UI.DANGER_TEXTE)
	col.add_child(_erreur_appairage)
	col.add_child(_texte("The relay only sees encrypted data: only this phone and your Mac know the key."))
	var apropos := Button.new()
	apropos.text = "About AImpire"
	apropos.flat = true
	apropos.alignment = HORIZONTAL_ALIGNMENT_LEFT
	apropos.custom_minimum_size.y = 48
	apropos.add_theme_font_size_override("font_size", 16)
	UI.lien(apropos)
	apropos.pressed.connect(func(): main.about.open())
	col.add_child(apropos)
	_marge_clavier = Control.new()
	col.add_child(_marge_clavier)
	couche.add_child(ecran)
	_placer_ecran()

# Cadre de l'appairage aux marges de l'écran ; marge du bas agrandie de la hauteur du clavier virtuel.
func _placer_ecran() -> void:
	if _cadre_ecran == null or ui == null:
		return
	var vue := main.get_viewport().get_visible_rect().size
	var largeur := minf(vue.x - ui.L - ui.R, 640.0)
	var gauche := maxf(ui.L, floorf((vue.x - largeur) / 2.0))
	_cadre_ecran.offset_left = gauche
	_cadre_ecran.offset_right = -(vue.x - gauche - largeur)
	_cadre_ecran.offset_top = ui.T
	_cadre_ecran.offset_bottom = -ui.B

# Hauteur du clavier virtuel (dp) : l'écran d'appairage garde le champ saisi au-dessus.
func hauteur_clavier() -> float:
	var h := DisplayServer.virtual_keyboard_get_height()
	var fen := main.get_window().size
	if h <= 0 or fen.x <= 0:
		return 0.0
	return h * main.get_viewport().get_visible_rect().size.x / float(fen.x)

func _montrer_champ(champ: Control) -> void:
	await get_tree().create_timer(0.4).timeout   # le clavier met un moment à s'ouvrir
	if not is_instance_valid(champ) or not ecran.visible:
		return
	_marge_clavier.custom_minimum_size.y = maxf(0.0, hauteur_clavier() - ui.B)
	await get_tree().process_frame
	_defile_ecran.ensure_control_visible(champ)

func _maj_bouton_relais() -> void:
	var t := _champ_relais.text.strip_edges()
	var r := normaliser_relais(t)
	var quoi := "the link's, otherwise " + SC.RELAIS_PAR_DEFAUT
	if t != "":
		quoi = (r + ("  (http: local network, not encrypted in transit)" if relais_en_clair(r) else "")) if r != "" else "invalid address"
	var debut := "Custom relay" if t != "" else "Relay"
	_bouton_relais.text = "%s: %s  %s" % [debut, quoi, "▴" if _champ_relais.visible else "change ▾"]

# Relais saisi à la main (remplace celui du lien) : "" si le champ est vide, "invalide" s'il ne convient pas.
func _relais_impose() -> String:
	var t := _champ_relais.text.strip_edges()
	if t == "":
		return ""
	var r := normaliser_relais(t)
	return r if r != "" else "invalide"

# Saisie des mots : aperçu numéroté (mot inconnu en rouge) et auto-complétion dès 3 lettres.
func _sur_mots(texte: String) -> void:
	_erreur_appairage.text = ""
	var liste := SC.mots()
	var saisis := texte.strip_edges().to_lower().split(" ", false)
	var apercu := PackedStringArray()
	for i in saisis.size():
		var m := saisis[i]
		var connu := liste.has(m)
		apercu.append("[color=%s]%d[/color] [color=%s]%s[/color]" % [UI.hex(UI.TEXTE_DOUX), i + 1, UI.hex(UI.TEXTE if connu else UI.DANGER_TEXTE), m])
	_apercu_mots.text = ("  ".join(apercu) + "   [color=%s](%d / 12)[/color]" % [UI.hex(UI.TEXTE_DOUX), saisis.size()]) if saisis.size() else ""
	for c in _suggestions.get_children():
		c.queue_free()
	var debut := "" if texte.ends_with(" ") or saisis.is_empty() else saisis[saisis.size() - 1]
	if debut.length() < 3 or liste.has(debut):
		return
	var n := 0
	for m in liste:
		if m.begins_with(debut):
			var b := Button.new()
			b.text = m
			b.custom_minimum_size = Vector2(80, 48)
			b.add_theme_font_size_override("font_size", UI.POLICE)
			b.focus_mode = Control.FOCUS_NONE
			b.pressed.connect(_completer.bind(m))
			_suggestions.add_child(b)
			n += 1
			if n >= 5:
				break

func _completer(mot: String) -> void:
	var t := _champ_mots.text
	var coupe := t.rstrip(" ").rfind(" ")
	_champ_mots.text = (t.substr(0, coupe + 1) if coupe >= 0 else "") + mot + " "
	_champ_mots.caret_column = _champ_mots.text.length()
	_champ_mots.grab_focus()
	_sur_mots(_champ_mots.text)

func _rejoindre() -> void:
	var lien := _champ_lien.text.strip_edges()
	var r: Dictionary
	var choisi := ""
	var impose := _relais_impose()
	if impose == "invalide":
		_erreur_appairage.text = "Invalid relay: https://host/ (http only on a local network), without # or ?, not the pairing link"
		return
	if lien != "":
		r = SC.from_link(lien)
		if r.ok:
			choisi = impose if impose != "" else normaliser_relais(String(r.relais))
			if choisi == "":
				_erreur_appairage.text = "The link points to a refused relay (http outside a local network): set an https relay"
				return
	elif _champ_mots.text.strip_edges() != "":
		r = SC.from_words(_champ_mots.text)
		choisi = impose if impose != "" else SC.RELAIS_PAR_DEFAUT
	else:
		r = {"ok": false, "erreur": "Paste the link or type the 12 words"}
	if not r.ok:
		_erreur_appairage.text = String(r.erreur)
		return
	var s: PackedByteArray = r.secret
	_adopter(s, choisi)
	_enregistrer_chaine()
	ecran.visible = false
	ui.barre.visible = true
	_champ_lien.text = ""
	_champ_mots.text = ""
	_apercu_mots.text = ""
	_reconstruire_reglages()   # la section « Téléphone » affiche la chaîne et « Oublier cette chaîne »
	main.hud.show_toast("Joined sync chain %s" % id.left(6))
	print("pairing: sync chain %s, relay %s" % [id.left(6), relais])

# ---------------------------------------------------------------------------
# Réglages du téléphone (ajoutés au menu Échap par settings.gd)
# ---------------------------------------------------------------------------

func _charger_reglages() -> void:
	journal_fps = OS.is_debug_build() or OS.get_environment("AIMPIRE_FPS") != ""
	var cfg := ConfigFile.new()
	if cfg.load(CHEMIN_REGLAGES) == OK:
		# l'ancienne clé « fps » (0.6.0) est ignorée : un 30 enregistré n'enferme personne en « Battery saver »
		fluidite = "battery" if String(cfg.get_value("telephone", "fluidite", "adaptive")) == "battery" else "adaptive"
		journal_fps = bool(cfg.get_value("telephone", "journal_fps", journal_fps))

func _enregistrer_reglages() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("telephone", "fluidite", fluidite)
	cfg.set_value("telephone", "journal_fps", journal_fps)
	cfg.save(CHEMIN_REGLAGES)

# Une ligne lisible avec « adb logcat -s godot » toutes les 2 s : images par seconde, plafond, état de la caméra, durée
# médiane et 95e centile des images, images de plus de 25 ms, la plus longue, appels de dessin, pilote, fenêtre.
#   FPS 60 cap 60 cam PINCH p50 16.6 p95 17.2 over25 0 max 18.9 draw 130 prim 210000 driver opengl3 win (1080, 2340)
func _journaliser_fps() -> void:
	var d := _durees.slice(0, _n_durees)
	d.sort()
	var n := d.size()
	var p50 := d[n / 2] if n else 0.0
	var p95 := d[mini(n - 1, int(n * 0.95))] if n else 0.0
	var lentes := 0
	for x in d:
		if x > 25.0:
			lentes += 1
	var etats := PackedStringArray()
	for e in _etats_vus:
		etats.append(main.rig.NOMS_ETATS[e])
	if etats.is_empty() and main.rig:
		etats.append(main.rig.nom_etat())
	print("FPS %d cap %d cam %s p50 %.1f p95 %.1f over25 %d max %.1f draw %d prim %d quality %s driver %s win %s" % [
		Engine.get_frames_per_second(), Engine.max_fps, "+".join(etats), p50, p95, lentes, d[n - 1] if n else 0.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), str(main.world.quality),
		RenderingServer.get_current_rendering_driver_name(), str(main.get_window().size)])
	_n_durees = 0
	_etats_vus.clear()

# Réglages sur le téléphone : le panneau du Mac n'est jamais montré, sa colonne est logée dans la feuille Settings.
func habiller_menu(menu: PanelContainer, col: VBoxContainer) -> void:
	menu.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.size = Vector2.ZERO
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col_reglages = col
	if ui:
		ui.reglages_reconstruits(col)

func _reconstruire_reglages() -> void:
	var ouvert_avant: bool = main.settings.menu.visible
	main.settings.menu.queue_free()
	main.settings.build_menu(main.settings._layer)
	main.settings.menu.visible = ouvert_avant

# --- Éléments de la feuille Settings (appelés par settings.gd dans l'ordre de docs/MOBILE-PORTRAIT.md §3.6) ---

# Mode discret en tête : un interrupteur qui montre s'il est actif (le Mac applique, l'état suivant revient flouté).
func reglage_discret(col: VBoxContainer) -> void:
	_interrupteur_discret = main.ui.interrupteur("Discreet mode (hides names and titles)", main.discret, func(on):
		_discret_touche_ms = Time.get_ticks_msec()
		main.discret = on
		main.hud._post("/reglage?cle=privacy&val=" + ("flou" if on else "normal")))
	col.add_child(_interrupteur_discret)

# L'interrupteur suit le mode discret de l'état reçu (changé sur le Mac, ou commande refusée), sauf dans les 15 s qui
# suivent un toucher : le temps que le Mac applique la commande et republie.
func _maj_interrupteur_discret() -> void:
	if is_instance_valid(_interrupteur_discret) and Time.get_ticks_msec() - _discret_touche_ms > 15000:
		UI.regler_interrupteur(_interrupteur_discret, main.discret)

# Fluidité : « Adaptive » (60 images/s pendant l'interaction, 30 au repos) ou « Battery saver » (30, puis 15).
func reglage_fluidite(col: VBoxContainer) -> void:
	col.add_child(main.ui.texte("Smoothness"))
	col.add_child(main.ui.segmente(["Adaptive", "Battery saver"], 1 if fluidite == "battery" else 0, func(i):
		fluidite = "battery" if i == 1 else "adaptive"
		_enregistrer_reglages()
		main.power._apply(main.power.state)))

func reglage_moteur(col: VBoxContainer) -> void:
	col.add_child(main.ui.texte("Renderer (applied at the next launch)"))
	col.add_child(main.ui.segmente(["OpenGL", "Vulkan"], 1 if moteur_vulkan() else 0, func(i):
		choisir_moteur(i == 1)
		main.hud.show_toast("Renderer changed: restart the app to apply it")))
	col.add_child(main.ui.texte("Current: %s (%s)" % [RenderingServer.get_current_rendering_driver_name(), RenderingServer.get_video_adapter_name()], UI.POLICE_META, UI.TEXTE_DOUX))

# Section « Phone » : chaîne et relais, mesure des FPS, oublier la chaîne.
func ajoute_reglages(col: VBoxContainer) -> void:
	col.add_child(main.ui.intertitre("Phone", 20))
	col.add_child(_texte(("Sync chain %s · relay %s%s" % [id.left(6), relais, "  (http: local network only, not encrypted in transit)" if relais_en_clair(relais) else ""]) if not secret.is_empty() else "No sync chain"))
	col.add_child(main.ui.interrupteur("Measure FPS (Android log)", journal_fps, func(on):
		journal_fps = on
		_mesure = 0.0
		_n_durees = 0
		_enregistrer_reglages()))
	if not secret.is_empty():
		var oublier: Button = main.ui.bouton("Forget this sync chain")
		oublier.pressed.connect(func():
			if not _oubli_confirme:
				_oubli_confirme = true
				oublier.text = "Confirm: forget sync chain %s" % id.left(6)
				return
			_oublier())
		col.add_child(oublier)

func _oublier() -> void:
	var chemin := chemin_chaine()
	if FileAccess.file_exists(chemin):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(chemin))
	get_tree().reload_current_scene()   # repart de zéro : écran d'appairage, monde vide

# AIMPIRE_GESTE, ou l'argument --geste= (téléphone : am start … --esa command_line_params).
static func _geste_demande() -> String:
	var g := OS.get_environment("AIMPIRE_GESTE")
	if g != "":
		return g
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--geste="):
			return a.substr(8)
	return ""
