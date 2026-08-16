extends Area3D


var _start_requested := false


func get_interaction_text() -> String:
	if _start_requested:
		return "Mission wird geladen ..."

	if multiplayer.is_server():
		return "Mission starten"

	return "Warte auf den Host"


func request_interaction(player: Node3D) -> void:
	if (
		_start_requested
		or player == null
		or not player.is_multiplayer_authority()
		or not multiplayer.is_server()
	):
		return

	_start_requested = true
	$ButtonMesh.position.y = -0.035
	Networking.start_game_from_lobby()
