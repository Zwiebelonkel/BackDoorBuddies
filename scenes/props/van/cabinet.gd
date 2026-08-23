class_name VanCabinet
extends Area3D


signal storage_changed
signal operation_failed(message: String)

const CAPACITY := 15

@export_range(1.0, 5.0, 0.1) var access_distance := 2.5

@onready var storage_interface: CanvasLayer = $"../StorageInterface"

var stored_item_paths: Array[String] = []
var stored_item_instance_ids: Array[String] = []


func _ready() -> void:
	add_to_group(&"van_cabinet")


func get_interaction_text() -> String:
	return "Van-Lager öffnen"


func request_interaction(player: Node3D) -> void:
	if (
		player == null
		or not player.has_method("enter_cabinet_storage")
		or not player.is_multiplayer_authority()
	):
		return

	player.call("enter_cabinet_storage", self)


func begin_use(player: Node3D) -> bool:
	if (
		player == null
		or not player.is_multiplayer_authority()
		or not is_instance_valid(storage_interface)
	):
		return false

	storage_interface.call("open_interface", self, player)
	request_storage_snapshot()
	return true


func end_use(player: Node3D) -> void:
	if is_instance_valid(storage_interface):
		storage_interface.call("close_interface", player)


func get_capacity() -> int:
	return CAPACITY


func get_storage_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var entry_count := mini(
		stored_item_paths.size(),
		stored_item_instance_ids.size()
	)

	for item_index in range(entry_count):
		var item_path := stored_item_paths[item_index]
		var loaded_resource := load(item_path)

		if not loaded_resource is ItemData:
			continue

		entries.append({
			"item_path": item_path,
			"item_instance_id": stored_item_instance_ids[item_index],
			"item_data": loaded_resource as ItemData,
		})

	return entries


func request_store_item(
	player: Node3D,
	item_instance_id: String,
	item_resource_path: String
) -> void:
	if player == null or not player.is_multiplayer_authority():
		return

	var peer_id := player.get_multiplayer_authority()

	if multiplayer.is_server():
		_server_store_item(peer_id, item_instance_id, item_resource_path)
	else:
		_request_store_item.rpc_id(
			1,
			item_instance_id,
			item_resource_path
		)


func request_take_item(player: Node3D, item_instance_id: String) -> void:
	if player == null or not player.is_multiplayer_authority():
		return

	var peer_id := player.get_multiplayer_authority()

	if multiplayer.is_server():
		_server_take_item(peer_id, item_instance_id)
	else:
		_request_take_item.rpc_id(1, item_instance_id)


func request_storage_snapshot() -> void:
	if multiplayer.is_server():
		_apply_storage_snapshot(
			stored_item_paths,
			stored_item_instance_ids
		)
	else:
		_request_storage_snapshot.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_store_item(
	item_instance_id: String,
	item_resource_path: String
) -> void:
	if not multiplayer.is_server():
		return

	_server_store_item(
		multiplayer.get_remote_sender_id(),
		item_instance_id,
		item_resource_path
	)


@rpc("any_peer", "call_remote", "reliable")
func _request_take_item(item_instance_id: String) -> void:
	if not multiplayer.is_server():
		return

	_server_take_item(
		multiplayer.get_remote_sender_id(),
		item_instance_id
	)


@rpc("any_peer", "call_remote", "reliable")
func _request_storage_snapshot() -> void:
	if not multiplayer.is_server():
		return

	var peer_id := multiplayer.get_remote_sender_id()

	if peer_id <= 0:
		return

	_sync_storage_snapshot.rpc_id(
		peer_id,
		stored_item_paths,
		stored_item_instance_ids
	)


