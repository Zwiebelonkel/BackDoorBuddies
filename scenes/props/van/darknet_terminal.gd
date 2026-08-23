class_name DarknetTerminal
extends Node3D


const SCREEN_SIZE := Vector2(1.28, 0.80)
const VIEWPORT_SIZE := Vector2i(1024, 640)
const SCREEN_CURVATURE := 0.025
const DELIVERY_STATUS := "DELIVERY_REQUIRED"
const TERMINAL_SHADER := preload(
	"res://scenes/props/van/darknet_terminal_screen.gdshader"
)
const PLAYER_ENTER_METHODS: Array[StringName] = [
	&"enter_darknet_terminal",
	&"enter_world_terminal",
	&"enter_terminal",
]

@export_group("Viewing")
@export_range(0.55, 1.6, 0.05) var viewing_distance := 1.25
@export_range(25.0, 70.0, 1.0) var viewing_fov := 48.0

@export_group("Delivery")
@export_range(0.05, 1.0, 0.05) var delivery_scan_interval := 0.15

@export_group("Local cargo")
@export_range(0.05, 1.0, 0.05) var local_items_scan_interval := 0.20

@onready var screen: MeshInstance3D = $Screen
@onready var screen_interaction: Area3D = $Interaction
@onready var viewport: SubViewport = $SubViewport
@onready var market_control: Control = $SubViewport/DarknetMarketV2
@onready var sale_drop_area: Area3D = $SaleDropArea
@onready var sale_drop_shape: CollisionShape3D = (
	$SaleDropArea/CollisionShape3D
)
@onready var sale_drop_label: Label3D = $SaleDropArea/DeliveryLabel
@onready var sale_drop_light: OmniLight3D = $SaleDropArea/DeliveryLight
@onready var sale_drop_visuals: Array[MeshInstance3D] = [
	$SaleDropArea/FloorGlow,
	$SaleDropArea/BorderFront,
	$SaleDropArea/BorderBack,
	$SaleDropArea/BorderLeft,
	$SaleDropArea/BorderRight,
]

var _active_user: Node3D = null
var _market_manager: Node = null
var _drop_zone_material: StandardMaterial3D = null
var _delivery_required := false
var _delivery_scan_time_remaining := 0.0
var _local_items_scan_time_remaining := 0.0
var _local_item_entries: Array[Dictionary] = []
var _local_items_signature := "<uninitialized>"
var _manager_bind_time_remaining := 0.0
var _pulse_time := 0.0
var _pointer_was_inside := false
var _last_viewport_pointer_position := Vector2(VIEWPORT_SIZE) * 0.5
var _pressed_mouse_buttons: Dictionary = {}


func _ready() -> void:
	add_to_group(&"darknet_terminal")
	viewport.size = VIEWPORT_SIZE
	_configure_screen_material()
	_configure_drop_zone_material()
	_resolve_market_manager()
	_bind_market_control()
	_update_drop_zone_visual(0.0)
	call_deferred("_scan_local_items")


func _process(delta: float) -> void:
	_pulse_time += delta
	_update_drop_zone_visual(delta)

	if not is_instance_valid(_active_user):
		_active_user = null

	if not is_instance_valid(_market_manager):
		_manager_bind_time_remaining -= delta

		if _manager_bind_time_remaining <= 0.0:
			_manager_bind_time_remaining = 0.5
			_resolve_market_manager()
			_bind_market_control()

	_local_items_scan_time_remaining -= delta

	if _local_items_scan_time_remaining <= 0.0:
		_local_items_scan_time_remaining = local_items_scan_interval
		_scan_local_items()

	if not multiplayer.is_server() or not _delivery_required:
		return

	_delivery_scan_time_remaining -= delta

	if _delivery_scan_time_remaining <= 0.0:
		_delivery_scan_time_remaining = delivery_scan_interval
		_scan_for_deliveries()


func get_interaction_text() -> String:
	if is_instance_valid(_active_user):
		return "Darknet-Terminal wird benutzt"

	return "Darknet-Terminal öffnen"


func begin_use(player: Node3D) -> bool:
	if (
		player == null
		or not player.is_multiplayer_authority()
		or (is_instance_valid(_active_user) and _active_user != player)
	):
		return false

	if _active_user == player:
		return true

	var entered_player_mode := false

	for method_name in PLAYER_ENTER_METHODS:
		if not player.has_method(method_name):
			continue

		var result: Variant = player.call(method_name, self)

		if result is bool and not bool(result):
			return false

		entered_player_mode = true
		break

	if not entered_player_mode:
		push_warning(
			"Player besitzt keine kompatible Darknet-Terminal-Methode."
		)
		return false

	_active_user = player
	_pointer_was_inside = false
	_bind_market_control()
	return true


