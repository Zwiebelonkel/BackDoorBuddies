class_name PlayerRightHandIK
extends Node

@export_node_path("CharacterBody3D") var player_path := NodePath("..")
@export_node_path("Skeleton3D") var skeleton_path := NodePath(
	"../playerModell/Armature/Skeleton3D"
)
@export var root_bone := &"RightUpperArm"
@export var tip_bone := &"RightHand"
@export_range(0.5, 1.0, 0.01) var reach_margin := 0.98
@export var pull_item_into_reach := true

var _player: FPSController
var _skeleton: Skeleton3D
var _solver: SkeletonIK3D
var _target: Marker3D
var _tip_bone_index := -1
var _active_grip_id := 0
var _tip_basis_offset := Basis.IDENTITY


func _ready() -> void:
	process_priority = 100
	call_deferred("_setup")


func _process(_delta: float) -> void:
	if _solver == null or _player == null or _skeleton == null:
		return

	if _player.is_dead or _is_ragdoll_active():
		_deactivate()
		return

	var grip := _player.get_active_right_hand_grip()
	var rig := _player.get_active_held_item_rig()

	if grip == null or rig == null:
		_deactivate()
		return

	if pull_item_into_reach:
		_pull_grip_into_reach(rig, grip)
	else:
		rig.position = Vector3.ZERO

	if _active_grip_id != grip.get_instance_id():
		_activate_grip(grip)

	_update_target(grip)

	_solver.start(true)


func _setup() -> void:
	_player = get_node_or_null(player_path) as FPSController
	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D

	if _player == null or _skeleton == null:
		push_warning("Right-Hand-IK: Spieler oder Skeleton3D fehlt.")
		return

	var root_bone_index := _skeleton.find_bone(root_bone)
	_tip_bone_index = _skeleton.find_bone(tip_bone)

	if root_bone_index < 0 or _tip_bone_index < 0:
		push_warning(
			"Right-Hand-IK: Armkette '%s' -> '%s' fehlt."
			% [root_bone, tip_bone]
		)
		return

	_target = Marker3D.new()
	_target.name = "RightHandIKTarget"
	_target.top_level = true
	_player.add_child(_target)

	_solver = SkeletonIK3D.new()
	_solver.name = "RightHandIKSolver"
	_solver.root_bone = root_bone
	_solver.tip_bone = tip_bone
	_solver.override_tip_basis = true
	_solver.interpolation = 1.0
	_solver.max_iterations = 12
	_skeleton.add_child(_solver)


func _pull_grip_into_reach(rig: Node3D, grip: Node3D) -> void:
	# Erst die unkorrigierte Item-Position herstellen. Item-Skripte animieren
	# weiterhin ihren eigenen lokalen Transform unterhalb dieses Rig-Nodes.
	rig.position = Vector3.ZERO
	rig.force_update_transform()
	grip.force_update_transform()

	var shoulder_index := _skeleton.find_bone(root_bone)
	var shoulder_transform := (
		_skeleton.global_transform
		* _skeleton.get_bone_global_pose(shoulder_index)
	)
	var shoulder_position := shoulder_transform.origin
	var grip_position := grip.global_position
	var shoulder_to_grip := grip_position - shoulder_position
	var maximum_reach := _get_maximum_arm_reach()

	if shoulder_to_grip.length() <= maximum_reach:
		return

	var reachable_position := (
		shoulder_position
		+ shoulder_to_grip.normalized() * maximum_reach
	)
	var global_correction := reachable_position - grip_position
	var rig_parent := rig.get_parent_node_3d()

	if rig_parent == null:
		return

	rig.position = rig_parent.global_basis.inverse() * global_correction
	rig.force_update_transform()
	grip.force_update_transform()


func _get_maximum_arm_reach() -> float:
	var lower_arm_index := _skeleton.find_bone(&"RightLowerArm")

	if lower_arm_index < 0 or _tip_bone_index < 0:
		return 0.5

	var local_reach := (
		_skeleton.get_bone_rest(lower_arm_index).origin.length()
		+ _skeleton.get_bone_rest(_tip_bone_index).origin.length()
	)
	var skeleton_scale := _skeleton.global_basis.get_scale().abs()
	var largest_scale := maxf(
		skeleton_scale.x,
		maxf(skeleton_scale.y, skeleton_scale.z)
	)
	return local_reach * largest_scale * reach_margin


func _activate_grip(grip: Node3D) -> void:
	if _solver.is_running():
		_solver.stop()

	_active_grip_id = grip.get_instance_id()
	var hand_transform := (
		_skeleton.global_transform
		* _skeleton.get_bone_global_pose(_tip_bone_index)
	)
	var grip_basis := grip.global_basis.orthonormalized()
	_tip_basis_offset = (
		grip_basis.inverse()
		* hand_transform.basis.orthonormalized()
	)


func _update_target(grip: Node3D) -> void:
	var grip_basis := grip.global_basis.orthonormalized()
	_target.global_transform = Transform3D(
		(grip_basis * _tip_basis_offset).orthonormalized(),
		grip.global_position
	)
	_solver.target = _target.global_transform


func _deactivate() -> void:
	if _solver != null and _solver.is_running():
		_solver.stop()

	_active_grip_id = 0

	if _player == null:
		return

	var rig := _player.get_active_held_item_rig()

	if rig != null:
		rig.position = Vector3.ZERO


func _is_ragdoll_active() -> bool:
	return (
		_player.ragdoll_controller != null
		and _player.ragdoll_controller.has_method("is_ragdoll_active")
		and _player.ragdoll_controller.is_ragdoll_active()
	)


func is_ik_active() -> bool:
	return _solver != null and _active_grip_id != 0


func get_grip_error() -> float:
	if not is_ik_active():
		return INF

	var grip := _player.get_active_right_hand_grip()

	if grip == null:
		return INF

	var hand_transform := (
		_skeleton.global_transform
		* _skeleton.get_bone_global_pose(_tip_bone_index)
	)
	return hand_transform.origin.distance_to(grip.global_position)
