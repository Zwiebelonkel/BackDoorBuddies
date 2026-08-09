class_name ProceduralRoom
extends Node3D


@export_group("Room")
@export var room_id: StringName = &"room"
@export var room_type: StringName = &"normal"

@export_range(0, 100, 1)
var minimum_generation_depth: int = 0

@export_range(0, 100, 1)
var maximum_generation_depth: int = 100

@export_group("Items")
@export_range(0, 50, 1)
var minimum_items: int = 0

@export_range(0, 50, 1)
var maximum_items: int = 3

@onready var sockets_root: Node3D = $DoorSockets
@onready var bounds_shape: CollisionShape3D = $RoomBounds/CollisionShape3D
@onready var item_spawn_points: Node3D = get_node_or_null("ItemSpawnPoints") as Node3D

var generation_depth: int = 0
var generation_index: int = 0


func get_free_sockets() -> Array[RoomSocket]:
	var result: Array[RoomSocket] = []

	for child in sockets_root.get_children():
		if child is RoomSocket:
			var socket := child as RoomSocket

			if not socket.occupied:
				result.append(socket)

	return result


func get_world_aabb(shrink: float = 0.03) -> AABB:
	var box := bounds_shape.shape as BoxShape3D

	assert(box != null, "%s requires a BoxShape3D RoomBounds shape." % name)

	var half_size := box.size * 0.5
	var first_corner := bounds_shape.global_transform * -half_size
	var minimum := first_corner
	var maximum := first_corner

	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			for z_sign in [-1.0, 1.0]:
				var local_corner := Vector3(
					half_size.x * x_sign,
					half_size.y * y_sign,
					half_size.z * z_sign
				)
				var world_corner := bounds_shape.global_transform * local_corner

				minimum.x = minf(minimum.x, world_corner.x)
				minimum.y = minf(minimum.y, world_corner.y)
				minimum.z = minf(minimum.z, world_corner.z)
				maximum.x = maxf(maximum.x, world_corner.x)
				maximum.y = maxf(maximum.y, world_corner.y)
				maximum.z = maxf(maximum.z, world_corner.z)

	var shrink_vector := Vector3.ONE * maxf(shrink, 0.0)
	var final_position := minimum + shrink_vector
	var final_size := maximum - minimum - shrink_vector * 2.0

	final_size.x = maxf(final_size.x, 0.001)
	final_size.y = maxf(final_size.y, 0.001)
	final_size.z = maxf(final_size.z, 0.001)

	return AABB(final_position, final_size)


func spawn_random_items(
	seed_value: int,
	item_parent: Node3D
) -> Array[Node3D]:
	var spawned_items: Array[Node3D] = []

	if item_spawn_points == null or item_parent == null:
		return spawned_items

	var available_points: Array[ItemSpawnPoint] = []

	for child in item_spawn_points.get_children():
		if not child is ItemSpawnPoint:
			continue

		var point := child as ItemSpawnPoint

		if point.spawn_enabled and point.spawn_table != null:
			available_points.append(point)

	if available_points.is_empty():
		return spawned_items

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_shuffle_points(available_points, rng)

	var maximum_possible := mini(maximum_items, available_points.size())
	var minimum_possible := mini(minimum_items, maximum_possible)

	if maximum_possible <= 0:
		return spawned_items

	var target_count := rng.randi_range(minimum_possible, maximum_possible)

	for point in available_points:
		if spawned_items.size() >= target_count:
			break

		var entry := point.spawn_table.pick_entry(rng)

		if entry == null:
			continue

		var spawn_transform_variant: Variant = _get_spawn_transform(point, entry, rng)

		if spawn_transform_variant == null:
			continue

		var spawn_transform: Transform3D = spawn_transform_variant
		var instance: Node = entry.item_scene.instantiate()
		var item := instance as Node3D

		if item == null:
			instance.free()
			push_warning("Item scene %s requires a Node3D root." % entry.item_id)
			continue

		item.name = "Item_%03d_%03d" % [generation_index, spawned_items.size()]
		item.set_meta("item_id", entry.item_id)
		item.transform = (
			item_parent.global_transform.affine_inverse()
			* spawn_transform
		)
		item_parent.add_child(item, true)
		spawned_items.append(item)

	return spawned_items


func _get_spawn_transform(
	point: ItemSpawnPoint,
	entry: ItemSpawnEntry,
	rng: RandomNumberGenerator
) -> Variant:
	var result := point.global_transform

	if point.random_y_rotation:
		var random_angle := rng.randf_range(-PI, PI)
		result.basis = Basis(Vector3.UP, random_angle) * result.basis

	if not point.snap_to_surface:
		result.origin += Vector3.UP * entry.vertical_offset
		return result

	var ray_from := point.global_position + Vector3.UP * point.ray_start_height
	var ray_to := point.global_position + Vector3.DOWN * point.ray_distance
	var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)

	query.collision_mask = point.surface_collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		push_warning("No surface below ItemSpawnPoint %s." % point.name)
		return null

	var hit_position: Vector3 = hit["position"]
	var hit_normal: Vector3 = hit["normal"]
	result.origin = hit_position + hit_normal * entry.vertical_offset

	return result


func _shuffle_points(
	points: Array[ItemSpawnPoint],
	rng: RandomNumberGenerator
) -> void:
	for index in range(points.size() - 1, 0, -1):
		var random_index := rng.randi_range(0, index)
		var temporary := points[index]

		points[index] = points[random_index]
		points[random_index] = temporary
