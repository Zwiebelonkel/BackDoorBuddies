class_name PistolHeld
extends Node3D

signal fired
signal bullet_hit(collider: Object, position: Vector3, normal: Vector3)

@export_group("Firing")
@export var fire_cooldown: float = 0.22
@export var automatic: bool = false
@export_range(1.0, 500.0, 1.0) var shot_distance: float = 100.0
@export_flags_3d_physics var hit_collision_mask: int = 0xFFFFFFFF
@export var attack_type: StringName = &"pistol"

@export_group("Weapon Sounds")

@export var pistol_shot_sound: AudioStream
@export var machine_pistol_shot_sound: AudioStream
@export var sniper_shot_sound: AudioStream
@export var shotgun_shot_sound: AudioStream

@export_range(-40.0, 10.0, 0.5)
var shot_sound_volume_db := 0.0

@export_range(1.0, 100.0, 1.0)
var shot_sound_max_distance := 40.0

@export_range(0.0, 0.2, 0.005)
var shot_pitch_variation := 0.025

@export_group("Muzzle Flash")
@export_range(0.01, 0.2, 0.005) var muzzle_flash_duration: float = 0.045
@export_range(0.0, 32.0, 0.1) var muzzle_flash_energy: float = 8.0
@export_range(0.1, 10.0, 0.1) var muzzle_flash_range: float = 3.0

@export_group("Shot Smoke")
@export var shot_smoke_enabled: bool = true
@export_range(1, 128, 1) var shot_smoke_amount: int = 46
@export_range(0.1, 10.0, 0.1) var shot_smoke_lifetime: float = 4.5
@export_range(0.0, 1.0, 0.01) var shot_smoke_opacity: float = 0.28
@export_range(0.01, 0.5, 0.005) var shot_smoke_puff_size: float = 0.13
@export_range(0.01, 2.0, 0.01) var shot_smoke_scale_max: float = 0.59
@export_range(4, 32, 1) var shot_smoke_texture_resolution: int = 8
@export_range(0.0, 90.0, 0.5) var shot_smoke_spread_degrees: float = 10.0
@export_range(0.0, 5.0, 0.01) var shot_smoke_velocity_min: float = 0.08
@export_range(0.0, 5.0, 0.01) var shot_smoke_velocity_max: float = 0.22
@export var shot_smoke_color := Color(0.72, 0.72, 0.68)

@export_group("Bullet Hole")
@export_range(0.005, 0.2, 0.001) var bullet_hole_radius: float = 0.028
@export_range(0.0, 600.0, 1.0) var bullet_hole_lifetime: float = 120.0
@export_range(1, 500, 1) var maximum_bullet_holes: int = 100

@export_group("Recoil Position")
@export var recoil_back_distance: float = 0.09
@export var recoil_up_distance: float = 0.025
@export var recoil_side_distance: float = 0.01

@export_group("Recoil Rotation")
@export var recoil_rotation_degrees := Vector3(
	-10.0,
	0.0,
	2.0
)

@export_group("Recoil Timing")
@export var recoil_duration: float = 0.045
@export var return_duration: float = 0.14

@export_group("Random Recoil")
@export var random_recoil_enabled: bool = true
@export var random_rotation_degrees: float = 1.5
@export var random_side_distance: float = 0.008

@export_group("Pistol Mechanical Animation")
@export var slide_back_distance: float = 0.22
@export var slide_back_direction := Vector3(0.0, 0.0, -1.0)
@export var slide_back_duration: float = 0.025
@export var slide_return_duration: float = 0.055

@export var trigger_rotation_degrees: float = -18.0
@export var trigger_pull_duration: float = 0.025
@export var trigger_return_duration: float = 0.07


var _slide: Node3D
var _trigger: Node3D

var _slide_rest_position: Vector3
var _trigger_rest_rotation: Vector3

var _mechanical_tween: Tween

var _can_fire := true
var _rest_position: Vector3
var _rest_rotation_degrees: Vector3
var _active_tween: Tween
var _muzzle_marker: Marker3D
var _shot_smoke_mesh: QuadMesh


