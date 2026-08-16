extends Node

signal host_created()
signal all_game_scenes_ready(peer_ids: Array[int])
signal player_display_names_changed()

const LOBBY_TYPE := Steam.LobbyType.LOBBY_TYPE_FRIENDS_ONLY
const MAX_MEMBERS := 4
const LOBBY_SCENE_PATH := "res://scenes/lobby.tscn"
const GAME_SCENE_PATH := "res://scenes/main.tscn"
const SERVER_PING_INTERVAL := 1.0
const SERVER_PING_TIMEOUT := 5.0

var peer: SteamMultiplayerPeer
var current_lobby_id: int = 0
var _is_joining := false
var _host_request_pending := false
var _game_transition_active := false
var _expected_game_peer_ids: Array[int] = []
var _ready_game_peer_ids: Array[int] = []
var _player_display_names: Dictionary = {}
var _display_name_refresh_remaining := 0.0
var _server_ping_ms := -1
var _server_ping_interval_remaining := 0.0
var _server_ping_response_age := 0.0


func _ready() -> void:
	Steam.initRelayNetworkAccess()

	Steam.lobby_created.connect(on_lobby_created)
	Steam.lobby_joined.connect(on_lobby_joined)
	Steam.join_requested.connect(on_join_requested)

	if not multiplayer.peer_disconnected.is_connected(
		_on_transition_peer_disconnected
	):
		multiplayer.peer_disconnected.connect(
			_on_transition_peer_disconnected
		)

	if not multiplayer.peer_connected.is_connected(
		_on_display_name_peer_connected
	):
		multiplayer.peer_connected.connect(
			_on_display_name_peer_connected
		)


func _process(delta: float) -> void:
	Steam.run_callbacks()
	_update_server_ping(delta)

	if not multiplayer.is_server() or peer == null:
		return

	_display_name_refresh_remaining -= delta

	if _display_name_refresh_remaining <= 0.0:
		_display_name_refresh_remaining = 1.0
		_refresh_player_display_names()


func get_server_ping_ms() -> int:
	return _server_ping_ms


func _update_server_ping(delta: float) -> void:
	var active_peer := multiplayer.multiplayer_peer

	if (
		peer == null
		or active_peer == null
		or active_peer.get_connection_status()
		!= MultiplayerPeer.CONNECTION_CONNECTED
	):
		_server_ping_ms = -1
		_server_ping_interval_remaining = 0.0
		_server_ping_response_age = 0.0
		return

	if multiplayer.is_server():
		_server_ping_ms = 0
		_server_ping_response_age = 0.0
		return

	_server_ping_interval_remaining -= delta
	_server_ping_response_age += delta

	if _server_ping_response_age >= SERVER_PING_TIMEOUT:
		_server_ping_ms = -1

	if _server_ping_interval_remaining > 0.0:
		return

	_server_ping_interval_remaining = SERVER_PING_INTERVAL
	_request_server_ping.rpc_id(1, int(Time.get_ticks_msec()))


