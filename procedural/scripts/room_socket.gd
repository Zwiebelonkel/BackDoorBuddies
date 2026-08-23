class_name RoomSocket
extends Marker3D


@export_group("Connection")
@export var socket_type: StringName = &"door"
@export var compatible_types: Array[StringName] = [&"door"]

## Logical floor inside the owning room at which this socket connects.
## Normal rooms use 0. A stairwell spanning two floors uses 0 downstairs
## and 1 upstairs. The generator combines this with the room's floor_index.
@export_range(0, 2, 1) var floor_offset: int = 0

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


func get_connection_floor_index() -> int:
	var room := get_room()

	if room == null:
		return floor_offset

	return room.floor_index + floor_offset


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
