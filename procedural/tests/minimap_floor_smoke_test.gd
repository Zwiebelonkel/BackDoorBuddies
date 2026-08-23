extends Node


const FLOOR_COUNT := 3
const FLOOR_HEIGHT := 3.0
const VAN_SCENE := preload("res://scenes/props/van/Van.tscn")
const PLAYER_SCENE := preload("res://scenes/PlayerController.tscn")
const PICKUP_SCENE := preload("res://procedural/items/pistol_pickup.tscn")
const CAMERA_SCENE := preload(
	"res://procedural/cameras/surveillance_camera.tscn"
)

var _generator: ProceduralLevelGenerator
var _players_root: Node3D
var _minimap: Node3D
var _van: CharacterBody3D
var _interaction_player: FPSController


func _ready() -> void:
	var exit_code := await _run_test()
	get_tree().quit(exit_code)


func _run_test() -> int:
	_build_fixture()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().physics_frame

	var map := _minimap.get_node_or_null("SubViewport/Map") as Control
	var interaction := _minimap.get_node_or_null("Interaction") as Area3D
	var interaction_shape := _minimap.get_node_or_null(
		"Interaction/CollisionShape3D"
	) as CollisionShape3D

	if (
		map == null
		or interaction == null
		or interaction_shape == null
		or interaction_shape.shape == null
		or not interaction.has_method("get_interaction_text")
		or not interaction.has_method("request_interaction")
	):
		return _fail("Minimap screen interaction is incomplete.")

	var required_methods: Array[StringName] = [
		&"get_available_floor_count",
		&"get_selected_floor",
		&"get_selected_floor_index",
		&"set_selected_floor",
		&"select_next_floor",
		&"select_previous_floor",
		&"get_scanned_room_count",
		&"get_scanned_item_count",
		&"get_scanned_player_count",
		&"get_scanned_camera_count",
	]

	for method_name in required_methods:
		if not map.has_method(method_name):
			return _fail("Minimap API '%s' is missing." % method_name)

	if int(map.call("get_available_floor_count")) != FLOOR_COUNT:
		return _fail("Minimap did not discover all three floors.")

	var ray_error := _validate_real_van_interaction_ray(interaction)

	if not ray_error.is_empty():
		return _fail(ray_error)

	for floor_index in range(FLOOR_COUNT):
		map.call("set_selected_floor", floor_index)

		if (
			int(map.call("get_selected_floor")) != floor_index
			or int(map.call("get_selected_floor_index")) != floor_index
		):
			return _fail("Minimap selected the wrong floor.")

		if int(map.call("get_scanned_room_count")) != 1:
			return _fail("Minimap mixed rooms from different floors.")

		if int(map.call("get_scanned_item_count")) != 1:
			return _fail("Minimap mixed items from different floors.")

		if int(map.call("get_scanned_player_count")) != 1:
			return _fail("Minimap mixed players from different floors.")

		if int(map.call("get_scanned_camera_count")) != 1:
			return _fail("Minimap mixed cameras from different floors.")

		var expected_status := "ETAGE %d / %d" % [
			floor_index + 1,
			FLOOR_COUNT,
		]

		if str(map.call("get_floor_status_text")) != expected_status:
			return _fail("Minimap floor status text is incorrect.")

	map.call("set_selected_floor", 0)
	map.call("select_previous_floor")

	if int(map.call("get_selected_floor")) != FLOOR_COUNT - 1:
		return _fail("Previous-floor selection did not wrap correctly.")

	map.call("select_next_floor")

	if "1 / 3" not in str(interaction.call("get_interaction_text")):
		return _fail("Map interaction text does not show the selected floor.")

	interaction.call("request_interaction", _players_root.get_child(0))

	if int(map.call("get_selected_floor")) != 1:
		return _fail("Interacting with the map did not select the next floor.")

	interaction.call("request_interaction", _players_root.get_child(0))
	interaction.call("request_interaction", _players_root.get_child(0))

	if int(map.call("get_selected_floor")) != 0:
		return _fail("Map interaction did not cycle back to the first floor.")

	if (
		int(map.call("get_total_scanned_item_count")) != FLOOR_COUNT
		or int(map.call("get_total_scanned_camera_count")) != FLOOR_COUNT
	):
		return _fail("Minimap total scan compatibility counts are incorrect.")

	print("MINIMAP_FLOOR_SMOKE_TEST_OK")
	return 0


