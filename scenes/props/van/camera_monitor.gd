extends Node3D


@export_range(0.2, 1.5, 0.05) var viewing_distance := 0.95
@export_range(20.0, 75.0, 1.0) var viewing_fov := 38.0
@export_range(10.0, 120.0, 1.0) var camera_pan_speed := 55.0

@onready var viewport: SubViewport = $SubViewport
@onready var feed_camera: Camera3D = $SubViewport/FeedCamera
@onready var feed_spotlight: SpotLight3D = $SubViewport/FeedCamera/FeedSpotLight
@onready var screen: MeshInstance3D = $MeshInstance3D
@onready var camera_label: Label = $SubViewport/Interface/CameraLabel
@onready var no_signal_overlay: Control = $SubViewport/Interface/NoSignal

var _sources: Array[Node] = []
var _source_index: int = -1
var _active_viewer: FPSController = null
var _hidden_player_source: FPSController = null
var _refresh_time_remaining := 0.0
var _fog_free_environment: Environment


func _ready() -> void:
	viewport.world_3d = get_viewport().world_3d
	_fog_free_environment = _create_fog_free_environment(
		get_viewport().world_3d.environment
	)
	feed_camera.environment = _fog_free_environment
	_configure_screen_material()
	refresh_cameras()
	_set_feed_spotlight_enabled(false)


func _process(delta: float) -> void:
	_refresh_time_remaining -= delta

	if _refresh_time_remaining <= 0.0:
		_refresh_time_remaining = 0.5
		refresh_cameras()

	if (
		is_instance_valid(_active_viewer)
		and not _active_viewer.is_using_camera_monitor(self)
	):
		_set_hidden_player_source(null)
		_active_viewer = null
		_set_feed_spotlight_enabled(false)

	_update_feed()


func refresh_cameras() -> void:
	var selected_key := get_current_source_key()
	_sources.clear()

	for node in get_tree().get_nodes_in_group(&"surveillance_camera"):
		var surveillance_camera := node as SurveillanceCamera

		if surveillance_camera != null and is_instance_valid(surveillance_camera):
			_sources.append(surveillance_camera)

	var current_scene := get_tree().current_scene
	var players_root := (
		current_scene.get_node_or_null("Players") as Node3D
		if current_scene != null
		else null
	)

	if players_root != null:
		for child in players_root.get_children():
			var player := child as FPSController

			if player != null and is_instance_valid(player):
				_sources.append(player)

	_sources.sort_custom(_source_precedes)
	_source_index = -1

	for index in range(_sources.size()):
		if _get_source_key(_sources[index]) == selected_key:
			_source_index = index
			break

	if _source_index < 0 and not _sources.is_empty():
		_source_index = 0

	_update_overlay()
	_sync_hidden_player_source()
	_set_feed_spotlight_enabled(is_instance_valid(_active_viewer))


func begin_view(player: FPSController) -> bool:
	if player == null or not player.is_multiplayer_authority():
		return false

	refresh_cameras()

	if _sources.is_empty():
		return false

	if is_instance_valid(_active_viewer) and _active_viewer != player:
		return false

	if not player.enter_camera_monitor(self):
		return false

	_active_viewer = player
	_sync_hidden_player_source()
	_set_feed_spotlight_enabled(true)
	return true


func end_view(player: FPSController) -> void:
	if _active_viewer != player:
		return

	_set_hidden_player_source(null)
	_active_viewer = null
	_set_feed_spotlight_enabled(false)


func next_camera() -> void:
	_change_source(1)


func previous_camera() -> void:
	_change_source(-1)


func rotate_current_camera(direction: float, delta: float) -> void:
	var surveillance_camera := _get_current_source() as SurveillanceCamera

	if surveillance_camera == null:
		return

	surveillance_camera.pan_by_degrees(
		direction * camera_pan_speed * delta
	)


func get_view_transform(viewer_position: Vector3) -> Transform3D:
	var screen_position := screen.global_position
	var screen_normal := screen.global_basis.y.normalized()

	if (viewer_position - screen_position).dot(screen_normal) < 0.0:
		screen_normal = -screen_normal

	var view_position := screen_position + screen_normal * viewing_distance
	var screen_up := screen.global_basis.z.normalized()

	if screen_up.dot(Vector3.UP) < 0.0:
		screen_up = -screen_up

	var view_basis := Basis.looking_at(
		(screen_position - view_position).normalized(),
		screen_up
	)
	return Transform3D(view_basis, view_position)


func get_viewing_fov() -> float:
	return viewing_fov


func set_fog_free_environment(environment: Environment) -> void:
	if environment == null:
		return

	_fog_free_environment = environment
	feed_camera.environment = _fog_free_environment


func get_camera_count() -> int:
	return _sources.size()


