extends Node3D


class DeliveryPlayer:
	extends Node3D

	var owned_instance_id := "delivery-flow-item-001"
	var owned_resource_path := "res://resources/items/weed.tres"


	func server_has_inventory_item(
		item_instance_id: String,
		item_resource_path: String
	) -> bool:
		return (
			item_instance_id == owned_instance_id
			and item_resource_path == owned_resource_path
		)


const ITEM_PATH := "res://resources/items/weed.tres"
const PICKUP_SCENE := preload("res://scenes/items/PickupItem.tscn")
const TERMINAL_SCENE := preload(
	"res://scenes/props/van/DarknetTerminal.tscn"
)


func _ready() -> void:
	var exit_code := await _run_test()
	get_tree().quit(exit_code)


func _run_test() -> int:
	var players := Node3D.new()
	players.name = "Players"
	add_child(players)
	var player := DeliveryPlayer.new()
	player.name = str(multiplayer.get_unique_id())
	players.add_child(player)

	var generator := Node3D.new()
	generator.name = "ProceduralLevelGenerator"
	add_child(generator)
	var spawned_items := Node3D.new()
	spawned_items.name = "SpawnedItems"
	generator.add_child(spawned_items)

	var manager := DarknetMarketManager.new()
	manager.name = "DarknetMarketManager"
	add_child(manager)
	var terminal := TERMINAL_SCENE.instantiate() as DarknetTerminal
	assert(terminal != null, "DarknetTerminal konnte nicht erstellt werden.")
	add_child(terminal)
	await get_tree().process_frame
	player.global_position = terminal.global_position

	manager.request_publish_listing(
		player.owned_instance_id,
		ITEM_PATH,
		1250
	)
	var listings := manager.get_listings_for_peer(
		multiplayer.get_unique_id()
	)

	if listings.size() != 1:
		return _fail("Listing wurde am echten Terminal nicht erstellt.")

	var listing_id := str(listings[0].get("id", ""))
	var listing := manager._listings.get(listing_id, {}) as Dictionary
	manager._generate_offer(listing)
	var payout := int(listing.get("offer_price", 0))
	manager.request_accept_offer(listing_id)

	if (
		str(listing.get("status", "")) != "DELIVERY_REQUIRED"
		or manager.get_wallet_for_peer(multiplayer.get_unique_id()) != 0
	):
		return _fail("Accept hat nicht zahlungsfrei auf Lieferung gewartet.")

	var drop_area := terminal.get_node("SaleDropArea") as Area3D
	var wrong_pickup := _make_pickup("wrong-delivery-item")
	spawned_items.add_child(wrong_pickup)
	wrong_pickup.global_position = drop_area.global_position
	var correct_pickup := _make_pickup(player.owned_instance_id)
	spawned_items.add_child(correct_pickup)
	correct_pickup.global_position = (
		drop_area.global_position + Vector3(2.0, 0.0, 0.0)
	)
	await get_tree().create_timer(0.24).timeout

	if manager.get_wallet_for_peer(multiplayer.get_unique_id()) != 0:
		return _fail("Falsches oder außerhalb liegendes Item wurde bezahlt.")

	correct_pickup.global_position = drop_area.global_position
	await get_tree().create_timer(0.24).timeout

	if manager.get_wallet_for_peer(multiplayer.get_unique_id()) != payout:
		return _fail("Räumlicher SaleDropArea-Scan hat nicht exakt ausgezahlt.")

	listings = manager.get_listings_for_peer(multiplayer.get_unique_id())

	if str(listings[0].get("status", "")) != "SOLD":
		return _fail("Räumliche Lieferung hat das Listing nicht abgeschlossen.")

	await get_tree().create_timer(0.24).timeout

	if manager.get_wallet_for_peer(multiplayer.get_unique_id()) != payout:
		return _fail("Dropzone-Scan hat dieselbe Lieferung doppelt bezahlt.")

	print("DARKNET_DELIVERY_FLOW_TEST_OK")
	return 0


func _make_pickup(item_instance_id: String) -> PickupItem:
	var pickup := PICKUP_SCENE.instantiate() as PickupItem
	pickup.item_data = load(ITEM_PATH) as ItemData
	pickup.item_instance_id = item_instance_id
	return pickup


func _fail(message: String) -> int:
	push_error("DARKNET_DELIVERY_FLOW_TEST_FAILED: " + message)
	return 1