func _ready() -> void:
	_rest_position = position
	_rest_rotation_degrees = rotation_degrees

	_muzzle_marker = find_child("Muzzle", true, false) as Marker3D
	_shot_smoke_mesh = _create_shot_smoke_mesh()

	var pistol_model := get_node_or_null("1911Model") as Node3D

	if pistol_model == null:
		return

	# Das sichtbare Modell nutzt kurze Bauteilnamen. Die alten Namen bleiben
	# als Fallback erhalten, damit beide Modellvarianten animiert werden.
	_slide = pistol_model.find_child("slider", true, false) as Node3D

	if _slide == null:
		_slide = pistol_model.find_child(
			"PistolBarrel_Pistol_Metal_0",
			true,
			false
		) as Node3D

	_trigger = pistol_model.find_child("trigger", true, false) as Node3D

	if _trigger == null:
		_trigger = pistol_model.find_child(
			"PistolTrigger_Pistol_Metal_0",
			true,
			false
		) as Node3D

	if _slide != null:
		_slide_rest_position = _slide.position
	else:
		push_error("Slide im sichtbaren 1911Model NICHT gefunden!")

	if _trigger != null:
		_trigger_rest_rotation = _trigger.rotation_degrees
	else:
		push_error("Trigger im sichtbaren 1911Model NICHT gefunden!")

func use_primary() -> void:
	if not _can_fire:
		return

	_can_fire = false

	# Gameplay-Systeme können zusätzlich auf Schuss und Treffer reagieren.
	fired.emit()
	_play_mechanical_animation()
	_play_owner_animation(&"ual/Pistol_Shoot")
	_fire_hitscan()

	await _play_recoil_animation().finished

	var remaining_cooldown := maxf(
		fire_cooldown - recoil_duration - return_duration,
		0.0
	)

	if remaining_cooldown > 0.0:
		await get_tree().create_timer(remaining_cooldown).timeout

	_can_fire = true


func _play_owner_animation(animation_name: StringName) -> void:
	var shooter := _find_shooter()

	if (
		shooter != null
		and shooter.is_multiplayer_authority()
		and shooter.has_method("play_player_action")
	):
		shooter.play_player_action(animation_name)


func _fire_hitscan() -> void:
	var shooter := _find_shooter()
	var aim_camera := _find_aim_camera(shooter)

	if aim_camera == null:
		push_warning("Waffenschuss ohne Camera3D abgebrochen.")
		return

	var ray_origin := aim_camera.global_position
	var ray_direction := -aim_camera.global_basis.z.normalized()
	var ray_end := ray_origin + ray_direction * shot_distance

	_spawn_muzzle_flash(ray_direction)
	_spawn_shot_smoke(ray_direction)
	_play_sound(attack_type)

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = hit_collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = true

	if shooter != null:
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

	var hit_position: Vector3 = hit["position"]
	var hit_normal: Vector3 = hit["normal"]
	var collider: Object = hit["collider"]
	var target_player := _find_player_from_collider(collider)

	if target_player != null:
		if (
			shooter != null
			and shooter.is_multiplayer_authority()
			and shooter.has_method("request_player_attack")
		):
			shooter.request_player_attack(
				target_player,
				attack_type,
				hit_position,
				hit_normal
			)
	else:
		_spawn_bullet_hole(collider, hit_position, hit_normal)

	bullet_hit.emit(collider, hit_position, hit_normal)


func _spawn_muzzle_flash(fallback_direction: Vector3) -> void:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		return

	var flash_root := Node3D.new()
	flash_root.name = "MuzzleFlash"
	current_scene.add_child(flash_root)

	if is_instance_valid(_muzzle_marker):
		flash_root.global_position = _muzzle_marker.global_position
	else:
		flash_root.global_position = global_position + fallback_direction * 0.4

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.16)
	light.light_energy = muzzle_flash_energy
	light.omni_range = muzzle_flash_range
	light.shadow_enabled = false
	flash_root.add_child(light)

	var flash_mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.1
	sphere.radial_segments = 8
	sphere.rings = 4
	flash_mesh.mesh = sphere

	var flash_material := StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color(1.0, 0.72, 0.25)
	flash_material.emission_enabled = true
	flash_material.emission = Color(1.0, 0.32, 0.04)
	flash_material.emission_energy_multiplier = 8.0
	flash_mesh.material_override = flash_material
	flash_mesh.scale = Vector3(
		randf_range(0.8, 1.25),
		randf_range(0.8, 1.2),
		randf_range(1.0, 1.65)
	)
	flash_root.add_child(flash_mesh)

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = muzzle_flash_duration
	timer.timeout.connect(flash_root.queue_free)
	flash_root.add_child(timer)
	timer.start()