func _build_fixture() -> void:
	_generator = ProceduralLevelGenerator.new()
	_generator.name = "ProceduralLevelGenerator"

	var rooms_root := Node3D.new()
	rooms_root.name = "GeneratedRooms"
	_generator.add_child(rooms_root)

	var items_root := Node3D.new()
	items_root.name = "SpawnedItems"
	_generator.add_child(items_root)
	add_child(_generator)

	_players_root = Node3D.new()
	_players_root.name = "Players"
	add_child(_players_root)

	_van = VAN_SCENE.instantiate() as CharacterBody3D
	_van.name = "TestVan"
	add_child(_van)
	_van.set_physics_process(false)
	_minimap = _van.get_node_or_null("Minimap") as Node3D

	_interaction_player = PLAYER_SCENE.instantiate() as FPSController
	_interaction_player.name = "999"
	add_child(_interaction_player)
	_interaction_player.set_physics_process(false)

	_generator.generated_bounds.clear()

	for floor_index in range(FLOOR_COUNT):
		var floor_y := float(floor_index) * FLOOR_HEIGHT
		var floor_x := float(floor_index) * 6.0
		_generator.generated_bounds.append(AABB(
			Vector3(floor_x, floor_y, 0.0),
			Vector3(4.0, FLOOR_HEIGHT - 0.1, 4.0)
		))

		var pickup := PICKUP_SCENE.instantiate() as PickupItem
		items_root.add_child(pickup)
		pickup.global_position = Vector3(
			floor_x + 2.0,
			floor_y + 0.03,
			2.0
		)

		var player := Node3D.new()
		player.name = str(floor_index + 1)
		_players_root.add_child(player)
		player.global_position = Vector3(
			floor_x + 1.0,
			floor_y,
			1.0
		)

		var surveillance_camera := (
			CAMERA_SCENE.instantiate() as SurveillanceCamera
		)
		add_child(surveillance_camera)
		surveillance_camera.global_position = Vector3(
			floor_x + 3.0,
			floor_y + 2.5,
			3.0
		)
		_generator.generated_surveillance_cameras.append(
			surveillance_camera
		)

	_set_generator_property_if_available(&"generated_floor_count", FLOOR_COUNT)
	_set_generator_property_if_available(&"target_floor_count", FLOOR_COUNT)
	_set_generator_property_if_available(&"floor_height", FLOOR_HEIGHT)


