extends CanvasLayer

const MIN_FPS := 30
const MAX_FPS := 240
const DEFAULT_FPS := 60
const MIN_RENDER_SCALE := 0.5
const MAX_RENDER_SCALE := 1.0
const DEFAULT_RENDER_SCALE := 1.0
const PERFORMANCE_RENDER_SCALE := 0.65
const DEFAULT_MSAA := Viewport.MSAA_DISABLED
const MIN_LOOK_SENSITIVITY := 0.25
const MAX_LOOK_SENSITIVITY := 3.0
const DEFAULT_LOOK_SENSITIVITY := 1.0
const OPTIONS_CONFIG_PATH := "user://options.cfg"
const MAIN_MENU_SCENE_PATH := "res://scenes/main_menu.tscn"

const META_DEFAULT_SHADOWS := &"options_default_shadows"
const META_DEFAULT_FOG := &"options_default_fog"
const META_DEFAULT_VOLUMETRIC_FOG := &"options_default_volumetric_fog"
const META_DEFAULT_GLOW := &"options_default_glow"
const META_DEFAULT_SDFGI := &"options_default_sdfgi"

@export var show_exit_to_main_menu := false

@onready var panel: PanelContainer = $PanelContainer
@onready var tabs: TabContainer = $PanelContainer/MarginContainer/VBoxContainer/Tabs
@onready var volume_slider: HSlider = $PanelContainer/MarginContainer/VBoxContainer/Tabs/General/GeneralMargin/GeneralOptions/VolumeRow/VolumeSlider
@onready var volume_value_label: Label = $PanelContainer/MarginContainer/VBoxContainer/Tabs/General/GeneralMargin/GeneralOptions/VolumeRow/VolumeValueLabel
@onready var look_sensitivity_slider: HSlider = $PanelContainer/MarginContainer/VBoxContainer/Tabs/General/GeneralMargin/GeneralOptions/LookSensitivityRow/LookSensitivitySlider
@onready var look_sensitivity_value_label: Label = $PanelContainer/MarginContainer/VBoxContainer/Tabs/General/GeneralMargin/GeneralOptions/LookSensitivityRow/LookSensitivityValueLabel
@onready var hide_own_body_check_box: CheckBox = $PanelContainer/MarginContainer/VBoxContainer/Tabs/General/GeneralMargin/GeneralOptions/HideOwnBodyRow/HideOwnBodyCheckBox
@onready var fps_spin_box: SpinBox = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Graphics/GraphicsScroll/GraphicsMargin/GraphicsOptions/FpsRow/FpsSpinBox
@onready var fullscreen_check_box: CheckBox = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Graphics/GraphicsScroll/GraphicsMargin/GraphicsOptions/FullscreenRow/FullscreenCheckBox
@onready var vsync_check_box: CheckBox = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Graphics/GraphicsScroll/GraphicsMargin/GraphicsOptions/VsyncRow/VsyncCheckBox
@onready var render_scale_slider: HSlider = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Graphics/GraphicsScroll/GraphicsMargin/GraphicsOptions/RenderScaleRow/RenderScaleSlider
@onready var render_scale_value_label: Label = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Graphics/GraphicsScroll/GraphicsMargin/GraphicsOptions/RenderScaleRow/RenderScaleValueLabel
@onready var msaa_option_button: OptionButton = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Graphics/GraphicsScroll/GraphicsMargin/GraphicsOptions/MsaaRow/MsaaOptionButton
@onready var shadows_check_box: CheckBox = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Graphics/GraphicsScroll/GraphicsMargin/GraphicsOptions/ShadowsRow/ShadowsCheckBox
@onready var fog_check_box: CheckBox = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Graphics/GraphicsScroll/GraphicsMargin/GraphicsOptions/FogRow/FogCheckBox
@onready var glow_check_box: CheckBox = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Graphics/GraphicsScroll/GraphicsMargin/GraphicsOptions/GlowRow/GlowCheckBox
@onready var sdfgi_check_box: CheckBox = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Graphics/GraphicsScroll/GraphicsMargin/GraphicsOptions/SdfgiRow/SdfgiCheckBox
@onready var hud_canvas_filters_check_box: CheckBox = $PanelContainer/MarginContainer/VBoxContainer/Tabs/Graphics/GraphicsScroll/GraphicsMargin/GraphicsOptions/HudCanvasFiltersRow/HudCanvasFiltersCheckBox
@onready var exit_to_main_menu_button: Button = $PanelContainer/MarginContainer/VBoxContainer/Footer/ExitToMainMenuButton

