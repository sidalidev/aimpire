extends Node
# Gestes simulés pour les captures et les mesures de fluidité (AIMPIRE_GESTE sur le Mac, --geste= sur le téléphone) :
# des événements tactiles injectés par Input.parse_input_event à partir de l'image 60, comme ceux d'un vrai doigt.
#   pan        : un doigt glisse de 500 dp vers le haut en 0,5 s, puis se lève à l'arrêt
#   fling      : un doigt lancé vers le haut en 0,15 s, la carte continue de glisser
#   pinch-in   : deux doigts se rapprochent (dézoom), pinch-out : ils s'écartent (zoom)
#   double-tap : deux touchers au centre de l'écran
# `boucle` : le geste recommence toutes les 3 s (mesure des FPS pendant l'interaction).

var main: Node
var nom := ""
var boucle := false
var _image := 0
var _debut := -1
var _pas := 0

func _ready() -> void:
	boucle = nom.ends_with("-loop")
	nom = nom.trim_suffix("-loop")

func _process(_dt: float) -> void:
	_image += 1
	if _image < 60:
		return
	if _debut < 0:
		_debut = _image
	var i := _image - _debut
	var vue: Vector2 = get_viewport().get_visible_rect().size
	var c := vue / 2.0
	match nom:
		"pan":
			_glisser(i, c + Vector2(0, 250), c + Vector2(0, -250), 30, true)
		"fling":
			_glisser(i, c + Vector2(0, 200), c + Vector2(0, -150), 9, false)
		"pinch-in":
			_pincer(i, c, 160.0, 50.0, 30)
		"pinch-out":
			_pincer(i, c, 50.0, 160.0, 30)
		"double-tap":
			if i == 0:
				_toucher(0, c, true, false)
			elif i == 1:
				_toucher(0, c, false, false)
			elif i == 8:
				_toucher(0, c, true, true)
			elif i == 9:
				_toucher(0, c, false, false)
	if boucle and i >= 180:
		_debut = _image + 1

func _toucher(index: int, pos: Vector2, appui: bool, double: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = appui
	e.double_tap = double
	Input.parse_input_event(e)

func _glisse(index: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = rel
	Input.parse_input_event(e)

# Un doigt de `a` à `b` en `n` images ; `repos` : immobile 5 images avant de se lever (pas de lancer).
func _glisser(i: int, a: Vector2, b: Vector2, n: int, repos: bool) -> void:
	if i == 0:
		_toucher(0, a, true, false)
	elif i <= n:
		var p := a.lerp(b, float(i) / n)
		_glisse(0, p, (b - a) / n)
	elif i == n + (6 if repos else 1):
		_toucher(0, b, false, false)

# Deux doigts de part et d'autre du centre, écart `e0` puis `e1` (dp) en `n` images.
func _pincer(i: int, c: Vector2, e0: float, e1: float, n: int) -> void:
	var d := Vector2(1, -1).normalized()
	if i == 0:
		_toucher(0, c - d * e0, true, false)
		_toucher(1, c + d * e0, true, false)
	elif i <= n:
		var e := lerpf(e0, e1, float(i) / n)
		var de := (e1 - e0) / n
		_glisse(0, c - d * e, -d * de)
		_glisse(1, c + d * e, d * de)
	elif i == n + 6:
		_toucher(0, c - d * e1, false, false)
		_toucher(1, c + d * e1, false, false)
