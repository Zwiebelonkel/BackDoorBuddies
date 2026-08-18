extends Node

@export_range(1, 200, 1) var maximum_blood_decals := 40
@export_range(0.0, 600.0, 1.0) var blood_decal_lifetime := 90.0
@export_range(1, 100, 1) var particle_amount := 28

@export_group("Wall Blood Splatter")
@export_range(0.5, 20.0, 0.5) var wall_splatter_distance := 8.0
@export_range(0.2, 3.0, 0.05) var gun_hit_splatter_size := 0.95
@export_range(0.2, 3.0, 0.05) var sniper_hit_splatter_size := 1.45

const BLOOD_ATTACHMENT_BONES: Array[StringName] = [
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

var _blood_texture: ImageTexture


func spawn_blood_impact(
	hit_position: Vector3,
	hit_normal: Vector3,
	projectile_direction := Vector3.ZERO,
	weapon_hit_type: StringName = &""
) -> void:
	var safe_normal := hit_normal.normalized()

	if safe_normal.length_squared() < 0.5:
		safe_normal = Vector3.UP

	_spawn_player_blood_decal(hit_position, safe_normal)
	_spawn_blood_particles(hit_position, safe_normal)

	if weapon_hit_type == &"pistol" or weapon_hit_type == &"sniper":
		_spawn_wall_blood_decal(
			hit_position,
			projectile_direction,
			weapon_hit_type
		)


func _spawn_player_blood_decal(
	hit_position: Vector3,
	hit_normal: Vector3
) -> void:
	var decal_parent := _find_player_decal_parent(hit_position)

	if decal_parent == null:
		return

	var decal := _create_blood_decal(
		decal_parent,
		"PlayerBloodDecal",
		"player_blood_decals",
		Vector3(0.32, 0.22, 0.32)
	)

	if decal == null:
		return

	decal.global_transform = Transform3D(
		_create_surface_basis(hit_normal),
		hit_position + hit_normal * 0.015
	)
	_randomize_decal(decal)


func _spawn_wall_blood_decal(
	hit_position: Vector3,
	projectile_direction: Vector3,
	weapon_hit_type: StringName
) -> void:
	var direction := projectile_direction.normalized()

	if direction.length_squared() < 0.5:
		return

	var query := PhysicsRayQueryParameters3D.create(
		hit_position + direction * 0.08,
		hit_position + direction * wall_splatter_distance
	)
	query.collision_mask = 1
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var player := get_parent() as CollisionObject3D

	if player != null:
		var exclusions: Array[RID] = [player.get_rid()]
		var hitbox := player.get_node_or_null("PlayerHitbox") as CollisionObject3D

		if hitbox != null:
			exclusions.append(hitbox.get_rid())

		query.exclude = exclusions

	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(
		query
	)

	if hit.is_empty():
		return

	var current_scene := get_tree().current_scene as Node3D

	if current_scene == null:
		return

	var splatter_size := (
		sniper_hit_splatter_size
		if weapon_hit_type == &"sniper"
		else gun_hit_splatter_size
	)
	var decal := _create_blood_decal(
		current_scene,
		"WallBloodDecal",
		"wall_blood_decals",
		Vector3(
			splatter_size,
			maxf(0.28, splatter_size * 0.35),
			splatter_size
		)
	)

	if decal == null:
		return

	var wall_normal: Vector3 = hit["normal"]
	decal.global_transform = Transform3D(
		_create_surface_basis(wall_normal),
		(hit["position"] as Vector3) + wall_normal * 0.012
	)
	_randomize_decal(decal)


func _find_player_decal_parent(hit_position: Vector3) -> Node3D:
	var player := get_parent() as Node3D

	if player == null:
		return null

	var skeleton := player.get_node_or_null(
		"playerModell/Armature/Skeleton3D"
	) as Skeleton3D

	if skeleton == null:
		return player

	var closest_bone := -1
	var closest_distance_squared := INF

	for bone_name in BLOOD_ATTACHMENT_BONES:
		var bone_id := skeleton.find_bone(bone_name)

		if bone_id < 0:
			continue

		var bone_position := (
			skeleton.global_transform
			* skeleton.get_bone_global_pose(bone_id)
		).origin
		var distance_squared := bone_position.distance_squared_to(hit_position)

		if distance_squared < closest_distance_squared:
			closest_distance_squared = distance_squared
			closest_bone = bone_id

	if closest_bone < 0:
		return player

	var attachment_name := "BloodAttachment_%s" % closest_bone
	var attachment := skeleton.get_node_or_null(
		attachment_name
	) as BoneAttachment3D

	if attachment == null:
		attachment = BoneAttachment3D.new()
		attachment.name = attachment_name
		attachment.bone_name = skeleton.get_bone_name(closest_bone)
		skeleton.add_child(attachment)

	return attachment


func _create_blood_decal(
	decal_parent: Node3D,
	decal_name: String,
	specific_group: StringName,
	decal_size: Vector3
) -> Decal:
	_prune_oldest_blood_decal()

	var decal := Decal.new()
	decal.name = decal_name
	decal.add_to_group("blood_decals")
	decal.add_to_group(specific_group)
	decal.size = decal_size
	decal.texture_albedo = _get_blood_texture()
	decal.modulate = Color(0.42, 0.015, 0.01, 0.9)
	decal.upper_fade = 0.08
	decal.lower_fade = 0.08
	decal_parent.add_child(decal)

	if blood_decal_lifetime > 0.0:
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = blood_decal_lifetime
		timer.timeout.connect(decal.queue_free)
		decal.add_child(timer)
		timer.start()

	return decal


func _prune_oldest_blood_decal() -> void:
	var existing_decals := get_tree().get_nodes_in_group("blood_decals")

	if existing_decals.size() < maximum_blood_decals:
		return

	var oldest := existing_decals.front() as Node

	if is_instance_valid(oldest):
		oldest.queue_free()


func _randomize_decal(decal: Decal) -> void:
	decal.rotate_y(randf_range(0.0, TAU))
	decal.scale = Vector3.ONE * randf_range(0.75, 1.25)


func _spawn_blood_particles(hit_position: Vector3, hit_normal: Vector3) -> void:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		return

	var particles := GPUParticles3D.new()
	particles.name = "BloodParticles"
	particles.amount = particle_amount
	particles.lifetime = 0.65
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.randomness = 0.45
	particles.visibility_aabb = AABB(Vector3(-3.0, -3.0, -3.0), Vector3.ONE * 6.0)
	current_scene.add_child(particles)
	particles.global_position = hit_position + hit_normal * 0.04

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = hit_normal.normalized()
	process_material.spread = 42.0
	process_material.initial_velocity_min = 1.6
	process_material.initial_velocity_max = 4.2
	process_material.gravity = Vector3(0.0, -8.5, 0.0)
	process_material.scale_min = 0.5
	process_material.scale_max = 1.35
	process_material.color = Color(0.5, 0.015, 0.008, 1.0)
	particles.process_material = process_material

	var droplet_mesh := SphereMesh.new()
	droplet_mesh.radius = 0.018
	droplet_mesh.height = 0.036
	droplet_mesh.radial_segments = 6
	droplet_mesh.rings = 3

	var droplet_material := StandardMaterial3D.new()
	droplet_material.albedo_color = Color(0.42, 0.008, 0.004, 1.0)
	droplet_material.roughness = 1
	droplet_mesh.material = droplet_material
	particles.draw_pass_1 = droplet_mesh
	particles.emitting = true

	var cleanup_timer := Timer.new()
	cleanup_timer.one_shot = true
	cleanup_timer.wait_time = particles.lifetime + 0.5
	cleanup_timer.timeout.connect(particles.queue_free)
	particles.add_child(cleanup_timer)
	cleanup_timer.start()


func _get_blood_texture() -> ImageTexture:
	if _blood_texture != null:
		return _blood_texture

	const TEXTURE_SIZE := 64
	var image := Image.create(
		TEXTURE_SIZE,
		TEXTURE_SIZE,
		false,
		Image.FORMAT_RGBA8
	)
	var center := Vector2.ONE * (float(TEXTURE_SIZE - 1) * 0.5)

	for y in range(TEXTURE_SIZE):
		for x in range(TEXTURE_SIZE):
			var offset := (Vector2(x, y) - center) / (TEXTURE_SIZE * 0.5)
			var angle := atan2(offset.y, offset.x)
			var edge := 0.57 + sin(angle * 7.0) * 0.1 + sin(angle * 13.0 + 1.7) * 0.06
			var alpha := clampf((edge - offset.length()) / 0.1, 0.0, 1.0)
			image.set_pixel(x, y, Color(0.48, 0.01, 0.006, alpha))

	_blood_texture = ImageTexture.create_from_image(image)
	return _blood_texture


func _create_surface_basis(normal: Vector3) -> Basis:
	var y_axis := normal.normalized()
	var reference := Vector3.RIGHT if absf(y_axis.dot(Vector3.UP)) > 0.98 else Vector3.UP
	var x_axis := reference.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Basis(x_axis, y_axis, z_axis).orthonormalized()
