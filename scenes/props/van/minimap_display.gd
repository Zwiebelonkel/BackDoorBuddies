extends Control


const BACKGROUND_COLOR := Color("07110d")
const GRID_COLOR := Color(0.12, 0.28, 0.2, 0.42)
const ROOM_COLOR := Color(0.09, 0.32, 0.2, 0.92)
const ROOM_BORDER_COLOR := Color(0.36, 0.9, 0.53, 1.0)
const LOCAL_PLAYER_COLOR := Color(0.3, 1.0, 0.5, 1.0)
const REMOTE_PLAYER_COLOR := Color(1.0, 0.73, 0.22, 1.0)
const ITEM_COLOR := Color(0.2, 0.78, 1.0, 1.0)
const LARGE_ITEM_COLOR := Color(1.0, 0.25, 0.65, 1.0)
const CAMERA_COLOR := Color(1.0, 0.42, 0.12, 1.0)
const CAMERA_VIEW_COLOR := Color(1.0, 0.52, 0.18, 0.72)

var _generator: ProceduralLevelGenerator
var _players_root: Node3D
var _redraw_time_remaining := 0.0


func _ready() -> void:
	_configure_screen_material()
	_resolve_world_nodes()
	queue_redraw()


func _process(delta: float) -> void:
	_redraw_time_remaining -= delta

	if _redraw_time_remaining > 0.0:
		return

	_redraw_time_remaining = 0.1
	_resolve_world_nodes()
	queue_redraw()


func _draw() -> void:
	var canvas_size := size
	draw_rect(Rect2(Vector2.ZERO, canvas_size), BACKGROUND_COLOR)
	_draw_grid(canvas_size)

	var font := ThemeDB.fallback_font
	draw_string(
		font,
		Vector2(24.0, 35.0),
		"RAUMSCAN",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		24,
		ROOM_BORDER_COLOR
	)

	if _generator == null or _generator.generated_bounds.is_empty():
		draw_string(
			font,
			Vector2(24.0, 74.0),
			"WARTE AUF GRUNDRISS ...",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			16,
			Color(0.55, 0.7, 0.6, 1.0)
		)
		return

	var world_rect := _get_world_rect()
	var map_rect := Rect2(
		Vector2(24.0, 56.0),
		Vector2(
			maxf(canvas_size.x - 48.0, 1.0),
			maxf(canvas_size.y - 94.0, 1.0)
		)
	)
	var map_scale := minf(
		map_rect.size.x / maxf(world_rect.size.x, 0.001),
		map_rect.size.y / maxf(world_rect.size.y, 0.001)
	)
	var drawn_size := world_rect.size * map_scale
	var map_origin := map_rect.position + (map_rect.size - drawn_size) * 0.5

	for bounds in _generator.generated_bounds:
		var room_position := _world_to_map(
			Vector2(bounds.position.x, bounds.position.z),
			world_rect,
			map_origin,
			map_scale
		)
		var room_size := Vector2(bounds.size.x, bounds.size.z) * map_scale
		var room_rect := Rect2(room_position, room_size)

		draw_rect(room_rect, ROOM_COLOR, true)
		draw_rect(room_rect, ROOM_BORDER_COLOR, false, 2.0, true)

	_draw_items(world_rect, map_origin, map_scale)
	_draw_cameras(world_rect, map_origin, map_scale)
	_draw_players(world_rect, map_origin, map_scale)
	draw_string(
		font,
		Vector2(24.0, canvas_size.y - 16.0),
		"CYAN: ITEM  PINK: GROSS  ORANGE: KAMERA  GRUEN/GELB: SPIELER",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		10,
		Color(0.55, 0.78, 0.62, 1.0)
	)


func _draw_grid(canvas_size: Vector2) -> void:
	for x in range(0, ceili(canvas_size.x), 32):
		draw_line(
			Vector2(float(x), 0.0),
			Vector2(float(x), canvas_size.y),
			GRID_COLOR,
			1.0
		)

	for y in range(0, ceili(canvas_size.y), 32):
		draw_line(
			Vector2(0.0, float(y)),
			Vector2(canvas_size.x, float(y)),
			GRID_COLOR,
			1.0
		)


func _draw_players(
	world_rect: Rect2,
	map_origin: Vector2,
	map_scale: float
) -> void:
	if _players_root == null:
		return

	for child in _players_root.get_children():
		var player := child as Node3D

		if player == null or not _is_inside_generated_room(player.global_position):
			continue

		var marker_position := _world_to_map(
			Vector2(player.global_position.x, player.global_position.z),
			world_rect,
			map_origin,
			map_scale
		)
		var is_local_player := (
			String(player.name).to_int() == multiplayer.get_unique_id()
		)
		var marker_color := (
			LOCAL_PLAYER_COLOR if is_local_player else REMOTE_PLAYER_COLOR
		)

		draw_circle(marker_position, 8.0, Color(0.0, 0.0, 0.0, 0.85))
		draw_circle(marker_position, 5.5, marker_color)


