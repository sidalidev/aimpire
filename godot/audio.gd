extends Node
# Son : bus Musique / Voix / Effets avec compresseur et limiteur sur le master (fort sans saturer),
# musique en boucle, répliques pré-générées (5 voix), voix détaillées à la demande (serveur /voix), effets.

var main: Node
var music := AudioStreamPlayer.new()
var voice := AudioStreamPlayer.new()
var sfx_pool: Array[AudioStreamPlayer] = []   # trois lecteurs d'effets : plusieurs sons courts peuvent se chevaucher
var ambient := AudioStreamPlayer.new()         # oiseaux et vent, en boucle discrète
var tts := HTTPRequest.new()
var voices := {}          # catégorie -> voix -> [AudioStream]   (fichiers voix/<cat>_<voix>_<n>.mp3)
var sounds := {}          # nom -> AudioStream (assets/sfx)
var last_voice := -10000

const LINES := {
	"travail": ["To work!", "Right away.", "Let's get to it!", "Understood.", "On my way!", "Here we go.", "Let's go!"],
	"fini": ["Done.", "Work finished!", "Mission accomplished.", "That's done.", "All done, chief!"],
	"attente": ["Awaiting your orders.", "Yes?", "Any instructions?"],
	"nouveau": ["Ready to serve!", "Here I am.", "At your command!"],
	"renfort": ["I'll handle it.", "Sending backup!", "On the way!"],
}

func setup() -> void:
	for bus in ["Musique", "Voix", "Effets"]:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, bus)
		AudioServer.set_bus_send(i, "Master")
	var comp := AudioEffectCompressor.new()
	comp.threshold = -12.0
	comp.ratio = 3.0
	AudioServer.add_bus_effect(0, comp)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.0
	AudioServer.add_bus_effect(0, lim)
	# musique : la boucle CC0 livrée avec le jeu, ou ta musique perso dans assets/music/local/ (ignorée par git) si elle existe
	var stream: AudioStream
	if ResourceLoader.exists("res://assets/music/local/ambiance.mp3"):
		var mp3: AudioStreamMP3 = load("res://assets/music/local/ambiance.mp3")
		mp3.loop = true
		stream = mp3
	else:
		var ogg: AudioStreamOggVorbis = load("res://assets/music/ambiance.ogg")
		ogg.loop = true
		stream = ogg
	music.stream = stream
	music.bus = "Musique"
	music.autoplay = true
	add_child(music)
	voice.bus = "Voix"
	add_child(voice)
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.bus = "Effets"
		add_child(p)
		sfx_pool.append(p)
	ambient.bus = "Effets"
	ambient.volume_db = -14.0
	add_child(ambient)
	add_child(tts)
	tts.request_completed.connect(_on_tts)
	_load_voices()
	if DirAccess.dir_exists_absolute("res://assets/sfx"):
		for f0 in DirAccess.get_files_at("res://assets/sfx"):
			var f := f0.trim_suffix(".import").trim_suffix(".remap")
			if (f.ends_with(".mp3") or f.ends_with(".wav") or f.ends_with(".ogg")) and not sounds.has(f.get_basename()):
				sounds[f.get_basename()] = load("res://assets/sfx/" + f)
	if sounds.has("oiseaux"):
		var o: AudioStream = sounds["oiseaux"]
		if o is AudioStreamOggVorbis:
			o.loop = true
		ambient.stream = o
		ambient.play()

