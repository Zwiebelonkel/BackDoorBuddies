class_name ProceduralLevelGenerator
extends Node3D


const SURVEILLANCE_CAMERA_SCENE := preload(
	"res://procedural/cameras/surveillance_camera.tscn"
)
const TARGET_CLUE_PICKUP_SCENE := preload(
	"res://procedural/items/target_clue_note_pickup.tscn"
)
const TARGET_CLUE_DRIVE_PICKUP_SCENE := preload(
	"res://procedural/items/target_clue_drive_pickup.tscn"
)
const NEON_BULB_SCENE := preload(
	"res://scenes/props/lights/NeonBulb.tscn"
)
const TARGET_CLUE_ITEM_PATHS := {
	&"age": "res://resources/items/target_note_age.tres",
	&"hair": "res://resources/items/target_drive_hair.tres",
	&"height": "res://resources/items/target_note_height.tres",
	&"skin_tone": "res://resources/items/target_note_skin_tone.tres",
}
const MAXIMUM_SUPPORTED_FLOORS := 3
const FLOOR_ALIGNMENT_TOLERANCE := 0.025
const NETWORK_GENERATION_SETTINGS_VERSION := 1

@export_group("Rooms")
@export var start_room_scene: PackedScene
@export var room_scenes: Array[PackedScene] = []
@export var large_room_scene: PackedScene

@export_range(0, 10, 1)
var minimum_large_rooms: int = 2

@export_group("Rare Rooms")
@export var rare_room_scene: PackedScene

@export_range(0.0, 1.0, 0.01)
var rare_room_chance: float = 0.08

@export_range(0, 3, 1)
var maximum_rare_rooms: int = 1

@export_group("Ceiling Neon")
@export var ceiling_neon_enabled := true

@export_range(1, 6, 1)
var maximum_neon_bulbs_per_room: int = 4

@export_group("Generation")
@export_range(1, 100, 1)
var maximum_rooms: int = 30

@export var generation_seed: int = 12345

@export_range(0.0, 0.25, 0.001)
var bounds_shrink: float = 0.03

@export_group("Floors")
## Dedicated two-floor connector room. When omitted, generation safely falls
## back to a single floor regardless of the configured minimum.
@export var stair_room_scene: PackedScene

@export_range(1, 3, 1)
var minimum_floors: int = 2

@export_range(1, 3, 1)
var maximum_floors: int = 3

## Vertical distance between the local Y=0 planes of adjacent normal rooms.
## It must match the authored rise and socket offsets of stair_room_scene.
@export_range(2.4, 6.0, 0.1)
var floor_height: float = 3.0

@export_group("Surveillance Cameras")
@export_range(0.0, 1.0, 0.05)
var surveillance_camera_room_chance: float = 0.35

@export_range(0, 100, 1)
var minimum_surveillance_cameras: int = 3

@export_range(0, 100, 1)
var maximum_surveillance_cameras: int = 8

@onready var rooms_root: Node3D = $GeneratedRooms
@onready var items_root: Node3D = $SpawnedItems

var rng := RandomNumberGenerator.new()
var generated_rooms: Array[ProceduralRoom] = []
var generated_bounds: Array[AABB] = []
var generated_surveillance_cameras: Array[SurveillanceCamera] = []
var generated_neon_bulbs: Array[Node3D] = []
var open_sockets: Array[RoomSocket] = []
var active_network_seed: int = 0
## Immutable settings used for the active network level. Keeping the exact
## snapshot prevents late joiners from observing later local configuration
## changes and generating a different layout for the same seed.
var active_network_generation_settings: Dictionary = {}
var target_floor_count: int = 1
var generated_floor_count: int = 0
var _generation_running := false
var _rare_room_enabled_for_generation := false


func start_network_generation(seed_override: int = 0) -> void:
	if not multiplayer.is_server():
		return

	var generation_settings := get_generation_settings_snapshot()

	if generation_settings.is_empty():
		push_error(
			"Cannot start network generation with invalid generator settings."
		)
		return

	active_network_seed = seed_override

	if active_network_seed == 0:
		active_network_seed = int(Time.get_unix_time_from_system())

	active_network_generation_settings = generation_settings.duplicate(true)
	generate_network_level.rpc(
		active_network_seed,
		active_network_generation_settings
	)


func sync_level_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or active_network_seed == 0:
		return

	# Legacy/direct callers may have created a level before settings snapshots
	# existed. Capture the current configuration as a safe fallback for them.
	if active_network_generation_settings.is_empty():
		active_network_generation_settings = get_generation_settings_snapshot()

	if active_network_generation_settings.is_empty():
		push_error("Cannot synchronize invalid generator settings to a peer.")
		return

	generate_network_level.rpc_id(
		peer_id,
		active_network_seed,
		active_network_generation_settings
	)


