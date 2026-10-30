extends RefCounted
# Retour haptique du téléphone (docs/MOBILE-PORTRAIT.md §3.7) : View.performHapticFeedback sur la vue racine de
# l'activité, appelé sur le fil de l'interface d'Android. Passer par la vue respecte le réglage système (vibrations au
# toucher coupées = rien) et n'exige aucune permission. Jamais Input.vibrate_handheld : il demande VIBRATE, que
# tools/check-repo.mjs refuse (docs/permissions.txt). Sans effet sur le Mac. Une vibration toutes les 50 ms au plus.

const LONG_PRESS := 0
const VIRTUAL_KEY := 1
const CLOCK_TICK := 4
const GESTURE_END := 13
const CONFIRM := 16
const REJECT := 17
const INTERVALLE_MS := 50

static var _dernier_ms := -1000
static var desactive := false   # tests

# Bouton de la barre, « x » d'une feuille, contrôle segmenté.
static func press() -> void:
	_jouer(VIRTUAL_KEY, VIRTUAL_KEY)

# Sélection changée, bord du monde atteint, limite du zoom franchie.
static func tick() -> void:
	_jouer(CLOCK_TICK, CLOCK_TICK)

# Une feuille se pose sur un cran après un glissé.
static func snap() -> void:
	_jouer(GESTURE_END, CLOCK_TICK)

# « Applied by the Mac ».
static func confirm() -> void:
	_jouer(CONFIRM, VIRTUAL_KEY)

# Commande refusée, Mac hors ligne, relais en erreur.
static func reject() -> void:
	_jouer(REJECT, LONG_PRESS)

static func disponible() -> bool:
	return not desactive and OS.get_name() == "Android" and Engine.has_singleton("AndroidRuntime")

static func _jouer(constante: int, repli: int) -> void:
	if not disponible():
		return
	var t := Time.get_ticks_msec()
	if t - _dernier_ms < INTERVALLE_MS:
		return
	_dernier_ms = t
	var rt = Engine.get_singleton("AndroidRuntime")
	var activite = rt.getActivity()
	if activite == null:
		return
	activite.runOnUiThread(rt.createRunnableFromGodotCallable(func():
		var vue = activite.getWindow().getDecorView()
		if vue != null and not vue.performHapticFeedback(constante):
			vue.performHapticFeedback(repli)))