func get_current_camera_id() -> int:
	var current_source := _get_current_source()
	var surveillance_camera := current_source as SurveillanceCamera

	if surveillance_camera != null:
		return surveillance_camera.camera_id

	var player := current_source as FPSController
	return -player.get_multiplayer_authority() if player != null else 0


func get_current_source_key() -> String:
	return _get_source_key(_get_current_source())


func get_interaction_text() -> String:
	if _sources.is_empty():
		return "Keine Kameras verbunden"

	return "Überwachung öffnen (%d Feeds)" % _sources.size()


func _change_source(direction: int) -> void:
	refresh_cameras()

	if _sources.is_empty():
		return

	_source_index = posmod(_source_index + direction, _sources.size())
	_update_overlay()
	_sync_hidden_player_source()
	_update_feed()


func _get_current_source() -> Node:
	if _source_index < 0 or _source_index >= _sources.size():
		return null

	var current_source := _sources[_source_index]
	return current_source if is_instance_valid(current_source) else null


func _get_source_key(source: Node) -> String:
	var surveillance_camera := source as SurveillanceCamera

	if surveillance_camera != null:
		return "camera:%03d" % surveillance_camera.camera_id

	var player := source as FPSController

	if player != null:
		return "player:%010d" % player.get_multiplayer_authority()

	return ""


func _get_source_transform(source: Node) -> Transform3D:
	var surveillance_camera := source as SurveillanceCamera

	if surveillance_camera != null:
		return surveillance_camera.get_feed_transform()

	var player := source as FPSController

	if player != null:
		return player.get_live_feed_transform()

	return Transform3D.IDENTITY


func _get_source_fov(source: Node) -> float:
	var surveillance_camera := source as SurveillanceCamera

	if surveillance_camera != null:
		return surveillance_camera.get_feed_fov()

	var player := source as FPSController
	return player.get_live_feed_fov() if player != null else 78.0


func _get_source_label(source: Node) -> String:
	var surveillance_camera := source as SurveillanceCamera

	if surveillance_camera != null:
		return surveillance_camera.get_display_name()

	var player := source as FPSController

	if player != null:
		return "SPIELER %s  |  LIVE" % player.name

	return "KEIN SIGNAL"


func _update_feed() -> void:
	var current_source := _get_current_source()
	_sync_hidden_player_source()

	if current_source == null:
		return

	feed_camera.global_transform = _get_source_transform(current_source)
	feed_camera.fov = _get_source_fov(current_source)


func _sync_hidden_player_source() -> void:
	var player_source := _get_current_source() as FPSController
	var desired_source := (
		player_source
		if (
			is_instance_valid(_active_viewer)
			and player_source != null
			and player_source != _active_viewer
		)
		else null
	)
	_set_hidden_player_source(desired_source)


func _set_hidden_player_source(player: FPSController) -> void:
	if _hidden_player_source == player:
		return

	if is_instance_valid(_hidden_player_source):
		_hidden_player_source.set_camera_monitor_model_hidden(false)

	_hidden_player_source = player

	if is_instance_valid(_hidden_player_source):
		_hidden_player_source.set_camera_monitor_model_hidden(true)


func _exit_tree() -> void:
	_set_hidden_player_source(null)


func _update_overlay() -> void:
	var current_source := _get_current_source()
	no_signal_overlay.visible = current_source == null

	if current_source == null:
		camera_label.text = "KEIN SIGNAL"
		return

	camera_label.text = "%s    %d/%d" % [
		_get_source_label(current_source),
		_source_index + 1,
		_sources.size()
	]


func _source_precedes(first: Node, second: Node) -> bool:
	var first_is_camera := first is SurveillanceCamera
	var second_is_camera := second is SurveillanceCamera

	if first_is_camera != second_is_camera:
		return first_is_camera

	return _get_source_key(first) < _get_source_key(second)


func _set_feed_spotlight_enabled(enabled: bool) -> void:
	# Monitor state is local-only. Other clients never enable this light, and
	# the local player's main camera is fixed on the monitor while it is active.
	feed_spotlight.visible = enabled and _get_current_source() != null


func _create_fog_free_environment(source: Environment) -> Environment:
	var environment := (
		source.duplicate(true) as Environment
		if source != null
		else Environment.new()
	)

	environment.resource_name = "VanCameraNoFogEnvironment"
	environment.fog_enabled = false
	environment.volumetric_fog_enabled = false
	environment.set_meta(&"options_default_fog", false)
	environment.set_meta(&"options_default_volumetric_fog", false)
	return environment


func _configure_screen_material() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_texture = viewport.get_texture()
	material.emission_enabled = true
	material.emission_texture = viewport.get_texture()
	material.emission_energy_multiplier = 1.25
	material.flags_unshaded = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	screen.material_override = material
