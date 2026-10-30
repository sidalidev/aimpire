extends RefCounted
# Cryptographie de la chaîne de sync, côté Godot (voir docs/SYNC.md). Miroir exact de daemon/sync-crypto.js :
# docs/SYNC-VECTEURS.json fait foi entre les deux (test : godot --headless --path godot -s tests/test_sync_crypto.gd).
# Godot n'a pas d'AES-GCM : AES-256-CBC + PKCS7, puis HMAC-SHA256 sur iv ‖ chiffré, vérifié avant tout déchiffrement.
# Toutes les fonctions sont statiques : var SC := preload("res://sync_crypto.gd") puis SC.derive_id(s).
# Les fonctions qui peuvent échouer renvoient un Dictionary {"ok": bool, ..., "erreur": String} au lieu de lever.

const TAILLE_SECRET := 16
const TAILLE_IV := 16
const TAILLE_MAC := 32
const VERSION_BLOB := 1
const TAILLE_MIN_BLOB := 65        # version (1) + iv (16) + un bloc chiffré (16) + mac (32)
const MAX_CLAIR := 16 * 1024 * 1024   # plafond après décompression gzip
const RELAIS_PAR_DEFAUT := "https://aimpire.sidali.dev/"
const LISTE_MOTS := "res://assets/bip39-english.txt"

static var _mots := PackedStringArray()
static var _index_mots := {}

# ---------------------------------------------------------------------------
# Primitives : SHA-256, HMAC, HKDF (RFC 5869), AES-256-CBC + PKCS7
# ---------------------------------------------------------------------------

static func sha256(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if data.size() > 0:
		ctx.update(data)
	return ctx.finish()

static func hmac_sha256(key: PackedByteArray, data: PackedByteArray) -> PackedByteArray:
	# Une clé vide équivaut à 32 octets nuls (HMAC complète la clé avec des zéros) ; HMACContext refuse la clé vide.
	var k := key
	if k.is_empty():
		k = PackedByteArray()
		k.resize(32)
	var ctx := HMACContext.new()
	ctx.start(HashingContext.HASH_SHA256, k)
	if data.size() > 0:
		ctx.update(data)
	return ctx.finish()

# HKDF-SHA256 : extraction PRK = HMAC(sel, ikm), puis expansion T(i) = HMAC(PRK, T(i-1) ‖ info ‖ i).
static func hkdf(ikm: PackedByteArray, salt: PackedByteArray, info: PackedByteArray, length: int) -> PackedByteArray:
	var prk := hmac_sha256(salt, ikm)
	var okm := PackedByteArray()
	var t := PackedByteArray()
	var i := 1
	while okm.size() < length:
		var bloc := PackedByteArray()
		bloc.append_array(t)
		bloc.append_array(info)
		bloc.append(i)
		t = hmac_sha256(prk, bloc)
		okm.append_array(t)
		i += 1
	return okm.slice(0, length)

# HKDF avec sel vide et info texte, comme hkdfSync("sha256", S, vide, info, n) côté Node.
static func hkdf_info(s: PackedByteArray, info: String, length: int) -> PackedByteArray:
	return hkdf(s, PackedByteArray(), info.to_utf8_buffer(), length)

static func pkcs7_pad(data: PackedByteArray) -> PackedByteArray:
	var n := 16 - data.size() % 16
	var out := data.duplicate()
	for _i in n:
		out.append(n)
	return out

# Longueur du remplissage PKCS7 (1 à 16), ou -1 s'il est incorrect.
static func pkcs7_longueur(data: PackedByteArray) -> int:
	if data.is_empty() or data.size() % 16 != 0:
		return -1
	var n: int = data[data.size() - 1]
	if n < 1 or n > 16:
		return -1
	for i in range(data.size() - n, data.size()):
		if data[i] != n:
			return -1
	return n

static func aes_cbc(encrypt: bool, key: PackedByteArray, iv: PackedByteArray, data: PackedByteArray) -> PackedByteArray:
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT if encrypt else AESContext.MODE_CBC_DECRYPT, key, iv)
	var out := aes.update(data)
	aes.finish()
	return out

