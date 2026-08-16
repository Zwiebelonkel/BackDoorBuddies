extends Area3D


func get_interaction_text() -> String:
	var van := get_parent()

	if van != null and van.has_method("get_driver_interaction_text"):
		return str(van.get_driver_interaction_text())

	return "Van fahren"


func request_interaction(player: Node3D) -> void:
	var van := get_parent()

	if van != null and van.has_method("request_drive"):
		van.request_drive(player)
