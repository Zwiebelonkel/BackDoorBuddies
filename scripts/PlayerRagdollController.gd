extends Node

const RAGDOLL_BONES: Array[StringName] = [
	&"Hips",
	&"Chest",
	&"Head",
	&"LeftUpperArm",
	&"LeftLowerArm",
	&"LeftHand",
	&"RightUpperArm",
	&"RightLowerArm",
	&"RightHand",
	&"LeftUpperLeg",
	&"LeftLowerLeg",
	&"LeftFoot",
	&"RightUpperLeg",
	&"RightLowerLeg",
	&"RightFoot",
]

@export_node_path("CharacterBody3D") var player_path := NodePath("..")
@export_node_path("Node3D") var model_root_path := NodePath("../playerModell")
@export var ragdoll_collision_layer: int = 4
@export var ragdoll_collision_mask: int = 1
@export_range(0.0, 10.0, 0.1) var death_impulse_multiplier := 1.0
@export_range(0.0, 20.0, 0.1) var maximum_death_impulse := 4.0
@export_range(0.1, 30.0, 0.1) var maximum_linear_speed := 6.0
@export_range(0.1, 50.0, 0.1) var maximum_angular_speed := 10.0

var _player: CharacterBody3D
var _skeleton: Skeleton3D
var _simulator: PhysicalBoneSimulator3D
var _physical_bones: Array[PhysicalBone3D] = []
var _requested_active := false
var _requested_impulse := Vector3.ZERO
var _is_ready := false


func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	call_deferred("_setup_ragdoll")


func _physics_process(_delta: float) -> void:
	if not is_ragdoll_active():
		return

	# Solver-Spitzen abfangen, damit ein Ragdoll bei ungünstigem Kontakt mit
	# Boden oder Wänden nicht unkontrolliert beschleunigt.
	for physical_bone in _physical_bones:
		physical_bone.linear_velocity = _clamp_velocity(
			physical_bone.linear_velocity,
			maximum_linear_speed
		)
		physical_bone.angular_velocity = _clamp_velocity(
			physical_bone.angular_velocity,
			maximum_angular_speed
		)


func set_ragdoll_active(active: bool, impulse := Vector3.ZERO) -> void:
	_requested_active = active
	_requested_impulse = impulse

	if not _is_ready:
		return

	if active:
		_start_ragdoll(impulse)
	else:
		_stop_ragdoll()


func is_ragdoll_active() -> bool:
	return _simulator != null and _simulator.is_simulating_physics()


func get_ragdoll_center_position() -> Vector3:
	for physical_bone in _physical_bones:
		if physical_bone.bone_name == &"Hips":
			return physical_bone.global_position

	return _player.global_position if _player != null else Vector3.ZERO


func _setup_ragdoll() -> void:
	var model_root := get_node_or_null(model_root_path)

	if model_root == null:
		push_warning("Player-Modell für das Ragdoll wurde nicht gefunden.")
		return

	_skeleton = model_root.find_child("Skeleton3D", true, false) as Skeleton3D

	if _skeleton == null:
		push_warning("Player-Modell besitzt kein Skeleton3D.")
		return

	_simulator = PhysicalBoneSimulator3D.new()
	_simulator.name = "PhysicalBoneSimulator3D"
	_skeleton.add_child(_simulator)

	for bone_name in RAGDOLL_BONES:
		_create_physical_bone(bone_name)

	if _player != null:
		_simulator.physical_bones_add_collision_exception(_player.get_rid())

	_is_ready = not _physical_bones.is_empty()

	if _requested_active:
		_start_ragdoll(_requested_impulse)


func _create_physical_bone(bone_name: StringName) -> void:
	var bone_id := _skeleton.find_bone(bone_name)

	if bone_id < 0:
		return

	var physical_bone := PhysicalBone3D.new()
	physical_bone.name = "Physical Bone %s" % bone_name
	physical_bone.bone_name = bone_name
	physical_bone.joint_type = (
		PhysicalBone3D.JOINT_TYPE_NONE
		if bone_name == &"Hips"
		else PhysicalBone3D.JOINT_TYPE_CONE
	)
	physical_bone.mass = _get_bone_mass(bone_name)
	physical_bone.friction = 0.8
	physical_bone.bounce = 0.05
	physical_bone.linear_damp = 1.25
	physical_bone.angular_damp = 1.75
	physical_bone.collision_layer = 0
	physical_bone.collision_mask = 0
	_simulator.add_child(physical_bone)

	var collision := CollisionShape3D.new()
	var shape_data := _get_bone_shape_data(bone_id, bone_name)
	var bone_length: float = shape_data["length"]
	var bone_radius: float = shape_data["radius"]
	var direction: Vector3 = shape_data["direction"]
	var capsule := CapsuleShape3D.new()
	capsule.radius = minf(bone_radius, bone_length * 0.45)
	capsule.height = maxf(bone_length, capsule.radius * 2.0)
	collision.shape = capsule
	collision.transform = Transform3D(
		_create_y_aligned_basis(direction),
		direction * bone_length * 0.5
	)
	physical_bone.add_child(collision)
	_physical_bones.append(physical_bone)