func _spawn_shot_smoke(fallback_direction: Vector3) -> void:
	if not shot_smoke_enabled:
		return

	var smoke_parent: Node3D = _muzzle_marker if (
		is_instance_valid(_muzzle_marker)
	) else self

	var smoke := GPUParticles3D.new()
	smoke.name = "ShotSmoke"
	smoke.add_to_group("shot_smoke")
	smoke.emitting = false
	smoke.amount = shot_smoke_amount
	smoke.lifetime = shot_smoke_lifetime
	smoke.one_shot = true
	smoke.explosiveness = 0.65
	smoke.randomness = 0.65
	smoke.local_coords = false
	smoke.visibility_aabb = AABB(
		Vector3(-4.0, -4.0, -4.0),
		Vector3(8.0, 8.0, 8.0)
	)
	smoke.draw_pass_1 = _shot_smoke_mesh

	var smoke_process := ParticleProcessMaterial.new()
	smoke_process.direction = (
		smoke_parent.global_basis.inverse()
		* fallback_direction.normalized()
	).normalized()
	smoke_process.spread = shot_smoke_spread_degrees
	smoke_process.initial_velocity_min = shot_smoke_velocity_min
	smoke_process.initial_velocity_max = maxf(
		shot_smoke_velocity_min,
		shot_smoke_velocity_max
	)
	smoke_process.angular_velocity_min = -8.0
	smoke_process.angular_velocity_max = 8.0
	smoke_process.gravity = Vector3(0.0, 0.06, 0.0)
	smoke_process.scale_min = 0.01
	smoke_process.scale_max = shot_smoke_scale_max
	smoke_process.color = Color(
		shot_smoke_color.r,
		shot_smoke_color.g,
		shot_smoke_color.b,
		shot_smoke_opacity
	)
	var alpha_curve := Curve.new()
	alpha_curve.add_point(Vector2(0.0, 0.35))
	alpha_curve.add_point(Vector2(0.12, 1.0))
	alpha_curve.add_point(Vector2(0.68, 0.72))
	alpha_curve.add_point(Vector2(1.0, 0.0))
	var alpha_texture := CurveTexture.new()
	alpha_texture.curve = alpha_curve
	smoke_process.alpha_curve = alpha_texture
	smoke.process_material = smoke_process

	# Der Emitter folgt dem Barrel. Bereits ausgestossene Partikel bleiben dank
	# local_coords = false dort in der Welt, wo sie entstanden sind.
	smoke_parent.add_child(smoke)
	smoke.position = (
		Vector3.ZERO
		if is_instance_valid(_muzzle_marker)
		else to_local(global_position + fallback_direction * 0.4)
	)
	smoke.finished.connect(smoke.queue_free)
	smoke.restart()
	smoke.emitting = true

	# Fallback, falls ein Rendering-Backend das finished-Signal nicht ausloest.
	# Zwei volle Zyklen lassen auch den zuletzt emittierten Partikeln Zeit,
	# einzeln auszublenden.
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = shot_smoke_lifetime * 2.0 + 0.25
	timer.timeout.connect(smoke.queue_free)
	smoke.add_child(timer)
	timer.start()


func _create_shot_smoke_mesh() -> QuadMesh:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.55),
		Color(1.0, 1.0, 1.0, 0.0),
	])

	var smoke_texture := GradientTexture2D.new()
	smoke_texture.width = shot_smoke_texture_resolution
	smoke_texture.height = shot_smoke_texture_resolution
	smoke_texture.gradient = gradient
	smoke_texture.fill = GradientTexture2D.FILL_RADIAL
	smoke_texture.fill_from = Vector2(0.5, 0.5)
	smoke_texture.fill_to = Vector2(1.0, 0.5)

	var smoke_material := StandardMaterial3D.new()
	smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_material.vertex_color_use_as_albedo = true
	smoke_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smoke_material.billboard_keep_scale = true
	smoke_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	smoke_material.albedo_texture = smoke_texture

	var smoke_mesh := QuadMesh.new()
	smoke_mesh.size = Vector2.ONE * shot_smoke_puff_size
	smoke_mesh.material = smoke_material
	return smoke_mesh


