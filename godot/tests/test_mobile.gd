extends SceneTree
# Fonctions pures de mobile.gd : routes du HUD vers commandes (docs/SYNC.md §6), adresses de relais, annexes, et
# aller-retour d'une commande chiffrée ; échelle de l'interface, textes 3D, zones sûres, plafond d'images, nombres courts
# (docs/MOBILE-PORTRAIT.md). Lancer : godot --headless --path godot -s tests/test_mobile.gd

const M := preload("res://mobile.gd")
const SC := preload("res://sync_crypto.gd")
const POWER := preload("res://power.gd")
const HUD := preload("res://hud.gd")
const PHONE := preload("res://phone_ui.gd")

var echecs := 0
var total := 0

func egal(cas: String, obtenu: Variant, attendu: Variant) -> void:
	total += 1
	if str(obtenu) != str(attendu):
		echecs += 1
		printerr("ÉCHEC ", cas, "  obtenu ", str(obtenu), ", attendu ", str(attendu))

func _initialize() -> void:
	# Échelle : une unité d'interface = un dp dans les deux orientations (§3.2)
	egal("échelle portrait 1080 × 2340", snappedf(M.calcul_echelle(2.625, Vector2i(1080, 2340)), 0.001), 3.111)
	egal("échelle paysage 2340 × 1080 (inchangée)", snappedf(M.calcul_echelle(2.625, Vector2i(2340, 1080)), 0.001), 1.75)
	egal("vue portrait en dp", (Vector2(1080, 2340) / (0.84375 * M.calcul_echelle(2.625, Vector2i(1080, 2340)))).round(), Vector2(411, 891))
	egal("capture Mac 540 × 1170 à 1,3125", (Vector2(540, 1170) / (540.0 / 1280.0 * M.calcul_echelle(1.3125, Vector2i(540, 1170)))).round(), Vector2(411, 891))
	egal("échelle bornée", [M.calcul_echelle(20.0, Vector2i(400, 800)), M.calcul_echelle(0.1, Vector2i(4000, 4000))], [6.0, 0.5])
	egal("textes 3D portrait", snappedf(M.echelle_textes_3d(2.625, Vector2i(1080, 2340)), 0.01), 1.36)
	egal("textes 3D paysage (inchangés)", snappedf(M.echelle_textes_3d(2.625, Vector2i(2340, 1080)), 0.01), 1.75)
	# Zones sûres sur les quatre bords (haut, droite, bas, gauche), en dp
	var k := 1.0 / 2.625
	egal("poinçon en haut", M.calcul_retraits(Rect2i(0, 126, 1080, 2214), Vector2i(1080, 2340), k), Vector4(48, 0, 0, 0))
	egal("barre de gestes en bas", M.calcul_retraits(Rect2i(0, 0, 1080, 2277), Vector2i(1080, 2340), k), Vector4(0, 0, 24, 0))
	egal("poinçon à gauche (paysage)", M.calcul_retraits(Rect2i(105, 0, 2235, 1080), Vector2i(2340, 1080), k), Vector4(0, 0, 0, 40))
	egal("zone sûre vide", M.calcul_retraits(Rect2i(), Vector2i(1080, 2340), k), Vector4.ZERO)
	# Plafond d'images du téléphone (§3.8)
	egal("interaction : 60", [POWER.plafond_telephone(true, "adaptive", false), POWER.plafond_telephone(true, "battery", true)], [60, 60])
	egal("repos Adaptive : 30", [POWER.plafond_telephone(false, "adaptive", false), POWER.plafond_telephone(false, "adaptive", true)], [30, 30])
	egal("Battery saver : 30 puis 15", [POWER.plafond_telephone(false, "battery", false), POWER.plafond_telephone(false, "battery", true)], [30, 15])
	# Nombres courts de la barre des ressources : 4 caractères au plus, jamais arrondis vers le haut
	egal("nombres courts", [HUD.court(0), HUD.court(999), HUD.court(1000), HUD.court(1250), HUD.court(9999), HUD.court(12345),
		HUD.court(999999), HUD.court(1234567), HUD.court(98765432)], ["0", "999", "1.0k", "1.2k", "9.9k", "12k", "999k", "1.2M", "98M"])
	for n in [0, 7, 999, 1000, 9999, 10000, 99999, 999999, 1000000, 9999999, 10000000, 999999999]:
		egal("4 caractères : %d" % n, HUD.court(n).length() <= 4, true)
	egal("activité d'un village", [PHONE.activite(3, 0.0), PHONE.activite(0, 0.2), PHONE.activite(0, 4.6)], ["3 active", "resting", "asleep 4 d"])

	# Routes autorisées depuis le téléphone, avec décodage des paramètres
	egal("réclamer", M.commande_de_route("/reclamer?village=%2Fsrv%2Fdemo%2Fharbor"), {"action": "reclamer", "village": "/srv/demo/harbor"})
	egal("construire", M.commande_de_route("/construire?id=colisee"), {"action": "construire", "id": "colisee"})
	egal("mode discret", M.commande_de_route("/reglage?cle=privacy&val=flou"), {"action": "reglage", "cle": "privacy", "val": "flou"})
	# Routes réservées au Mac ou mal formées : refusées
	for r in ["/action?kind=pr&session=x", "/fete", "/objectif?village=a&texte=b", "/vu", "/reglage?cle=privacy&val=rien",
			"/reglage?cle=autre&val=flou", "/reclamer", "/construire?id=", ""]:
		egal("refusé : " + r, M.commande_de_route(r), {})

	# Adresses de relais
	egal("relais https", M.normaliser_relais(" https://aimpire.sidali.dev "), "https://aimpire.sidali.dev/")
	egal("relais local", M.normaliser_relais("http://127.0.0.1:8787"), "http://127.0.0.1:8787/")
	egal("relais sans schéma", M.normaliser_relais("aimpire.sidali.dev"), "")
	egal("relais ftp", M.normaliser_relais("ftp://x.y/"), "")
	egal("lien d'appairage collé comme relais", M.normaliser_relais("https://aimpire.sidali.dev/#s=AAECAwQFBgcICQoLDA0ODw"), "")
	egal("relais avec requête", M.normaliser_relais("https://aimpire.sidali.dev/?x=1"), "")
	egal("relais avec identifiants", M.normaliser_relais("https://a:b@aimpire.sidali.dev/"), "")
	egal("http hors réseau local", M.normaliser_relais("http://exemple.fr/"), "")
	egal("http émulateur", M.normaliser_relais("http://10.0.2.2:7701"), "http://10.0.2.2:7701/")
	egal("http Wi-Fi", M.normaliser_relais("http://192.168.1.20:7701/"), "http://192.168.1.20:7701/")
	egal("http 172.20", M.normaliser_relais("http://172.20.0.3:7701/"), "http://172.20.0.3:7701/")
	egal("http 172.32 refusé", M.normaliser_relais("http://172.32.0.1/"), "")
	egal("chemin gardé, casse de l'hôte", M.normaliser_relais("https://Exemple.FR/relais"), "https://exemple.fr/relais/")
	egal("relais en clair", [M.relais_en_clair("http://10.0.2.2:7701/"), M.relais_en_clair("https://x.fr/")], [true, false])

	# Annexes : rapport par période, journal, mode discret
	var m: Node = M.new()
	egal("rien reçu", m.annexe("rapport", "/rapport?periode=jour") is String, true)
	m.annexes = {"rapport": {"jour": "J", "semaine": "S"}, "journal": [{"t": 1, "text": "a"}], "digest": {"since": 0}, "commandes": []}
	egal("rapport du jour", m.annexe("rapport", "/rapport?periode=jour"), {"texte": "J"})
	egal("rapport de la semaine", m.annexe("rapport", "/rapport?periode=semaine"), {"texte": "S"})
	egal("journal", m.annexe("journal", "/journal"), {"entrees": [{"t": 1, "text": "a"}]})
	m.annexes = {"rapport": null, "journal": null, "digest": null, "commandes": []}
	egal("discret : rapport", m.annexe("rapport", "/rapport?periode=jour"), "Report unavailable in discreet mode")
	egal("discret : digest", m.annexe("digest", "/digest"), "Unavailable in discreet mode")
	m.free()

	# Fraîcheur : mesurée avec le ts authentifié du Mac, X-AImpire-Maj ne peut que l'aggraver
	var f: Node = M.new()
	var sf := "000102030405060708090a0b0c0d0e0f".hex_decode()
	var maintenant := int(Time.get_unix_time_from_system() * 1000.0)
	f._adopter(sf, "https://aimpire.sidali.dev/", maintenant - 10 * 60000)
	egal("téléphone pas encore à jour : pas d'accusation", f.texte_bandeau().begins_with("Updating… · Mac state from "), true)
	f._contact_ms = Time.get_ticks_msec()
	f.maj_relais = maintenant   # relais qui prétend que tout est frais
	egal("relais menteur : silence quand même", f.mac_silencieux(), true)
	egal("libellé du silence", f.texte_bandeau().begins_with("The Mac has not published for 10 min (AImpire closed"), true)
	f.dernier_ts = maintenant - 5000
	f.maj_relais = maintenant - 3 * 3600000   # relais qui dit plus vieux : on aggrave
	egal("X-AImpire-Maj aggrave", f.mac_silencieux(), true)
	f.maj_relais = 0
	egal("état récent : pas de bandeau", f.texte_bandeau(), "")
	f._erreur = "Relay unreachable, retrying…"
	egal("hors ligne : âge de l'état gardé", f.texte_bandeau().contains("Mac state from "), true)
	f._erreur = ""
	egal("heure d'hier", M.heure(maintenant - 86400000).begins_with("yesterday "), true)
	# Réponses inutiles trop rapides : 1, 2 puis 5 s
	f._rapides = 0
	for attendu in [1.0, 2.0, 5.0, 5.0]:
		var avant: float = f._maintenant()
		f._reponse_inutile(50)
		egal("attente après réponse rapide", snappedf(f._relance - avant, 0.5), attendu)
	f._reponse_inutile(24000)
	egal("vraie attente : on remet à zéro", f._rapides, 0)
	# Enveloppe : version inconnue et état plus ancien refusés sans rien afficher
	var cf: Dictionary = SC.derive_keys(sf)
	egal("état plus ancien refusé", f._recevoir(SC.encrypt_json(cf, {"type": "etat", "v": 1, "ts": maintenant - 60000, "etat": {}})), false)
	egal("version plus récente refusée", f._recevoir(SC.encrypt_json(cf, {"type": "etat", "v": 2, "ts": maintenant, "etat": {}})), false)
	egal("message de version", f._alerte, "The Mac runs a newer version: update the app")
	# dernier_ts survit à un redémarrage (chaine.cfg)
	OS.set_environment("AIMPIRE_CHAINE", "user://test-chaine.cfg")
	f.dernier_ts = 0
	f._enregistrer_chaine()
	f.dernier_ts = maintenant
	f._noter_dernier_ts(true)
	var relue_c: Dictionary = M.lire_chaine()
	egal("dernier_ts relu", int(relue_c.get("dernier_ts", 0)), maintenant)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test-chaine.cfg"))
	OS.set_environment("AIMPIRE_CHAINE", "")
	f.free()

	# Commande chiffrée comme le fait envoyer() : se relit avec les clés de la chaîne, pas avec d'autres
	var s := "000102030405060708090a0b0c0d0e0f".hex_decode()
	var cles: Dictionary = SC.derive_keys(s)
	var cmd := {"type": "cmd", "ts": 1760000000000, "nonce": "00112233445566778899aabbccddeeff"}
	cmd.merge(M.commande_de_route("/construire?id=colisee"))
	var blob := SC.encrypt_json(cles, cmd)
	var r: Dictionary = SC.decrypt_json(cles, blob)
	var relue: Dictionary = r.get("objet", {})
	egal("commande relue", [relue.get("type"), int(relue.get("ts", 0)), relue.get("nonce"), relue.get("action"), relue.get("id")],
		["cmd", 1760000000000, "00112233445566778899aabbccddeeff", "construire", "colisee"])
	egal("ts envoyé comme entier", JSON.stringify(cmd).contains("\"ts\":1760000000000,"), true)
	var autre: Dictionary = SC.derive_keys("ffffffffffffffffffffffffffffffff".hex_decode())
	egal("autre chaîne : refusée", SC.decrypt_json(autre, blob).ok, false)

	if echecs:
		printerr("%d / %d vérifications en échec" % [echecs, total])
		quit(1)
	else:
		print("mobile : %d vérifications, tout est vert" % total)
		quit(0)