var _config := ConfigFile.new()
var _loading_options := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	exit_to_main_menu_button.visible = show_exit_to_main_menu
	_setup_msaa_options()
	_load_options()

	if not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)

	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		for player in get_tree().get_nodes_in_group("local_player_controller"):
			if (
				player.has_method("is_using_cabinet_storage")
				and bool(player.call("is_using_cabinet_storage"))
			):
				player.call("exit_cabinet_storage")
				get_viewport().set_input_as_handled()
				return

			if (
				player.has_method("is_using_darknet_terminal")
				and bool(player.call("is_using_darknet_terminal"))
			):
				player.call("exit_darknet_terminal")
				get_viewport().set_input_as_handled()
				return

			if (
				player.has_method("is_using_camera_monitor")
				and player.is_using_camera_monitor()
			):
				player.exit_camera_monitor()
				get_viewport().set_input_as_handled()
				return

		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	set_open(not visible)


func set_open(is_open: bool) -> void:
	visible = is_open
	get_tree().paused = is_open

	if is_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if tabs.current_tab == 0:
			volume_slider.grab_focus()
		else:
			fps_spin_box.grab_focus()
	else:
		Input.mouse_mode = (
			Input.MOUSE_MODE_CAPTURED
			if show_exit_to_main_menu
			else Input.MOUSE_MODE_VISIBLE
		)
		_save_options()


func _setup_msaa_options() -> void:
	msaa_option_button.clear()
	msaa_option_button.add_item("Off", Viewport.MSAA_DISABLED)
	msaa_option_button.add_item("2x", Viewport.MSAA_2X)
	msaa_option_button.add_item("4x", Viewport.MSAA_4X)
	msaa_option_button.add_item("8x", Viewport.MSAA_8X)


func _load_options() -> void:
	_config.load(OPTIONS_CONFIG_PATH)
	_loading_options = true

	var fps := clampi(
		int(_config.get_value("video", "max_fps", DEFAULT_FPS)),
		MIN_FPS,
		MAX_FPS
	)
	var fullscreen := bool(_config.get_value("video", "fullscreen", false))
	var vsync := bool(_config.get_value("video", "vsync", true))
	var render_scale := clampf(
		float(
			_config.get_value(
				"graphics",
				"render_scale",
				DEFAULT_RENDER_SCALE
			)
		),
		MIN_RENDER_SCALE,
		MAX_RENDER_SCALE
	)
	var msaa := int(_config.get_value("graphics", "msaa_3d", DEFAULT_MSAA))
	var shadows := bool(_config.get_value("graphics", "shadows", true))
	var fog := bool(_config.get_value("graphics", "fog", true))
	var glow := bool(_config.get_value("graphics", "glow", true))
	var sdfgi := bool(_config.get_value("graphics", "sdfgi", true))
	var hud_canvas_filters := bool(
		_config.get_value("graphics", "hud_canvas_filters", true)
	)
	var volume := clampf(
		float(_config.get_value("audio", "master_volume", 1.0)),
		0.0,
		1.0
	)
	var look_sensitivity := clampf(
		float(
			_config.get_value(
				"controls",
				"look_sensitivity",
				DEFAULT_LOOK_SENSITIVITY
			)
		),
		MIN_LOOK_SENSITIVITY,
		MAX_LOOK_SENSITIVITY
	)
	var hide_own_body := bool(
		_config.get_value("gameplay", "hide_own_body", false)
	)

	fps_spin_box.value = fps
	fullscreen_check_box.button_pressed = fullscreen
	vsync_check_box.button_pressed = vsync
	render_scale_slider.value = render_scale
	_update_render_scale_label(render_scale)
	_select_msaa(msaa)
	shadows_check_box.button_pressed = shadows
	fog_check_box.button_pressed = fog
	glow_check_box.button_pressed = glow
	sdfgi_check_box.button_pressed = sdfgi
	hud_canvas_filters_check_box.button_pressed = hud_canvas_filters
	volume_slider.value = volume
	_update_volume_label(volume)
	look_sensitivity_slider.value = look_sensitivity
	_update_look_sensitivity_label(look_sensitivity)
	hide_own_body_check_box.button_pressed = hide_own_body

	_loading_options = false
	_apply_all_options()