func _spawn_bullet_hole(
	collider: Object,
	hit_position: Vector3,
	hit_normal: Vector3
) -> void:
	_remove_oldest_bullet_hole_if_needed()

	var bullet_hole := Node3D.new()
	bullet_hole.name = "BulletHole"
	bullet_hole.add_to_group("bullet_holes")

	var parent_node := collider as Node

	if parent_node == null or not parent_node.is_inside_tree():
		parent_node = get_tree().current_scene

	if parent_node == null:
		bullet_hole.queue_free()
		return

	parent_node.add_child(bullet_hole)
	bullet_hole.global_transform = Transform3D(
		_create_surface_basis(hit_normal),
		hit_position + hit_normal * 0.002
	)
	bullet_hole.rotate_y(randf_range(0.0, TAU))
	bullet_hole.scale = Vector3.ONE * randf_range(0.85, 1.15)

	var dark_center := MeshInstance3D.new()
	var center_mesh := CylinderMesh.new()
	center_mesh.top_radius = bullet_hole_radius * 0.72
	center_mesh.bottom_radius = bullet_hole_radius * 0.72
	center_mesh.height = 0.0015
	center_mesh.radial_segments = 12
	dark_center.mesh = center_mesh
	dark_center.material_override = _create_impact_material(
		Color(0.008, 0.006, 0.004, 1.0)
	)
	bullet_hole.add_child(dark_center)

	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = bullet_hole_radius * 0.68
	rim_mesh.outer_radius = bullet_hole_radius
	rim_mesh.rings = 12
	rim_mesh.ring_segments = 6
	rim.mesh = rim_mesh
	rim.position.y = 0.001
	rim.material_override = _create_impact_material(
		Color(0.055, 0.035, 0.02, 1.0)
	)
	bullet_hole.add_child(rim)

	if bullet_hole_lifetime > 0.0:
		var lifetime_timer := Timer.new()
		lifetime_timer.one_shot = true
		lifetime_timer.wait_time = bullet_hole_lifetime
		lifetime_timer.timeout.connect(bullet_hole.queue_free)
		bullet_hole.add_child(lifetime_timer)
		lifetime_timer.start()


func _create_impact_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _create_surface_basis(normal: Vector3) -> Basis:
	var surface_normal := normal.normalized()
	var reference := (
		Vector3.RIGHT
		if absf(surface_normal.dot(Vector3.UP)) > 0.98
		else Vector3.UP
	)
	var tangent := reference.cross(surface_normal).normalized()
	var bitangent := tangent.cross(surface_normal).normalized()
	return Basis(tangent, surface_normal, bitangent).orthonormalized()


func _remove_oldest_bullet_hole_if_needed() -> void:
	var bullet_holes := get_tree().get_nodes_in_group("bullet_holes")

	if bullet_holes.size() < maximum_bullet_holes:
		return

	var oldest_hole := bullet_holes.front() as Node

	if is_instance_valid(oldest_hole):
		oldest_hole.queue_free()


func _find_shooter() -> CollisionObject3D:
	var current_node: Node = self

	while current_node != null:
		if current_node is CharacterBody3D:
			return current_node as CollisionObject3D

		current_node = current_node.get_parent()

	return null


func _find_aim_camera(shooter: CollisionObject3D) -> Camera3D:
	if shooter == null:
		return null

	return shooter.get_node_or_null("Head/Camera3D") as Camera3D


func _find_player_from_collider(collider: Object) -> Node:
	var current_node := collider as Node

	while current_node != null:
		if current_node is FPSController:
			return current_node

		current_node = current_node.get_parent()

	return null


func _play_recoil_animation() -> Tween:
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()

	var random_side := 0.0
	var random_pitch := 0.0
	var random_yaw := 0.0
	var random_roll := 0.0

	if random_recoil_enabled:
		random_side = randf_range(
			-random_side_distance,
			random_side_distance
		)

		random_pitch = randf_range(
			-random_rotation_degrees,
			random_rotation_degrees
		)

		random_yaw = randf_range(
			-random_rotation_degrees,
			random_rotation_degrees
		)

		random_roll = randf_range(
			-random_rotation_degrees,
			random_rotation_degrees
		)

	# Positive Z-Richtung bedeutet bei einem Kamerakind:
	# zurück zur Kamera.
	var recoil_position := (
		_rest_position
		+ Vector3(
			recoil_side_distance + random_side,
			recoil_up_distance,
			recoil_back_distance
		)
	)

	var recoil_rotation := (
		_rest_rotation_degrees
		+ recoil_rotation_degrees
		+ Vector3(
			random_pitch,
			random_yaw,
			random_roll
		)
	)

	_active_tween = create_tween()
	_active_tween.set_trans(Tween.TRANS_QUAD)
	_active_tween.set_ease(Tween.EASE_OUT)

	# Schneller Rückstoß.
	_active_tween.tween_property(
		self,
		"position",
		recoil_position,
		recoil_duration
	)

	_active_tween.parallel().tween_property(
		self,
		"rotation_degrees",
		recoil_rotation,
		recoil_duration
	)

	# Etwas langsamer in die Ruheposition zurück.
	_active_tween.set_trans(Tween.TRANS_SINE)
	_active_tween.set_ease(Tween.EASE_IN_OUT)

	_active_tween.tween_property(
		self,
		"position",
		_rest_position,
		return_duration
	)

	_active_tween.parallel().tween_property(
		self,
		"rotation_degrees",
		_rest_rotation_degrees,
		return_duration
	)

	return _active_tween
	
