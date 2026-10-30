extends SceneTree
# Test de la section « Chaîne de sync » des réglages (sync_panel.gd), sans serveur :
#   godot --headless --path godot -s tests/test_sync_panel.gd
# Vérifie l'image du QR (zone de silence, un pixel par module), les 12 mots numérotés et la bascule créer / détail.

var _echecs := 0
var _verifs := 0

func _verifier(cond: bool, quoi: String) -> void:
	_verifs += 1
	if not cond:
		_echecs += 1
		printerr("ÉCHEC : ", quoi)

func _initialize() -> void:
	var Panneau := preload("res://sync_panel.gd")
	# Matrice factice 21 × 21 : diagonale et première ligne sombres.
	var lignes: Array = []
	for y in 21:
		var l := ""
		for x in 21:
			l += "1" if (x == y or y == 0) else "0"
		lignes.append(l)
	var qr := {"taille": 21, "modules": lignes}
	var tex: ImageTexture = Panneau.texture_qr(qr)
	_verifier(tex != null, "texture créée")
	var img := tex.get_image()
	_verifier(img.get_width() == 29 and img.get_height() == 29, "21 modules + 2 × 4 de zone de silence")
	_verifier(img.get_pixel(0, 0).r > 0.9, "zone de silence claire")
	_verifier(img.get_pixel(4, 4).r < 0.1, "module (0,0) sombre")
	_verifier(img.get_pixel(4 + 5, 4 + 5).r < 0.1, "diagonale sombre")
	_verifier(img.get_pixel(4 + 3, 4 + 5).r > 0.9, "module (3,5) clair")
	_verifier(img.get_pixel(4 + 20, 4).r < 0.1, "première ligne sombre")
	_verifier(Panneau.texture_qr({"taille": 3, "modules": ["1"]}) == null, "matrice incohérente refusée")
	_verifier(Panneau._duree(3000) == "3 s" and Panneau._duree(125000) == "2 min", "durées")
	_verifier(Panneau._taille(21504) == "21 KB" and Panneau._taille(500) == "500 B", "tailles")
	_verifier(Panneau.relais_saisi("") == "https://aimpire.sidali.dev/", "relay: empty means the official relay")
	_verifier(Panneau.relais_saisi(" https://relay.example.org ") == "https://relay.example.org/", "relay: https normalised")
	_verifier(Panneau.relais_saisi("https://Relay.example.org:8443/aimpire") == "https://relay.example.org:8443/aimpire/", "relay: port and path")
	_verifier(Panneau.relais_saisi("http://127.0.0.1:7701") == "http://127.0.0.1:7701/", "relay: http on this machine")
	for refuse in ["http://relay.example.org", "ftp://x/", "relay.example.org", "https://a@b/", "https://x/?a=1", "https://aimpire.sidali.dev/#s=AAEC", "https://.x/"]:
		_verifier(Panneau.relais_saisi(refuse) == "", "relay refused: " + refuse)

	_panneau = Panneau.new()
	root.add_child(_panneau)

# Le panneau est prêt (_ready) à la première image seulement.
var _panneau: VBoxContainer
var _fait := false

func _process(_delta: float) -> bool:
	if _fait:
		return true
	_fait = true
	var qr: Dictionary = {"taille": 21, "modules": []}
	for y in 21:
		var l := ""
		for x in 21:
			l += "1" if (x == y or y == 0) else "0"
		qr.modules.append(l)
	var p := _panneau
	_verifier(p._creer.visible and not p._detail.visible, "sans chaîne : bouton Créer seul")
	_verifier(p._relais.visible and p._champ_relais.text == "https://aimpire.sidali.dev/", "without a chain: relay field with the official relay")
	var mots := ["abandon", "amount", "liar", "amount", "expire", "adjust", "cage", "candy", "arch", "gather", "drum", "buyer"]
	p.appliquer_etat({"enabled": true, "relay": "https://aimpire.sidali.dev/", "id_court": "b054a8",
		"lien": "https://aimpire.sidali.dev/#s=AAECAwQFBgcICQoLDA0ODw", "mots": mots, "qr": qr,
		"dernier_envoi": int(Time.get_unix_time_from_system() * 1000.0) - 3000, "octets": 21504, "erreur": "", "commandes": 2})
	_verifier(not p._creer.visible and p._detail.visible, "avec chaîne : détail affiché")
	_verifier(not p._relais.visible, "with a chain: no relay field")
	_verifier(not p._secret.visible and p._afficher.visible, "secret caché par défaut")
	p.basculer_secret()
	_verifier(p._secret.visible, "secret affiché sur demande")
	p._secret_jusqua = Time.get_ticks_msec() - 1
	p._echeances()
	_verifier(not p._secret.visible, "secret recaché au bout de 60 s")
	_verifier(p._lien.text.ends_with("#s=AAECAwQFBgcICQoLDA0ODw"), "lien affiché")
	_verifier(p._mots.get_child_count() == 12, "12 mots")
	var premier: Label = p._mots.get_child(0)
	var dernier: Label = p._mots.get_child(11)
	_verifier(premier.text == "1. abandon" and dernier.text == "12. buyer", "mots numérotés dans l'ordre")
	_verifier(p._envoi.text.begins_with("Last sent ") and p._envoi.text.contains("21 KB") and p._envoi.text.contains("2 command"), "état de la publication : " + p._envoi.text)
	_verifier(p._qr.texture != null and p._qr.custom_minimum_size.x >= 29 * 2, "QR affiché")
	_verifier(p._id.text.contains("b054a8"), "id court affiché")
	p.appliquer_etat({"enabled": true, "lien": p._lien.text, "qr": qr, "mots": mots, "erreur": "Relay unreachable", "dernier_envoi": 0})
	_verifier(p._statut.visible and p._statut.text == "Relay unreachable", "erreur affichée")
	_verifier(p._envoi.text == "Not published to the relay yet.", "jamais publié")
	p.basculer_secret()
	p.appliquer_etat({"enabled": true, "masque": true, "id_court": "b054a8", "relay": "https://aimpire.sidali.dev/", "dernier_envoi": 0})
	_verifier(p._masque.visible and not p._afficher.visible and not p._secret.visible, "mode discret : secret masqué, pas de bouton")
	_verifier(p._lien.text == "" and p._qr.texture == null, "mode discret : lien et QR retirés")
	p.appliquer_etat({"enabled": false})
	_verifier(p._creer.visible and not p._detail.visible, "après suppression : bouton Créer")
	_verifier(not p._confirmation.visible, "pas de confirmation sans clic")
	p.queue_free()

	if _echecs == 0:
		print("test_sync_panel : %d vérifications, tout est vert" % _verifs)
	else:
		printerr("test_sync_panel : %d échec(s) sur %d" % [_echecs, _verifs])
	quit(1 if _echecs else 0)
	return false