@rpc("authority", "call_local", "reliable")
func generate_network_level(
	seed_value: int,
	generation_settings: Dictionary = {}
) -> void:
	if _generation_running:
		push_warning("Level generation is already running.")
		return

	# The optional dictionary preserves the original one-argument API for
	# offline tools and older tests. Network starts always provide a snapshot.
	if not generation_settings.is_empty():
		if not apply_generation_settings_snapshot(generation_settings):
			push_error(
				"Rejected invalid network generation settings for seed %d."
				% seed_value
			)
			return

		active_network_generation_settings = (
			get_generation_settings_snapshot()
		)
	elif multiplayer.is_server():
		active_network_generation_settings = (
			get_generation_settings_snapshot()
		)

	active_network_seed = seed_value
	await generate_level(seed_value, multiplayer.is_server())


## Returns an RPC-safe, versioned description of every exported value that
## can affect deterministic room, floor, light, or camera generation.
func get_generation_settings_snapshot() -> Dictionary:
	var room_scene_paths: Array[String] = []

	for room_scene in room_scenes:
		var room_scene_path := _get_packed_scene_path(room_scene)

		if room_scene_path.is_empty():
			push_error(
				"Every configured room scene needs a saved resource path."
			)
			return {}

		room_scene_paths.append(room_scene_path)

	var snapshot := {
		"version": NETWORK_GENERATION_SETTINGS_VERSION,
		"start_room_scene_path": _get_packed_scene_path(start_room_scene),
		"room_scene_paths": room_scene_paths,
		"large_room_scene_path": _get_packed_scene_path(large_room_scene),
		"minimum_large_rooms": minimum_large_rooms,
		"rare_room_scene_path": _get_packed_scene_path(rare_room_scene),
		"rare_room_chance": rare_room_chance,
		"maximum_rare_rooms": maximum_rare_rooms,
		"ceiling_neon_enabled": ceiling_neon_enabled,
		"maximum_neon_bulbs_per_room": maximum_neon_bulbs_per_room,
		"maximum_rooms": maximum_rooms,
		"bounds_shrink": bounds_shrink,
		"stair_room_scene_path": _get_packed_scene_path(stair_room_scene),
		"minimum_floors": minimum_floors,
		"maximum_floors": maximum_floors,
		"floor_height": floor_height,
		"surveillance_camera_room_chance": (
			surveillance_camera_room_chance
		),
		"minimum_surveillance_cameras": minimum_surveillance_cameras,
		"maximum_surveillance_cameras": maximum_surveillance_cameras,
	}
	var normalized_snapshot := _normalize_generation_settings(snapshot)

	if normalized_snapshot.is_empty():
		push_error("The local generator settings are not network-safe.")

	return normalized_snapshot


## Validates and applies the snapshot atomically. No generator property is
## changed when a required key, value, or PackedScene cannot be resolved.
func apply_generation_settings_snapshot(settings: Dictionary) -> bool:
	var normalized := _normalize_generation_settings(settings)

	if normalized.is_empty():
		return false

	var loaded_start_room := _load_packed_scene_path(
		normalized["start_room_scene_path"]
	)
	var loaded_room_scenes: Array[PackedScene] = []

	for scene_path_value in normalized["room_scene_paths"]:
		var loaded_room := _load_packed_scene_path(str(scene_path_value))

		if loaded_room == null:
			return false

		loaded_room_scenes.append(loaded_room)

	var large_room_path := str(normalized["large_room_scene_path"])
	var rare_room_path := str(normalized["rare_room_scene_path"])
	var stair_room_path := str(normalized["stair_room_scene_path"])
	var loaded_large_room := _load_optional_packed_scene_path(
		large_room_path
	)
	var loaded_rare_room := _load_optional_packed_scene_path(
		rare_room_path
	)
	var loaded_stair_room := _load_optional_packed_scene_path(
		stair_room_path
	)

	if (
		loaded_start_room == null
		or loaded_room_scenes.is_empty()
		or (not large_room_path.is_empty() and loaded_large_room == null)
		or (not rare_room_path.is_empty() and loaded_rare_room == null)
		or (not stair_room_path.is_empty() and loaded_stair_room == null)
	):
		return false

	start_room_scene = loaded_start_room
	room_scenes = loaded_room_scenes
	large_room_scene = loaded_large_room
	minimum_large_rooms = int(normalized["minimum_large_rooms"])
	rare_room_scene = loaded_rare_room
	rare_room_chance = float(normalized["rare_room_chance"])
	maximum_rare_rooms = int(normalized["maximum_rare_rooms"])
	ceiling_neon_enabled = bool(normalized["ceiling_neon_enabled"])
	maximum_neon_bulbs_per_room = int(
		normalized["maximum_neon_bulbs_per_room"]
	)
	maximum_rooms = int(normalized["maximum_rooms"])
	bounds_shrink = float(normalized["bounds_shrink"])
	stair_room_scene = loaded_stair_room
	minimum_floors = int(normalized["minimum_floors"])
	maximum_floors = int(normalized["maximum_floors"])
	floor_height = float(normalized["floor_height"])
	surveillance_camera_room_chance = float(
		normalized["surveillance_camera_room_chance"]
	)
	minimum_surveillance_cameras = int(
		normalized["minimum_surveillance_cameras"]
	)
	maximum_surveillance_cameras = int(
		normalized["maximum_surveillance_cameras"]
	)
	return true


