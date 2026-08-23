extends Control


signal floor_changed(floor_index: int, floor_count: int)


const MAX_FLOOR_COUNT := 3
const DEFAULT_FLOOR_HEIGHT := 3.0
const FLOOR_CLUSTER_TOLERANCE := 0.75
const ROOM_HEIGHT_TOLERANCE := 0.08
const ROOM_FOOTPRINT_TOLERANCE := 0.08
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
const ENTRANCE_COLOR := Color(1.0, 0.9, 0.2, 1.0)
const ENTRANCE_GROUP := &"procedural_scan_entrance"

var _generator: ProceduralLevelGenerator
var _players_root: Node3D
var _redraw_time_remaining := 0.0
var _selected_floor_index := 0
var _available_floor_count := 1
var _floor_elevations: Array[float] = [0.0]


func _ready() -> void:
	_configure_screen_material()
	_resolve_world_nodes()
	_refresh_floor_layout()
	queue_redraw()


func _process(delta: float) -> void:
	_redraw_time_remaining -= delta

	if _redraw_time_remaining > 0.0:
		return

	_redraw_time_remaining = 0.1
	_resolve_world_nodes()
	_refresh_floor_layout()
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
	_draw_floor_status(font, canvas_size)

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

	var selected_bounds := _get_selected_bounds()

	if selected_bounds.is_empty():
		draw_string(
			font,
			Vector2(24.0, 82.0),
			"KEINE RAEUME AUF DIESER ETAGE",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			16,
			Color(0.55, 0.7, 0.6, 1.0)
		)
		return

	var world_rect := _get_world_rect(selected_bounds)
	var map_rect := Rect2(
		Vector2(24.0, 72.0),
		Vector2(
			maxf(canvas_size.x - 48.0, 1.0),
			maxf(canvas_size.y - 110.0, 1.0)
		)
	)
	var map_scale := minf(
		map_rect.size.x / maxf(world_rect.size.x, 0.001),
		map_rect.size.y / maxf(world_rect.size.y, 0.001)
	)
	var drawn_size := world_rect.size * map_scale
	var map_origin := map_rect.position + (map_rect.size - drawn_size) * 0.5

	for bounds in selected_bounds:
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
	_draw_entrances(world_rect, map_origin, map_scale)
	draw_string(
		font,
		Vector2(24.0, canvas_size.y - 23.0),
		"CYAN: ITEM  PINK: GROSS  ORANGE: KAMERA",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		10,
		Color(0.55, 0.78, 0.62, 1.0)
	)
	draw_string(
		font,
		Vector2(24.0, canvas_size.y - 9.0),
		"GRUEN/GELB: SPIELER  GELBE TUER: EINGANG",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		10,
		Color(0.55, 0.78, 0.62, 1.0)
	)


