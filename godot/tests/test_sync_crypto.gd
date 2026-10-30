extends SceneTree
# Vérifie godot/sync_crypto.gd contre docs/SYNC-VECTEURS.json (les mêmes vecteurs que daemon/test/sync-crypto.test.js).
# Lancer : godot --headless --path godot -s tests/test_sync_crypto.gd   (code de sortie 1 au premier écart)

const SC := preload("res://sync_crypto.gd")

var echecs := 0
var total := 0

func verifie(cas: String, ok: bool, detail := "") -> void:
	total += 1
	if ok:
		return
	echecs += 1
	printerr("ÉCHEC ", cas, ("  " + detail) if detail != "" else "")

func egal(cas: String, obtenu: Variant, attendu: Variant) -> void:
	verifie(cas, obtenu == attendu, "obtenu %s, attendu %s" % [str(obtenu), str(attendu)])

func _init() -> void:
	var chemin := ProjectSettings.globalize_path("res://").path_join("../docs/SYNC-VECTEURS.json").simplify_path()
	var texte := FileAccess.get_file_as_string(chemin)
	var V: Dictionary = JSON.parse_string(texte) if texte != "" else {}
	if V.is_empty():
		printerr("vecteurs introuvables : ", chemin)
		quit(1)
		return
	var s: PackedByteArray = String(V.secret_hex).hex_decode()

	# Identifiant, jeton d'écriture, clés
	egal("id", SC.derive_id(s), V.id)
	egal("id depuis W", SC.id_du_jeton(String(V.jeton_ecriture)), V.id)
	egal("jeton d'écriture", SC.derive_write_token(s), V.jeton_ecriture)
	egal("empreinte du jeton", SC.sha256(String(V.jeton_ecriture).to_utf8_buffer()).hex_encode(), V.empreinte_jeton)
	var k: Dictionary = SC.derive_keys(s)
	egal("K_enc", (k.enc as PackedByteArray).hex_encode(), V.k_enc_hex)
	egal("K_mac", (k.mac as PackedByteArray).hex_encode(), V.k_mac_hex)

	# HKDF : vecteurs officiels RFC 5869
	for c in V.hkdf_rfc5869:
		var okm := SC.hkdf(String(c.ikm_hex).hex_decode(), String(c.sel_hex).hex_decode(), String(c.info_hex).hex_decode(), int(c.longueur))
		egal("HKDF " + String(c.cas), okm.hex_encode(), c.okm_hex)

	# Mots et lien
	egal("12 mots", " ".join(SC.to_words(s)), " ".join(PackedStringArray(V.mots)))
	var dm: Dictionary = SC.from_words(" ".join(PackedStringArray(V.mots)).to_upper() + "  ")
	verifie("mots vers secret", dm.ok and (dm.secret as PackedByteArray).hex_encode() == V.secret_hex, str(dm))
	for c in V.bip39_officiels:
		var e: PackedByteArray = String(c.entropie_hex).hex_decode()
		egal("BIP39 officiel " + String(c.entropie_hex), " ".join(SC.to_words(e)), c.mots)
		var r: Dictionary = SC.from_words(c.mots)
		verifie("BIP39 retour " + String(c.entropie_hex), r.ok and (r.secret as PackedByteArray).hex_encode() == c.entropie_hex, str(r))
	for m in V.mots_invalides:
		var r: Dictionary = SC.from_words(m)
		verifie("mots invalides refusés : " + String(m), not r.ok)
	egal("lien", SC.to_link(s), V.lien)
	var dl: Dictionary = SC.from_link(V.lien)
	verifie("lien vers secret", dl.ok and (dl.secret as PackedByteArray).hex_encode() == V.secret_hex, str(dl))
	egal("relais du lien", dl.get("relais", ""), "https://aimpire.sidali.dev/")
	egal("relais d'un lien local", SC.relais_du_lien("http://127.0.0.1:8787/#s=x"), "http://127.0.0.1:8787/")
	for l in V.liens_invalides:
		var r: Dictionary = SC.from_link(l)
		verifie("lien invalide refusé : " + String(l), not r.ok)

	# Blob de référence : chiffrement octet pour octet, puis déchiffrement
	var b: Dictionary = V.blob
	var blob := SC.encrypt_blob(k, String(b.clair).to_utf8_buffer(), String(b.iv_hex).hex_decode())
	egal("blob (hex)", blob.hex_encode(), b.blob_hex)
	egal("blob (base64)", Marshalls.raw_to_base64(blob), b.blob_base64)
	egal("chiffré", blob.slice(17, blob.size() - 32).hex_encode(), b.chiffre_hex)
	egal("mac", blob.slice(blob.size() - 32).hex_encode(), b.mac_hex)
	var d: Dictionary = SC.decrypt_blob(k, String(b.blob_hex).hex_decode())
	verifie("déchiffrement du blob", d.ok and (d.clair as PackedByteArray).get_string_from_utf8() == b.clair, str(d))

	# État gzippé par Node : même chiffré, puis déchiffrement + décompression + JSON
	var g: Dictionary = V.blob_gzip
	egal("blob gzip (hex)", SC.encrypt_blob(k, String(g.gzip_hex).hex_decode(), String(g.iv_hex).hex_decode()).hex_encode(), g.blob_hex)
	var dg: Dictionary = SC.decrypt_json(k, String(g.blob_hex).hex_decode())
	verifie("état gzippé déchiffré", dg.ok and JSON.stringify(dg.get("objet")) == JSON.stringify(g.objet), str(dg))

	# État bourré (champ FEXTRA de l'en-tête gzip) : le décodeur gzip de Godot doit le sauter
	var gb: Dictionary = V.blob_bourre
	egal("blob bourré (hex)", SC.encrypt_blob(k, String(gb.gzip_hex).hex_decode(), String(gb.iv_hex).hex_decode()).hex_encode(), gb.blob_hex)
	var db: Dictionary = SC.decrypt_json(k, String(gb.blob_hex).hex_decode())
	verifie("état bourré déchiffré", db.ok and JSON.stringify(db.get("objet")) == JSON.stringify(gb.objet), str(db))

	# Commande chiffrée par Node, lue par Godot
	var dc: Dictionary = SC.decrypt_json(k, String(V.blob_commande.blob_hex).hex_decode())
	verifie("commande déchiffrée", dc.ok and JSON.stringify(dc.get("objet")) == JSON.stringify(V.blob_commande.objet), str(dc))

	# Cas négatifs : tous refusés
	for cas in V.negatifs:
		var r: Dictionary = SC.decrypt_blob(k, String(V.negatifs[cas]).hex_decode())
		verifie("refus " + String(cas), not r.ok, str(r))
	var rm: Dictionary = SC.decrypt_blob(k, String(V.negatifs.mac_faux_hex).hex_decode())
	egal("mac faux : motif", rm.get("erreur", ""), "mac")

	# Aller-retour aléatoire (secret, iv, tailles de clair variées)
	var s2 := SC.generer_secret()
	var k2: Dictionary = SC.derive_keys(s2)
	for n in [0, 1, 15, 16, 17, 1000]:
		var clair := PackedByteArray()
		clair.resize(n)
		clair.fill(7)
		var bl := SC.encrypt_blob(k2, clair)
		egal("taille du blob pour %d octets" % n, bl.size(), 1 + 16 + (n / 16 + 1) * 16 + 32)
		var r: Dictionary = SC.decrypt_blob(k2, bl)
		verifie("aller-retour %d octets" % n, r.ok and r.clair == clair, str(r))
	var cmd := {"type": "cmd", "ts": 1760000000000, "nonce": "00ff", "action": "reglage", "cle": "privacy", "val": "flou"}
	var rc: Dictionary = SC.decrypt_json(k2, SC.encrypt_json(k2, cmd))
	# JSON.parse renvoie les nombres en flottants : on compare à la version relue de l'original.
	verifie("aller-retour JSON", rc.ok and JSON.stringify(rc.objet) == JSON.stringify(JSON.parse_string(JSON.stringify(cmd))), str(rc))
	var rw: Dictionary = SC.from_words(" ".join(SC.to_words(s2)))
	verifie("aller-retour mots", rw.ok and rw.secret == s2)
	var rl: Dictionary = SC.from_link(SC.to_link(s2, "http://127.0.0.1:8787"))
	verifie("aller-retour lien", rl.ok and rl.secret == s2 and rl.relais == "http://127.0.0.1:8787/")
	verifie("deux chiffrements diffèrent (iv aléatoire)", SC.encrypt_json(k2, cmd) != SC.encrypt_json(k2, cmd))

	if echecs > 0:
		printerr("sync_crypto : %d échec(s) sur %d vérifications" % [echecs, total])
		quit(1)
	else:
		print("sync_crypto : %d vérifications, tout est vert" % total)
		quit(0)