func _normalize_generation_settings(settings: Dictionary) -> Dictionary:
	if (
		not _setting_is_integer_in_range(
			settings,
			"version",
			NETWORK_GENERATION_SETTINGS_VERSION,
			NETWORK_GENERATION_SETTINGS_VERSION
		)
		or not _setting_is_scene_path(
			settings,
			"start_room_scene_path",
			false
		)
		or not _setting_is_scene_path_array(settings, "room_scene_paths")
		or not _setting_is_scene_path(
			settings,
			"large_room_scene_path",
			true
		)
		or not _setting_is_integer_in_range(
			settings,
			"minimum_large_rooms",
			0,
			10
		)
		or not _setting_is_scene_path(
			settings,
			"rare_room_scene_path",
			true
		)
		or not _setting_is_number_in_range(
			settings,
			"rare_room_chance",
			0.0,
			1.0
		)
		or not _setting_is_integer_in_range(
			settings,
			"maximum_rare_rooms",
			0,
			3
		)
		or not _setting_is_bool(settings, "ceiling_neon_enabled")
		or not _setting_is_integer_in_range(
			settings,
			"maximum_neon_bulbs_per_room",
			1,
			6
		)
		or not _setting_is_integer_in_range(
			settings,
			"maximum_rooms",
			1,
			100
		)
		or not _setting_is_number_in_range(
			settings,
			"bounds_shrink",
			0.0,
			0.25
		)
		or not _setting_is_scene_path(
			settings,
			"stair_room_scene_path",
			true
		)
		or not _setting_is_integer_in_range(
			settings,
			"minimum_floors",
			1,
			MAXIMUM_SUPPORTED_FLOORS
		)
		or not _setting_is_integer_in_range(
			settings,
			"maximum_floors",
			1,
			MAXIMUM_SUPPORTED_FLOORS
		)
		or not _setting_is_number_in_range(
			settings,
			"floor_height",
			2.4,
			6.0
		)
		or not _setting_is_number_in_range(
			settings,
			"surveillance_camera_room_chance",
			0.0,
			1.0
		)
		or not _setting_is_integer_in_range(
			settings,
			"minimum_surveillance_cameras",
			0,
			100
		)
		or not _setting_is_integer_in_range(
			settings,
			"maximum_surveillance_cameras",
			0,
			100
		)
	):
		return {}

	var normalized_room_paths: Array[String] = []

	for scene_path_value in settings["room_scene_paths"]:
		normalized_room_paths.append(str(scene_path_value))

	return {
		"version": NETWORK_GENERATION_SETTINGS_VERSION,
		"start_room_scene_path": str(settings["start_room_scene_path"]),
		"room_scene_paths": normalized_room_paths,
		"large_room_scene_path": str(settings["large_room_scene_path"]),
		"minimum_large_rooms": int(settings["minimum_large_rooms"]),
		"rare_room_scene_path": str(settings["rare_room_scene_path"]),
		"rare_room_chance": float(settings["rare_room_chance"]),
		"maximum_rare_rooms": int(settings["maximum_rare_rooms"]),
		"ceiling_neon_enabled": bool(settings["ceiling_neon_enabled"]),
		"maximum_neon_bulbs_per_room": int(
			settings["maximum_neon_bulbs_per_room"]
		),
		"maximum_rooms": int(settings["maximum_rooms"]),
		"bounds_shrink": float(settings["bounds_shrink"]),
		"stair_room_scene_path": str(settings["stair_room_scene_path"]),
		"minimum_floors": int(settings["minimum_floors"]),
		"maximum_floors": int(settings["maximum_floors"]),
		"floor_height": float(settings["floor_height"]),
		"surveillance_camera_room_chance": float(
			settings["surveillance_camera_room_chance"]
		),
		"minimum_surveillance_cameras": int(
			settings["minimum_surveillance_cameras"]
		),
		"maximum_surveillance_cameras": int(
			settings["maximum_surveillance_cameras"]
		),
	}


