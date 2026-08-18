extends Node3D

@onready var camera: Camera3D = $Shooter/Head/Camera3D
@onready var sniper: SniperHeld = $Shooter/Head/Camera3D/SniperHeld

var _shot_count := 0


func _ready() -> void:
	assert(InputMap.has_action("secondary_use"))
	assert(sniper.attack_type == &"sniper")
	assert(sniper.shot_distance >= 500.0)

	var item := load("res://resources/items/sniper.tres") as ItemData
	assert(item != null)
	assert(item.world_model != null)
	assert(item.held_model != null)

	sniper.fired.connect(func() -> void: _shot_count += 1)
	sniper.shot_smoke_lifetime = 0.1
	sniper.use_secondary(true)
	await get_tree().create_timer(0.2).timeout
	assert(camera.fov < 20.0)
	assert(sniper.scope_overlay.visible)
	var initial_scope_fov := sniper.get_current_scope_fov()
	assert(sniper.adjust_scope_zoom(1.0))
	await get_tree().create_timer(0.1).timeout
	assert(sniper.get_current_scope_fov() < initial_scope_fov)
	assert(is_equal_approx(camera.fov, sniper.get_current_scope_fov()))
	assert("x" in sniper.zoom_label.text)
	assert(sniper.adjust_scope_zoom(-1.0))
	await get_tree().create_timer(0.1).timeout
	assert(is_equal_approx(sniper.get_current_scope_fov(), initial_scope_fov))

	sniper.use_primary()
	await get_tree().process_frame
	assert(_shot_count == 1)
	assert(get_tree().get_nodes_in_group("shot_smoke").size() == 1)
	var smoke := get_tree().get_first_node_in_group(
		"shot_smoke"
	) as GPUParticles3D
	assert(smoke != null)
	assert(smoke.get_parent() == sniper.get_node("Muzzle"))
	assert(not smoke.local_coords)
	var smoke_process := smoke.process_material as ParticleProcessMaterial
	assert(smoke_process != null)
	assert(smoke_process.alpha_curve != null)
	var smoke_mesh := smoke.draw_pass_1 as QuadMesh
	assert(smoke_mesh != null)
	var smoke_material := smoke_mesh.material as StandardMaterial3D
	assert(smoke_material != null)
	assert(
		smoke_material.texture_filter
		== BaseMaterial3D.TEXTURE_FILTER_NEAREST
	)

	sniper.use_secondary(false)
	await get_tree().create_timer(0.2).timeout
	assert(is_equal_approx(camera.fov, 75.0))
	assert(not sniper.scope_overlay.visible)
	await get_tree().create_timer(0.5).timeout
	assert(get_tree().get_nodes_in_group("shot_smoke").is_empty())

	print("SNIPER_SHOT_SMOKE_TEST_PASS")
	get_tree().quit()
