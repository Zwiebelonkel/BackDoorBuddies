extends CanvasLayer

const MIN_FPS := 30
const MAX_FPS := 240
const DEFAULT_FPS := 60
const MIN_LOOK_SENSITIVITY := 0.25
const MAX_LOOK_SENSITIVITY := 3.0
const DEFAULT_LOOK_SENSITIVITY := 1.0
const OPTIONS_CONFIG_PATH := "user://options.cfg"
const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"

@export var show_exit_to_main_menu := false

@onready var panel: PanelContainer = $PanelContainer
@onready var fps_spin_box: SpinBox = $PanelContainer/MarginContainer/VBoxContainer/FpsRow/FpsSpinBox
@onready var fullscreen_check_box: CheckBox = $PanelContainer/MarginContainer/VBoxContainer/FullscreenRow/FullscreenCheckBox
@onready var volume_slider: HSlider = $PanelContainer/MarginContainer/VBoxContainer/VolumeRow/VolumeSlider
@onready var volume_value_label: Label = $PanelContainer/MarginContainer/VBoxContainer/VolumeRow/VolumeValueLabel
@onready var look_sensitivity_slider: HSlider = $PanelContainer/MarginContainer/VBoxContainer/LookSensitivityRow/LookSensitivitySlider
@onready var look_sensitivity_value_label: Label = $PanelContainer/MarginContainer/VBoxContainer/LookSensitivityRow/LookSensitivityValueLabel
@onready var exit_to_main_menu_button: Button = $PanelContainer/MarginContainer/VBoxContainer/ExitToMainMenuButton

var _config := ConfigFile.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	exit_to_main_menu_button.visible = show_exit_to_main_menu
	_load_options()
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	set_open(not visible)


func set_open(is_open: bool) -> void:
	visible = is_open
	get_tree().paused = is_open

	if is_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		fps_spin_box.grab_focus()
	else:
		Input.mouse_mode = (
			Input.MOUSE_MODE_CAPTURED
			if show_exit_to_main_menu
			else Input.MOUSE_MODE_VISIBLE
		)
		_save_options()


func _load_options() -> void:
	_config.load(OPTIONS_CONFIG_PATH)

	var fps := int(_config.get_value("video", "max_fps", DEFAULT_FPS))
	var fullscreen := bool(_config.get_value("video", "fullscreen", false))
	var volume := float(_config.get_value("audio", "master_volume", 1.0))
	var look_sensitivity := float(
		_config.get_value(
			"controls",
			"look_sensitivity",
			DEFAULT_LOOK_SENSITIVITY
		)
	)

	_apply_max_fps(fps)
	_apply_fullscreen(fullscreen)
	_apply_master_volume(volume)
	_apply_look_sensitivity(look_sensitivity)

	fps_spin_box.value = Engine.max_fps if Engine.max_fps > 0 else DEFAULT_FPS
	fullscreen_check_box.button_pressed = _is_fullscreen()
	volume_slider.value = volume
	_update_volume_label(volume)
	look_sensitivity_slider.value = clampf(
		look_sensitivity,
		MIN_LOOK_SENSITIVITY,
		MAX_LOOK_SENSITIVITY
	)
	_update_look_sensitivity_label(look_sensitivity_slider.value)


func _save_options() -> void:
	_config.set_value("video", "max_fps", int(fps_spin_box.value))
	_config.set_value("video", "fullscreen", fullscreen_check_box.button_pressed)
	_config.set_value("audio", "master_volume", volume_slider.value)
	_config.set_value(
		"controls",
		"look_sensitivity",
		look_sensitivity_slider.value
	)
	_config.save(OPTIONS_CONFIG_PATH)


func _apply_max_fps(fps: int) -> void:
	Engine.max_fps = clampi(fps, MIN_FPS, MAX_FPS)


func _apply_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
	)


func _apply_master_volume(linear_volume: float) -> void:
	var clamped_volume := clampf(linear_volume, 0.0, 1.0)
	var master_bus_index := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_bus_index, linear_to_db(clamped_volume))
	AudioServer.set_bus_mute(master_bus_index, is_zero_approx(clamped_volume))


func _apply_look_sensitivity(sensitivity: float) -> void:
	var clamped_sensitivity := clampf(
		sensitivity,
		MIN_LOOK_SENSITIVITY,
		MAX_LOOK_SENSITIVITY
	)

	for player in get_tree().get_nodes_in_group("local_player_controller"):
		if player.has_method("apply_look_sensitivity"):
			player.apply_look_sensitivity(clamped_sensitivity)


func _is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func _update_volume_label(linear_volume: float) -> void:
	volume_value_label.text = "%d%%" % roundi(linear_volume * 100.0)


func _update_look_sensitivity_label(sensitivity: float) -> void:
	look_sensitivity_value_label.text = "%d%%" % roundi(sensitivity * 100.0)


func _on_fps_spin_box_value_changed(value: float) -> void:
	_apply_max_fps(int(value))
	_save_options()


func _on_fullscreen_check_box_toggled(toggled_on: bool) -> void:
	_apply_fullscreen(toggled_on)
	_save_options()


func _on_volume_slider_value_changed(value: float) -> void:
	_apply_master_volume(value)
	_update_volume_label(value)
	_save_options()


func _on_look_sensitivity_slider_value_changed(value: float) -> void:
	_apply_look_sensitivity(value)
	_update_look_sensitivity_label(value)
	_save_options()


func _on_close_button_pressed() -> void:
	set_open(false)


func _on_exit_to_main_menu_button_pressed() -> void:
	_save_options()
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Networking.leave_lobby()

	var error := get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)

	if error != OK:
		push_error("Hauptmenü konnte nicht geladen werden: %s" % error)