func _setting_is_integer_in_range(
	settings: Dictionary,
	key: String,
	minimum_value: int,
	maximum_value: int
) -> bool:
	if not settings.has(key) or typeof(settings[key]) != TYPE_INT:
		return false

	var value := int(settings[key])
	return value >= minimum_value and value <= maximum_value


func _setting_is_number_in_range(
	settings: Dictionary,
	key: String,
	minimum_value: float,
	maximum_value: float
) -> bool:
	if not settings.has(key):
		return false

	var value_type := typeof(settings[key])

	if value_type != TYPE_INT and value_type != TYPE_FLOAT:
		return false

	var value := float(settings[key])
	return (
		is_finite(value)
		and value >= minimum_value
		and value <= maximum_value
	)


func _setting_is_bool(settings: Dictionary, key: String) -> bool:
	return settings.has(key) and typeof(settings[key]) == TYPE_BOOL


func _setting_is_scene_path(
	settings: Dictionary,
	key: String,
	allow_empty: bool
) -> bool:
	if not settings.has(key):
		return false

	var value_type := typeof(settings[key])

	if value_type != TYPE_STRING and value_type != TYPE_STRING_NAME:
		return false

	var scene_path := str(settings[key])

	if scene_path.is_empty():
		return allow_empty

	return (
		scene_path.begins_with("res://")
		and (scene_path.ends_with(".tscn") or scene_path.ends_with(".scn"))
	)


func _setting_is_scene_path_array(
	settings: Dictionary,
	key: String
) -> bool:
	if not settings.has(key):
		return false

	var value = settings[key]

	if not (value is Array or value is PackedStringArray) or value.is_empty():
		return false

	for scene_path_value in value:
		var temporary_settings := {"scene_path": scene_path_value}

		if not _setting_is_scene_path(
			temporary_settings,
			"scene_path",
			false
		):
			return false

	return true


func _get_packed_scene_path(scene: PackedScene) -> String:
	if scene == null:
		return ""

	var scene_path := scene.resource_path

	if not scene_path.begins_with("res://"):
		return ""

	return scene_path


func _load_optional_packed_scene_path(scene_path: String) -> PackedScene:
	if scene_path.is_empty():
		return null

	return _load_packed_scene_path(scene_path)


func _load_packed_scene_path(scene_path: String) -> PackedScene:
	if (
		not scene_path.begins_with("res://")
		or not ResourceLoader.exists(scene_path)
	):
		return null

	return load(scene_path) as PackedScene


func generate_level(
	seed_value: int,
	should_spawn_items: bool = true
) -> void:
	if _generation_running:
		push_warning("Level generation is already running.")
		return

	if start_room_scene == null:
		push_error("No Start Room Scene configured.")
		return

	if room_scenes.is_empty():
		push_error("No Room Scenes configured.")
		return

	_generation_running = true
	_clear_generated_nodes()
	rng.seed = seed_value
	target_floor_count = _select_target_floor_count(seed_value)
	_roll_rare_room_for_generation(seed_value)

	var start_instance := start_room_scene.instantiate()
	var first_room := start_instance as ProceduralRoom

	if first_room == null:
		start_instance.free()
		push_error("The start room requires ProceduralRoom on its root.")
		_generation_running = false
		return

	first_room.name = "Room_000"
	first_room.generation_depth = 0
	first_room.generation_index = 0
	first_room.floor_index = 0
	rooms_root.add_child(first_room)

	generated_rooms.append(first_room)
	generated_bounds.append(first_room.get_world_aabb(bounds_shrink))
	open_sockets.append_array(first_room.get_free_sockets())
	_refresh_generated_floor_count()

	if not _generate_required_floor_backbone():
		# Keep the runtime state truthful if authored stair geometry is invalid.
		# Normal room generation may continue on the floors reached so far.
		target_floor_count = maxi(generated_floor_count, 1)

	while generated_rooms.size() < maximum_rooms and not open_sockets.is_empty():
		var socket_index := _select_open_socket_index()
		var target_socket := open_sockets[socket_index]
		open_sockets.remove_at(socket_index)

		if not is_instance_valid(target_socket) or target_socket.occupied:
			continue

		if not _try_attach_room(target_socket):
			target_socket.close_socket()

	_close_remaining_sockets()
	_spawn_ceiling_neon_bulbs(seed_value)
	await get_tree().process_frame
	_spawn_surveillance_cameras(seed_value)

	if should_spawn_items:
		await get_tree().physics_frame

		for room_index in range(generated_rooms.size()):
			var room := generated_rooms[room_index]
			var room_seed := seed_value + (room_index + 1) * 1_000_003
			room.spawn_random_items(room_seed, items_root)

		_spawn_target_clues(seed_value)

	_generation_running = false
	print(
		"Generation complete. Rooms: %d | Floors: %d | Seed: %d"
		% [generated_rooms.size(), generated_floor_count, seed_value]
	)


