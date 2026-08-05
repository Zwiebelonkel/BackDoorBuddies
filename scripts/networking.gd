extends Node

signal host_created()

const LOBBY_TYPE := Steam.LobbyType.LOBBY_TYPE_FRIENDS_ONLY
const MAX_MEMBERS := 4
const GAME_SCENE_PATH := "res://scenes/main.tscn"

var peer: SteamMultiplayerPeer
var current_lobby_id: int = 0
var _is_joining := false


func _ready() -> void:
	Steam.initRelayNetworkAccess()

	Steam.lobby_created.connect(on_lobby_created)
	Steam.lobby_joined.connect(on_lobby_joined)
	Steam.join_requested.connect(on_join_requested)


func _process(_delta: float) -> void:
	Steam.run_callbacks()


func host_lobby() -> void:
	Steam.createLobby(LOBBY_TYPE, MAX_MEMBERS)


func host_lobby_after_scene_change() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if get_tree().current_scene == null:
		push_error("Die Spielszene wurde noch nicht geladen.")
		return

	host_lobby()


func on_lobby_created(connect: int, lobby_id: int) -> void:
	if connect != Steam.RESULT_OK:
		push_error("Steam-Lobby konnte nicht erstellt werden: %s" % connect)
		return

	current_lobby_id = lobby_id

	peer = SteamMultiplayerPeer.new()
	peer.server_relay = true

	var result := peer.create_host()

	if result != OK:
		push_error("Steam-Host konnte nicht erstellt werden: %s" % result)
		return

	multiplayer.multiplayer_peer = peer
	host_created.emit()


func on_lobby_joined(
	lobby_id: int,
	_permissions: int,
	_locked: bool,
	response: int
) -> void:
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		push_error("Steam-Lobby konnte nicht betreten werden: %s" % response)
		_is_joining = false
		return

	current_lobby_id = lobby_id

	var lobby_owner := Steam.getLobbyOwner(lobby_id)

	# Der Host erhält lobby_joined ebenfalls, ist aber schon verbunden.
	if lobby_owner == Steam.getSteamID():
		return

	# Der eingeladene Spieler muss zuerst die Spielszene laden.
	var scene_loaded := await _change_to_game_scene()

	if not scene_loaded:
		_is_joining = false
		return

	# Warten, bis Main, Players und MultiplayerSpawner im Tree sind.
	await get_tree().process_frame
	await get_tree().process_frame

	peer = SteamMultiplayerPeer.new()
	peer.server_relay = true

	var result := peer.create_client(lobby_owner)

	if result != OK:
		push_error("Verbindung zum Steam-Host fehlgeschlagen: %s" % result)
		_is_joining = false
		return

	multiplayer.multiplayer_peer = peer
	_is_joining = false


func on_join_requested(lobby_id: int, _steam_id: int) -> void:
	if _is_joining:
		return

	_is_joining = true
	Steam.joinLobby(lobby_id)


func _change_to_game_scene() -> bool:
	var tree := get_tree()

	tree.paused = false

	# Falls der Client schon in der richtigen Szene ist,
	# muss sie nicht erneut geladen werden.
	if tree.current_scene != null:
		if tree.current_scene.scene_file_path == GAME_SCENE_PATH:
			return true

	var error := tree.change_scene_to_file(GAME_SCENE_PATH)

	if error != OK:
		push_error(
			"Game-Szene konnte beim Client nicht geladen werden: %s"
			% error
		)
		return false

	# change_scene_to_file() schließt den Szenenwechsel
	# erst am Ende des Frames ab.
	await tree.process_frame
	await tree.process_frame

	if tree.current_scene == null:
		push_error("Nach dem Szenenwechsel existiert keine aktuelle Szene.")
		return false

	return tree.current_scene.scene_file_path == GAME_SCENE_PATH
