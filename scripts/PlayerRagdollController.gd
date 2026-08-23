extends Node

signal camera_attachment_ready

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

@export_group("Impact Response")
@export_range(0.0, 1.0, 0.05) var inherited_velocity_factor := 0.65
@export_range(0.0, 15.0, 0.1) var maximum_inherited_speed := 4.5
@export_range(0.0, 1.0, 0.05) var impact_bone_impulse_share := 0.52
@export_range(0.0, 1.0, 0.05) var chest_impulse_share := 0.30
@export_range(0.0, 1.0, 0.05) var hips_impulse_share := 0.18
@export_range(0.0, 2.0, 0.05) var tumble_torque_scale := 0.35
@export_range(0.0, 10.0, 0.1) var maximum_torque_impulse := 2.5

var _player: CharacterBody3D
var _skeleton: Skeleton3D
var _simulator: PhysicalBoneSimulator3D
var _physical_bones: Array[PhysicalBone3D] = []
var _requested_active := false
var _requested_impulse := Vector3.ZERO
var _requested_impact_position := Vector3.ZERO
var _requested_inherited_velocity := Vector3.ZERO
var _last_impact_bone_name: StringName = &""
var _last_applied_impulse := Vector3.ZERO
var _is_ready := false
var _camera_attachment_ready := false


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


func set_ragdoll_active(
	active: bool,
	impulse := Vector3.ZERO,
	impact_position := Vector3.ZERO,
	inherited_velocity := Vector3.ZERO
) -> void:
	_requested_active = active
	_requested_impulse = impulse
	_requested_impact_position = impact_position
	_requested_inherited_velocity = inherited_velocity

	if not _is_ready:
		return

	if active:
		_start_ragdoll(
			impulse,
			impact_position,
			inherited_velocity
		)
	else:
		_stop_ragdoll()


func is_ragdoll_active() -> bool:
	return _simulator != null and _simulator.is_simulating_physics()


func get_ragdoll_center_position() -> Vector3:
	for physical_bone in _physical_bones:
		if physical_bone.bone_name == &"Hips":
			return physical_bone.global_position

	return _player.global_position if _player != null else Vector3.ZERO


func get_ragdoll_head_bone() -> PhysicalBone3D:
	if not _camera_attachment_ready:
		return null

	return _find_physical_bone(&"Head")


func get_last_impact_bone_name() -> StringName:
	return _last_impact_bone_name


func get_last_applied_impulse() -> Vector3:
	return _last_applied_impulse


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
		_start_ragdoll(
			_requested_impulse,
			_requested_impact_position,
			_requested_inherited_velocity
		)


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
	physical_bone.friction = (
		1.0 if String(bone_name).contains("Foot") else 0.85
	)
	physical_bone.bounce = 0.0
	physical_bone.linear_damp = 1.1
	physical_bone.angular_damp = 2.2
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