func _draw_items(
	world_rect: Rect2,
	map_origin: Vector2,
	map_scale: float
) -> void:
	if _generator == null or not is_instance_valid(_generator.items_root):
		return

	for child in _generator.items_root.get_children():
		var pickup := child as PickupItem

		if (
			pickup == null
			or pickup.item_data == null
			or not _is_inside_generated_room(pickup.global_position)
		):
			continue

		var marker_position := _world_to_map(
			Vector2(pickup.global_position.x, pickup.global_position.z),
			world_rect,
			map_origin,
			map_scale
		)
		var is_large := pickup.item_data.is_large_item
		var half_size := 6.0 if is_large else 3.5
		var marker_color := LARGE_ITEM_COLOR if is_large else ITEM_COLOR
		var marker_rect := Rect2(
			marker_position - Vector2.ONE * half_size,
			Vector2.ONE * half_size * 2.0
		)

		draw_rect(marker_rect.grow(2.0), Color(0.0, 0.0, 0.0, 0.9), true)
		draw_rect(marker_rect, marker_color, true)


func _draw_cameras(
	world_rect: Rect2,
	map_origin: Vector2,
	map_scale: float
) -> void:
	if _generator == null:
		return

	for surveillance_camera in _generator.generated_surveillance_cameras:
		if not is_instance_valid(surveillance_camera):
			continue

		var feed_transform := surveillance_camera.get_feed_transform()
		var marker_position := _world_to_map(
			Vector2(feed_transform.origin.x, feed_transform.origin.z),
			world_rect,
			map_origin,
			map_scale
		)
		var world_forward := -feed_transform.basis.z.normalized()
		var map_forward := Vector2(world_forward.x, world_forward.z)

		if map_forward.is_zero_approx():
			map_forward = Vector2.UP
		else:
			map_forward = map_forward.normalized()

		var view_end := marker_position + map_forward * 16.0
		var view_side := Vector2(-map_forward.y, map_forward.x) * 6.0
		draw_line(
			marker_position,
			view_end + view_side,
			CAMERA_VIEW_COLOR,
			2.0,
			true
		)
		draw_line(
			marker_position,
			view_end - view_side,
			CAMERA_VIEW_COLOR,
			2.0,
			true
		)
		draw_circle(marker_position, 7.0, Color(0.0, 0.0, 0.0, 0.9))
		draw_circle(marker_position, 4.5, CAMERA_COLOR)
		draw_line(
			marker_position,
			marker_position + map_forward * 10.0,
			Color(1.0, 0.85, 0.52, 1.0),
			3.0,
			true
		)


func get_scanned_item_count() -> int:
	if _generator == null or not is_instance_valid(_generator.items_root):
		return 0

	var result := 0

	for child in _generator.items_root.get_children():
		var pickup := child as PickupItem

		if (
			pickup != null
			and pickup.item_data != null
			and _is_inside_generated_room(pickup.global_position)
		):
			result += 1

	return result


func get_scanned_camera_count() -> int:
	if _generator == null:
		return 0

	var result := 0

	for surveillance_camera in _generator.generated_surveillance_cameras:
		if is_instance_valid(surveillance_camera):
			result += 1

	return result


func _get_world_rect() -> Rect2:
	var first_bounds := _generator.generated_bounds[0]
	var result := Rect2(
		Vector2(first_bounds.position.x, first_bounds.position.z),
		Vector2(first_bounds.size.x, first_bounds.size.z)
	)

	for bounds in _generator.generated_bounds:
		result = result.expand(Vector2(bounds.position.x, bounds.position.z))
		result = result.expand(Vector2(bounds.end.x, bounds.end.z))

	return result


func _world_to_map(
	world_point: Vector2,
	world_rect: Rect2,
	map_origin: Vector2,
	map_scale: float
) -> Vector2:
	return map_origin + (world_point - world_rect.position) * map_scale


func _is_inside_generated_room(point: Vector3) -> bool:
	if _generator == null:
		return false

	for bounds in _generator.generated_bounds:
		if (
			point.x >= bounds.position.x
			and point.x <= bounds.end.x
			and point.z >= bounds.position.z
			and point.z <= bounds.end.z
		):
			return true

	return false


func _resolve_world_nodes() -> void:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		return

	if not is_instance_valid(_generator):
		_generator = current_scene.get_node_or_null(
			"ProceduralLevelGenerator"
		) as ProceduralLevelGenerator

	if not is_instance_valid(_players_root):
		_players_root = current_scene.get_node_or_null("Players") as Node3D


func _configure_screen_material() -> void:
	var viewport := get_parent() as SubViewport
	var display_root := viewport.get_parent() if viewport != null else null
	var screen := (
		display_root.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if display_root != null
		else null
	)

	if viewport == null or screen == null:
		return

	var material := StandardMaterial3D.new()
	material.albedo_texture = viewport.get_texture()
	material.emission_enabled = true
	material.emission_texture = viewport.get_texture()
	material.emission_energy_multiplier = 1.35
	material.flags_unshaded = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	screen.material_override = material