func _get_bone_shape_data(
	bone_id: int,
	bone_name: StringName
) -> Dictionary:
	var child_direction := Vector3.ZERO

	for child_id in _skeleton.get_bone_children(bone_id):
		var child_name := _skeleton.get_bone_name(child_id)

		if child_name in RAGDOLL_BONES:
			child_direction = _skeleton.get_bone_rest(child_id).origin
			break

	var fallback_length := 0.2
	var radius := 0.075

	if bone_name == &"Hips":
		fallback_length = 0.22
		radius = 0.13
	elif bone_name == &"Chest":
		fallback_length = 0.38
		radius = 0.14
	elif bone_name == &"Head":
		fallback_length = 0.22
		radius = 0.115
	elif String(bone_name).contains("Hand"):
		fallback_length = 0.16
		radius = 0.055
	elif String(bone_name).contains("Foot"):
		fallback_length = 0.2
		radius = 0.065
	elif String(bone_name).contains("UpperLeg"):
		radius = 0.095
	elif String(bone_name).contains("LowerLeg"):
		radius = 0.075
	elif String(bone_name).contains("UpperArm"):
		radius = 0.075
	else:
		radius = 0.06

	var length := child_direction.length()

	if length < 0.05:
		length = fallback_length
		child_direction = Vector3.UP

	return {
		"length": length,
		"radius": radius,
		"direction": child_direction.normalized(),
	}


func _get_bone_mass(bone_name: StringName) -> float:
	if bone_name == &"Hips" or bone_name == &"Chest":
		return 4.0

	if bone_name == &"Head":
		return 2.0

	if String(bone_name).contains("Leg"):
		return 2.0

	return 1.0


func _start_ragdoll(impulse: Vector3) -> void:
	if _simulator.is_simulating_physics():
		return

	for physical_bone in _physical_bones:
		physical_bone.collision_layer = ragdoll_collision_layer
		physical_bone.collision_mask = ragdoll_collision_mask
		physical_bone.linear_velocity = Vector3.ZERO
		physical_bone.angular_velocity = Vector3.ZERO

	_simulator.active = true
	_simulator.influence = 1.0
	_simulator.physical_bones_start_simulation()

	var safe_impulse := _clamp_velocity(
		impulse * death_impulse_multiplier,
		maximum_death_impulse
	)

	if safe_impulse.length_squared() > 0.001:
		for physical_bone in _physical_bones:
			var impulse_weight := _get_impulse_weight(
				physical_bone.bone_name
			)

			if impulse_weight > 0.0:
				physical_bone.apply_central_impulse(
					safe_impulse * impulse_weight
				)


func _stop_ragdoll() -> void:
	if _simulator.is_simulating_physics():
		_simulator.physical_bones_stop_simulation()

	for physical_bone in _physical_bones:
		physical_bone.collision_layer = 0
		physical_bone.collision_mask = 0
		physical_bone.linear_velocity = Vector3.ZERO
		physical_bone.angular_velocity = Vector3.ZERO

	_skeleton.reset_bone_poses()


func _create_y_aligned_basis(direction: Vector3) -> Basis:
	var y_axis := direction.normalized()
	var reference := Vector3.RIGHT if absf(y_axis.dot(Vector3.UP)) > 0.98 else Vector3.UP
	var x_axis := reference.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()


func _get_impulse_weight(bone_name: StringName) -> float:
	if bone_name == &"Hips":
		return 0.5

	if bone_name == &"Chest":
		return 0.35

	if bone_name == &"Head":
		return 0.15

	return 0.0


func _clamp_velocity(value: Vector3, maximum_speed: float) -> Vector3:
	if not value.is_finite():
		return Vector3.ZERO

	var length_squared := value.length_squared()
	var maximum_squared := maximum_speed * maximum_speed

	if length_squared <= maximum_squared:
		return value

	return value.normalized() * maximum_speed
