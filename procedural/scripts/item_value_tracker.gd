class_name ItemValueTracker
extends Node


signal values_changed(van_value: int, generated_room_value: int)

@export var generator_path: NodePath = ^"../ProceduralLevelGenerator"
@export_range(0.05, 2.0, 0.05) var refresh_interval: float = 0.25

var van_value: int = 0
var generated_room_value: int = 0
var _generator: ProceduralLevelGenerator
var _refresh_time_remaining := 0.0
var _has_published_values := false


func _ready() -> void:
	add_to_group(&"item_value_tracker")
	call_deferred("refresh_values")


func _process(delta: float) -> void:
	_refresh_time_remaining -= delta

	if _refresh_time_remaining > 0.0:
		return

	_refresh_time_remaining = refresh_interval
	refresh_values()


func refresh_values() -> void:
	_resolve_generator()

	var next_van_value := 0
	var next_generated_room_value := 0

	if _generator != null and is_instance_valid(_generator.items_root):
		for child in _generator.items_root.get_children():
			var pickup := child as PickupItem

			if pickup == null or pickup.item_data == null:
				continue

			var item_value := maxi(pickup.item_data.value, 0)

			if _is_point_in_van(pickup.global_position):
				next_van_value += item_value
			elif _is_point_in_generated_room(pickup.global_position):
				next_generated_room_value += item_value

	if (
		not _has_published_values
		or next_van_value != van_value
		or next_generated_room_value != generated_room_value
	):
		van_value = next_van_value
		generated_room_value = next_generated_room_value
		_has_published_values = true
		values_changed.emit(van_value, generated_room_value)


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


func _is_point_in_generated_room(point: Vector3) -> bool:
	if _generator == null:
		return false

	for bounds in _generator.generated_bounds:
		var bounds_end := bounds.end

		if (
			point.x >= bounds.position.x
			and point.x <= bounds_end.x
			and point.z >= bounds.position.z
			and point.z <= bounds_end.z
		):
			return true

	return false


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