func _save_options() -> void:
	if _loading_options:
		return

	_config.set_value("video", "max_fps", int(fps_spin_box.value))
	_config.set_value("video", "fullscreen", fullscreen_check_box.button_pressed)
	_config.set_value("video", "vsync", vsync_check_box.button_pressed)
	_config.set_value("graphics", "render_scale", render_scale_slider.value)
	_config.set_value("graphics", "msaa_3d", _get_selected_msaa())
	_config.set_value("graphics", "shadows", shadows_check_box.button_pressed)
	_config.set_value("graphics", "fog", fog_check_box.button_pressed)
	_config.set_value("graphics", "glow", glow_check_box.button_pressed)
	_config.set_value("graphics", "sdfgi", sdfgi_check_box.button_pressed)
	_config.set_value(
		"graphics",
		"hud_canvas_filters",
		hud_canvas_filters_check_box.button_pressed
	)
	_config.set_value("audio", "master_volume", volume_slider.value)
	_config.set_value(
		"controls",
		"look_sensitivity",
		look_sensitivity_slider.value
	)
	_config.set_value(
		"gameplay",
		"hide_own_body",
		hide_own_body_check_box.button_pressed
	)

	var error := _config.save(OPTIONS_CONFIG_PATH)
	if error != OK:
		push_warning("Optionen konnten nicht gespeichert werden: %s" % error)


func _apply_all_options() -> void:
	_apply_max_fps(int(fps_spin_box.value))
	_apply_fullscreen(fullscreen_check_box.button_pressed)
	_apply_vsync(vsync_check_box.button_pressed)
	_apply_render_scale(render_scale_slider.value)
	_apply_msaa(_get_selected_msaa())
	_apply_world_graphics()
	_apply_hud_canvas_filters(hud_canvas_filters_check_box.button_pressed)
	_apply_master_volume(volume_slider.value)
	_apply_look_sensitivity(look_sensitivity_slider.value)
	_apply_hide_own_body(hide_own_body_check_box.button_pressed)


func _apply_max_fps(fps: int) -> void:
	Engine.max_fps = clampi(fps, MIN_FPS, MAX_FPS)


func _apply_fullscreen(enabled: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN
		if enabled
		else DisplayServer.WINDOW_MODE_WINDOWED
	)


func _apply_vsync(enabled: bool) -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED
		if enabled
		else DisplayServer.VSYNC_DISABLED
	)


func _apply_render_scale(scale: float) -> void:
	get_viewport().scaling_3d_scale = clampf(
		scale,
		MIN_RENDER_SCALE,
		MAX_RENDER_SCALE
	)


func _apply_msaa(msaa: int) -> void:
	get_viewport().msaa_3d = msaa as Viewport.MSAA


func _apply_world_graphics() -> void:
	# The traversal also catches dynamically generated rooms, players and lights.
	_apply_graphics_to_branch(get_tree().root)


func _apply_graphics_to_branch(node: Node) -> void:
	_apply_graphics_to_node(node)

	for child in node.get_children():
		_apply_graphics_to_branch(child)


func _apply_graphics_to_node(node: Node) -> void:
	if not is_instance_valid(node):
		return

	if node is Light3D:
		var light := node as Light3D
		if not light.has_meta(META_DEFAULT_SHADOWS):
			light.set_meta(META_DEFAULT_SHADOWS, light.shadow_enabled)
		light.shadow_enabled = (
			bool(light.get_meta(META_DEFAULT_SHADOWS))
			and shadows_check_box.button_pressed
		)
	elif node is WorldEnvironment:
		_apply_environment_graphics((node as WorldEnvironment).environment)
	elif node is Camera3D:
		_apply_environment_graphics((node as Camera3D).environment)


