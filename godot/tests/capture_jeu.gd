extends SceneTree
# Capture d'écran du jeu complet après quelques secondes (vérifications visuelles) :
#   AIMPIRE_CAPTURE=/chemin/image.png godot --path godot -s tests/capture_jeu.gd
# Avec AIMPIRE_REGLAGES=1, le menu des réglages (et sa section de sync) est ouvert au démarrage.

var _images := 0

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")

func _process(_delta: float) -> bool:
	_images += 1
	if _images < int(OS.get_environment("AIMPIRE_CAPTURE_IMAGES") if OS.get_environment("AIMPIRE_CAPTURE_IMAGES") != "" else "300"):
		return false
	var chemin := OS.get_environment("AIMPIRE_CAPTURE")
	if chemin == "":
		chemin = "user://capture.png"
	var err := root.get_texture().get_image().save_png(chemin)
	print("capture ", chemin, " : ", error_string(err))
	return true
