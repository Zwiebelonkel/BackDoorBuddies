extends Control

const GAME_SCENE_PATH := "res://scenes/main.tscn"


func _ready() -> void:
	$MenuPanel/VBoxContainer/HostButton.grab_focus()


func _on_host_button_pressed() -> void:
	var tree := get_tree()
	tree.paused = false

	var error := tree.change_scene_to_file(GAME_SCENE_PATH)

	if error != OK:
		push_error("Game-Szene konnte nicht geladen werden: %s" % error)
		return

	Networking.host_lobby_after_scene_change()


func _on_options_button_pressed() -> void:
	$OptionsMenu.set_open(true)


func _on_quit_button_pressed() -> void:
	get_tree().quit()
