@tool
class_name ProceduralRoomShell
extends Node3D


const DOOR_WIDTH := 1.2
const DOOR_HEIGHT := 2.2
const WALL_HEIGHT := 3.0
const WALL_THICKNESS := 0.15
const SLAB_THICKNESS := 0.1

@export var room_size := Vector2(6.0, 5.0):
	set(value):
		room_size = Vector2(maxf(value.x, DOOR_WIDTH + 0.2), maxf(value.y, DOOR_WIDTH + 0.2))
		_request_rebuild()

@export var door_sides: Array[StringName] = [&"north", &"south"]:
	set(value):
		door_sides = value
		_request_rebuild()

@export_group("Appearance")
@export var floor_color := Color(0.16, 0.17, 0.19):
	set(value):
		floor_color = value
		_request_rebuild()

@export var wall_color := Color(0.42, 0.43, 0.46):
	set(value):
		wall_color = value
		_request_rebuild()

@export var ceiling_color := Color(0.25, 0.26, 0.28):
	set(value):
		ceiling_color = value
		_request_rebuild()

var _rebuild_queued := false


func _ready() -> void:
	_rebuild()


func _request_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return

	_rebuild_queued = true
	call_deferred("_rebuild")


func _rebuild() -> void:
	_rebuild_queued = false

	var floor_root := get_node_or_null("Floor") as Node3D
	var walls_root := get_node_or_null("Walls") as Node3D
	var ceiling_root := get_node_or_null("Ceiling") as Node3D
	var static_body := get_node_or_null("../StaticBody3D") as StaticBody3D

	if floor_root == null or walls_root == null or ceiling_root == null or static_body == null:
		return

	_clear_generated_children(floor_root)
	_clear_generated_children(walls_root)
	_clear_generated_children(ceiling_root)
	_clear_generated_children(static_body)

	var floor_material := _create_material(floor_color)
	var wall_material := _create_material(wall_color)
	var ceiling_material := _create_material(ceiling_color)

	_add_visual_box(
		floor_root,
		"FloorMesh",
		Vector3(room_size.x, SLAB_THICKNESS, room_size.y),
		Vector3(0.0, -SLAB_THICKNESS * 0.5, 0.0),
		floor_material
	)
	_add_collision_box(
		static_body,
		"FloorCollision",
		Vector3(room_size.x, SLAB_THICKNESS, room_size.y),
		Vector3(0.0, -SLAB_THICKNESS * 0.5, 0.0)
	)

	_add_visual_box(
		ceiling_root,
		"CeilingMesh",
		Vector3(room_size.x, SLAB_THICKNESS, room_size.y),
		Vector3(0.0, WALL_HEIGHT + SLAB_THICKNESS * 0.5, 0.0),
		ceiling_material
	)
	_add_collision_box(
		static_body,
		"CeilingCollision",
		Vector3(room_size.x, SLAB_THICKNESS, room_size.y),
		Vector3(0.0, WALL_HEIGHT + SLAB_THICKNESS * 0.5, 0.0)
	)

	_build_wall(&"north", walls_root, static_body, wall_material)
	_build_wall(&"south", walls_root, static_body, wall_material)
	_build_wall(&"east", walls_root, static_body, wall_material)
	_build_wall(&"west", walls_root, static_body, wall_material)


func _build_wall(
	side: StringName,
	walls_root: Node3D,
	static_body: StaticBody3D,
	material: StandardMaterial3D
) -> void:
	var horizontal := side == &"north" or side == &"south"
	var wall_length := room_size.x if horizontal else room_size.y
	var wall_position := Vector3.ZERO

	if side == &"north":
		wall_position.z = -room_size.y * 0.5
	elif side == &"south":
		wall_position.z = room_size.y * 0.5
	elif side == &"east":
		wall_position.x = room_size.x * 0.5
	else:
		wall_position.x = -room_size.x * 0.5

	if side not in door_sides:
		_add_wall_piece(side, "Full", wall_length, WALL_HEIGHT, 0.0, WALL_HEIGHT * 0.5, horizontal, wall_position, walls_root, static_body, material)
		return

	var side_length := (wall_length - DOOR_WIDTH) * 0.5
	var side_offset := DOOR_WIDTH * 0.5 + side_length * 0.5

	_add_wall_piece(side, "Left", side_length, WALL_HEIGHT, -side_offset, WALL_HEIGHT * 0.5, horizontal, wall_position, walls_root, static_body, material)
	_add_wall_piece(side, "Right", side_length, WALL_HEIGHT, side_offset, WALL_HEIGHT * 0.5, horizontal, wall_position, walls_root, static_body, material)
	_add_wall_piece(side, "Lintel", DOOR_WIDTH, WALL_HEIGHT - DOOR_HEIGHT, 0.0, DOOR_HEIGHT + (WALL_HEIGHT - DOOR_HEIGHT) * 0.5, horizontal, wall_position, walls_root, static_body, material)


func _add_wall_piece(
	side: StringName,
	suffix: String,
	length: float,
	height: float,
	horizontal_offset: float,
	y_position: float,
	horizontal: bool,
	wall_position: Vector3,
	walls_root: Node3D,
	static_body: StaticBody3D,
	material: StandardMaterial3D
) -> void:
	var size := Vector3(length, height, WALL_THICKNESS) if horizontal else Vector3(WALL_THICKNESS, height, length)
	var position := wall_position

	if horizontal:
		position.x = horizontal_offset
	else:
		position.z = horizontal_offset

	position.y = y_position
	var piece_name := "%s%s" % [String(side).capitalize(), suffix]

	_add_visual_box(walls_root, piece_name, size, position, material)
	_add_collision_box(static_body, piece_name + "Collision", size, position)


func _add_visual_box(
	parent: Node3D,
	node_name: String,
	size: Vector3,
	position: Vector3,
	material: StandardMaterial3D
) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()

	mesh.size = size
	mesh.material = material
	mesh_instance.name = node_name
	mesh_instance.mesh = mesh
	mesh_instance.position = position
	parent.add_child(mesh_instance)


func _add_collision_box(
	parent: StaticBody3D,
	node_name: String,
	size: Vector3,
	position: Vector3
) -> void:
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()

	shape.size = size
	collision.name = node_name
	collision.shape = shape
	collision.position = position
	parent.add_child(collision)


func _create_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material


func _clear_generated_children(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