func get_generated_floor_count() -> int:
	return generated_floor_count


func get_rooms_on_floor(requested_floor_index: int) -> Array[ProceduralRoom]:
	var result: Array[ProceduralRoom] = []

	if (
		requested_floor_index < 0
		or requested_floor_index >= MAXIMUM_SUPPORTED_FLOORS
	):
		return result

	for room in generated_rooms:
		if is_instance_valid(room) and room.covers_floor(requested_floor_index):
			result.append(room)

	return result


func get_floor_elevation(requested_floor_index: int) -> float:
	return float(maxi(requested_floor_index, 0)) * floor_height


func get_floor_world_y(requested_floor_index: int) -> float:
	return _get_floor_base_world_y() + get_floor_elevation(
		requested_floor_index
	)


func get_floor_index_at_height(world_y: float) -> int:
	if generated_floor_count <= 0 or floor_height <= 0.0:
		return 0

	return clampi(
		roundi((world_y - _get_floor_base_world_y()) / floor_height),
		0,
		generated_floor_count - 1
	)


func _select_target_floor_count(seed_value: int) -> int:
	if stair_room_scene == null:
		if minimum_floors > 1:
			push_warning(
				"Multiple floors requested without a stair_room_scene; "
				+ "falling back to one floor."
			)

		return 1

	var room_capacity := clampi(
		maximum_rooms,
		1,
		MAXIMUM_SUPPORTED_FLOORS
	)
	var configured_maximum := clampi(
		maximum_floors,
		1,
		mini(MAXIMUM_SUPPORTED_FLOORS, room_capacity)
	)
	var configured_minimum := clampi(
		minimum_floors,
		1,
		configured_maximum
	)
	var floor_rng := RandomNumberGenerator.new()
	floor_rng.seed = seed_value + 3_141_592_653
	return floor_rng.randi_range(configured_minimum, configured_maximum)


func _generate_required_floor_backbone() -> bool:
	if target_floor_count <= 1:
		return true

	if stair_room_scene == null:
		return false

	for upper_floor_index in range(1, target_floor_count):
		if generated_rooms.size() >= maximum_rooms:
			push_warning(
				"Room limit reached before floor %d could be connected."
				% upper_floor_index
			)
			return false

		if not _attach_stair_to_floor(upper_floor_index):
			push_warning(
				"Could not create a safe stair connection to floor %d."
				% upper_floor_index
			)
			return false

	return true


func _attach_stair_to_floor(upper_floor_index: int) -> bool:
	var lower_floor_index := upper_floor_index - 1
	var candidates: Array[RoomSocket] = []

	for socket in open_sockets:
		if (
			is_instance_valid(socket)
			and not socket.occupied
			and socket.get_connection_floor_index() == lower_floor_index
		):
			candidates.append(socket)

	_shuffle_with_generator(candidates)

	for target_socket in candidates:
		var target_room := target_socket.get_room()

		if target_room == null:
			continue

		if _try_attach_packed_room(
			target_socket,
			stair_room_scene,
			target_room.generation_depth + 1,
			0,
			lower_floor_index,
			upper_floor_index
		):
			open_sockets.erase(target_socket)
			return true

	return false


func _select_open_socket_index() -> int:
	if _get_large_room_count() < minimum_large_rooms:
		var room_door_indices: Array[int] = []

		for index in range(open_sockets.size()):
			var socket := open_sockets[index]

			if (
				is_instance_valid(socket)
				and not socket.occupied
				and socket.socket_type == &"room_door"
			):
				room_door_indices.append(index)

		if not room_door_indices.is_empty():
			return room_door_indices[
				rng.randi_range(0, room_door_indices.size() - 1)
			]

	return rng.randi_range(0, open_sockets.size() - 1)


func _get_large_room_count() -> int:
	var count := 0

	for room in generated_rooms:
		if is_instance_valid(room) and room.room_type == &"large":
			count += 1

	return count