func end_use(player: Node3D) -> void:
	if player != null and _active_user != player:
		return

	_release_all_mouse_buttons()
	_active_user = null
	_pointer_was_inside = false

	var focus_owner := viewport.gui_get_focus_owner()

	if focus_owner != null:
		focus_owner.release_focus()


func is_used_by(player: Node3D = null) -> bool:
	if not is_instance_valid(_active_user):
		return false

	return player == null or _active_user == player


func get_view_transform(viewer_position: Vector3) -> Transform3D:
	var screen_position := screen.global_position
	var screen_normal := screen.global_basis.z.normalized()

	if (viewer_position - screen_position).dot(screen_normal) < 0.0:
		screen_normal = -screen_normal

	var view_position := screen_position + screen_normal * viewing_distance
	var screen_up := screen.global_basis.y.normalized()

	if screen_up.dot(Vector3.UP) < 0.0:
		screen_up = -screen_up

	var view_basis := Basis.looking_at(
		(screen_position - view_position).normalized(),
		screen_up
	)
	return Transform3D(view_basis, view_position)


func get_viewing_fov() -> float:
	return viewing_fov


func forward_input(event: InputEvent, camera: Camera3D) -> bool:
	if event == null or not is_instance_valid(_active_user):
		return false

	if event is InputEventMouse:
		return _forward_mouse_input(event as InputEventMouse, camera)

	var forwarded_event := event.duplicate() as InputEvent

	if forwarded_event == null:
		return false

	viewport.push_input(forwarded_event, true)
	return true


func _forward_mouse_input(event: InputEventMouse, camera: Camera3D) -> bool:
	if camera == null:
		return false

	var ray_origin := camera.project_ray_origin(event.position)
	var ray_direction := camera.project_ray_normal(event.position).normalized()
	var screen_normal := screen.global_basis.z.normalized()
	var denominator := ray_direction.dot(screen_normal)

	if absf(denominator) < 0.0001:
		return _forward_pointer_outside(event)

	var ray_distance := (
		(screen.global_position - ray_origin).dot(screen_normal)
		/ denominator
	)

	if ray_distance < 0.0:
		return _forward_pointer_outside(event)

	var hit_position := ray_origin + ray_direction * ray_distance
	var local_hit := screen.to_local(hit_position)
	var half_size := SCREEN_SIZE * 0.5

	if (
		absf(local_hit.x) > half_size.x
		or absf(local_hit.y) > half_size.y
	):
		return _forward_pointer_outside(event)

	var mesh_position := Vector2(
		local_hit.x / SCREEN_SIZE.x + 0.5,
		0.5 - local_hit.y / SCREEN_SIZE.y
	)
	var centered_position := mesh_position * 2.0 - Vector2.ONE
	var warped_position := centered_position * (
		1.0 + SCREEN_CURVATURE * centered_position.length_squared()
	)
	var normalized_position := warped_position * 0.5 + Vector2.ONE * 0.5

	if (
		normalized_position.x < 0.0
		or normalized_position.x > 1.0
		or normalized_position.y < 0.0
		or normalized_position.y > 1.0
	):
		return _forward_pointer_outside(event)

	var viewport_position := normalized_position * Vector2(viewport.size)
	var forwarded_event := event.duplicate() as InputEventMouse

	if forwarded_event == null:
		return false

	forwarded_event.position = viewport_position
	forwarded_event.global_position = viewport_position
	viewport.push_input(forwarded_event, true)
	_last_viewport_pointer_position = viewport_position
	_pointer_was_inside = true

	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton

		if button_event.pressed:
			_pressed_mouse_buttons[button_event.button_index] = true
		else:
			_pressed_mouse_buttons.erase(button_event.button_index)

	return true


