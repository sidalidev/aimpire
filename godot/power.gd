extends Node
# Énergie : le jeu ne doit pas vider la batterie. Plafond de FPS selon l'état de la fenêtre, gel du monde quand elle est
# réduite, cadence de sondage du serveur adaptée. Sur batterie, on reste à 30 FPS.
#   premier plan        : 60 FPS (ou le taux de l'écran si plus bas), qualité auto
#   visible sans focus  : 60 FPS (incrustation posée dans un coin pendant que tu travailles), 30 sur batterie
#   réduite / cachée    : 5 FPS, musique en pause, monde gelé, sondage toutes les 5 s
# Téléphone (docs/MOBILE-PORTRAIT.md §3.8) : 60 dès qu'un doigt touche, que la caméra ou une feuille bouge, et 1 s après
# (poke) ; au repos 30 en « Adaptive » ; « Battery saver » : 30, puis 15 après 20 s sans toucher. _apply ne tourne qu'aux
# transitions, jamais à chaque image.

const INTERACTION_MS := 1000

var main: Node
var state := ""
var on_battery := false
var interactif := false      # téléphone : un doigt, la caméra ou une feuille a bougé depuis moins d'une seconde
var _interaction_ms := 0
var _batt_check := 0.0
var _music_was_paused := false

func _ready() -> void:
	# Mac : sans synchro verticale, le plafond de FPS fait tout. Téléphone : synchro gardée, sinon un plafond de 30 obtenu
	# en dormant donne des images irrégulières (saccades en glissant la caméra) et l'écran peut rester à 120 Hz.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if main.mobile else DisplayServer.VSYNC_DISABLED)
	_apply("focus")

# Appelé par la caméra, les feuilles et le premier contact d'un doigt : 60 images par seconde pendant 1 s.
func poke() -> void:
	_interaction_ms = Time.get_ticks_msec()
	if not interactif and main.mobile:
		interactif = true
		_apply(state)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_apply("focus")
		if main.started and main.hud:
			main.hud.fetch_digest()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_apply("blur")
	elif what == NOTIFICATION_APPLICATION_PAUSED:   # téléphone : l'app passe en arrière-plan
		_apply("hidden")
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_apply("focus")

func _process(delta: float) -> void:
	if interactif and Time.get_ticks_msec() - _interaction_ms > INTERACTION_MS:
		interactif = false
		_apply(state)
	var minimized := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
	if minimized and state != "hidden":
		_apply("hidden")
	elif not minimized and state == "hidden":
		_apply("focus" if DisplayServer.window_is_focused() else "blur")
	_batt_check -= delta
	if _batt_check <= 0.0:
		_batt_check = 60.0
		_check_battery()

func _check_battery() -> void:
	if OS.get_name() != "macOS":
		return
	var out := []
	if OS.execute("pmset", ["-g", "batt"], out) == 0 and out.size():
		var was := on_battery
		on_battery = "Battery Power" in String(out[0])
		if was != on_battery:
			_apply(state)

# Plafond du téléphone selon l'interaction et le réglage « Smoothness ».
static func plafond_telephone(interaction: bool, fluidite: String, en_veille: bool) -> int:
	if interaction:
		return 60
	if fluidite == "battery":
		return 15 if en_veille else 30
	return 30

func _apply(s: String) -> void:
	var state_prev := state
	state = s
	var screen_hz := DisplayServer.screen_get_refresh_rate()
	var top := int(screen_hz) if screen_hz > 0 else 60
	if main.mobile:
		top = plafond_telephone(interactif, main.mobile.fluidite, main.mobile.en_veille)
		on_battery = false
	match s:
		"focus":
			Engine.max_fps = 30 if on_battery else top
		"blur":
			Engine.max_fps = 30 if on_battery else mini(60, top)
		"hidden":
			Engine.max_fps = 5
	var hidden := s == "hidden"
	if hidden != (state_prev == "hidden") or state_prev == "":
		if main.world:
			main.world.process_mode = Node.PROCESS_MODE_DISABLED if hidden else Node.PROCESS_MODE_INHERIT
		if main.poll_timer:
			main.poll_timer.wait_time = 5.0 if hidden else 0.5
	if main.audio:
		if hidden and state_prev != "hidden":
			_music_was_paused = main.audio.music.stream_paused
			main.audio.music.stream_paused = true
		elif not hidden and state_prev == "hidden":
			main.audio.music.stream_paused = _music_was_paused
