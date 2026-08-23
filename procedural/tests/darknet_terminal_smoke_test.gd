extends Node


const PICKUP_SCENE := preload("res://scenes/items/PickupItem.tscn")
const PLAYER_SCENE := preload("res://scenes/PlayerController.tscn")
const ITEM_PATH := "res://resources/items/weed.tres"

var _mesh_button_pressed := false


class TerminalPlayer:
	extends Node3D

	signal inventory_changed(items: Array[ItemData], selected_index: int)

	var inventory: Array[ItemData] = []


	func enter_darknet_terminal(_terminal: Node3D) -> bool:
		return true


	func get_inventory_instance_ids() -> Array[String]:
		return []


	func select_inventory_item(_slot_index: int) -> void:
		pass


func _ready() -> void:
	var generator := Node3D.new()
	generator.name = "ProceduralLevelGenerator"
	add_child(generator)
	var spawned_items := Node3D.new()
	spawned_items.name = "SpawnedItems"
	generator.add_child(spawned_items)

	var cargo_area := Area3D.new()
	cargo_area.name = "CargoArea"
	cargo_area.add_to_group(&"van_item_zone")
	add_child(cargo_area)
	var cargo_shape := CollisionShape3D.new()
	cargo_shape.name = "CollisionShape3D"
	var cargo_box := BoxShape3D.new()
	cargo_box.size = Vector3(4.0, 4.0, 4.0)
	cargo_shape.shape = cargo_box
	cargo_area.add_child(cargo_shape)

	var terminal_scene := preload(
		"res://scenes/props/van/DarknetTerminal.tscn"
	)
	var terminal := terminal_scene.instantiate() as DarknetTerminal
	assert(terminal != null, "DarknetTerminal konnte nicht instanziiert werden.")
	add_child(terminal)
	await get_tree().process_frame

	var viewport := terminal.get_node("SubViewport") as SubViewport
	var market_ui := viewport.get_node("DarknetMarketV2") as Control
	var interaction := terminal.get_node("Interaction") as Area3D
	var drop_area := terminal.get_node("SaleDropArea") as Area3D
	var drop_shape := drop_area.get_node("CollisionShape3D") as CollisionShape3D
	var drop_box := drop_shape.shape as BoxShape3D
	var screen := terminal.get_node("Screen") as MeshInstance3D

	assert(viewport.size == Vector2i(1024, 640), "Falsche Terminal-Auflösung.")
	assert(
		viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"Terminal-Viewport aktualisiert sich nicht dauerhaft."
	)
	assert(market_ui.has_method("bind_player"), "Produktions-UI ist nicht gebunden.")
	assert(
		market_ui.has_method("bind_market_manager"),
		"MarketManager-Binding fehlt."
	)
	assert(interaction.has_method("request_interaction"), "E-Interaktion fehlt.")
	assert(drop_box != null, "SaleDropArea benötigt eine BoxShape3D.")
	assert(
		drop_box.size.is_equal_approx(Vector3(0.9, 0.35, 1.1)),
		"SaleDropArea besitzt die falsche Größe."
	)
	assert(
		screen.material_override is ShaderMaterial,
		"SubViewportTexture wurde nicht auf das Mesh-Material gelegt."
	)
	assert(
		terminal.is_in_group(&"darknet_terminal"),
		"Serverseitige Terminal-Nähe kann nicht validiert werden."
	)
	var inventory_list := market_ui.get_node(
		"Margin/VBox/MainTabs/SELL/Content/InventoryPanel/Margin/VBox/InventoryList"
	) as ItemList
	var list_focus := inventory_list.get_theme_stylebox("focus")
	var selected_row := inventory_list.get_theme_stylebox("selected")
	assert(
		list_focus is StyleBoxFlat
		and not (list_focus as StyleBoxFlat).draw_center,
		"ItemList-Fokus färbt weiterhin die gesamte Inventarfläche."
	)
	assert(
		selected_row is StyleBoxFlat
		and (selected_row as StyleBoxFlat).draw_center,
		"Die ausgewählte Inventarzeile besitzt keine eigene Markierung."
	)

	var real_player := PLAYER_SCENE.instantiate() as FPSController
	real_player.name = str(multiplayer.get_unique_id())
	real_player.set_multiplayer_authority(multiplayer.get_unique_id())
	add_child(real_player)
	await get_tree().process_frame
	real_player.set_physics_process(false)
	assert(real_player.player_hud != null, "Lokales PlayerHUD wurde nicht erzeugt.")
	assert(real_player.player_hud.visible, "PlayerHUD ist vor Terminalnutzung unsichtbar.")
	assert(
		terminal.begin_use(real_player),
		"Echter Spieler konnte den Terminalmodus nicht starten."
	)
	assert(
		not real_player.player_hud.visible,
		"PlayerHUD bleibt während der Terminalnutzung sichtbar."
	)
	real_player.exit_darknet_terminal()
	assert(
		real_player.player_hud.visible,
		"PlayerHUD wurde nach Terminalnutzung nicht wiederhergestellt."
	)
	real_player.queue_free()
	await get_tree().process_frame

	var player := TerminalPlayer.new()
	player.set_multiplayer_authority(multiplayer.get_unique_id())
	add_child(player)
	assert(terminal.begin_use(player), "Terminal-Fokusmodus konnte nicht starten.")
	assert(terminal.is_used_by(player), "Terminal speichert den aktiven Nutzer nicht.")

	var cargo_pickup := PICKUP_SCENE.instantiate() as PickupItem
	cargo_pickup.item_data = load(ITEM_PATH) as ItemData
	cargo_pickup.item_instance_id = "terminal-cargo-item-001"
	spawned_items.add_child(cargo_pickup)
	await get_tree().process_frame
	terminal.call("_scan_local_items")

	var local_entries: Variant = market_ui.get("_inventory_entries")
	assert(
		local_entries is Array
		and (local_entries as Array).size() == 1
		and str((local_entries as Array)[0].get("instance_id", ""))
		== cargo_pickup.item_instance_id,
		"Ein Pickup in der CargoArea erscheint nicht als lokales Item."
	)

	cargo_pickup.global_position = Vector3(10.0, 0.0, 0.0)
	terminal.call("_scan_local_items")
	local_entries = market_ui.get("_inventory_entries")
	assert(
		local_entries is Array and (local_entries as Array).is_empty(),
		"Ein aus dem Van entferntes Pickup bleibt im Terminal sichtbar."
	)

	var click_probe := Button.new()
	click_probe.position = Vector2(462.0, 295.0)
	click_probe.size = Vector2(100.0, 50.0)
	click_probe.text = "CLICK TEST"
	click_probe.pressed.connect(_on_mesh_button_pressed)
	viewport.add_child(click_probe)

	var camera := Camera3D.new()
	terminal.add_child(camera)
	camera.global_transform = terminal.get_view_transform(
		terminal.global_position + Vector3(-1.0, 1.35, 0.0)
	)
	camera.fov = terminal.get_viewing_fov()
	camera.make_current()
	await get_tree().process_frame
	var pointer_center := get_viewport().get_visible_rect().size * 0.5
	var pointer_event := InputEventMouseMotion.new()
	pointer_event.position = pointer_center
	pointer_event.global_position = pointer_center
	assert(
		terminal.forward_input(pointer_event, camera),
		"Mausstrahl trifft die klickbare Mesh-Oberfläche nicht."
	)
	var click_event := InputEventMouseButton.new()
	click_event.position = pointer_center
	click_event.global_position = pointer_center
	click_event.button_index = MOUSE_BUTTON_LEFT
	click_event.pressed = true
	assert(
		terminal.forward_input(click_event, camera),
		"Mesh-Klick erreicht den SubViewport nicht."
	)
	click_event.pressed = false
	assert(
		terminal.forward_input(click_event, camera),
		"Mesh-Klick-Release erreicht den SubViewport nicht."
	)
	await get_tree().process_frame
	assert(
		_mesh_button_pressed,
		"Der 3D-Mesh-Klick hat keinen echten SubViewport-Button ausgelöst."
	)

	var key_event := InputEventKey.new()
	key_event.keycode = KEY_TAB
	key_event.pressed = true
	assert(
		terminal.forward_input(key_event, null),
		"Keyboard-Input erreicht den SubViewport nicht."
	)
	terminal.end_use(player)
	assert(not terminal.is_used_by(player), "Terminal-Fokus wurde nicht beendet.")

	print("DARKNET_TERMINAL_SMOKE_TEST_OK")
	get_tree().quit()


func _on_mesh_button_pressed() -> void:
	_mesh_button_pressed = true
