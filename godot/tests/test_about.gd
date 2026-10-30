extends SceneTree
# Écran « About » (about.gd) : date, empreinte, textes embarqués, garde-fous de l'effacement, pages construites.
#   godot --headless --path godot -s tests/test_about.gd

const A := preload("res://about.gd")
const TX := preload("res://about_texts.gd")

var echecs := 0
var total := 0

func egal(cas: String, obtenu: Variant, attendu: Variant) -> void:
	total += 1
	if str(obtenu) != str(attendu):
		echecs += 1
		printerr("ÉCHEC ", cas, "  obtenu ", str(obtenu), ", attendu ", str(attendu))

func _initialize() -> void:
	egal("date", A.date_lisible("2026-10-24"), "24 Oct 2026")
	egal("date janvier", A.date_lisible("2027-01-05"), "5 Jan 2027")
	egal("date invalide", A.date_lisible("24/10/2026"), "24/10/2026")
	egal("mois invalide", A.date_lisible("2026-13-01"), "2026-13-01")
	var h := "79:E3:7E:06:72:10:2C:6B:EC:29:B0:E8:B5:5E:58:C0:51:62:98:C7:17:BE:6E:9E:77:18:DC:50:63:6E:9E:A0"
	egal("empreinte normalisée", A.empreinte_normale(h), TX.SIGNING_SHA256_ANDROID)
	egal("empreinte courte", A.empreinte_courte(h), "79e37e06…9ea0")
	egal("empreinte invalide", A.empreinte_courte("abc"), "")
	egal("revue datée", RegEx.create_from_string("^\\d{4}-\\d{2}-\\d{2}$").search(TX.SECURITY_REVIEW) != null, true)
	var version := String(ProjectSettings.get_setting("application/config/version"))
	egal("CHANGELOG embarqué pour la version", TX.CHANGELOG.contains("## %s (" % version), true)
	egal("PRIVACY embarqué", TX.PRIVACY.begins_with("# Privacy policy"), true)
	egal("4 principes", A.PRINCIPES.size(), 4)
	egal("open source", A.PRINCIPES[3], "The code is open source, so anyone can check this.")
	egal("source code link", A.DEPOT, "https://github.com/sidalidev/aimpire")
	var lic := A.licences_tierces()
	egal("licenses: Godot", lic.contains("Godot Engine") and lic.contains(Engine.get_license_text().strip_edges().left(40)), true)
	egal("licenses: components", lic.contains("FreeType"), true)
	egal("licenses: Bun MIT", lic.contains("Bun itself is MIT-licensed") and lic.contains("Permission is hereby granted"), true)
	for plat in ["mac", "android"]:
		var f: Array = A.fuites(plat)
		egal("fuites %s : mise à jour" % plat, f.any(func(x): return String(x[1]).contains("aimpire.sidali.dev")), true)
		egal("fuites %s : le relais voit" % plat, f.any(func(x): return String(x[1]).contains("never sees the content")), true)
	egal("Mac : voix détaillées", A.fuites("mac").any(func(x): return String(x[1]).contains("ElevenLabs")), true)
	egal("Android : pas de voix", A.fuites("android").any(func(x): return String(x[1]).contains("ElevenLabs")), false)
	egal("Mac : ~/.claude jamais touché", A.texte_effacement("mac").contains("~/.claude are never touched"), true)
	# Mêmes faits dans PRIVACY.md que sur l'écran
	for phrase in ["never sees the content", "120 characters at most", "You can turn it off in Settings", "30 days"]:
		egal("PRIVACY.md : " + phrase, TX.PRIVACY.contains(phrase), true)
	# Aucun tiret long ni demi-cadratin dans les textes affichés
	var tout := TX.CHANGELOG + TX.PRIVACY + A.texte_effacement("mac") + A.texte_effacement("android")
	for f in A.fuites("mac") + A.fuites("android"):
		tout += String(f[0]) + String(f[1])
	egal("pas de tiret long", tout.contains(String.chr(0x2014)) or tout.contains(String.chr(0x2013)), false)
	# Markdown
	egal("markdown titre", A.markdown_bbcode("# T\n## 0.6.0 (x): y\n- a\n  b\n\npara\nsuite\n## z"), "[b]0.6.0 (x): y[/b]\n  •  a b\n\npara suite\n[b]z[/b]")
	egal("markdown crochets", A.markdown_bbcode("[x]"), "[lb]x]")
	egal("markdown gras", A.markdown_bbcode("**Sync**: x"), "[b]Sync[/b]: x")
	# Garde-fous de l'effacement
	var maison := "/home/x"
	egal("user:// AImpire", A.peut_effacer("/home/x/Library/Application Support/Godot/app_userdata/AImpire", maison), true)
	egal("Android", A.peut_effacer("/data/user/0/dev.sidali.aimpire/files", maison), true)
	for refuse in ["", "/", "/home/x", "/home", "relatif/aimpire", "/home/x/.claude", "/home/x/.claude/aimpire", "/home/x/Documents", "/tmp/aimpire/../x"]:
		egal("refusé " + refuse, A.peut_effacer(refuse, maison), false)
	# vider_dossier sur un dossier temporaire
	var tmp := OS.get_cache_dir().path_join("aimpire-test-about-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(tmp.path_join("maj/sous"))
	for f in ["reglages.cfg", "chaine.cfg", ".cache", "maj/x.zip", "maj/sous/y"]:
		var fa := FileAccess.open(tmp.path_join(f), FileAccess.WRITE)
		fa.store_string("x")
		fa.close()
	egal("vider_dossier", A.vider_dossier(tmp), 7)
	egal("dossier vide", DirAccess.get_files_at(tmp).size() + DirAccess.get_directories_at(tmp).size(), 0)
	DirAccess.remove_absolute(tmp)
	# Certificat lu dans le bloc de signature d'un APK publié (s'il a été construit sur cette machine)
	var apk := ProjectSettings.globalize_path("res://").path_join("../build/AImpire.apk")
	if FileAccess.file_exists(apk):
		egal("certificat de l'APK", A.sha256_hex(A.certificat_fichier(apk)), TX.SIGNING_SHA256_ANDROID)
	egal("pas un APK", A.certificat_fichier(ProjectSettings.globalize_path("res://icon.png")).size(), 0)
	egal("fichier absent", A.certificat_fichier("/nonexistent/x.apk").size(), 0)
	# Pages construites sans main (textes, boutons)
	var ecran := A.new()
	root.add_child(ecran)
	await process_frame
	for p in A.PAGES:
		ecran.open(p)
		egal("page " + p, ecran.page, p)
		egal("page %s : du contenu" % p, ecran._col.get_child_count() > 2, true)
	ecran.open("erase")
	egal("effacer désactivé", ecran._bouton_effacer.disabled, true)
	ecran._champ.text = "erase"
	ecran._maj_confirmation()
	egal("minuscules refusées", ecran._bouton_effacer.disabled, true)
	ecran._champ.text = "ERASE"
	ecran._maj_confirmation()
	egal("ERASE accepté", ecran._bouton_effacer.disabled, false)
	egal("retour vers About", [ecran.retour(), ecran.page], [true, "about"])
	egal("retour en double ignoré", [ecran.retour(), ecran.page, ecran.visible], [true, "about", true])
	ecran._dernier_retour_ms = -1000
	egal("retour ferme", [ecran.retour(), ecran.visible], [true, false])
	ecran._dernier_retour_ms = -1000
	egal("rien d'ouvert", ecran.retour(), false)
	print("test_about : %d/%d" % [total - echecs, total])
	quit(1 if echecs else 0)
