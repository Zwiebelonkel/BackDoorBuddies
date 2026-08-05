extends Node3D

const PLAYER_CONTROLLER = preload("res://scenes/PlayerController.tscn")

@onready var players_container: Node3D = $Players
@onready var spawn_point: Marker3D = $SpawnPoint

var players: Array[CharacterBody3D] = []


func _ready() -> void:
	Networking.host_created.connect(on_host_created)

	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func on_host_created() -> void:
	# Host-Player erzeugen.
	spawn_player(multiplayer.get_unique_id())

	# Alle später beitretenden Spieler erzeugen.
	if not multiplayer.peer_connected.is_connected(spawn_player):
		multiplayer.peer_connected.connect(spawn_player)


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

	# Wichtig: unter Main/Players hinzufügen.
	players_container.add_child(new_player, true)

	initialize_player(new_player)


func initialize_player(player: CharacterBody3D) -> void:
	if player == null:
		return

	player.global_position = spawn_point.global_position

	for other in players:
		if is_instance_valid(other) and other != player:
			player.add_collision_exception_with(other)
			other.add_collision_exception_with(player)

	if not players.has(player):
		players.append(player)


func _on_host_pressed() -> void:
	Networking.host_lobby()


func _on_multiplayer_spawner_spawned(node: Node) -> void:
	if node is CharacterBody3D:
		initialize_player(node as CharacterBody3D)

func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var player := players_container.get_node_or_null(str(peer_id)) as CharacterBody3D

	if player == null:
		return

	players.erase(player)
	player.queue_free()
