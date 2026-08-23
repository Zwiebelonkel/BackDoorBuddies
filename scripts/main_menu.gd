extends Control

const LOBBY_SCENE_PATH := "res://scenes/lobby.tscn"

@onready var menu_panel: PanelContainer = $MenuPanel
@onready var host_button: Button = $MenuPanel/VBoxContainer/HostButton


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_play_intro()
	host_button.grab_focus()


func _play_intro() -> void:
	var resting_position := menu_panel.position
	menu_panel.position = resting_position + Vector2(-28.0, 0.0)
	menu_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(menu_panel, "position", resting_position, 0.55)
	tween.tween_property(
		menu_panel,
		"modulate",
		Color.WHITE,
		0.35
	)


func _on_host_button_pressed() -> void:
	var tree := get_tree()
	tree.paused = false

	var error := tree.change_scene_to_file(LOBBY_SCENE_PATH)

	if error != OK:
		push_error("Lobby-Szene konnte nicht geladen werden: %s" % error)
		return

	Networking.host_lobby_after_scene_change()


func _on_options_button_pressed() -> void:
	$OptionsMenu.set_open(true)


func _on_quit_button_pressed() -> void:
	get_tree().quit()
