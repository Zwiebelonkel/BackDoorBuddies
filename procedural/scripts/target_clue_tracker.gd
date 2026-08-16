class_name TargetClueTracker
extends Node

signal clue_analyzed(clue_type: StringName, value: String)

@export var generator_path: NodePath = ^"../ProceduralLevelGenerator"
@export_range(0.05, 2.0, 0.05) var refresh_interval := 0.2

var _generator: ProceduralLevelGenerator
var _refresh_time_remaining := 0.0


func _ready() -> void:
	add_to_group(&"target_clue_tracker")
	call_deferred("refresh_clues")


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	_refresh_time_remaining -= delta

	if _refresh_time_remaining > 0.0:
		return

	_refresh_time_remaining = refresh_interval
	refresh_clues()


func refresh_clues() -> void:
	if not multiplayer.is_server() or not SessionManager.mission_in_progress:
		return

	_resolve_generator()

	if _generator == null or not is_instance_valid(_generator.items_root):
		return

	for child in _generator.items_root.get_children():
		var pickup := child as PickupItem

		if (
			pickup == null
			or pickup.item_data == null
			or not pickup.item_data.is_mission_clue
			or pickup.has_meta(&"target_clue_analyzed")
			or not _is_point_in_van(pickup.global_position)
		):
			continue

		pickup.set_meta(&"target_clue_analyzed", true)
		var clue_type := pickup.item_data.target_clue_type

		if SessionManager.reveal_target_clue(clue_type):
			clue_analyzed.emit(
				clue_type,
				SessionManager.get_target_attribute_value(clue_type)
			)


func _resolve_generator() -> void:
	if is_instance_valid(_generator):
		return

	_generator = get_node_or_null(generator_path) as ProceduralLevelGenerator

	if _generator != null:
		return

	var current_scene := get_tree().current_scene

	if current_scene != null:
		_generator = current_scene.get_node_or_null(
			"ProceduralLevelGenerator"
		) as ProceduralLevelGenerator


func _is_point_in_van(point: Vector3) -> bool:
	for zone_node in get_tree().get_nodes_in_group(&"van_item_zone"):
		var zone := zone_node as Area3D

		if zone == null:
			continue

		var collision_shape := zone.get_node_or_null(
			"CollisionShape3D"
		) as CollisionShape3D

		if collision_shape == null:
			continue

		var box := collision_shape.shape as BoxShape3D

		if box == null:
			continue

		var local_point := (
			collision_shape.global_transform.affine_inverse()
			* point
		)
		var half_size := box.size * 0.5

		if (
			absf(local_point.x) <= half_size.x
			and absf(local_point.y) <= half_size.y
			and absf(local_point.z) <= half_size.z
		):
			return true

	return false