func _forward_pointer_outside(event: InputEventMouse) -> bool:
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton

		if (
			button_event.pressed
			or not _pressed_mouse_buttons.has(button_event.button_index)
		):
			return false

		var forwarded_release := event.duplicate() as InputEventMouseButton

		if forwarded_release == null:
			return false

		forwarded_release.position = _last_viewport_pointer_position
		forwarded_release.global_position = _last_viewport_pointer_position
		viewport.push_input(forwarded_release, true)
		_pressed_mouse_buttons.erase(button_event.button_index)
		return true

	if not _pointer_was_inside or not event is InputEventMouseMotion:
		return false

	var forwarded_event := event.duplicate() as InputEventMouseMotion

	if forwarded_event == null:
		return false

	forwarded_event.position = Vector2(-64.0, -64.0)
	forwarded_event.global_position = forwarded_event.position
	viewport.push_input(forwarded_event, true)
	_pointer_was_inside = false
	return true


func _release_all_mouse_buttons() -> void:
	for button_value in _pressed_mouse_buttons.keys():
		var release_event := InputEventMouseButton.new()
		release_event.button_index = int(button_value)
		release_event.pressed = false
		release_event.position = _last_viewport_pointer_position
		release_event.global_position = _last_viewport_pointer_position
		viewport.push_input(release_event, true)

	_pressed_mouse_buttons.clear()


func _configure_screen_material() -> void:
	var material := ShaderMaterial.new()
	material.shader = TERMINAL_SHADER
	material.set_shader_parameter("terminal_texture", viewport.get_texture())
	material.set_shader_parameter("curvature", SCREEN_CURVATURE)
	screen.material_override = material


func _configure_drop_zone_material() -> void:
	if sale_drop_visuals.is_empty():
		return

	var source_material := (
		sale_drop_visuals[0].material_override as StandardMaterial3D
	)

	_drop_zone_material = (
		source_material.duplicate(true) as StandardMaterial3D
		if source_material != null
		else StandardMaterial3D.new()
	)
	_drop_zone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_drop_zone_material.emission_enabled = true

	for visual in sale_drop_visuals:
		visual.material_override = _drop_zone_material


func _update_drop_zone_visual(_delta: float) -> void:
	var pulse := 0.5 + 0.5 * sin(_pulse_time * 5.5)
	var color := (
		Color(0.12, 1.0, 0.32, lerpf(0.55, 0.95, pulse))
		if _delivery_required
		else Color(0.035, 0.32, 0.11, 0.28)
	)

	if _drop_zone_material != null:
		_drop_zone_material.albedo_color = color
		_drop_zone_material.emission = Color(color.r, color.g, color.b, 1.0)
		_drop_zone_material.emission_energy_multiplier = (
			lerpf(1.4, 4.5, pulse) if _delivery_required else 0.65
		)

	sale_drop_label.text = (
		"DELIVERY REQUIRED\nDROP SOLD ITEM"
		if _delivery_required
		else "SALE DROP"
	)
	sale_drop_label.modulate = (
		Color(0.45, 1.0, 0.58, lerpf(0.65, 1.0, pulse))
		if _delivery_required
		else Color(0.12, 0.42, 0.2, 0.72)
	)
	sale_drop_light.light_energy = (
		lerpf(0.45, 2.4, pulse) if _delivery_required else 0.0
	)


func _resolve_market_manager() -> void:
	if is_instance_valid(_market_manager):
		return

	_market_manager = get_tree().get_first_node_in_group(
		&"darknet_market_manager"
	)

	if _market_manager == null:
		return

	var callback := Callable(self, "_on_market_state_changed")

	if (
		_market_manager.has_signal("market_state_changed")
		and not _market_manager.is_connected("market_state_changed", callback)
	):
		_market_manager.connect("market_state_changed", callback)

	if _market_manager.has_method("get_state_snapshot"):
		var snapshot: Variant = _market_manager.call("get_state_snapshot")

		if snapshot is Dictionary:
			_on_market_state_changed(snapshot as Dictionary)


func _bind_market_control() -> void:
	if market_control == null:
		return

	if (
		is_instance_valid(_market_manager)
		and market_control.has_method("bind_market_manager")
	):
		market_control.call("bind_market_manager", _market_manager)

	if (
		is_instance_valid(_active_user)
		and market_control.has_method("bind_player")
	):
		market_control.call("bind_player", _active_user)

	if market_control.has_method("bind_local_items"):
		market_control.call("bind_local_items", _local_item_entries)


func _on_market_state_changed(snapshot: Dictionary) -> void:
	_delivery_required = false

	for listing_value in snapshot.get("listings", []):
		if (
			listing_value is Dictionary
			and str((listing_value as Dictionary).get("status", ""))
			== DELIVERY_STATUS
		):
			_delivery_required = true
			break

	_delivery_scan_time_remaining = 0.0
	_update_drop_zone_visual(0.0)


