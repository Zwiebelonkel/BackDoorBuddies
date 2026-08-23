extends Node


class MarketTestPlayer:
	extends Node3D

	var owned_instance_id := "market-test-item-001"
	var owned_resource_path := "res://resources/items/weed.tres"


	func server_has_inventory_item(
		item_instance_id: String,
		item_resource_path: String
	) -> bool:
		return (
			item_instance_id == owned_instance_id
			and item_resource_path == owned_resource_path
		)


const PICKUP_SCENE := preload("res://scenes/items/PickupItem.tscn")
const ITEM_PATH := "res://resources/items/weed.tres"


func _ready() -> void:
	var exit_code := await _run_test()
	get_tree().quit(exit_code)


func _run_test() -> int:
	var players := Node3D.new()
	players.name = "Players"
	add_child(players)

	var test_player := MarketTestPlayer.new()
	test_player.name = str(multiplayer.get_unique_id())
	players.add_child(test_player)

	var terminal := Node3D.new()
	terminal.name = "DarknetTerminal"
	terminal.add_to_group(&"darknet_terminal")
	add_child(terminal)

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

	var manager := DarknetMarketManager.new()
	manager.name = "DarknetMarketManager"
	add_child(manager)
	await get_tree().process_frame

	test_player.global_position = Vector3(10.0, 0.0, 0.0)
	manager.request_publish_listing(
		test_player.owned_instance_id,
		ITEM_PATH,
		100
	)

	if not manager.get_listings_for_peer(
		multiplayer.get_unique_id()
	).is_empty():
		return _fail("A player outside the van used the market remotely.")

	test_player.global_position = Vector3.ZERO

	manager.request_publish_listing(
		test_player.owned_instance_id,
		ITEM_PATH,
		100
	)

	var listings := manager.get_listings_for_peer(
		multiplayer.get_unique_id()
	)

	if listings.size() != 1:
		return _fail("Publishing did not create exactly one listing.")

	manager.request_publish_listing(
		"  %s  " % test_player.owned_instance_id,
		"  %s  " % ITEM_PATH,
		100
	)
	listings = manager.get_listings_for_peer(multiplayer.get_unique_id())

	if listings.size() != 1:
		return _fail("Whitespace bypassed the item reservation.")

	var listing_id := str(listings[0].get("id", ""))
	var internal_listing := manager._listings.get(listing_id, {}) as Dictionary
	manager._generate_offer(internal_listing)
	var payout := int(internal_listing.get("offer_price", 0))

	if payout <= 0:
		return _fail("Generated offer has no payout.")

	manager.request_accept_offer(listing_id)
	listings = manager.get_listings_for_peer(multiplayer.get_unique_id())

	if str(listings[0].get("status", "")) != "DELIVERY_REQUIRED":
		return _fail("Accept did not enter DELIVERY_REQUIRED.")

	if manager.get_wallet_for_peer(multiplayer.get_unique_id()) != 0:
		return _fail("Accept paid before physical delivery.")

	var wrong_pickup := _make_pickup("wrong-instance")
	add_child(wrong_pickup)
	await get_tree().process_frame

	if manager.try_complete_delivery(wrong_pickup):
		return _fail("A different item instance completed the sale.")

	if manager.get_wallet_for_peer(multiplayer.get_unique_id()) != 0:
		return _fail("Wrong delivery changed the wallet.")

	var already_claimed_pickup := _make_pickup(
		test_player.owned_instance_id
	)
	add_child(already_claimed_pickup)
	await get_tree().process_frame

	if not already_claimed_pickup.server_claim_for_sale():
		return _fail("Test setup could not claim the stale pickup.")

	if manager.try_complete_delivery(already_claimed_pickup):
		return _fail("An already claimed pickup completed the sale.")

	if manager.get_wallet_for_peer(multiplayer.get_unique_id()) != 0:
		return _fail("An already claimed pickup changed the wallet.")

	already_claimed_pickup.queue_free()

	var correct_pickup := _make_pickup(test_player.owned_instance_id)
	add_child(correct_pickup)
	await get_tree().process_frame

	if not manager.try_complete_delivery(correct_pickup):
		return _fail("The reserved item did not complete the sale.")

	if manager.get_wallet_for_peer(multiplayer.get_unique_id()) != payout:
		return _fail("Physical delivery did not credit the exact payout.")

	listings = manager.get_listings_for_peer(multiplayer.get_unique_id())

	if str(listings[0].get("status", "")) != "SOLD":
		return _fail("Completed delivery did not mark the listing SOLD.")

	if manager.try_complete_delivery(correct_pickup):
		return _fail("The same delivery completed twice.")

	if manager.get_wallet_for_peer(multiplayer.get_unique_id()) != payout:
		return _fail("The same delivery was paid twice.")

	var outside_pickup := _make_pickup("outside-cargo-item")
	spawned_items.add_child(outside_pickup)
	outside_pickup.global_position = Vector3(10.0, 0.0, 0.0)
	await get_tree().process_frame
	manager.request_publish_listing(
		outside_pickup.item_instance_id,
		ITEM_PATH,
		100
	)

	if manager.get_listings_for_peer(multiplayer.get_unique_id()).size() != 1:
		return _fail("An item outside the van was listed as local cargo.")

	var cargo_pickup := _make_pickup("van-cargo-item")
	spawned_items.add_child(cargo_pickup)
	await get_tree().process_frame
	manager.request_publish_listing(
		cargo_pickup.item_instance_id,
		ITEM_PATH,
		100
	)
	listings = manager.get_listings_for_peer(multiplayer.get_unique_id())

	if listings.size() != 2:
		return _fail("A concrete PickupItem in the van could not be listed.")

	if cargo_pickup.item_instance_id not in manager.get_all_reserved_instance_ids():
		return _fail("Reserved van cargo is not exposed to the local UI.")

	print("DARKNET_MARKET_SMOKE_TEST_OK")
	return 0


func _make_pickup(item_instance_id: String) -> PickupItem:
	var pickup := PICKUP_SCENE.instantiate() as PickupItem
	pickup.item_data = load(ITEM_PATH) as ItemData
	pickup.item_instance_id = item_instance_id
	return pickup


func _fail(message: String) -> int:
	push_error("DARKNET_MARKET_SMOKE_TEST_FAILED: " + message)
	return 1
