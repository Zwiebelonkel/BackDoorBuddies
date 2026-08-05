extends CanvasLayer

const MIN_FPS := 30
const MAX_FPS := 240
const DEFAULT_FPS := 60
const OPTIONS_CONFIG_PATH := "user://options.cfg"

@onready var panel: PanelContainer = $PanelContainer
@onready var fps_spin_box: SpinBox = $PanelContainer/MarginContainer/VBoxContainer/FpsRow/FpsSpinBox
@onready var fullscreen_check_box: CheckBox = $PanelContainer/MarginContainer/VBoxContainer/FullscreenRow/FullscreenCheckBox
@onready var volume_slider: HSlider = $PanelContainer/MarginContainer/VBoxContainer/VolumeRow/VolumeSlider
@onready var volume_value_label: Label = $PanelContainer/MarginContainer/VBoxContainer/VolumeRow/VolumeValueLabel

var _config := ConfigFile.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
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
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_save_options()


func _load_options() -> void:
	_config.load(OPTIONS_CONFIG_PATH)

	var fps := int(_config.get_value("video", "max_fps", DEFAULT_FPS))
	var fullscreen := bool(_config.get_value("video", "fullscreen", false))
	var volume := float(_config.get_value("audio", "master_volume", 1.0))

	_apply_max_fps(fps)
	_apply_fullscreen(fullscreen)
	_apply_master_volume(volume)

	fps_spin_box.value = Engine.max_fps if Engine.max_fps > 0 else DEFAULT_FPS
	fullscreen_check_box.button_pressed = _is_fullscreen()
	volume_slider.value = volume
	_update_volume_label(volume)


func _save_options() -> void:
	_config.set_value("video", "max_fps", int(fps_spin_box.value))
	_config.set_value("video", "fullscreen", fullscreen_check_box.button_pressed)
	_config.set_value("audio", "master_volume", volume_slider.value)
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


func _is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func _update_volume_label(linear_volume: float) -> void:
	volume_value_label.text = "%d%%" % roundi(linear_volume * 100.0)


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


func _on_close_button_pressed() -> void:
	set_open(false)