func _scan_for_deliveries() -> void:
	if (
		not is_instance_valid(_market_manager)
		or not _market_manager.has_method("try_complete_delivery")
	):
		return

	var items_root := _get_spawned_items_root()

	if items_root == null:
		return

	for child in items_root.get_children():
		var pickup := child as PickupItem

		if pickup == null or not _is_point_in_sale_drop_area(
			pickup.global_position
		):
			continue

		if bool(_market_manager.call("try_complete_delivery", pickup)):
			break


func _scan_local_items() -> void:
	var entries: Array[Dictionary] = []
	var items_root := _get_spawned_items_root()
	var cargo_area := _get_cargo_area()

	if items_root != null and cargo_area != null:
		for child in items_root.get_children():
			var pickup := child as PickupItem

			if (
				pickup == null
				or pickup.item_data == null
				or pickup.item_data.is_mission_clue
				or pickup.item_instance_id.strip_edges().is_empty()
				or not _is_point_in_area(
					pickup.global_position,
					cargo_area
				)
			):
				continue

			var item_data := pickup.item_data
			entries.append({
				"instance_id": pickup.item_instance_id.strip_edges(),
				"resource_path": item_data.resource_path,
				"name": item_data.display_name,
				"value": maxi(item_data.value, 0),
				"icon": item_data.icon,
				"source": "VAN",
			})

	entries.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		var first_name := str(first.get("name", ""))
		var second_name := str(second.get("name", ""))

		if first_name == second_name:
			return str(first.get("instance_id", "")) < str(
				second.get("instance_id", "")
			)

		return first_name.naturalnocasecmp_to(second_name) < 0
	)

	var signature_parts: Array[String] = []

	for entry in entries:
		signature_parts.append(
			"%s:%s" % [
				str(entry.get("instance_id", "")),
				str(entry.get("resource_path", "")),
			]
		)

	var next_signature := "|".join(signature_parts)

	if next_signature == _local_items_signature:
		return

	_local_items_signature = next_signature
	_local_item_entries = entries

	if market_control != null and market_control.has_method("bind_local_items"):
		market_control.call("bind_local_items", _local_item_entries)


func _get_spawned_items_root() -> Node3D:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		return null

	return current_scene.get_node_or_null(
		"ProceduralLevelGenerator/SpawnedItems"
	) as Node3D


func _get_cargo_area() -> Area3D:
	var parent_node := get_parent()

	if parent_node != null:
		var sibling_area := parent_node.get_node_or_null("CargoArea") as Area3D

		if sibling_area != null and sibling_area.is_in_group(&"van_item_zone"):
			return sibling_area

	var closest_area: Area3D = null
	var closest_distance_squared := INF

	for zone_node in get_tree().get_nodes_in_group(&"van_item_zone"):
		var zone := zone_node as Area3D

		if zone == null:
			continue

		var distance_squared := global_position.distance_squared_to(
			zone.global_position
		)

		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_area = zone

	return closest_area


func _is_point_in_area(point: Vector3, area: Area3D) -> bool:
	if area == null:
		return false

	var collision_shape := area.get_node_or_null(
		"CollisionShape3D"
	) as CollisionShape3D

	if collision_shape == null:
		return false

	var box := collision_shape.shape as BoxShape3D

	if box == null:
		return false

	var local_point := collision_shape.global_transform.affine_inverse() * point
	var half_size := box.size * 0.5
	return (
		absf(local_point.x) <= half_size.x
		and absf(local_point.y) <= half_size.y
		and absf(local_point.z) <= half_size.z
	)


func _is_point_in_sale_drop_area(point: Vector3) -> bool:
	if sale_drop_shape == null:
		return false

	var box := sale_drop_shape.shape as BoxShape3D

	if box == null:
		return false

	var local_point := (
		sale_drop_shape.global_transform.affine_inverse()
		* point
	)
	var half_size := box.size * 0.5
	return (
		absf(local_point.x) <= half_size.x
		and absf(local_point.y) <= half_size.y
		and absf(local_point.z) <= half_size.z
	)


func _exit_tree() -> void:
	if not is_instance_valid(_market_manager):
		return

	var callback := Callable(self, "_on_market_state_changed")

	if _market_manager.is_connected("market_state_changed", callback):
		_market_manager.disconnect("market_state_changed", callback)
