extends Node3D

signal mission_intro_finished

const PLAYER_CONTROLLER = preload("res://scenes/PlayerController.tscn")
const PICKUP_ITEM_SCENE: PackedScene = preload(
	"res://scenes/items/PickupItem.tscn"
)

@onready var players_container: Node3D = $Players
@onready var level_generator: ProceduralLevelGenerator = $ProceduralLevelGenerator
@onready var items_container: Node3D = $ProceduralLevelGenerator/SpawnedItems
@onready var item_spawner: MultiplayerSpawner = $ProceduralLevelGenerator/ItemSpawner
@onready var spawn_point: Marker3D = $Hall/HallSpawnPoint
@onready var mission_intro: MissionIntro = $MissionIntro
@onready var outside_world_environment: WorldEnvironment = $Environment/Outside
@onready var van_camera_monitor: Node3D = $Hall/Van/CameraMonitor

var players: Array[CharacterBody3D] = []
var _game_started := false
var _mission_intro_active := true
var _indoor_environment: Environment

const SPAWN_OFFSETS: Array[Vector3] = [
	Vector3.ZERO,
	Vector3(1.5, 0.0, 0.0),
	Vector3(-1.5, 0.0, 0.0),
	Vector3(0.0, 0.0, 1.5),
	Vector3(0.0, 0.0, -1.5),
]


func _ready() -> void:
	_indoor_environment = _create_fog_free_environment(
		outside_world_environment.environment
	)
	van_camera_monitor.call(
		"set_fog_free_environment",
		_indoor_environment
	)
	item_spawner.spawn_function = _spawn_dropped_item

	if mission_intro.has_finished():
		_on_mission_intro_sequence_finished()
	elif not mission_intro.sequence_finished.is_connected(
		_on_mission_intro_sequence_finished
	):
		mission_intro.sequence_finished.connect(
			_on_mission_intro_sequence_finished
		)

	if not Networking.all_game_scenes_ready.is_connected(
		_on_all_game_scenes_ready
	):
		Networking.all_game_scenes_ready.connect(_on_all_game_scenes_ready)

	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	if multiplayer.is_server() and Networking.is_game_scene_ready():
		_on_all_game_scenes_ready(Networking.get_game_peer_ids())


func _process(_delta: float) -> void:
	update_local_camera_environment()


func get_indoor_environment() -> Environment:
	return _indoor_environment


func is_position_inside_building(point: Vector3) -> bool:
	for bounds in level_generator.generated_bounds:
		if (
			point.x >= bounds.position.x
			and point.x <= bounds.end.x
			and point.z >= bounds.position.z
			and point.z <= bounds.end.z
		):
			return true

	return false


func update_local_camera_environment() -> void:
	if _indoor_environment == null:
		return

	for player_node in players:
		var player := player_node as FPSController

		if (
			player == null
			or not is_instance_valid(player)
			or not player.is_multiplayer_authority()
			or player.camera == null
		):
			continue

		var target_environment := (
			_indoor_environment
			if is_position_inside_building(player.global_position)
			else null
		)

		if player.camera.environment != target_environment:
			player.camera.environment = target_environment


func _create_fog_free_environment(source: Environment) -> Environment:
	var environment := (
		source.duplicate(true) as Environment
		if source != null
		else Environment.new()
	)

	environment.resource_name = "IndoorNoFogEnvironment"
	environment.fog_enabled = false
	environment.volumetric_fog_enabled = false
	environment.set_meta(&"options_default_fog", false)
	environment.set_meta(&"options_default_volumetric_fog", false)
	return environment


func _spawn_dropped_item(data: Variant) -> Node:
	if not data is Dictionary:
		push_error("Ungültige Drop-Daten erhalten.")
		return null

	var item_path := str(data.get("item_path", ""))
	var spawn_position := data.get("position", Vector3.ZERO) as Vector3
	var spawn_rotation := data.get("rotation", Vector3.ZERO) as Vector3

	if item_path.is_empty():
		push_error("Dem gedroppten Item fehlt der ItemData-Pfad.")
		return null

	var loaded_data := load(item_path)

	if not loaded_data is ItemData:
		push_error("Ungültige ItemData beim Drop: " + item_path)
		return null

	var pickup := PICKUP_ITEM_SCENE.instantiate() as PickupItem

	if pickup == null:
		push_error("PickupItem konnte nicht erstellt werden.")
		return null

	pickup.item_data = loaded_data as ItemData
	pickup.position = spawn_position
	pickup.rotation = spawn_rotation
	pickup.use_initial_pickup_delay = true

	return pickup


