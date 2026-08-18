extends Node

const ITEM_PATHS := [
	"res://resources/items/1911.tres",
	"res://resources/items/sniper.tres",
	"res://resources/items/knife.tres",
	"res://resources/items/cocaine.tres",
	"res://resources/items/cokeBrick.tres",
	"res://resources/items/mdma.tres",
	"res://resources/items/weed.tres",
	"res://resources/items/weedBag.tres",
	"res://resources/items/target_note_age.tres",
]


func _ready() -> void:
	var player_scene := load(
		"res://scenes/PlayerController.tscn"
	) as PackedScene
	var player := player_scene.instantiate()
	player.name = "2"
	add_child(player)

	await get_tree().process_frame
	await get_tree().process_frame

	var hand_ik := player.get_node("PlayerRightHandIK")

	for item_path in ITEM_PATHS:
		var item := load(item_path) as ItemData
		assert(item != null)
		assert(item.held_model != null)
		player._equip_world_item(item)

		for frame in 5:
			await get_tree().process_frame

		assert(player.get_active_right_hand_grip() != null)
		assert(player.get_active_held_item_rig() != null)
		hand_ik._process(0.0)
		assert(hand_ik.is_ik_active())
		assert(
			hand_ik.get_grip_error() < 0.02,
			"Right-Hand-IK verfehlt den Griff von %s."
			% item_path
		)

		player._clear_world_held_item()
		await get_tree().process_frame
		assert(not hand_ik.is_ik_active())

	player.queue_free()
	await get_tree().process_frame

	var local_player := player_scene.instantiate()
	local_player.name = "1"
	add_child(local_player)
	await get_tree().process_frame
	await get_tree().process_frame

	var pistol := load("res://resources/items/1911.tres") as ItemData
	local_player._equip_item(pistol)

	for frame in 5:
		await get_tree().process_frame

	var local_hand_ik := local_player.get_node("PlayerRightHandIK")
	assert(local_player.held_item_instance.get_parent() == local_player.held_item_rig)
	assert(local_player.held_item_instance._find_shooter() == local_player)
	local_hand_ik._process(0.0)
	assert(local_hand_ik.is_ik_active())
	assert(
		local_hand_ik.get_grip_error() < 0.02,
		"Lokale Right-Hand-IK-Abweichung: %f"
		% local_hand_ik.get_grip_error()
	)

	# Simuliert Rückstoß/Sway auf dem Item selbst: Die Hand muss den bewegten
	# Griff im nächsten Frame wieder erreichen.
	local_player.held_item_instance.position += Vector3(0.04, 0.03, -0.12)
	local_player.held_item_instance.rotation_degrees += Vector3(-8.0, 2.0, 3.0)
	await get_tree().process_frame
	await get_tree().process_frame
	local_hand_ik._process(0.0)
	assert(
		local_hand_ik.get_grip_error() < 0.02,
		"Dynamische Right-Hand-IK-Abweichung: %f"
		% local_hand_ik.get_grip_error()
	)

	local_player._clear_held_item()
	await get_tree().process_frame
	assert(not local_hand_ik.is_ik_active())

	print("RIGHT_HAND_IK_SMOKE_TEST_OK")
	get_tree().quit()
