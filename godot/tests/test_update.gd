extends SceneTree
# Mises à jour (update.gd) : comparaison de versions, lecture du manifeste, puis bouton « Mettre à jour » montré ou caché
# avec un faux update.json servi par le relais Node local (relay/server.js, AIMPIRE_RELEASES_DIR dans un dossier temporaire).
# Lancer : godot --headless --path godot -s tests/test_update.gd   (Node 22 dans le PATH)

const U := preload("res://update.gd")
const PORT := 7719

var echecs := 0
var total := 0
var _pid := 0

func egal(cas: String, obtenu: Variant, attendu: Variant) -> void:
	total += 1
	if str(obtenu) != str(attendu):
		echecs += 1
		printerr("ÉCHEC ", cas, "  obtenu ", str(obtenu), ", attendu ", str(attendu))

func _initialize() -> void:
	_purs()
	await _avec_relais()
	if _pid:
		OS.kill(_pid)
	print("test_update : %d/%d" % [total - echecs, total])
	quit(1 if echecs else 0)

func _purs() -> void:
	egal("plus récente", U.comparer_versions("0.5.0", "0.4.9"), 1)
	egal("dizaines", U.comparer_versions("0.10.0", "0.9.9"), 1)
	egal("plus ancienne", U.comparer_versions("0.4.0", "0.5.0"), -1)
	egal("zéros implicites", U.comparer_versions("1.0", "1.0.0"), 0)
	egal("préfixe v", U.comparer_versions("v0.5.0", "0.5.0"), 0)
	egal("suffixe ignoré", U.comparer_versions("0.5.0-beta", "0.5.0"), 0)
	egal("majeure", U.comparer_versions("1.0.0", "0.99.99"), 1)
	egal("versions valides", [U.version_valide("0.5.0"), U.version_valide("v1.2"), U.version_valide("abc"), U.version_valide("1.2.3.4.5"), U.version_valide("")], [true, true, false, false, false])
	egal("origine", [U.origine("https://Aimpire.sidali.dev/update.json"), U.origine("http://127.0.0.1:7719/x"), U.origine("ftp://x/"), U.origine("https://a@b/")],
		["https://aimpire.sidali.dev/", "http://127.0.0.1:7719/", "", ""])

	var o := "https://aimpire.sidali.dev/"
	var m := JSON.stringify({"version": "0.6.0", "notes": "Nouveautés",
		"mac": {"url": o + "download/AImpire-0.6.0-macos.zip", "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
		"android": {"url": o + "download/aimpire-0.5.1.apk", "sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc", "version": "0.5.1"}})
	egal("mac plus récent", U.analyser(m, "0.5.0", "mac", o), {"version": "0.6.0", "url": o + "download/AImpire-0.6.0-macos.zip", "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "notes": "Nouveautés"})
	egal("version de la plateforme prioritaire", U.analyser(m, "0.5.0", "android", o).get("version"), "0.5.1")
	egal("android déjà à jour", U.analyser(m, "0.5.1", "android", o), {})
	egal("même version", U.analyser(m, "0.6.0", "mac", o), {})
	egal("installée plus récente", U.analyser(m, "0.7.0", "mac", o), {})
	egal("plateforme inconnue", U.analyser(m, "0.5.0", "", o), {})
	egal("JSON invalide", U.analyser("{ pas du json", "0.5.0", "mac", o), {})
	egal("tableau", U.analyser("[1]", "0.5.0", "mac", o), {})
	egal("sans entrée mac", U.analyser(JSON.stringify({"version": "9.0.0"}), "0.5.0", "mac", o), {})
	for url in ["https://ailleurs.fr/download/AImpire-0.6.0-macos.zip", o + "AImpire-0.6.0-macos.zip", o + "download/../x",
			o + "download/x.zip?y=1", "javascript:alert(1)", "file:///etc/passwd", "http://aimpire.sidali.dev/download/a.zip"]:
		egal("URL refusée " + url, U.analyser(JSON.stringify({"version": "0.6.0", "mac": {"url": url, "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}), "0.5.0", "mac", o), {})
	for sha in ["", "ab", "a".repeat(63), "g".repeat(64)]:
		egal("sha256 refusé " + sha, U.analyser(JSON.stringify({"version": "0.6.0", "mac": {"url": o + "download/a.zip", "sha256": sha}}), "0.5.0", "mac", o), {})
	egal("version mal formée", U.analyser(JSON.stringify({"version": "neuf", "mac": {"url": o + "download/a.zip", "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}), "0.5.0", "mac", o), {})
	egal("texte Mac", U.texte_bouton("0.6.0", "mac"), "Update to 0.6.0")
	egal("texte Android : passe par le navigateur", U.texte_bouton("0.6.0", "android").contains("install through the browser"), true)
	for t in [U.texte_bouton("0.6.0", "mac"), U.texte_bouton("0.6.0", "android")]:
		egal("sans tiret long", t.contains(String.chr(0x2014)) or t.contains(String.chr(0x2013)), false)

# Relais local qui sert update.json, puis le module réel : bouton montré si la version publiée dépasse l'installée.
func _avec_relais() -> void:
	var dossier := OS.get_cache_dir().path_join("aimpire-test-update-%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(dossier)
	var base := "http://127.0.0.1:%d/" % PORT
	_ecrire(dossier, "9.0.0", base)
	OS.set_environment("PORT", str(PORT))
	OS.set_environment("HOST", "127.0.0.1")
	OS.set_environment("AIMPIRE_RELEASES_DIR", dossier)
	OS.set_environment("AIMPIRE_UPDATE_PLATEFORME", "mac")   # même résultat sur Linux (CI)
	var script := ProjectSettings.globalize_path("res://").path_join("../relay/server.js").simplify_path()
	_pid = OS.create_process("/usr/bin/env", ["node", script])
	egal("relais lancé", _pid > 0, true)
	var pret := false
	for i in 50:
		await create_timer(0.1).timeout
		var r := await _code_http(base + "health")
		if r == 200:
			pret = true
			break
	egal("relais prêt", pret, true)
	if not pret:
		return

	var maj: Node = U.new()
	maj.url_manifeste = base + "update.json"
	maj.active = false   # pas de vérification automatique : le test la déclenche
	root.add_child(maj)
	var parent := Control.new()
	root.add_child(parent)
	var bouton: Button = maj.creer_bouton()
	parent.add_child(bouton)
	egal("bouton caché au départ", bouton.visible, false)

	maj.active = true
	maj.verifier()
	await maj.disponible_change
	egal("version disponible", maj.disponible.get("version"), "9.0.0")
	egal("bouton visible", bouton.visible, true)
	egal("texte du bouton", bouton.text, "Update to 9.0.0")
	egal("URL du zip", maj.disponible.get("url"), base + "download/AImpire-9.0.0-macos.zip")
	maj.telecharger()
	var r: Array = await maj.telechargement_fini
	egal("paquet vérifié", r[0], true)
	egal("paquet présent", FileAccess.file_exists(r[1]), true)
	DirAccess.remove_absolute(r[1])

	_ecrire(dossier, "9.0.0", base, "f".repeat(64))   # empreinte qui ne correspond pas au fichier servi
	maj.verifier()
	await maj.disponible_change
	maj.telecharger()
	r = await maj.telechargement_fini
	egal("paquet modifié refusé", r[0], false)
	egal("paquet modifié supprimé", FileAccess.file_exists(U.DOSSIER_MAJ.path_join("AImpire-9.0.0-macos.zip")), false)
	_ecrire(dossier, "9.0.0", base)

	var second: Button = maj.creer_bouton()   # le bouton du menu, créé après coup, apparaît aussi
	parent.add_child(second)
	egal("bouton du menu visible", second.visible, true)

	OS.set_environment("AIMPIRE_UPDATE_PLATEFORME", "android")
	maj.verifier()
	await maj.disponible_change
	egal("android : texte", bouton.text.contains("browser"), true)
	egal("android : URL de l'APK", maj.disponible.get("url"), base + "download/aimpire-9.0.0.apk")

	_ecrire(dossier, U.version_installee(), base)   # plus rien de neuf
	maj.verifier()
	await maj.disponible_change
	egal("même version : rien", maj.disponible, {})
	egal("même version : bouton caché", bouton.visible, false)
	egal("même version : bouton du menu caché", second.visible, false)

	DirAccess.remove_absolute(dossier.path_join("update.json"))   # manifeste absent : rien, pas d'erreur visible
	maj.verifier()
	for i in 50:
		await create_timer(0.1).timeout
		if maj.derniere_erreur != "":
			break
	egal("manifeste absent : erreur notée", maj.derniere_erreur.contains("404"), true)
	egal("manifeste absent : bouton caché", bouton.visible, false)
	maj.queue_free()
	parent.queue_free()
	for nom in DirAccess.get_files_at(dossier):
		DirAccess.remove_absolute(dossier.path_join(nom))
	DirAccess.remove_absolute(dossier)

func _ecrire(dossier: String, version: String, base: String, sha_mac := "") -> void:
	var zip := dossier.path_join("AImpire-%s-macos.zip" % version)
	var z := FileAccess.open(zip, FileAccess.WRITE)
	z.store_string("faux paquet " + version)
	z.close()
	var f := FileAccess.open(dossier.path_join("update.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": version, "notes": "Essai",
		"mac": {"url": base + "download/AImpire-%s-macos.zip" % version, "sha256": sha_mac if sha_mac != "" else U.sha256_fichier(zip)},
		"android": {"url": base + "download/aimpire-%s.apk" % version, "sha256": "0".repeat(64)}}))
	f.close()

func _code_http(url: String) -> int:
	var h := HTTPRequest.new()
	root.add_child(h)
	if h.request(url) != OK:
		h.queue_free()
		return 0
	var r: Array = await h.request_completed
	h.queue_free()
	return int(r[1])