func _spawn_ceiling_neon_bulbs(seed_value: int) -> void:
	generated_neon_bulbs.clear()

	if not ceiling_neon_enabled or maximum_neon_bulbs_per_room <= 0:
		return

	for room_index in range(generated_rooms.size()):
		var room := generated_rooms[room_index]
		var room_seed := seed_value + (room_index + 1) * 2_000_033
		var room_lights := room.spawn_ceiling_neon_bulbs(
			NEON_BULB_SCENE,
			room_seed,
			maximum_neon_bulbs_per_room
		)

		generated_neon_bulbs.append_array(room_lights)


func _get_rare_room_count() -> int:
	var count := 0

	for room in generated_rooms:
		if is_instance_valid(room) and room.room_type == &"rare":
			count += 1

	return count


func _roll_rare_room_for_generation(seed_value: int) -> void:
	_rare_room_enabled_for_generation = false

	if (
		rare_room_scene == null
		or maximum_rare_rooms <= 0
		or rare_room_chance <= 0.0
	):
		return

	var rare_rng := RandomNumberGenerator.new()

	# A separate deterministic roll keeps the normal layout RNG unchanged.
	rare_rng.seed = seed_value + 4_982_347_031
	_rare_room_enabled_for_generation = (
		rare_rng.randf() < rare_room_chance
	)


func _spawn_target_clues(seed_value: int) -> void:
	if not SessionManager.has_active_session():
		return

	var required_clues := SessionManager.get_required_target_clues()

	if required_clues.is_empty():
		return

	var spawn_points: Array[ItemSpawnPoint] = []

	for room in generated_rooms:
		if room.generation_index == 0 or room.item_spawn_points == null:
			continue

		for child in room.item_spawn_points.get_children():
			var point := child as ItemSpawnPoint

			if point != null and point.spawn_enabled:
				spawn_points.append(point)

	if spawn_points.size() < required_clues.size():
		push_warning(
			"Not enough spawn points for all target clues: %d/%d."
			% [spawn_points.size(), required_clues.size()]
		)

	var clue_rng := RandomNumberGenerator.new()
	clue_rng.seed = seed_value + 8_314_159
	_shuffle_item_spawn_points(spawn_points, clue_rng)

	for clue_index in range(mini(required_clues.size(), spawn_points.size())):
		var clue_type := required_clues[clue_index]
		var item_path := str(TARGET_CLUE_ITEM_PATHS.get(clue_type, ""))
		var item_data := load(item_path) as ItemData

		if item_data == null:
			push_warning("Target clue ItemData is missing: " + item_path)
			continue

		var pickup_scene := (
			TARGET_CLUE_DRIVE_PICKUP_SCENE
			if clue_type == &"hair"
			else TARGET_CLUE_PICKUP_SCENE
		)
		var pickup := pickup_scene.instantiate() as PickupItem

		if pickup == null:
			push_warning("Target clue pickup scene requires PickupItem.")
			continue

		var point := spawn_points[clue_index]
		var jitter := (
			point.global_basis.x.normalized()
			* clue_rng.randf_range(-0.16, 0.16)
			+ point.global_basis.z.normalized()
			* clue_rng.randf_range(-0.16, 0.16)
		)
		var spawn_basis := Basis(
			Vector3.UP,
			clue_rng.randf_range(-PI, PI)
		)
		var spawn_transform := Transform3D(
			spawn_basis,
			point.global_position + jitter + Vector3.UP * 0.045
		)

		pickup.name = "TargetClue_%s" % String(clue_type)
		pickup.item_data = item_data
		pickup.set_meta("item_id", item_data.item_id)
		pickup.set_meta("target_clue_type", clue_type)
		pickup.transform = (
			items_root.global_transform.affine_inverse()
			* spawn_transform
		)
		items_root.add_child(pickup, true)


func _shuffle_item_spawn_points(
	points: Array[ItemSpawnPoint],
	random_generator: RandomNumberGenerator
) -> void:
	for index in range(points.size() - 1, 0, -1):
		var random_index := random_generator.randi_range(0, index)
		var temporary := points[index]

		points[index] = points[random_index]
		points[random_index] = temporary


func _clear_generated_nodes() -> void:
	generated_rooms.clear()
	generated_bounds.clear()
	generated_surveillance_cameras.clear()
	generated_neon_bulbs.clear()
	open_sockets.clear()
	generated_floor_count = 0
	target_floor_count = 1

	for root in [rooms_root, items_root]:
		for child in root.get_children():
			root.remove_child(child)
			child.queue_free()