# Pre-generated villager lines (godot/assets/voix/<cat>_<voice>_<n>.mp3). They are not shipped with the source:
# tools/gen-voices.mjs creates them with your own ELEVENLABS_API_KEY. Without them the villagers stay silent and
# only show their speech bubble.
func _load_voices() -> void:
	const DIR := "res://assets/voix"
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for f0 in DirAccess.get_files_at(DIR):
		var f := f0.trim_suffix(".import").trim_suffix(".remap")   # in an export, resources show up under these names
		if not f.ends_with(".mp3"):
			continue
		var parts := f.get_basename().split("_")
		if parts.size() != 3 or not LINES.has(parts[0]) or not parts[1].is_valid_int() or not parts[2].is_valid_int():
			continue
		var cat: String = parts[0]
		var vi := int(parts[1])
		var li := int(parts[2])
		if vi < 0 or li < 0 or li >= LINES[cat].size() or not ResourceLoader.exists(DIR + "/" + f):
			continue
		var stream = load(DIR + "/" + f)
		if not (stream is AudioStream):
			continue
		if not voices.has(cat):
			voices[cat] = {}
		if not voices[cat].has(vi):
			voices[cat][vi] = []
		while voices[cat][vi].size() <= li:
			voices[cat][vi].append(null)
		voices[cat][vi][li] = stream

func toggle_music() -> void:
	music.stream_paused = not music.stream_paused

func play_sfx(name: String, volume_db: float = 0.0) -> void:
	if not sounds.has(name):
		return
	for p in sfx_pool:
		if not p.playing:
			p.stream = sounds[name]
			p.volume_db = volume_db
			p.play()
			return

# Phrase courte et propre tirée d'un message : sans markdown, coupée à la première phrase, n caractères au plus.
static func short(t: String, n: int = 70) -> String:
	var x := t
	for ch in ["**", "`", "#", "*", "_", ">", "[", "]"]:
		x = x.replace(ch, "")
	x = x.replace("\n", " ").strip_edges()
	for stop in [". ", "! ", "? ", ": ", "; "]:
		var i := x.find(stop)
		if i > 12:
			x = x.substr(0, i)
	if x.length() > n:
		x = x.substr(0, n)
		var sp := x.rfind(" ")
		if sp > 20:
			x = x.substr(0, sp)
		x += "…"
	return x

# Un personnage parle. Avec `text` : bulle précise (« pense » au début d'une tâche, « dit » à la fin), et voix détaillée si activée.
func say(cat: String, p: Node, text: String = "") -> void:
	var st: Dictionary = main.settings.data
	if text != "" and main.started:
		p.say_text(text, "pense" if cat == "travail" else "dit")
		if st.voix_on and st.voix_detaillees and main.mobile == null and Time.get_ticks_msec() - last_voice > 2200:
			last_voice = Time.get_ticks_msec()
			if tts.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
				tts.request(main.net.url("/voix?t=%s&v=%d" % [text.uri_encode(), int(p.voice)]), main.net.headers())
			return
	if not main.started or not st.voix_on or Time.get_ticks_msec() - last_voice < 2200:
		return
	if not voices.has(cat) or voices[cat].is_empty():
		# no voice files (they are generated locally by tools/gen-voices.mjs): the bubble alone
		if text == "" and LINES.has(cat):
			last_voice = Time.get_ticks_msec()
			p.say_text(LINES[cat][randi() % LINES[cat].size()])
		return
	var by_voice: Dictionary = voices[cat]
	var vi: int = p.voice % by_voice.size()
	var pool: Array = by_voice.get(vi, by_voice.values()[0])
	if pool.is_empty():
		return
	var i: int = randi() % pool.size()
	if pool[i] == null:
		return
	last_voice = Time.get_ticks_msec()
	_play_voice(pool[i])
	if text == "":
		p.say_text(LINES[cat][min(i, LINES[cat].size() - 1)])

func _on_tts(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200 or body.is_empty():
		return
	var st := AudioStreamMP3.new()
	st.data = body
	_play_voice(st)

# Joue une voix en baissant un peu la musique le temps de la phrase.
func _play_voice(stream: AudioStream) -> void:
	voice.stream = stream
	voice.play()
	var idx := AudioServer.get_bus_index("Musique")
	var base := linear_to_db(maxf(main.settings.data.musique, 0.0001))
	var duck := create_tween()
	duck.tween_method(func(d): AudioServer.set_bus_volume_db(idx, d), base, base - 7.0, 0.2)
	duck.tween_interval(stream.get_length())
	duck.tween_method(func(d): AudioServer.set_bus_volume_db(idx, d), base - 7.0, base, 0.8)
