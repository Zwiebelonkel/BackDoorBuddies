extends Control

const GAME_SCENE_PATH := "res://scenes/main.tscn"


func _ready() -> void:
	$MenuPanel/VBoxContainer/HostButton.grab_focus()


func _on_host_button_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE_PATH)
	await get_tree().process_frame
	Networking.host_lobby()


func _on_options_button_pressed() -> void:
	$OptionsMenu.set_open(true)


func _on_quit_button_pressed() -> void:
	get_tree().quit()
