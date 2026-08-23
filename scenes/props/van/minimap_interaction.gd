extends Area3D


func get_interaction_text() -> String:
	var map := _get_map_control()

	if map == null:
		return "Map-Scan"

	var floor_count := int(map.call("get_available_floor_count"))
	var floor_index := int(map.call("get_selected_floor_index"))

	if floor_count <= 1:
		return "Map-Scan: Etage 1 / 1"

	return "Map-Scan: Etage wechseln (%d / %d)" % [
		floor_index + 1,
		floor_count,
	]


func request_interaction(player: Node3D) -> void:
	if player == null or not player.is_multiplayer_authority():
		return

	var map := _get_map_control()

	if map != null:
		map.call("select_next_floor")


func _get_map_control() -> Control:
	var display_root := get_parent()

	if display_root == null:
		return null

	return display_root.get_node_or_null("SubViewport/Map") as Control