func _validate_real_van_interaction_ray(interaction: Area3D) -> String:
	if _van == null or _interaction_player == null:
		return "Real van or FPSController fixture is missing."

	var right_wall := _van.get_node_or_null(
		"RightWallCollision"
	) as CollisionShape3D
	var camera := _interaction_player.get_node_or_null(
		"Head/Camera3D"
	) as Camera3D
	var interaction_ray := _interaction_player.get_node_or_null(
		"Head/Camera3D/InteractionRay"
	) as RayCast3D

	if (
		right_wall == null
		or right_wall.shape == null
		or camera == null
		or interaction_ray == null
	):
		return "Real van minimap ray fixture is incomplete."

	interaction_ray.enabled = true
	interaction_ray.collide_with_areas = true
	interaction_ray.collide_with_bodies = true

	if not interaction_ray.collide_with_bodies:
		return "FPSController interaction ray does not collide with bodies."

	var ray_length := interaction_ray.target_position.length()
	var screen_normal := interaction.global_basis.y.normalized()

	if ray_length <= 0.1 or screen_normal.is_zero_approx():
		return "FPSController interaction ray or minimap normal is invalid."

	var desired_camera_position := (
		interaction.global_position + screen_normal * (ray_length - 0.1)
	)
	var camera_offset := (
		camera.global_position - _interaction_player.global_position
	)
	_interaction_player.global_position = desired_camera_position - camera_offset
	camera.look_at(interaction.global_position, Vector3.UP)
	interaction_ray.force_raycast_update()
	var ray_start := interaction_ray.global_position
	var ray_end := interaction_ray.to_global(interaction_ray.target_position)
	var wall_exclusions: Array[RID] = [
		interaction.get_rid(),
		_interaction_player.get_rid(),
	]
	var player_hitbox := _interaction_player.get_node_or_null(
		"PlayerHitbox"
	) as CollisionObject3D

	if player_hitbox != null:
		wall_exclusions.append(player_hitbox.get_rid())

	var wall_query := PhysicsRayQueryParameters3D.create(
		ray_start,
		ray_end,
		interaction_ray.collision_mask,
		wall_exclusions
	)
	wall_query.collide_with_areas = true
	wall_query.collide_with_bodies = true
	var wall_hit: Dictionary = (
		get_viewport().world_3d.direct_space_state.intersect_ray(wall_query)
	)

	if (
		not interaction_ray.is_colliding()
		or interaction_ray.get_collider() != interaction
	):
		return "FPSController ray misses minimap. %s" % _format_ray_diagnostics(
			interaction,
			interaction_ray,
			right_wall,
			ray_start,
			ray_end,
			wall_hit
		)

	if wall_hit.get("collider") != _van:
		return "No real van body exists behind the minimap interaction area."

	var shape_index := int(wall_hit.get("shape", -1))
	var shape_owner_id := _van.shape_find_owner(shape_index)
	var hit_shape_owner := (
		_van.shape_owner_get_owner(shape_owner_id)
		if shape_owner_id >= 0
		else null
	)

	if hit_shape_owner != right_wall:
		return "The minimap is not mounted directly in front of RightWallCollision."

	var interaction_distance := ray_start.distance_to(
		interaction_ray.get_collision_point()
	)
	var wall_distance := ray_start.distance_to(
		wall_hit.get("position", ray_end) as Vector3
	)

	if interaction_distance >= wall_distance:
		return "Minimap interaction area is not in front of RightWallCollision."

	return ""


func _format_ray_diagnostics(
	interaction: Area3D,
	interaction_ray: RayCast3D,
	right_wall: CollisionShape3D,
	ray_start: Vector3,
	ray_end: Vector3,
	wall_hit: Dictionary
) -> String:
	var collider := interaction_ray.get_collider()
	var collider_name := "<none>"

	if collider is Node:
		collider_name = str((collider as Node).get_path())
	elif collider != null:
		collider_name = str(collider)

	var wall_aabb := AABB()

	if right_wall.shape is BoxShape3D:
		var wall_box := right_wall.shape as BoxShape3D
		wall_aabb = right_wall.global_transform * AABB(
			-wall_box.size * 0.5,
			wall_box.size
		)

	return (
		"area=%s ray_start=%s ray_end=%s collider=%s hit=%s "
		+ "wall_origin=%s wall_aabb=%s excluded_area_hit=%s"
	) % [
		interaction.global_position,
		ray_start,
		ray_end,
		collider_name,
		interaction_ray.get_collision_point(),
		right_wall.global_position,
		wall_aabb,
		wall_hit.get("position", Vector3.ZERO),
	]


func _set_generator_property_if_available(
	property_name: StringName,
	value: Variant
) -> void:
	for property_data in _generator.get_property_list():
		if StringName(property_data.get("name", "")) == property_name:
			_generator.set(property_name, value)
			return


func _fail(message: String) -> int:
	push_error("MINIMAP_FLOOR_SMOKE_TEST_FAILED: " + message)
	return 1
