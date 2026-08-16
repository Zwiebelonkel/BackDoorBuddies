extends Node

@export_range(1, 200, 1) var maximum_blood_decals := 40
@export_range(0.0, 600.0, 1.0) var blood_decal_lifetime := 90.0
@export_range(1, 100, 1) var particle_amount := 28

var _blood_texture: ImageTexture


func spawn_blood_impact(hit_position: Vector3, hit_normal: Vector3) -> void:
	var safe_normal := hit_normal.normalized()

	if safe_normal.length_squared() < 0.5:
		safe_normal = Vector3.UP

	_spawn_blood_decal(hit_position, safe_normal)
	_spawn_blood_particles(hit_position, safe_normal)


func _spawn_blood_decal(hit_position: Vector3, hit_normal: Vector3) -> void:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		return

	var existing_decals := get_tree().get_nodes_in_group("blood_decals")

	if existing_decals.size() >= maximum_blood_decals:
		var oldest := existing_decals.front() as Node

		if is_instance_valid(oldest):
			oldest.queue_free()

	var decal := Decal.new()
	decal.name = "BloodDecal"
	decal.add_to_group("blood_decals")
	decal.size = Vector3(0.32, 0.22, 0.32)
	decal.texture_albedo = _get_blood_texture()
	decal.modulate = Color(0.42, 0.015, 0.01, 0.9)
	decal.upper_fade = 0.08
	decal.lower_fade = 0.08
	current_scene.add_child(decal)
	decal.global_transform = Transform3D(
		_create_surface_basis(hit_normal),
		hit_position + hit_normal * 0.015
	)
	decal.rotate_y(randf_range(0.0, TAU))
	decal.scale = Vector3.ONE * randf_range(0.75, 1.25)

	if blood_decal_lifetime > 0.0:
		var timer := Timer.new()
		timer.one_shot = true
		timer.wait_time = blood_decal_lifetime
		timer.timeout.connect(decal.queue_free)
		decal.add_child(timer)
		timer.start()


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
	droplet_material.roughness = 0.55
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