func _apply_environment_graphics(environment: Environment) -> void:
	if environment == null:
		return

	if not environment.has_meta(META_DEFAULT_FOG):
		environment.set_meta(META_DEFAULT_FOG, environment.fog_enabled)
	if not environment.has_meta(META_DEFAULT_VOLUMETRIC_FOG):
		environment.set_meta(
			META_DEFAULT_VOLUMETRIC_FOG,
			environment.volumetric_fog_enabled
		)
	if not environment.has_meta(META_DEFAULT_GLOW):
		environment.set_meta(META_DEFAULT_GLOW, environment.glow_enabled)
	if not environment.has_meta(META_DEFAULT_SDFGI):
		environment.set_meta(META_DEFAULT_SDFGI, environment.sdfgi_enabled)

	environment.fog_enabled = (
		bool(environment.get_meta(META_DEFAULT_FOG))
		and fog_check_box.button_pressed
	)
	environment.volumetric_fog_enabled = (
		bool(environment.get_meta(META_DEFAULT_VOLUMETRIC_FOG))
		and fog_check_box.button_pressed
	)
	environment.glow_enabled = (
		bool(environment.get_meta(META_DEFAULT_GLOW))
		and glow_check_box.button_pressed
	)
	environment.sdfgi_enabled = (
		bool(environment.get_meta(META_DEFAULT_SDFGI))
		and sdfgi_check_box.button_pressed
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


func _apply_hide_own_body(enabled: bool) -> void:
	for player in get_tree().get_nodes_in_group("local_player_controller"):
		if player.has_method("apply_hide_own_body"):
			player.apply_hide_own_body(enabled)


func _apply_hud_canvas_filters(enabled: bool) -> void:
	for hud in get_tree().get_nodes_in_group("player_hud"):
		_apply_hud_canvas_filters_to_node(hud, enabled)


func _apply_hud_canvas_filters_to_node(node: Node, enabled: bool) -> void:
	if (
		is_instance_valid(node)
		and node.has_method("set_hud_canvas_filters_enabled")
	):
		node.call("set_hud_canvas_filters_enabled", enabled)


func _is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func _select_msaa(msaa: int) -> void:
	var item_index := msaa_option_button.get_item_index(msaa)
	if item_index < 0:
		item_index = msaa_option_button.get_item_index(DEFAULT_MSAA)
	msaa_option_button.select(item_index)


func _get_selected_msaa() -> int:
	return msaa_option_button.get_selected_id()


func _update_volume_label(linear_volume: float) -> void:
	volume_value_label.text = "%d%%" % roundi(linear_volume * 100.0)


func _update_look_sensitivity_label(sensitivity: float) -> void:
	look_sensitivity_value_label.text = "%d%%" % roundi(sensitivity * 100.0)


func _update_render_scale_label(scale: float) -> void:
	render_scale_value_label.text = "%d%%" % roundi(scale * 100.0)


func _on_tree_node_added(node: Node) -> void:
	if node is Light3D or node is WorldEnvironment or node is Camera3D:
		call_deferred("_apply_graphics_to_node", node)

	if node.is_in_group("player_hud"):
		call_deferred(
			"_apply_hud_canvas_filters_to_node",
			node,
			hud_canvas_filters_check_box.button_pressed
		)


func _on_fps_spin_box_value_changed(value: float) -> void:
	if _loading_options:
		return
	_apply_max_fps(int(value))
	_save_options()


func _on_fullscreen_check_box_toggled(toggled_on: bool) -> void:
	if _loading_options:
		return
	_apply_fullscreen(toggled_on)
	_save_options()


func _on_vsync_check_box_toggled(toggled_on: bool) -> void:
	if _loading_options:
		return
	_apply_vsync(toggled_on)
	_save_options()


func _on_render_scale_slider_value_changed(value: float) -> void:
	_update_render_scale_label(value)
	if _loading_options:
		return
	_apply_render_scale(value)
	_save_options()


func _on_msaa_option_button_item_selected(_index: int) -> void:
	if _loading_options:
		return
	_apply_msaa(_get_selected_msaa())
	_save_options()


func _on_world_graphics_toggled(_toggled_on: bool) -> void:
	if _loading_options:
		return
	_apply_world_graphics()
	_save_options()


func _on_performance_preset_button_pressed() -> void:
	_loading_options = true
	render_scale_slider.value = PERFORMANCE_RENDER_SCALE
	_update_render_scale_label(PERFORMANCE_RENDER_SCALE)
	_select_msaa(Viewport.MSAA_DISABLED)
	shadows_check_box.button_pressed = false
	fog_check_box.button_pressed = false
	glow_check_box.button_pressed = false
	sdfgi_check_box.button_pressed = false
	hud_canvas_filters_check_box.button_pressed = false
	_loading_options = false
	_apply_all_options()
	_save_options()


func _on_volume_slider_value_changed(value: float) -> void:
	_update_volume_label(value)
	if _loading_options:
		return
	_apply_master_volume(value)
	_save_options()


func _on_look_sensitivity_slider_value_changed(value: float) -> void:
	_update_look_sensitivity_label(value)
	if _loading_options:
		return
	_apply_look_sensitivity(value)
	_save_options()


func _on_hide_own_body_check_box_toggled(toggled_on: bool) -> void:
	if _loading_options:
		return
	_apply_hide_own_body(toggled_on)
	_save_options()


func _on_hud_canvas_filters_check_box_toggled(toggled_on: bool) -> void:
	if _loading_options:
		return
	_apply_hud_canvas_filters(toggled_on)
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
