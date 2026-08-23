extends Area3D


func get_interaction_text() -> String:
	var terminal := get_parent()

	if terminal != null and terminal.has_method("get_interaction_text"):
		return str(terminal.get_interaction_text())

	return "Darknet-Terminal öffnen"


func request_interaction(player: Node3D) -> void:
	var terminal := get_parent()

	if terminal != null and terminal.has_method("begin_use"):
		terminal.begin_use(player)
