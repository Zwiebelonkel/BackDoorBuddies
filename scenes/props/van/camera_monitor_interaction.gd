extends Area3D


func get_interaction_text() -> String:
	var monitor := get_parent()

	if monitor != null and monitor.has_method("get_interaction_text"):
		return str(monitor.get_interaction_text())

	return "Kamera wechseln"


func request_interaction(player: Node3D) -> void:
	if player == null or not player.is_multiplayer_authority():
		return

	var monitor := get_parent()

	if monitor != null and monitor.has_method("begin_view"):
		monitor.begin_view(player)