func _draw_floor_status(font: Font, canvas_size: Vector2) -> void:
	var floor_text := "ETAGE %d / %d" % [
		_selected_floor_index + 1,
		_available_floor_count,
	]
	draw_string(
		font,
		Vector2(canvas_size.x - 190.0, 35.0),
		floor_text,
		HORIZONTAL_ALIGNMENT_RIGHT,
		166.0,
		20,
		ROOM_BORDER_COLOR
	)
	draw_string(
		font,
		Vector2(24.0, 55.0),
		"[E] ETAGE WECHSELN",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		12,
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

		if (
			player == null
			or not _is_node_on_floor(player, _selected_floor_index)
			or not _is_inside_floor_room(
				player.global_position,
				_selected_floor_index
			)
		):
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
			or not _is_node_on_floor(pickup, _selected_floor_index)
			or not _is_inside_floor_room(
				pickup.global_position,
				_selected_floor_index
			)
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
		if (
			not is_instance_valid(surveillance_camera)
			or not _is_node_on_floor(
				surveillance_camera,
				_selected_floor_index
			)
		):
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


func _draw_entrances(
	world_rect: Rect2,
	map_origin: Vector2,
	map_scale: float
) -> void:
	for world_position in get_scanned_entrance_world_positions():
		var marker_position := _world_to_map(
			Vector2(world_position.x, world_position.z),
			world_rect,
			map_origin,
			map_scale
		)
		var door_rect := Rect2(
			marker_position - Vector2(5.0, 8.0),
			Vector2(10.0, 16.0)
		)

		# A filled door silhouette remains readable over room borders and other
		# markers even when the entrance sits directly on the room AABB edge.
		draw_rect(door_rect.grow(2.0), Color(0.0, 0.0, 0.0, 0.92), true)
		draw_rect(door_rect, ENTRANCE_COLOR, true)
		draw_line(
			marker_position + Vector2(-2.5, -5.0),
			marker_position + Vector2(-2.5, 5.0),
			Color(0.08, 0.08, 0.04, 1.0),
			2.0,
			true
		)
		draw_circle(
			marker_position + Vector2(2.3, 0.5),
			1.25,
			Color(0.08, 0.08, 0.04, 1.0)
		)


func get_scanned_item_count() -> int:
	_refresh_floor_layout()

	if _generator == null or not is_instance_valid(_generator.items_root):
		return 0

	var result := 0

	for child in _generator.items_root.get_children():
		var pickup := child as PickupItem

		if (
			pickup != null
			and pickup.item_data != null
			and _is_node_on_floor(pickup, _selected_floor_index)
			and _is_inside_floor_room(
				pickup.global_position,
				_selected_floor_index
			)
		):
			result += 1

	return result


func get_total_scanned_item_count() -> int:
	_refresh_floor_layout()

	if _generator == null or not is_instance_valid(_generator.items_root):
		return 0

	var result := 0

	for child in _generator.items_root.get_children():
		var pickup := child as PickupItem

		if pickup == null or pickup.item_data == null:
			continue

		var floor_index := _get_floor_index_for_point(pickup.global_position)

		if (
			floor_index >= 0
			and _is_inside_floor_room(pickup.global_position, floor_index)
		):
			result += 1

	return result


func get_scanned_camera_count() -> int:
	_refresh_floor_layout()

	if _generator == null:
		return 0

	var result := 0

	for surveillance_camera in _generator.generated_surveillance_cameras:
		if (
			is_instance_valid(surveillance_camera)
			and _is_node_on_floor(
				surveillance_camera,
				_selected_floor_index
			)
		):
			result += 1

	return result


func get_total_scanned_camera_count() -> int:
	if _generator == null:
		return 0

	var result := 0

	for surveillance_camera in _generator.generated_surveillance_cameras:
		if is_instance_valid(surveillance_camera):
			result += 1

	return result


func get_scanned_room_count() -> int:
	_refresh_floor_layout()

	if _generator == null:
		return 0

	var result := 0

	for bounds_index in range(_generator.generated_bounds.size()):
		if _room_occupies_floor(bounds_index, _selected_floor_index):
			result += 1

	return result


func get_scanned_player_count() -> int:
	_refresh_floor_layout()

	if not is_instance_valid(_players_root):
		return 0

	var result := 0

	for child in _players_root.get_children():
		var player := child as Node3D

		if (
			player != null
			and _is_node_on_floor(player, _selected_floor_index)
			and _is_inside_floor_room(
				player.global_position,
				_selected_floor_index
			)
		):
			result += 1

	return result


func get_scanned_entrance_count() -> int:
	return get_scanned_entrance_world_positions().size()


func get_scanned_entrance_world_positions() -> Array[Vector3]:
	_refresh_floor_layout()
	var result: Array[Vector3] = []

	for entrance in _get_building_entrance_doors():
		if (
			_is_node_on_floor(entrance, _selected_floor_index)
			and _is_inside_floor_room(
				entrance.global_position,
				_selected_floor_index
			)
		):
			result.append(entrance.global_position)

	return result


func get_available_floor_count() -> int:
	_refresh_floor_layout()
	return _available_floor_count


func get_selected_floor_index() -> int:
	_refresh_floor_layout()
	return _selected_floor_index


func get_selected_floor() -> int:
	return get_selected_floor_index()


func get_floor_status_text() -> String:
	_refresh_floor_layout()
	return "ETAGE %d / %d" % [
		_selected_floor_index + 1,
		_available_floor_count,
	]


func set_selected_floor(floor_index: int) -> int:
	_refresh_floor_layout()
	var clamped_index := clampi(
		floor_index,
		0,
		maxi(_available_floor_count - 1, 0)
	)

	if clamped_index == _selected_floor_index:
		return _selected_floor_index

	_selected_floor_index = clamped_index
	floor_changed.emit(_selected_floor_index, _available_floor_count)
	queue_redraw()
	return _selected_floor_index


func select_next_floor() -> int:
	_refresh_floor_layout()

	if _available_floor_count <= 1:
		return _selected_floor_index

	return set_selected_floor(
		(_selected_floor_index + 1) % _available_floor_count
	)


func select_previous_floor() -> int:
	_refresh_floor_layout()

	if _available_floor_count <= 1:
		return _selected_floor_index

	return set_selected_floor(
		(_selected_floor_index - 1 + _available_floor_count)
		% _available_floor_count
	)


func _get_world_rect(floor_bounds: Array[AABB]) -> Rect2:
	var first_bounds := floor_bounds[0]
	var result := Rect2(
		Vector2(first_bounds.position.x, first_bounds.position.z),
		Vector2(first_bounds.size.x, first_bounds.size.z)
	)

	for bounds in floor_bounds:
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


func _get_selected_bounds() -> Array[AABB]:
	var result: Array[AABB] = []

	if _generator == null:
		return result

	for bounds_index in range(_generator.generated_bounds.size()):
		if _room_occupies_floor(bounds_index, _selected_floor_index):
			result.append(_generator.generated_bounds[bounds_index])

	return result


func _get_building_entrance_doors() -> Array[Node3D]:
	var result: Array[Node3D] = []

	if _generator == null:
		return result

	for node in get_tree().get_nodes_in_group(ENTRANCE_GROUP):
		var entrance := node as Node3D

		if (
			is_instance_valid(entrance)
			and _generator.is_ancestor_of(entrance)
		):
			result.append(entrance)

	if not result.is_empty():
		return result

	# Compatibility fallback for authored start-room scenes made before the
	# explicit scanner group existed.
	for room in _generator.generated_rooms:
		if (
			not is_instance_valid(room)
			or room.room_type != &"start"
		):
			continue

		var entrance := room.get_node_or_null("ExitDoor") as Node3D

		if entrance != null:
			result.append(entrance)

	return result


func _is_inside_floor_room(point: Vector3, floor_index: int) -> bool:
	if _generator == null:
		return false

	for bounds_index in range(_generator.generated_bounds.size()):
		if not _room_occupies_floor(bounds_index, floor_index):
			continue

		var bounds := _generator.generated_bounds[bounds_index]

		if _point_is_inside_bounds_xz(point, bounds):
			return true

	return false


func _is_node_on_floor(node: Node3D, floor_index: int) -> bool:
	if node == null:
		return false

	var current: Node = node

	while current != null and current != _generator:
		var explicit_floor := int(_get_object_property(
			current,
			&"floor_index",
			-1
		))

		if explicit_floor >= 0:
			var floor_span := maxi(int(_get_object_property(
				current,
				&"floor_span",
				1
			)), 1)

			if floor_span == 1:
				return floor_index == explicit_floor

			var point_floor := _get_floor_index_for_point(node.global_position)
			return (
				floor_index == point_floor
				and floor_index >= explicit_floor
				and floor_index < explicit_floor + floor_span
			)

		current = current.get_parent()

	return _get_floor_index_for_point(node.global_position) == floor_index


func _get_floor_index_for_point(point: Vector3) -> int:
	if _generator == null or _generator.generated_bounds.is_empty():
		return -1

	# Gameplay roots sit on the floor plane, just below the intentionally
	# shrunken room AABBs. Classify their height first so floor-zero players
	# and surface-snapped pickups are not lost at that small authoring margin.
	var height_floor := _get_floor_index_for_height(point.y)

	for bounds_index in range(_generator.generated_bounds.size()):
		var bounds := _generator.generated_bounds[bounds_index]

		if (
			_room_occupies_floor(bounds_index, height_floor)
			and _point_is_inside_bounds_xz(point, bounds)
			and point.y >= bounds.position.y - ROOM_HEIGHT_TOLERANCE
			and point.y <= bounds.end.y + ROOM_HEIGHT_TOLERANCE
		):
			return height_floor

	var closest_floor := -1
	var closest_vertical_distance := INF

	for bounds_index in range(_generator.generated_bounds.size()):
		var bounds := _generator.generated_bounds[bounds_index]

		if not _point_is_inside_bounds_xz(point, bounds):
			continue

		var vertical_distance := 0.0

		if point.y < bounds.position.y:
			vertical_distance = bounds.position.y - point.y
		elif point.y > bounds.end.y:
			vertical_distance = point.y - bounds.end.y

		var room_floor := _get_point_floor_for_room(
			bounds_index,
			point.y
		)

		if vertical_distance <= ROOM_HEIGHT_TOLERANCE:
			return room_floor

		if vertical_distance < closest_vertical_distance:
			closest_vertical_distance = vertical_distance
			closest_floor = room_floor

	return closest_floor


func _point_is_inside_bounds_xz(point: Vector3, bounds: AABB) -> bool:
	return (
		point.x >= bounds.position.x - ROOM_FOOTPRINT_TOLERANCE
		and point.x <= bounds.end.x + ROOM_FOOTPRINT_TOLERANCE
		and point.z >= bounds.position.z - ROOM_FOOTPRINT_TOLERANCE
		and point.z <= bounds.end.z + ROOM_FOOTPRINT_TOLERANCE
	)


func _get_point_floor_for_room(bounds_index: int, height: float) -> int:
	var room := _get_room_for_bounds_index(bounds_index)
	var base_floor := int(_get_object_property(room, &"floor_index", -1))
	var floor_span := maxi(int(_get_object_property(
		room,
		&"floor_span",
		1
	)), 1)

	if base_floor < 0:
		# Legacy fixtures and older generators expose only one AABB per room.
		# In that case the bounds' base identifies the room floor; using the
		# point height would move cameras in the upper half to the next floor.
		return _get_floor_index_for_height(
			_generator.generated_bounds[bounds_index].position.y
		)

	if floor_span == 1:
		return clampi(base_floor, 0, _available_floor_count - 1)

	return clampi(
		_get_floor_index_for_height(height),
		base_floor,
		mini(base_floor + floor_span - 1, _available_floor_count - 1)
	)


func _get_floor_index_for_height(height: float) -> int:
	if _generator != null and _generator.has_method("get_floor_index_at_height"):
		return clampi(
			int(_generator.call("get_floor_index_at_height", height)),
			0,
			_available_floor_count - 1
		)

	var result := 0

	for floor_index in range(1, _floor_elevations.size()):
		var floor_boundary := (
			_floor_elevations[floor_index - 1]
			+ _floor_elevations[floor_index]
		) * 0.5

		if height < floor_boundary:
			break

		result = floor_index

	return clampi(result, 0, _available_floor_count - 1)


func _room_occupies_floor(bounds_index: int, floor_index: int) -> bool:
	if (
		_generator == null
		or bounds_index < 0
		or bounds_index >= _generator.generated_bounds.size()
	):
		return false

	var room := _get_room_for_bounds_index(bounds_index)

	if room != null and room.has_method("occupies_floor"):
		return bool(room.call("occupies_floor", floor_index))

	var base_floor := int(_get_object_property(room, &"floor_index", -1))

	if base_floor >= 0:
		var floor_span := maxi(int(_get_object_property(
			room,
			&"floor_span",
			1
		)), 1)
		return (
			floor_index >= base_floor
			and floor_index < base_floor + floor_span
		)

	var bounds := _generator.generated_bounds[bounds_index]
	return _get_floor_index_for_height(bounds.position.y) == floor_index


func _get_room_for_bounds_index(bounds_index: int) -> Node:
	if (
		_generator == null
		or bounds_index < 0
		or bounds_index >= _generator.generated_rooms.size()
	):
		return null

	return _generator.generated_rooms[bounds_index]


func _refresh_floor_layout() -> void:
	var previous_count := _available_floor_count
	var previous_floor := _selected_floor_index
	var inferred_elevations := _infer_floor_elevations()
	var generated_floor_count := int(_get_object_property(
		_generator,
		&"generated_floor_count",
		0
	))
	_available_floor_count = clampi(
		generated_floor_count if generated_floor_count > 0 else maxi(
			inferred_elevations.size(),
			1
		),
		1,
		MAX_FLOOR_COUNT
	)

	var floor_height := float(_get_object_property(
		_generator,
		&"floor_height",
		-1.0
	))

	if floor_height <= 0.0 and inferred_elevations.size() > 1:
		floor_height = (
			inferred_elevations[1] - inferred_elevations[0]
		)

	if floor_height <= 0.0:
		floor_height = DEFAULT_FLOOR_HEIGHT

	floor_height = maxf(floor_height, 0.1)
	var floor_base := _infer_floor_base(floor_height, inferred_elevations)
	_floor_elevations.clear()

	for floor_index in range(_available_floor_count):
		_floor_elevations.append(floor_base + floor_height * floor_index)

	_selected_floor_index = clampi(
		_selected_floor_index,
		0,
		_available_floor_count - 1
	)

	if (
		previous_count != _available_floor_count
		or previous_floor != _selected_floor_index
	):
		floor_changed.emit(_selected_floor_index, _available_floor_count)


func _infer_floor_elevations() -> Array[float]:
	var candidates: Array[float] = []

	if _generator == null:
		return candidates

	for bounds in _generator.generated_bounds:
		candidates.append(bounds.position.y)

	candidates.sort()
	var result: Array[float] = []
	var cluster_counts: Array[int] = []

	for elevation in candidates:
		if (
			result.is_empty()
			or absf(elevation - result.back()) > FLOOR_CLUSTER_TOLERANCE
		):
			result.append(elevation)
			cluster_counts.append(1)
			continue

		var last_index := result.size() - 1
		var count := cluster_counts[last_index]
		result[last_index] = (
			(result[last_index] * count + elevation) / float(count + 1)
		)
		cluster_counts[last_index] = count + 1

	if result.size() > MAX_FLOOR_COUNT:
		result.resize(MAX_FLOOR_COUNT)

	return result


func _infer_floor_base(
	floor_height: float,
	inferred_elevations: Array[float]
) -> float:
	var candidates: Array[float] = []

	if _generator != null:
		for bounds_index in range(_generator.generated_bounds.size()):
			var room := _get_room_for_bounds_index(bounds_index)
			var floor_index := int(_get_object_property(
				room,
				&"floor_index",
				-1
			))

			if floor_index >= 0:
				candidates.append(
					_generator.generated_bounds[bounds_index].position.y
					- floor_height * floor_index
				)

	if candidates.is_empty():
		return inferred_elevations[0] if not inferred_elevations.is_empty() else 0.0

	candidates.sort()
	return candidates[candidates.size() >> 1]


func _get_object_property(
	object: Object,
	property_name: StringName,
	fallback: Variant
) -> Variant:
	if object == null:
		return fallback

	for property in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return object.get(property_name)

	return fallback


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
