extends Area3D


const BUTTON_RELEASE_HEIGHT := 0.12
const BUTTON_PRESSED_HEIGHT := -0.035

var _press_tween: Tween


func get_interaction_text() -> String:
	if not multiplayer.is_server():
		return "Nur der Host kann Spieler einladen"

	if Networking.current_lobby_id == 0:
		return "Steam-Lobby wird vorbereitet ..."

	return "Spieler einladen"


func request_interaction(player: Node3D) -> void:
	if (
		player == null
		or not player.is_multiplayer_authority()
		or not multiplayer.is_server()
	):
		return

	if not Networking.open_lobby_invite_overlay():
		return

	_play_press_animation()


func _play_press_animation() -> void:
	var button_mesh := $ButtonMesh as MeshInstance3D

	if button_mesh == null:
		return

	if _press_tween != null and _press_tween.is_valid():
		_press_tween.kill()

	button_mesh.position.y = BUTTON_PRESSED_HEIGHT
	_press_tween = create_tween()
	_press_tween.tween_property(
		button_mesh,
		"position:y",
		BUTTON_RELEASE_HEIGHT,
		0.18
	)