func server_spawn_dropped_item(
	item_path: String,
	spawn_position: Vector3,
	spawn_rotation: Vector3
) -> void:
	if not multiplayer.is_server():
		return

	if item_path.is_empty():
		return

	var spawn_data := {
		"item_path": item_path,
		"position": spawn_position,
		"rotation": spawn_rotation
	}

	item_spawner.spawn(spawn_data)

func _on_all_game_scenes_ready(peer_ids: Array[int]) -> void:
	if not multiplayer.is_server() or _game_started:
		return

	_game_started = true
	_apply_session_difficulty()
	level_generator.start_network_generation()

	# Host-Player erzeugen.
	for peer_id in peer_ids:
		spawn_player(peer_id)

	# Alle später beitretenden Spieler erzeugen.
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)


func _apply_session_difficulty() -> void:
	level_generator.maximum_rooms = SessionManager.get_target_room_count()
	level_generator.surveillance_camera_room_chance = (
		SessionManager.get_surveillance_camera_chance()
	)
	level_generator.minimum_surveillance_cameras = (
		SessionManager.get_minimum_surveillance_cameras()
	)
	level_generator.maximum_surveillance_cameras = (
		SessionManager.get_maximum_surveillance_cameras()
	)


func _on_peer_connected(peer_id: int) -> void:
	spawn_player(peer_id)
	level_generator.sync_level_to_peer(peer_id)
	await get_tree().process_frame

	for player in players:
		if (
			is_instance_valid(player)
			and player.has_method("server_sync_vitals_to_peer")
		):
			player.server_sync_vitals_to_peer(peer_id)


func spawn_player(peer_id: int) -> void:
	# Nur der Server soll Netzwerkspieler erzeugen.
	if not multiplayer.is_server():
		return
		
	var existing_player := players_container.get_node_or_null(str(peer_id))
	if existing_player != null:
		existing_player.queue_free()
		await existing_player.tree_exited
	# Doppeltes Spawnen verhindern.
	if players_container.has_node(str(peer_id)):
		return

	var new_player := PLAYER_CONTROLLER.instantiate() as CharacterBody3D

	if new_player == null:
		push_error("PlayerController konnte nicht instanziiert werden.")
		return

	# Vor add_child setzen, damit der NodePath bei allen Peers stimmt.
	new_player.name = str(peer_id)
	new_player.position = players_container.to_local(_find_free_spawn_position())

	# Wichtig: unter Main/Players hinzufügen.
	players_container.add_child(new_player, true)

	_register_player(new_player)


func _register_player(player: CharacterBody3D) -> void:
	if player == null:
		return

	for other in players:
		if is_instance_valid(other) and other != player:
			player.add_collision_exception_with(other)
			other.add_collision_exception_with(player)

	if not players.has(player):
		players.append(player)

	if player.is_multiplayer_authority():
		update_local_camera_environment()

	if _mission_intro_active and player.is_multiplayer_authority():
		player.set_process_unhandled_input(false)
		player.set_physics_process(false)


func is_mission_intro_active() -> bool:
	return _mission_intro_active


func _on_mission_intro_sequence_finished() -> void:
	if not _mission_intro_active:
		return

	_mission_intro_active = false

	for player in players:
		if is_instance_valid(player) and player.is_multiplayer_authority():
			player.set_process_unhandled_input(true)
			player.set_physics_process(true)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	mission_intro_finished.emit()


func _find_free_spawn_position() -> Vector3:
	for offset in SPAWN_OFFSETS:
		var candidate := spawn_point.global_position + offset
		var is_free := true

		for other in players:
			if (
				is_instance_valid(other)
				and other.global_position.distance_to(candidate) < 1.0
			):
				is_free = false
				break

		if is_free:
			return candidate

	# MAX_MEMBERS ist kleiner als die Kandidatenzahl; dieser Fallback schützt
	# trotzdem vor Überlappungen, falls die Lobbygröße später erhöht wird.
	return spawn_point.global_position + Vector3(
		float(players.size()) * 1.5,
		0.0,
		0.0
	)


func _on_multiplayer_spawner_spawned(node: Node) -> void:
	if node is CharacterBody3D:
		_register_player(node as CharacterBody3D)

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var player := players_container.get_node_or_null(str(peer_id)) as CharacterBody3D

	if player == null:
		return

	players.erase(player)
	player.queue_free()