func _try_attach_room(target_socket: RoomSocket) -> bool:
	var target_room := target_socket.get_room()

	if target_room == null:
		return false

	var next_depth := target_room.generation_depth + 1
	var candidates: Array[PackedScene] = room_scenes.duplicate()
	var rare_room_available := (
		_rare_room_enabled_for_generation
		and rare_room_scene != null
		and _get_rare_room_count() < maximum_rare_rooms
		and rare_room_scene not in candidates
	)

	if rare_room_available:
		candidates.append(rare_room_scene)

	_shuffle_with_generator(candidates)

	if (
		_get_large_room_count() < minimum_large_rooms
		and large_room_scene != null
		and large_room_scene in candidates
	):
		candidates.erase(large_room_scene)
		candidates.push_front(large_room_scene)

	# Once a seed wins the rare roll, offer that room first on every compatible
	# socket until it fits. The scene's own depth limit still applies.
	if rare_room_available:
		candidates.erase(rare_room_scene)
		candidates.push_front(rare_room_scene)

	var attempt_number := 0

	for packed_scene in candidates:
		if _try_attach_packed_room(
			target_socket,
			packed_scene,
			next_depth,
			attempt_number
		):
			return true

		attempt_number += 1

	return false


func _try_attach_packed_room(
	target_socket: RoomSocket,
	packed_scene: PackedScene,
	next_depth: int,
	attempt_number: int,
	required_floor_index: int = -1,
	required_highest_floor_index: int = -1
) -> bool:
	if packed_scene == null:
		return false

	var candidate_instance: Node = packed_scene.instantiate()
	var candidate := candidate_instance as ProceduralRoom

	if candidate == null:
		candidate_instance.free()
		return false

	if (
		next_depth < candidate.minimum_generation_depth
		or next_depth > candidate.maximum_generation_depth
	):
		candidate.free()
		return false

	candidate.name = "Candidate_%d_%d" % [
		generated_rooms.size(),
		attempt_number,
	]
	candidate.generation_depth = next_depth
	candidate.generation_index = generated_rooms.size()
	rooms_root.add_child(candidate)

	var entrances := candidate.get_free_sockets()
	_shuffle_with_generator(entrances)

	for entrance in entrances:
		if not target_socket.is_compatible_with(entrance):
			continue

		var candidate_floor_index := _calculate_candidate_floor_index(
			target_socket,
			entrance
		)

		if (
			required_floor_index >= 0
			and candidate_floor_index != required_floor_index
		):
			continue

		if not _candidate_floor_range_is_valid(
			candidate,
			candidate_floor_index
		):
			continue

		candidate.floor_index = candidate_floor_index

		if (
			required_highest_floor_index >= 0
			and candidate.get_highest_floor_index()
			!= required_highest_floor_index
		):
			continue

		_align_room_to_socket(candidate, entrance, target_socket)

		if not _floor_connection_is_safe(
			target_socket,
			candidate,
			entrance
		):
			continue

		var candidate_bounds := candidate.get_world_aabb(bounds_shrink)

		if _bounds_overlap_existing(candidate_bounds):
			continue

		_register_connected_room(
			target_socket,
			candidate,
			entrance,
			candidate_bounds
		)
		return true

	rooms_root.remove_child(candidate)
	candidate.free()
	return false


func _calculate_candidate_floor_index(
	target_socket: RoomSocket,
	entrance: RoomSocket
) -> int:
	return (
		target_socket.get_connection_floor_index()
		- entrance.floor_offset
	)


func _candidate_floor_range_is_valid(
	candidate: ProceduralRoom,
	candidate_floor_index: int
) -> bool:
	return (
		candidate_floor_index >= 0
		and candidate_floor_index < target_floor_count
		and candidate_floor_index + candidate.floor_span
		<= target_floor_count
		and candidate_floor_index + candidate.floor_span - 1
		< MAXIMUM_SUPPORTED_FLOORS
	)


