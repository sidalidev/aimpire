extends SceneTree
# Capture et contrôle de la mise en page (docs/MOBILE-PORTRAIT.md §5.2), lancé par tools/capture-portrait.sh :
#   AIMPIRE_AUDIT_SORTIE=<image.png> AIMPIRE_AUDIT_IMAGES=<n> godot --path godot -s tests/audit_portrait.gd
# Charge le jeu, attend n images, enregistre l'image de la fenêtre, puis parcourt les Control visibles du mode téléphone
# et signale : un texte, un bouton ou un champ qui sort de l'écran sur les côtés ou passe sous la zone sûre (poinçon en
# haut, barre de gestes en bas hors d'une liste qui défile), un Label ou un Button sans retour à la ligne plus étroit que
# son texte, une cible tactile de moins de 48 dp, une police de moins de 14 sp. Code de sortie 1 s'il y a quelque chose.

# AIMPIRE_AUDIT_PAGES=n : après la première image, chaque liste qui défile descend d'une hauteur visible, n - 1 fois, avec
# une image et un contrôle à chaque page (<image>-p2.png, …) : le bas des feuilles longues est vérifié aussi.

var _images := 0
var _attendre := 240
var _pages := 1
var _page := 1
var _total := 0

func _initialize() -> void:
	var n := OS.get_environment("AIMPIRE_AUDIT_IMAGES")
	if n.is_valid_int():
		_attendre = int(n)
	var p := OS.get_environment("AIMPIRE_AUDIT_PAGES")
	if p.is_valid_int():
		_pages = maxi(1, int(p))
	change_scene_to_file("res://main.tscn")

func _process(_delta: float) -> bool:
	_images += 1
	if _images < _attendre:
		return false
	# AIMPIRE_AUDIT_TOAST=1 : l'image attend qu'un toast soit affiché (machine lente : il ne dure que quelques secondes)
	if _page == 1 and OS.get_environment("AIMPIRE_AUDIT_TOAST") == "1" and _images < _attendre + 1200:
		var m := current_scene
		if m == null or m.get("hud") == null or not m.hud.toast.visible:
			return false
	var chemin := OS.get_environment("AIMPIRE_AUDIT_SORTIE")
	if chemin != "" and _page > 1:
		chemin = chemin.get_basename() + "-p%d.png" % _page
	if chemin != "":
		var err := root.get_texture().get_image().save_png(chemin)
		print("capture ", chemin, " : ", error_string(err))
	var main := current_scene
	if main == null or main.get("mobile") == null:
		print("audit : pas de mode téléphone, rien à contrôler")
		return true
	var problemes := auditer(root, main.mobile.retraits, root.get_visible_rect().size)
	for p in problemes:
		print("AUDIT ", p)
	_total += problemes.size()
	if _page < _pages and _defiler(root):
		_page += 1
		_attendre = _images + 4
		return false
	print("audit : %d problème(s)" % _total)
	quit(1 if _total else 0)
	return false

# Fait descendre d'une page chaque liste visible qui défile ; false si aucune ne peut plus descendre.
static func _defiler(n: Node) -> bool:
	var bouge := false
	for enfant in n.get_children():
		if enfant is CanvasLayer and not enfant.visible:
			continue
		if enfant is ScrollContainer and enfant.is_visible_in_tree():
			var sc: ScrollContainer = enfant
			var avant := sc.scroll_vertical
			sc.scroll_vertical = avant + int(sc.size.y * 0.9)
			bouge = bouge or sc.scroll_vertical != avant
		bouge = _defiler(enfant) or bouge
	return bouge

static func auditer(racine: Node, retraits: Vector4, vue: Vector2) -> PackedStringArray:
	var out := PackedStringArray()
	var zone := Rect2(retraits.w, retraits.x, vue.x - retraits.w - retraits.y, vue.y - retraits.x - retraits.z)
	_parcourir(racine, zone, vue, out)
	return out

static func _calque_visible(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if p is CanvasLayer and not p.visible:
			return false
		p = p.get_parent()
	return true

# Rectangle réellement visible : coupé par les ancêtres qui rognent leur contenu (défilement) et par l'écran.
static func _visible(c: Control, vue: Vector2) -> Rect2:
	var r := c.get_global_rect()
	var p := c.get_parent()
	while p:
		if p is Control and (p.clip_contents or p is ScrollContainer):
			r = r.intersection(p.get_global_rect())
		p = p.get_parent()
	return r.intersection(Rect2(Vector2.ZERO, vue))

static func _dans_defilement(c: Control) -> bool:
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false

static func _parcourir(n: Node, zone: Rect2, vue: Vector2, out: PackedStringArray) -> void:
	for enfant in n.get_children():
		if enfant is CanvasLayer and not enfant.visible:
			continue
		if enfant is Control:
			var c: Control = enfant
			if not c.is_visible_in_tree() or not _calque_visible(c):
				continue
			_controler(c, zone, vue, out)
		_parcourir(enfant, zone, vue, out)

static func _texte_de(c: Control) -> String:
	if c is Label or c is Button or c is LineEdit:
		return String(c.text).left(40).replace("\n", " ")
	if c is RichTextLabel:
		return c.get_parsed_text().left(40).replace("\n", " ")
	return ""

static func _controler(c: Control, zone: Rect2, vue: Vector2, out: PackedStringArray) -> void:
	var contenu := c is Label or c is BaseButton or c is LineEdit or c is RichTextLabel or c is Slider
	if not contenu:
		return
	var vu := _visible(c, vue)
	if vu.size.x < 1.0 or vu.size.y < 1.0:
		return   # défilé hors de la vue ou hors de l'écran
	var r := c.get_global_rect()
	var nom := "%s \"%s\" %s" % [c.get_class(), _texte_de(c), str(r).replace(" ", "")]
	var vide := _texte_de(c).strip_edges() == "" and not (c is BaseButton)
	if not vide:
		if r.position.x < zone.position.x - 0.5 or r.end.x > zone.end.x + 0.5:
			# coupé sur un côté : seulement si l'ancêtre qui rogne ne le cache pas (texte coupé visible)
			out.append("sort de l'écran sur un côté : " + nom)
		elif vu.position.y < zone.position.y - 0.5:
			out.append("sous la zone sûre du haut : " + nom)
		elif vu.end.y > zone.end.y + 0.5 and not _dans_defilement(c):
			out.append("sous la zone sûre du bas : " + nom)
	if (c is Label and c.autowrap_mode == TextServer.AUTOWRAP_OFF and c.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and not c.clip_text) \
			or (c is Button and c.autowrap_mode == TextServer.AUTOWRAP_OFF and c.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING and not c.clip_text):
		var largeur := c.get_minimum_size().x
		if largeur > c.size.x + 0.5 or (c.get_parent() is Control and r.end.x > (c.get_parent() as Control).get_global_rect().end.x + 0.5 and not (c.get_parent() is ScrollContainer)):
			out.append("texte plus large que sa place : " + nom)
	if (c is BaseButton or c is LineEdit or c is Slider) and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and not (c is BaseButton and c.disabled):
		if minf(r.size.x, r.size.y) < 47.5:
			out.append("cible tactile de moins de 48 dp (%dx%d) : %s" % [int(r.size.x), int(r.size.y), nom])
	var taille := c.get_theme_font_size("normal_font_size") if c is RichTextLabel else c.get_theme_font_size("font_size")
	if taille < 14 and not (c is Slider):
		out.append("police de %d sp : %s" % [taille, nom])