func _start_ragdoll(
	impulse: Vector3,
	impact_position: Vector3,
	inherited_velocity: Vector3
) -> void:
	if _simulator == null:
		return

	if _simulator.is_simulating_physics():
		return

	_camera_attachment_ready = false

	for physical_bone in _physical_bones:
		physical_bone.collision_layer = ragdoll_collision_layer
		physical_bone.collision_mask = ragdoll_collision_mask
		physical_bone.linear_velocity = Vector3.ZERO
		physical_bone.angular_velocity = Vector3.ZERO

	_simulator.active = true
	_simulator.influence = 1.0
	_simulator.physical_bones_start_simulation()

	await get_tree().physics_frame

	if not _requested_active or not is_ragdoll_active():
		return

	_camera_attachment_ready = true
	camera_attachment_ready.emit()

	var inherited_motion := _clamp_velocity(
		inherited_velocity,
		maximum_inherited_speed
	) * inherited_velocity_factor

	for physical_bone in _physical_bones:
		physical_bone.linear_velocity = inherited_motion

	var final_impulse := impulse * death_impulse_multiplier

	if not final_impulse.is_finite():
		final_impulse = Vector3.ZERO

	if final_impulse.length() > maximum_death_impulse:
		final_impulse = (
			final_impulse.normalized()
			* maximum_death_impulse
		)

	_last_applied_impulse = final_impulse
	_last_impact_bone_name = &""

	if final_impulse.length_squared() < 0.001:
		return

	var impact_bone := _find_closest_physical_bone(impact_position)
	var chest := _find_physical_bone(&"Chest")
	var hips := _find_physical_bone(&"Hips")
	var impulse_weights: Dictionary = {}
	_add_impulse_weight(
		impulse_weights,
		impact_bone,
		impact_bone_impulse_share
	)
	_add_impulse_weight(impulse_weights, chest, chest_impulse_share)
	_add_impulse_weight(impulse_weights, hips, hips_impulse_share)
	var total_weight := 0.0

	for weight_value in impulse_weights.values():
		total_weight += float(weight_value)

	if total_weight > 0.001:
		for bone_value in impulse_weights.keys():
			var weighted_bone := bone_value as PhysicalBone3D

			if weighted_bone == null:
				continue

			weighted_bone.apply_central_impulse(
				final_impulse
				* float(impulse_weights[weighted_bone])
				/ total_weight
			)

	if impact_bone != null:
		_last_impact_bone_name = impact_bone.bone_name
		var ragdoll_center := (
			hips.global_position
			if hips != null
			else impact_bone.global_position
		)
		var lever := impact_position - ragdoll_center
		var torque_impulse := _clamp_velocity(
			lever.cross(final_impulse) * tumble_torque_scale,
			maximum_torque_impulse
		)

		if torque_impulse.length_squared() > 0.001:
			impact_bone.angular_velocity = _clamp_velocity(
				impact_bone.angular_velocity
				+ torque_impulse / maxf(impact_bone.mass, 0.1),
				maximum_angular_speed
			)


func _find_physical_bone(
	bone_name: StringName
) -> PhysicalBone3D:
	for physical_bone in _physical_bones:
		if physical_bone.bone_name == bone_name:
			return physical_bone

	return null


func _find_closest_physical_bone(
	position: Vector3
) -> PhysicalBone3D:
	var closest_bone: PhysicalBone3D = null
	var closest_distance_squared := INF

	for physical_bone in _physical_bones:
		var distance_squared := physical_bone.global_position.distance_squared_to(
			position
		)

		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_bone = physical_bone

	return closest_bone


func _add_impulse_weight(
	weights: Dictionary,
	physical_bone: PhysicalBone3D,
	weight: float
) -> void:
	if physical_bone == null or weight <= 0.0:
		return

	weights[physical_bone] = (
		float(weights.get(physical_bone, 0.0)) + weight
	)


func _stop_ragdoll() -> void:
	if _simulator == null:
		return

	_camera_attachment_ready = false

	if _simulator.is_simulating_physics():
		_simulator.physical_bones_stop_simulation()

	for physical_bone in _physical_bones:
		physical_bone.collision_layer = 0
		physical_bone.collision_mask = 0
		physical_bone.linear_velocity = Vector3.ZERO
		physical_bone.angular_velocity = Vector3.ZERO

	_skeleton.reset_bone_poses()
	_last_impact_bone_name = &""
	_last_applied_impulse = Vector3.ZERO


func _create_y_aligned_basis(direction: Vector3) -> Basis:
	var y_axis := direction.normalized()
	var reference := Vector3.RIGHT if absf(y_axis.dot(Vector3.UP)) > 0.98 else Vector3.UP
	var x_axis := reference.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()


func _clamp_velocity(value: Vector3, maximum_speed: float) -> Vector3:
	if not value.is_finite():
		return Vector3.ZERO

	var length_squared := value.length_squared()
	var maximum_squared := maximum_speed * maximum_speed

	if length_squared <= maximum_squared:
		return value

	return value.normalized() * maximum_speed
