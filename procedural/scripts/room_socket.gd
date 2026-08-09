class_name RoomSocket
extends Marker3D


@export_group("Connection")
@export var socket_type: StringName = &"door"
@export var compatible_types: Array[StringName] = [&"door"]

@export_group("Unused Socket")
@export var cap_scene: PackedScene

var occupied: bool = false


func is_compatible_with(other: RoomSocket) -> bool:
	if other == null:
		return false

	if occupied or other.occupied:
		return false

	if other.socket_type not in compatible_types:
		return false

	if socket_type not in other.compatible_types:
		return false

	return true


func close_socket() -> void:
	if occupied:
		return

	occupied = true

	if cap_scene == null:
		return

	var cap := cap_scene.instantiate() as Node3D

	if cap == null:
		push_warning("Cap scene requires a Node3D root.")
		return

	add_child(cap)
	cap.transform = Transform3D.IDENTITY


func get_room() -> ProceduralRoom:
	var current: Node = get_parent()

	while current != null:
		if current is ProceduralRoom:
			return current as ProceduralRoom

		current = current.get_parent()

	return null