# Comparaison en temps constant (pas de sortie anticipée au premier octet différent).
static func egal_constant(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff := 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0

static func octets_aleatoires(n: int) -> PackedByteArray:
	return Crypto.new().generate_random_bytes(n)

# ---------------------------------------------------------------------------
# Secret, identifiant et clés
# ---------------------------------------------------------------------------

static func generer_secret() -> PackedByteArray:
	return octets_aleatoires(TAILLE_SECRET)

# id = hex(SHA-256("aimpire-id" ‖ W en ASCII))[0:32] : le relais peut vérifier qu'un id appartient à W (docs/SYNC.md §2).
static func id_du_jeton(w: String) -> String:
	var data := "aimpire-id".to_utf8_buffer()
	data.append_array(w.to_ascii_buffer())
	return sha256(data).hex_encode().substr(0, 32)

static func derive_id(s: PackedByteArray) -> String:
	return id_du_jeton(derive_write_token(s))

# W = hex(HKDF(S, "aimpire-write", 32)), envoyé en « Authorization: Bearer W ».
static func derive_write_token(s: PackedByteArray) -> String:
	return hkdf_info(s, "aimpire-write", 32).hex_encode()

# {"enc": K_enc, "mac": K_mac}, 32 octets chacune.
static func derive_keys(s: PackedByteArray) -> Dictionary:
	return {"enc": hkdf_info(s, "aimpire-enc", 32), "mac": hkdf_info(s, "aimpire-mac", 32)}

# ---------------------------------------------------------------------------
# Blobs : 0x01 ‖ iv (16) ‖ AES-256-CBC(K_enc, iv, PKCS7(clair)) ‖ HMAC-SHA256(K_mac, iv ‖ chiffré)
# ---------------------------------------------------------------------------

static func blob_bien_forme(blob: PackedByteArray) -> bool:
	return blob.size() >= TAILLE_MIN_BLOB and blob[0] == VERSION_BLOB and (blob.size() - 1 - TAILLE_IV - TAILLE_MAC) % 16 == 0

# iv vide : tiré au hasard (toujours, sauf dans les tests).
static func encrypt_blob(keys: Dictionary, clair: PackedByteArray, iv := PackedByteArray()) -> PackedByteArray:
	var v := iv if iv.size() == TAILLE_IV else octets_aleatoires(TAILLE_IV)
	var enc: PackedByteArray = keys.enc
	var mac: PackedByteArray = keys.mac
	var chiffre := aes_cbc(true, enc, v, pkcs7_pad(clair))
	var signe := v.duplicate()
	signe.append_array(chiffre)
	var out := PackedByteArray([VERSION_BLOB])
	out.append_array(signe)
	out.append_array(hmac_sha256(mac, signe))
	return out

# {"ok": true, "clair": PackedByteArray} ou {"ok": false, "erreur": "..."}. Le mac est vérifié avant de déchiffrer.
static func decrypt_blob(keys: Dictionary, blob: PackedByteArray) -> Dictionary:
	if not blob_bien_forme(blob):
		return {"ok": false, "erreur": "format"}
	var enc: PackedByteArray = keys.enc
	var mac: PackedByteArray = keys.mac
	var signe := blob.slice(1, blob.size() - TAILLE_MAC)
	var recu := blob.slice(blob.size() - TAILLE_MAC)
	if not egal_constant(hmac_sha256(mac, signe), recu):
		return {"ok": false, "erreur": "mac"}
	var iv := signe.slice(0, TAILLE_IV)
	var brut := aes_cbc(false, enc, iv, signe.slice(TAILLE_IV))
	var n := pkcs7_longueur(brut)
	if n < 0:
		return {"ok": false, "erreur": "remplissage"}
	return {"ok": true, "clair": brut.slice(0, brut.size() - n)}

static func est_gzip(data: PackedByteArray) -> bool:
	return data.size() >= 2 and data[0] == 0x1f and data[1] == 0x8b

# Chiffre un objet en JSON (commandes du téléphone : jamais compressées, toujours petites).
static func encrypt_json(keys: Dictionary, obj: Variant, iv := PackedByteArray()) -> PackedByteArray:
	return encrypt_blob(keys, JSON.stringify(obj).to_utf8_buffer(), iv)

# {"ok": true, "objet": Variant} ; le clair peut être gzippé (états du Mac) ou non.
static func decrypt_json(keys: Dictionary, blob: PackedByteArray) -> Dictionary:
	var r: Dictionary = decrypt_blob(keys, blob)
	if not r.ok:
		return r
	var clair: PackedByteArray = r.clair
	if est_gzip(clair):
		clair = clair.decompress_dynamic(MAX_CLAIR, FileAccess.COMPRESSION_GZIP)
		if clair.is_empty():
			return {"ok": false, "erreur": "gzip"}
	var json := JSON.new()
	if json.parse(clair.get_string_from_utf8()) != OK:
		return {"ok": false, "erreur": "json"}
	return {"ok": true, "objet": json.data}

# ---------------------------------------------------------------------------
# base64url sans remplissage (RFC 4648 §5)
# ---------------------------------------------------------------------------

static func base64url_encode(data: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(data).replace("+", "-").replace("/", "_").rstrip("=")

# Tableau vide si le texte contient autre chose que l'alphabet base64url.
static func base64url_decode(text: String) -> PackedByteArray:
	var t := text.rstrip("=")
	var re := RegEx.create_from_string("^[A-Za-z0-9_-]+$")
	if re.search(t) == null or t.length() % 4 == 1:
		return PackedByteArray()
	t = t.replace("-", "+").replace("_", "/")
	while t.length() % 4 != 0:
		t += "="
	return Marshalls.base64_to_raw(t)

# ---------------------------------------------------------------------------
# Lien d'appairage : https://aimpire.sidali.dev/#s=<base64url(S)>
# ---------------------------------------------------------------------------

static func to_link(s: PackedByteArray, base := RELAIS_PAR_DEFAUT) -> String:
	return (base if base.ends_with("/") else base + "/") + "#s=" + base64url_encode(s)

# {"ok": true, "secret": PackedByteArray, "relais": "https://hôte/"} ou {"ok": false, "erreur": "..."}.
static func from_link(url: String) -> Dictionary:
	var texte := url.strip_edges()
	var diese := texte.find("#")
	if diese < 0:
		return {"ok": false, "erreur": "Invalid link: no fragment"}
	var valeur := ""
	for part in texte.substr(diese + 1).split("&"):
		if part.begins_with("s="):
			valeur = part.substr(2)
	var s := base64url_decode(valeur) if valeur != "" else PackedByteArray()
	if s.size() != TAILLE_SECRET:
		return {"ok": false, "erreur": "Invalid link: secret missing or malformed"}
	return {"ok": true, "secret": s, "relais": relais_du_lien(texte)}

# Origine du lien (schéma, hôte, port) suivie de « / » ; relais par défaut si le lien n'a pas de schéma.
static func relais_du_lien(url: String) -> String:
	var sep := url.find("://")
	if sep < 0:
		return RELAIS_PAR_DEFAUT
	var fin := url.length()
	for c in ["/", "#", "?"]:
		var p := url.find(c, sep + 3)
		if p >= 0 and p < fin:
			fin = p
	return url.substr(0, fin) + "/"

# ---------------------------------------------------------------------------
# 12 mots BIP39 (liste anglaise officielle, assets/bip39-english.txt)
# ---------------------------------------------------------------------------

static func mots() -> PackedStringArray:
	if _mots.is_empty():
		var f := FileAccess.open(LISTE_MOTS, FileAccess.READ)
		if f == null:
			push_error("BIP39 word list not found: " + LISTE_MOTS)
			return _mots
		for l in f.get_as_text().split("\n", false):
			var m := l.strip_edges()
			if m != "":
				_index_mots[m] = _mots.size()
				_mots.append(m)
	return _mots

static func to_words(s: PackedByteArray) -> PackedStringArray:
	var liste := mots()
	var bits: Array[int] = []
	for octet in s:
		for k in range(7, -1, -1):
			bits.append((octet >> k) & 1)
	var controle: int = sha256(s)[0] >> 4
	for k in range(3, -1, -1):
		bits.append((controle >> k) & 1)
	var out := PackedStringArray()
	for w in 12:
		var idx := 0
		for k in 11:
			idx = (idx << 1) | bits[w * 11 + k]
		out.append(liste[idx])
	return out

# {"ok": true, "secret": PackedByteArray} ou {"ok": false, "erreur": "..."}. Insensible à la casse et aux espaces.
static func from_words(text: String) -> Dictionary:
	mots()
	var liste := PackedStringArray()
	for m in text.strip_edges().to_lower().replace("\n", " ").replace("\t", " ").split(" ", false):
		liste.append(m)
	if liste.size() != 12:
		return {"ok": false, "erreur": "Exactly 12 words are needed"}
	var bits: Array[int] = []
	for m in liste:
		if not _index_mots.has(m):
			return {"ok": false, "erreur": "Unknown word: " + m}
		var idx: int = _index_mots[m]
		for k in range(10, -1, -1):
			bits.append((idx >> k) & 1)
	var s := PackedByteArray()
	for b in TAILLE_SECRET:
		var v := 0
		for k in 8:
			v = (v << 1) | bits[b * 8 + k]
		s.append(v)
	var controle := 0
	for k in 4:
		controle = (controle << 1) | bits[128 + k]
	if controle != sha256(s)[0] >> 4:
		return {"ok": false, "erreur": "Wrong checksum: check the words"}
	return {"ok": true, "secret": s}
