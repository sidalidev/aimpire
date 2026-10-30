extends Node
# Remplaçant minimal de main.gd pour tester camera_rig.gd seul (tests/test_tactile.gd, tests/test_camera_portrait.gd).
var selected := "village-de-depart"
var selected_building := ""
var mobile = null
var villages := {}
var last_state := {}