func _play_mechanical_animation() -> void:
	if _mechanical_tween != null and _mechanical_tween.is_valid():
		_mechanical_tween.kill()

	if _slide == null and _trigger == null:
		return

	# Falls durch schnelles automatisches Feuern die vorherige Animation
	# unterbrochen wurde, erst sauber auf Ausgangsposition setzen.
	if _slide != null:
		_slide.position = _slide_rest_position

	if _trigger != null:
		_trigger.rotation_degrees = _trigger_rest_rotation

	_mechanical_tween = create_tween()
	_mechanical_tween.set_trans(Tween.TRANS_QUAD)
	_mechanical_tween.set_ease(Tween.EASE_OUT)

	# ------------------------------------------------
	# SLIDE
	# ------------------------------------------------

	if _slide != null:
		# Bei deinem Modell müssen wir eventuell X/Y/Z anpassen.
		# Z ist hier zunächst die Bewegungsachse des Schlittens.
		var slide_back_position := (
			_slide_rest_position
			+ slide_back_direction.normalized() * slide_back_distance
		)

		_mechanical_tween.tween_property(
			_slide,
			"position",
			slide_back_position,
			slide_back_duration
		)

		_mechanical_tween.tween_property(
			_slide,
			"position",
			_slide_rest_position,
			slide_return_duration
		)

	# ------------------------------------------------
	# TRIGGER
	# ------------------------------------------------

	if _trigger != null:
		var pulled_rotation := (
			_trigger_rest_rotation
			+ Vector3(
				trigger_rotation_degrees,
				0.0,
				0.0
			)
		)

		# Trigger parallel zum Slide bewegen.
		var trigger_tween := create_tween()

		trigger_tween.set_trans(Tween.TRANS_QUAD)
		trigger_tween.set_ease(Tween.EASE_OUT)

		trigger_tween.tween_property(
			_trigger,
			"rotation_degrees",
			pulled_rotation,
			trigger_pull_duration
		)

		trigger_tween.set_trans(Tween.TRANS_SINE)
		trigger_tween.set_ease(Tween.EASE_IN_OUT)

		trigger_tween.tween_property(
			_trigger,
			"rotation_degrees",
			_trigger_rest_rotation,
			trigger_return_duration
		)
		
func _play_sound(type: StringName) -> void:
	var sound: AudioStream = null

	match type:
		&"pistol":
			sound = pistol_shot_sound

		&"mp":
			sound = machine_pistol_shot_sound

		&"sniper":
			sound = sniper_shot_sound

		&"shotgun":
			sound = shotgun_shot_sound

		_:
			push_warning(
				"Kein Waffen-Sound für attack_type '%s' definiert."
				% String(type)
			)
			return

	if sound == null:
		push_warning(
			"AudioStream für attack_type '%s' ist leer."
			% String(type)
		)
		return

	var sound_player := AudioStreamPlayer3D.new()

	sound_player.name = "WeaponShotSound"
	sound_player.stream = sound
	sound_player.volume_db = shot_sound_volume_db
	sound_player.max_distance = shot_sound_max_distance

	sound_player.pitch_scale = randf_range(
		1.0 - shot_pitch_variation,
		1.0 + shot_pitch_variation
	)

	var current_scene := get_tree().current_scene

	if current_scene == null:
		return

	current_scene.add_child(sound_player)

	if is_instance_valid(_muzzle_marker):
		sound_player.global_position = _muzzle_marker.global_position
	else:
		sound_player.global_position = global_position

	sound_player.finished.connect(
		sound_player.queue_free
	)

	sound_player.play()