func _server_store_item(
	peer_id: int,
	item_instance_id: String,
	item_resource_path: String
) -> bool:
	if not multiplayer.is_server():
		return false

	var normalized_instance_id := item_instance_id.strip_edges()
	var normalized_item_path := item_resource_path.strip_edges()
	var player := _find_player(peer_id)

	if not _can_player_access(player):
		_reject_operation(peer_id, "Zu weit vom Van-Lager entfernt.")
		return false

	if stored_item_paths.size() >= CAPACITY:
		_reject_operation(peer_id, "Das Van-Lager ist voll.")
		return false

	if (
		normalized_instance_id.is_empty()
		or normalized_item_path.is_empty()
		or normalized_instance_id in stored_item_instance_ids
	):
		_reject_operation(peer_id, "Ungültiger Lagertransfer.")
		return false

	if _is_item_reserved(peer_id, normalized_instance_id):
		_reject_operation(
			peer_id,
			"Darknet-reservierte Items können nicht eingelagert werden."
		)
		return false

	var loaded_resource := load(normalized_item_path)

	if not loaded_resource is ItemData:
		_reject_operation(peer_id, "Itemdaten konnten nicht geladen werden.")
		return false

	if (
		not player.has_method("server_extract_inventory_item_for_storage")
		or not bool(player.call(
			"server_extract_inventory_item_for_storage",
			normalized_instance_id,
			normalized_item_path
		))
	):
		_reject_operation(peer_id, "Item befindet sich nicht mehr im Inventar.")
		return false

	stored_item_paths.append(normalized_item_path)
	stored_item_instance_ids.append(normalized_instance_id)
	_publish_storage_snapshot()
	return true


func _server_take_item(peer_id: int, item_instance_id: String) -> bool:
	if not multiplayer.is_server():
		return false

	var normalized_instance_id := item_instance_id.strip_edges()
	var player := _find_player(peer_id)

	if not _can_player_access(player):
		_reject_operation(peer_id, "Zu weit vom Van-Lager entfernt.")
		return false

	var item_index := stored_item_instance_ids.find(normalized_instance_id)

	if item_index < 0 or item_index >= stored_item_paths.size():
		_reject_operation(peer_id, "Item befindet sich nicht mehr im Van-Lager.")
		return false

	var item_path := stored_item_paths[item_index]
	var loaded_resource := load(item_path)

	if not loaded_resource is ItemData:
		_reject_operation(peer_id, "Itemdaten konnten nicht geladen werden.")
		return false

	if (
		not player.has_method("server_receive_item")
		or not bool(player.call(
			"server_receive_item",
			loaded_resource as ItemData,
			normalized_instance_id
		))
	):
		_reject_operation(peer_id, "Inventar ist voll oder Hände sind belegt.")
		return false

	stored_item_paths.remove_at(item_index)
	stored_item_instance_ids.remove_at(item_index)
	_publish_storage_snapshot()
	return true


func _find_player(peer_id: int) -> Node3D:
	if peer_id <= 0:
		return null

	var current_scene := get_tree().current_scene

	if current_scene == null:
		return null

	var players_root := current_scene.get_node_or_null("Players")

	if players_root == null:
		return null

	return players_root.get_node_or_null(str(peer_id)) as Node3D


func _can_player_access(player: Node3D) -> bool:
	return (
		player != null
		and is_instance_valid(player)
		and not bool(player.get("is_dead"))
		and player.global_position.distance_to(global_position) <= access_distance
	)


func _is_item_reserved(peer_id: int, item_instance_id: String) -> bool:
	for manager in get_tree().get_nodes_in_group(&"darknet_market_manager"):
		if not manager.has_method("get_reserved_instance_ids"):
			continue

		var reserved_value: Variant = manager.call(
			"get_reserved_instance_ids",
			peer_id
		)

		if reserved_value is Array and item_instance_id in reserved_value:
			return true

	return false


func _publish_storage_snapshot() -> void:
	_sync_storage_snapshot.rpc(
		stored_item_paths,
		stored_item_instance_ids
	)


@rpc("authority", "call_local", "reliable")
func _sync_storage_snapshot(
	item_paths: Array[String],
	item_instance_ids: Array[String]
) -> void:
	if not multiplayer.is_server() and multiplayer.get_remote_sender_id() != 1:
		return

	_apply_storage_snapshot(item_paths, item_instance_ids)


func _apply_storage_snapshot(
	item_paths: Array[String],
	item_instance_ids: Array[String]
) -> void:
	stored_item_paths = item_paths.duplicate()
	stored_item_instance_ids = item_instance_ids.duplicate()

	if stored_item_paths.size() > CAPACITY:
		stored_item_paths.resize(CAPACITY)

	if stored_item_instance_ids.size() > stored_item_paths.size():
		stored_item_instance_ids.resize(stored_item_paths.size())

	storage_changed.emit()


func _reject_operation(peer_id: int, message: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		operation_failed.emit(message)
	elif peer_id > 0:
		_notify_operation_failed.rpc_id(peer_id, message)


@rpc("authority", "call_remote", "reliable")
func _notify_operation_failed(message: String) -> void:
	operation_failed.emit(message)
