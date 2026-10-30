extends RefCounted
# Accès au serveur local : adresse (AIMPIRE_PORT), jeton lu dans le dossier de données (le serveur l'y écrit en 0600).
# Le dossier de données est le même que celui du serveur : AIMPIRE_HOME, sinon ~/Library/Application Support/AImpire.

var base := "http://127.0.0.1:7777"
var token := ""

func _init() -> void:
	var port := OS.get_environment("AIMPIRE_PORT")
	if port != "":
		base = "http://127.0.0.1:" + port
	# Le jeton est lu à la première requête protégée (headers) : en mode téléphone, il n'est jamais lu.

static func data_dir() -> String:
	var home := OS.get_environment("AIMPIRE_HOME")
	if home != "":
		return home
	match OS.get_name():
		"macOS":
			return OS.get_environment("HOME") + "/Library/Application Support/AImpire"
		"Windows":
			return OS.get_environment("APPDATA") + "\\AImpire"
		_:
			var xdg := OS.get_environment("XDG_DATA_HOME")
			return (xdg if xdg != "" else OS.get_environment("HOME") + "/.local/share") + "/aimpire"

func _read_token() -> String:
	var f := FileAccess.open(data_dir().path_join("token"), FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text().strip_edges()

# En-têtes à joindre aux requêtes protégées (POST, voix). Relit le jeton s'il manquait (serveur démarré après le jeu).
func headers() -> PackedStringArray:
	if token == "":
		token = _read_token()
	return PackedStringArray(["Authorization: Bearer " + token])

func url(path: String) -> String:
	return base + path

# Chemin du serveur : binaire embarqué dans l'app (Contents/Resources/aimpire-server), sinon `node daemon/server.js` du dépôt.
static func server_command() -> Array:
	var exe := OS.get_executable_path().get_base_dir()
	var embedded := exe.path_join("../Resources/aimpire-server")
	if FileAccess.file_exists(embedded):
		return [embedded, []]
	var script := ProjectSettings.globalize_path("res://").path_join("../daemon/server.js")
	if FileAccess.file_exists(script):
		for node in ["/opt/homebrew/bin/node", "/usr/local/bin/node"]:
			if FileAccess.file_exists(node):
				return [node, [script]]
		var nvm := OS.get_environment("HOME") + "/.nvm/versions/node"
		var versions := DirAccess.get_directories_at(nvm)
		if versions.size():
			versions.sort()
			return [nvm.path_join(versions[-1]).path_join("bin/node"), [script]]
		return ["/usr/bin/env", ["node", script]]
	return []

var _pid := 0
var _fails := 0
var _next_try := 0.0

# Appelé quand /state échoue : relance le serveur avec un délai croissant (1, 2, 5, 15 s).
func on_failure() -> void:
	_fails += 1
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next_try:
		return
	var delays := [1.0, 2.0, 5.0, 15.0]
	_next_try = now + delays[mini(_fails - 1, delays.size() - 1)]
	if _fails < 3:
		return
	var cmd := server_command()
	if cmd.is_empty():
		return
	var args: PackedStringArray = PackedStringArray(cmd[1])
	args.append("--parent-pid=%d" % OS.get_process_id())
	_pid = OS.create_process(String(cmd[0]), args)
	print("server restarted (pid %d)" % _pid)

func on_success() -> void:
	_fails = 0
