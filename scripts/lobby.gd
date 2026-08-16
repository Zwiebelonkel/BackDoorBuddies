extends Node3D


const PLAYER_CONTROLLER := preload("res://scenes/PlayerController.tscn")
const PISTOL_PICKUP := preload("res://procedural/items/pistol_pickup.tscn")
const SNIPER_PICKUP := preload("res://procedural/items/sniper_pickup.tscn")
const KNIFE_PICKUP := preload("res://procedural/items/knife_pickup.tscn")
const PICKUP_ITEM_SCENE: PackedScene = preload(
	"res://scenes/items/PickupItem.tscn"
)

@onready var players_container: Node3D = $Players
@onready var item_spawner: MultiplayerSpawner = $ItemSpawner
@onready var spawn_point: Marker3D = $PlayerSpawn
@onready var status_label: Label = $LobbyUI/Status

var players: Array[CharacterBody3D] = []
var _host_bootstrapped := false

const SPAWN_OFFSETS: Array[Vector3] = [
	Vector3.ZERO,
	Vector3(1.4, 0.0, 0.0),
	Vector3(-1.4, 0.0, 0.0),
	Vector3(0.0, 0.0, 1.4),
]


func _ready() -> void:
	item_spawner.spawn_function = _spawn_dropped_item

	if not Networking.host_created.is_connected(_on_host_created):
		Networking.host_created.connect(_on_host_created)

	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)

	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	_update_status()


func _process(_delta: float) -> void:
	_update_status()


func _on_host_created() -> void:
	if _host_bootstrapped or not multiplayer.is_server():
		return

	_host_bootstrapped = true
	_spawn_lobby_weapons()
	spawn_player(multiplayer.get_unique_id())


func _spawn_lobby_weapons() -> void:
	var weapons_root := $WeaponPickups as Node3D

	if weapons_root == null:
		return

	if not weapons_root.has_node("PistolPickup"):
		var pistol := PISTOL_PICKUP.instantiate() as PickupItem
		pistol.name = "PistolPickup"
		pistol.position = Vector3(-4.6, 1.08, -2.3)
		pistol.rotation = Vector3(0.0, 0.4, 0.0)
		pistol.rotate_model = true
		pistol.floating_enabled = true
		weapons_root.add_child(pistol, true)

	if not weapons_root.has_node("KnifePickup"):
		var knife := KNIFE_PICKUP.instantiate() as PickupItem
		knife.name = "KnifePickup"
		knife.position = Vector3(-3.0, 1.08, -2.3)
		knife.rotation = Vector3(0.0, -0.4, 0.0)
		knife.rotate_model = true
		knife.floating_enabled = true
		weapons_root.add_child(knife, true)

	if not weapons_root.has_node("SniperPickup"):
		var sniper := SNIPER_PICKUP.instantiate() as PickupItem
		sniper.name = "SniperPickup"
		sniper.position = Vector3(-1.4, 1.08, -2.3)
		sniper.rotation = Vector3(0.0, 0.15, 0.0)
		sniper.rotate_model = true
		sniper.floating_enabled = true
		weapons_root.add_child(sniper, true)


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		spawn_player(peer_id)


func spawn_player(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id <= 0:
		return

	if players_container.has_node(str(peer_id)):
		return

	var player := PLAYER_CONTROLLER.instantiate() as CharacterBody3D

	if player == null:
		push_error("Lobby-Spieler konnte nicht erstellt werden.")
		return

	player.name = str(peer_id)
	player.position = players_container.to_local(_find_free_spawn_position())
	players_container.add_child(player, true)
	_register_player(player)


func _register_player(player: CharacterBody3D) -> void:
	if player == null or player.name == "0":
		return

	for other in players:
		if is_instance_valid(other) and other != player:
			player.add_collision_exception_with(other)
			other.add_collision_exception_with(player)

	if not players.has(player):
		players.append(player)


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

	return spawn_point.global_position


func _on_multiplayer_spawner_spawned(node: Node) -> void:
	var player := node as CharacterBody3D

	if player != null:
		_register_player(player)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var player := players_container.get_node_or_null(
		str(peer_id)
	) as CharacterBody3D

	if player == null:
		return

	players.erase(player)
	player.queue_free()


func server_spawn_dropped_item(
	item_path: String,
	spawn_position: Vector3,
	spawn_rotation: Vector3
) -> void:
	if not multiplayer.is_server() or item_path.is_empty():
		return

	item_spawner.spawn({
		"item_path": item_path,
		"position": spawn_position,
		"rotation": spawn_rotation,
	})


func _spawn_dropped_item(data: Variant) -> Node:
	if not data is Dictionary:
		return null

	var item_path := str(data.get("item_path", ""))
	var loaded_data := load(item_path)

	if not loaded_data is ItemData:
		return null

	var pickup := PICKUP_ITEM_SCENE.instantiate() as PickupItem

	if pickup == null:
		return null

	pickup.item_data = loaded_data as ItemData
	pickup.position = data.get("position", Vector3.ZERO) as Vector3
	pickup.rotation = data.get("rotation", Vector3.ZERO) as Vector3
	pickup.use_initial_pickup_delay = true
	return pickup


func _update_status() -> void:
	if status_label == null:
		return

	var connected_count := players_container.get_child_count() - 1
	var role_text := "HOST" if multiplayer.is_server() else "SPIELER"
	status_label.text = "%s  |  %d/4 VERBUNDEN" % [
		role_text,
		maxi(connected_count, 0),
	]
