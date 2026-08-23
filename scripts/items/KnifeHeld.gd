class_name KnifeHeld
extends Node3D

@export_group("Attack")
@export var attack_cooldown: float = 0.45
@export var stab_distance: float = 0.35
@export_range(0.5, 5.0, 0.1) var hit_distance: float = 2.0
@export_flags_3d_physics var hit_collision_mask: int = 0xFFFFFFFF
@export var stab_duration: float = 0.08
@export var return_duration: float = 0.16
@export var attack_rotation_degrees := Vector3(-25.0, 0.0, -10.0)

var _can_attack := true
var _rest_position: Vector3
var _rest_rotation_degrees: Vector3


func _ready() -> void:
	_rest_position = position
	_rest_rotation_degrees = rotation_degrees


func use_primary() -> void:
	if not _can_attack:
		return

	_can_attack = false
	_perform_stab_hit()

	await _play_stab_animation()
	await get_tree().create_timer(
		maxf(attack_cooldown - stab_duration - return_duration, 0.0)
	).timeout

	_can_attack = true

func _perform_stab_hit() -> void:
	var shooter := _find_shooter()

	if shooter == null or not shooter.is_multiplayer_authority():
		return

	var aim_camera := shooter.get_node_or_null("Head/Camera3D") as Camera3D

	if aim_camera == null:
		return

	var ray_origin := aim_camera.global_position
	var ray_end := ray_origin - aim_camera.global_basis.z.normalized() * hit_distance
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = hit_collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var exclusions: Array[RID] = [shooter.get_rid()]
	var shooter_hitbox := shooter.get_node_or_null(
		"PlayerHitbox"
	) as CollisionObject3D

	if shooter_hitbox != null:
		exclusions.append(shooter_hitbox.get_rid())

	query.exclude = exclusions

	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		return

	var target_player := _find_player_from_collider(hit["collider"])

	if target_player == null or not shooter.has_method("request_player_attack"):
		return

	shooter.request_player_attack(
		target_player,
		&"knife",
		hit["position"],
		hit["normal"]
	)


func _find_shooter() -> CharacterBody3D:
	var current_node: Node = self

	while current_node != null:
		if current_node is CharacterBody3D:
			return current_node as CharacterBody3D

		current_node = current_node.get_parent()

	return null


func _find_player_from_collider(collider: Object) -> Node:
	var current_node := collider as Node

	while current_node != null:
		if current_node is FPSController:
			return current_node

		current_node = current_node.get_parent()

	return null


func _play_stab_animation() -> void:
	var attack_position := _rest_position + Vector3(0.0, 0.0, -stab_distance)
	var attack_rotation := _rest_rotation_degrees + attack_rotation_degrees

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)

	tween.tween_property(
		self,
		"position",
		attack_position,
		stab_duration
	)

	tween.parallel().tween_property(
		self,
		"rotation_degrees",
		attack_rotation,
		stab_duration
	)

	tween.set_ease(Tween.EASE_IN_OUT)

	tween.tween_property(
		self,
		"position",
		_rest_position,
		return_duration
	)

	tween.parallel().tween_property(
		self,
		"rotation_degrees",
		_rest_rotation_degrees,
		return_duration
	)

	await tween.finished