@rpc("any_peer", "call_remote", "unreliable")
func _request_server_ping(sent_at_msec: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()

	if sender_id <= 0:
		return

	_reply_server_ping.rpc_id(sender_id, sent_at_msec)


@rpc("authority", "call_remote", "unreliable")
func _reply_server_ping(sent_at_msec: int) -> void:
	if multiplayer.is_server():
		return

	var elapsed_msec := int(Time.get_ticks_msec()) - sent_at_msec
	_server_ping_ms = clampi(elapsed_msec, 0, 60_000)
	_server_ping_response_age = 0.0


func host_lobby() -> void:
	_host_request_pending = true
	Steam.createLobby(LOBBY_TYPE, MAX_MEMBERS)


func open_lobby_invite_overlay() -> bool:
	if not multiplayer.is_server():
		return false

	if current_lobby_id == 0:
		push_warning(
			"Der Steam-Einladungsdialog ist erst nach Erstellung der Lobby "
			+ "verfuegbar."
		)
		return false

	Steam.activateGameOverlayInviteDialog(current_lobby_id)
	return true


func leave_lobby() -> void:
	SessionManager.clear_session()
	_is_joining = false
	_host_request_pending = false
	_game_transition_active = false
	_expected_game_peer_ids.clear()
	_ready_game_peer_ids.clear()
	_player_display_names.clear()
	_server_ping_ms = -1
	_server_ping_interval_remaining = 0.0
	_server_ping_response_age = 0.0
	player_display_names_changed.emit()

	if current_lobby_id != 0:
		Steam.leaveLobby(current_lobby_id)
		current_lobby_id = 0

	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

	peer = null


func host_lobby_after_scene_change() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if get_tree().current_scene == null:
		push_error("Die Spielszene wurde noch nicht geladen.")
		return
	if get_tree().current_scene.scene_file_path != LOBBY_SCENE_PATH:
		return

	host_lobby()


func on_lobby_created(connect: int, lobby_id: int) -> void:
	if not _host_request_pending:
		if connect == Steam.RESULT_OK and lobby_id != 0:
			Steam.leaveLobby(lobby_id)
		return

	_host_request_pending = false

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
	SessionManager.start_new_session()
	_refresh_player_display_names()
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

	# Der eingeladene Spieler muss zuerst den Lobbyraum laden.
	var scene_loaded := await _change_to_scene(LOBBY_SCENE_PATH)

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


func start_game_from_lobby() -> void:
	if not multiplayer.is_server() or _game_transition_active:
		return

	_game_transition_active = true
	_expected_game_peer_ids.clear()
	_ready_game_peer_ids.clear()
	_expected_game_peer_ids.append(multiplayer.get_unique_id())

	for peer_id in multiplayer.get_peers():
		_expected_game_peer_ids.append(peer_id)

	if current_lobby_id != 0:
		Steam.setLobbyJoinable(current_lobby_id, false)

	if not SessionManager.has_active_session():
		SessionManager.start_new_session()

	if not SessionManager.begin_mission():
		_game_transition_active = false
		return

	_load_game_scene.rpc(SessionManager.get_state_snapshot())


func is_game_scene_ready() -> bool:
	return (
		_game_transition_active
		and not _expected_game_peer_ids.is_empty()
		and _ready_game_peer_ids.size() >= _expected_game_peer_ids.size()
	)


func get_game_peer_ids() -> Array[int]:
	return _expected_game_peer_ids.duplicate()


func get_player_display_name(peer_id: int) -> String:
	return str(_player_display_names.get(peer_id, ""))


@rpc("authority", "call_local", "reliable")
func _load_game_scene(session_snapshot: Dictionary) -> void:
	SessionManager.apply_authoritative_snapshot(session_snapshot)
	var scene_loaded := await _change_to_scene(GAME_SCENE_PATH)

	if not scene_loaded:
		return

	if multiplayer.is_server():
		_register_game_scene_ready(multiplayer.get_unique_id())
	else:
		_report_game_scene_ready.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _report_game_scene_ready() -> void:
	if not multiplayer.is_server() or not _game_transition_active:
		return

	_register_game_scene_ready(multiplayer.get_remote_sender_id())


func _register_game_scene_ready(peer_id: int) -> void:
	if peer_id not in _expected_game_peer_ids:
		return

	if peer_id not in _ready_game_peer_ids:
		_ready_game_peer_ids.append(peer_id)

	if is_game_scene_ready():
		all_game_scenes_ready.emit(get_game_peer_ids())


func _on_transition_peer_disconnected(peer_id: int) -> void:
	if _player_display_names.erase(peer_id):
		_broadcast_player_display_names()

	if not _game_transition_active:
		return

	_expected_game_peer_ids.erase(peer_id)
	_ready_game_peer_ids.erase(peer_id)

	if is_game_scene_ready():
		all_game_scenes_ready.emit(get_game_peer_ids())


func _on_display_name_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	SessionManager.sync_to_peer(peer_id)
	_refresh_player_display_names()

	if not _player_display_names.is_empty():
		_sync_player_display_names.rpc_id(
			peer_id,
			_player_display_names.duplicate()
		)


func _refresh_player_display_names() -> void:
	if not multiplayer.is_server() or peer == null:
		return

	var peer_ids: Array[int] = [multiplayer.get_unique_id()]
	peer_ids.append_array(multiplayer.get_peers())
	var names_changed := false

	for peer_id in peer_ids:
		var steam_id: int = peer.get_steam_id_for_peer_id(peer_id)

		if steam_id == 0:
			continue

		var display_name := (
			str(Steam.getPersonaName())
			if steam_id == int(Steam.getSteamID())
			else str(Steam.getFriendPersonaName(steam_id))
		)
		display_name = _sanitize_display_name(display_name)

		if display_name.is_empty():
			continue

		if str(_player_display_names.get(peer_id, "")) != display_name:
			_player_display_names[peer_id] = display_name
			names_changed = true

	if names_changed:
		_broadcast_player_display_names()


func _broadcast_player_display_names() -> void:
	if not multiplayer.is_server():
		return

	_sync_player_display_names.rpc(_player_display_names.duplicate())


@rpc("authority", "call_local", "reliable")
func _sync_player_display_names(display_names: Dictionary) -> void:
	_player_display_names.clear()

	for peer_id_value in display_names:
		var peer_id := int(peer_id_value)
		var display_name := _sanitize_display_name(
			str(display_names[peer_id_value])
		)

		if peer_id > 0 and not display_name.is_empty():
			_player_display_names[peer_id] = display_name

	player_display_names_changed.emit()


func _sanitize_display_name(display_name: String) -> String:
	display_name = display_name.replace("\n", " ").replace("\r", " ")
	display_name = display_name.strip_edges()

	if display_name.is_empty() or display_name.to_lower() == "[unknown]":
		return ""

	if display_name.length() > 32:
		display_name = display_name.left(31) + "…"

	return display_name


func _change_to_scene(scene_path: String) -> bool:
	var tree := get_tree()

	tree.paused = false

	# Falls der Client schon in der richtigen Szene ist,
	# muss sie nicht erneut geladen werden.
	if tree.current_scene != null:
		if tree.current_scene.scene_file_path == scene_path:
			return true

	var error := tree.change_scene_to_file(scene_path)

	if error != OK:
		push_error(
			"Netzwerkszene %s konnte nicht geladen werden: %s"
			% [scene_path, error]
		)
		return false

	# change_scene_to_file() schließt den Szenenwechsel
	# erst am Ende des Frames ab.
	await tree.process_frame
	await tree.process_frame

	if tree.current_scene == null:
		push_error("Nach dem Szenenwechsel existiert keine aktuelle Szene.")
		return false

	return tree.current_scene.scene_file_path == scene_path