func _floor_connection_is_safe(
	target_socket: RoomSocket,
	candidate: ProceduralRoom,
	entrance: RoomSocket
) -> bool:
	var target_floor_index := target_socket.get_connection_floor_index()
	var entrance_floor_index := candidate.get_socket_floor_index(entrance)

	if (
		target_floor_index < 0
		or target_floor_index >= target_floor_count
		or entrance_floor_index != target_floor_index
	):
		return false

	var expected_connection_y := get_floor_world_y(target_floor_index)
	var expected_room_y := get_floor_world_y(candidate.floor_index)
	var sockets_meet := (
		target_socket.global_position.distance_to(entrance.global_position)
		<= FLOOR_ALIGNMENT_TOLERANCE
	)
	var elevations_match := (
		absf(target_socket.global_position.y - expected_connection_y)
		<= FLOOR_ALIGNMENT_TOLERANCE
		and absf(entrance.global_position.y - expected_connection_y)
		<= FLOOR_ALIGNMENT_TOLERANCE
		and absf(candidate.global_position.y - expected_room_y)
		<= FLOOR_ALIGNMENT_TOLERANCE
	)
	var candidate_is_upright := (
		candidate.global_basis.y.normalized().dot(Vector3.UP) >= 0.999
	)
	return (
		sockets_meet
		and elevations_match
		and candidate_is_upright
		and _room_socket_elevations_are_safe(candidate)
	)


func _room_socket_elevations_are_safe(room: ProceduralRoom) -> bool:
	for socket in room.get_free_sockets():
		if socket.floor_offset < 0 or socket.floor_offset >= room.floor_span:
			return false

		var socket_floor_index := room.get_socket_floor_index(socket)

		if (
			socket_floor_index < 0
			or socket_floor_index >= target_floor_count
			or absf(
				socket.global_position.y
				- get_floor_world_y(socket_floor_index)
			) > FLOOR_ALIGNMENT_TOLERANCE
		):
			return false

	return true


func _register_connected_room(
	target_socket: RoomSocket,
	candidate: ProceduralRoom,
	entrance: RoomSocket,
	candidate_bounds: AABB
) -> void:
	target_socket.occupied = true
	entrance.occupied = true
	candidate.name = "Room_%03d" % generated_rooms.size()
	generated_rooms.append(candidate)
	generated_bounds.append(candidate_bounds)

	for new_socket in candidate.get_free_sockets():
		open_sockets.append(new_socket)

	_refresh_generated_floor_count()


func _refresh_generated_floor_count() -> void:
	var highest_floor_index := -1

	for room in generated_rooms:
		if is_instance_valid(room):
			highest_floor_index = maxi(
				highest_floor_index,
				room.get_highest_floor_index()
			)

	generated_floor_count = clampi(
		highest_floor_index + 1,
		0,
		MAXIMUM_SUPPORTED_FLOORS
	)


func _get_floor_base_world_y() -> float:
	return rooms_root.global_position.y


func _align_room_to_socket(
	room: ProceduralRoom,
	room_socket: RoomSocket,
	target_socket: RoomSocket
) -> void:
	var socket_inside_room := (
		room.global_transform.affine_inverse()
		* room_socket.global_transform
	)
	var flip_transform := Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	var desired_socket_transform := target_socket.global_transform * flip_transform

	room.global_transform = desired_socket_transform * socket_inside_room.affine_inverse()


func _bounds_overlap_existing(candidate_bounds: AABB) -> bool:
	for existing_bounds in generated_bounds:
		if candidate_bounds.intersects(existing_bounds):
			return true

	return false


func _close_remaining_sockets() -> void:
	for socket in open_sockets:
		if is_instance_valid(socket) and not socket.occupied:
			socket.close_socket()

	open_sockets.clear()


func _spawn_surveillance_cameras(seed_value: int) -> void:
	if generated_rooms.is_empty() or maximum_surveillance_cameras <= 0:
		return

	var camera_rng := RandomNumberGenerator.new()
	camera_rng.seed = seed_value + 6_721_918_019
	var candidates: Array[ProceduralRoom] = generated_rooms.duplicate()
	_shuffle_with_rng(candidates, camera_rng)

	var target_count := 0

	for _room in candidates:
		if camera_rng.randf() <= surveillance_camera_room_chance:
			target_count += 1

	var minimum_count := mini(minimum_surveillance_cameras, candidates.size())
	var maximum_count := mini(
		maxi(maximum_surveillance_cameras, minimum_count),
		candidates.size()
	)
	target_count = clampi(target_count, minimum_count, maximum_count)

	for camera_index in range(target_count):
		var camera := candidates[camera_index].spawn_surveillance_camera(
			SURVEILLANCE_CAMERA_SCENE,
			camera_rng,
			camera_index + 1
		)

		if camera != null:
			generated_surveillance_cameras.append(camera)


func _shuffle_with_generator(values: Array) -> void:
	_shuffle_with_rng(values, rng)


func _shuffle_with_rng(
	values: Array,
	random_generator: RandomNumberGenerator
) -> void:
	for index in range(values.size() - 1, 0, -1):
		var random_index := random_generator.randi_range(0, index)
		var temporary = values[index]

		values[index] = values[random_index]
		values[random_index] = temporary
