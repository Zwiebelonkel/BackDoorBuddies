class_name DarknetMarketManager
extends Node


signal market_state_changed(snapshot: Dictionary)
signal sale_completed(
	owner_peer_id: int,
	listing_id: String,
	payout: int,
	wallet: int
)

const STATUS_LISTED := "LISTED"
const STATUS_OFFER_RECEIVED := "OFFER_RECEIVED"
const STATUS_COUNTER_SENT := "COUNTER_SENT"
const STATUS_DELIVERY_REQUIRED := "DELIVERY_REQUIRED"
const STATUS_SOLD := "SOLD"
const STATUS_DECLINED := "DECLINED"
const STATUS_CANCELLED := "CANCELLED"
const TERMINAL_USE_DISTANCE := 3.0

const BUYER_NAMES: Array[String] = [
	"corpsebuyer_77",
	"ghostpacket",
	"NOFACE_14",
	"redroom_vendor",
	"deadchannel",
	"blackwire",
	"skinmarket_02",
	"NULLCLIENT",
]

var _listings: Dictionary = {}
var _wallets: Dictionary = {}
var _next_listing_sequence := 1
var _rng := RandomNumberGenerator.new()
var _initial_sync_pending := false
var _sync_retry_time_remaining := 0.0


func _ready() -> void:
	add_to_group(&"darknet_market_manager")
	_rng.randomize()

	if multiplayer.is_server():
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)

		if not multiplayer.peer_disconnected.is_connected(
			_on_peer_disconnected
		):
			multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	else:
		_initial_sync_pending = true

	_publish_state(false)


func _process(_delta: float) -> void:
	if not multiplayer.is_server():
		_process_initial_sync(_delta)
		return

	var now := Time.get_ticks_msec()
	var changed := false

	for listing_value in _listings.values():
		var listing := listing_value as Dictionary
		var status := str(listing.get("status", ""))

		if (
			status == STATUS_LISTED
			and now >= int(listing.get("offer_due_msec", 0))
		):
			_generate_offer(listing)
			changed = true
		elif (
			status == STATUS_COUNTER_SENT
			and now >= int(listing.get("counter_due_msec", 0))
		):
			_resolve_counter_offer(listing)
			changed = true

	if changed:
		_publish_state()


func request_publish_listing(
	item_instance_id: String,
	item_resource_path: String,
	asking_price: int
) -> void:
	if multiplayer.is_server():
		_server_publish_listing(
			multiplayer.get_unique_id(),
			item_instance_id,
			item_resource_path,
			asking_price
		)
	else:
		_request_publish_listing.rpc_id(
			1,
			item_instance_id,
			item_resource_path,
			asking_price
		)


func request_accept_offer(listing_id: String) -> void:
	if multiplayer.is_server():
		_server_accept_offer(multiplayer.get_unique_id(), listing_id)
	else:
		_request_accept_offer.rpc_id(1, listing_id)


func request_decline_offer(listing_id: String) -> void:
	if multiplayer.is_server():
		_server_decline_offer(multiplayer.get_unique_id(), listing_id)
	else:
		_request_decline_offer.rpc_id(1, listing_id)


func request_counter_offer(listing_id: String, counter_price: int) -> void:
	if multiplayer.is_server():
		_server_counter_offer(
			multiplayer.get_unique_id(),
			listing_id,
			counter_price
		)
	else:
		_request_counter_offer.rpc_id(1, listing_id, counter_price)


func try_complete_delivery(pickup: PickupItem) -> bool:
	if not multiplayer.is_server() or pickup == null:
		return false

	if pickup.item_data == null or pickup.item_instance_id.is_empty():
		return false

	for listing_value in _listings.values():
		var listing := listing_value as Dictionary

		if str(listing.get("status", "")) != STATUS_DELIVERY_REQUIRED:
			continue

		if (
			str(listing.get("item_instance_id", ""))
			!= pickup.item_instance_id
		):
			continue

		if (
			str(listing.get("item_resource_path", ""))
			!= pickup.item_data.resource_path
		):
			continue

		if (
			not pickup.has_method("server_claim_for_sale")
			or not bool(pickup.call("server_claim_for_sale"))
		):
			continue

		listing["status"] = STATUS_SOLD
		listing["completed_at_msec"] = Time.get_ticks_msec()

		var owner_peer_id := int(listing.get("owner_peer_id", 0))
		var listing_id := str(listing.get("id", ""))
		var payout := maxi(int(listing.get("offer_price", 0)), 0)
		var wallet := maxi(int(_wallets.get(owner_peer_id, 0)), 0) + payout
		_wallets[owner_peer_id] = wallet

		pickup.queue_free()

		_publish_state()
		_send_sale_completed(
			owner_peer_id,
			listing_id,
			payout,
			wallet
		)
		return true

	return false


func get_state_snapshot() -> Dictionary:
	var public_listings: Array[Dictionary] = []

	for listing_value in _listings.values():
		var listing := (listing_value as Dictionary).duplicate(true)
		listing.erase("offer_due_msec")
		listing.erase("counter_due_msec")
		public_listings.append(listing)

	public_listings.sort_custom(func(first: Dictionary, second: Dictionary):
		return int(first.get("sequence", 0)) > int(second.get("sequence", 0))
	)

	return {
		"listings": public_listings,
		"wallets": _wallets.duplicate(true),
	}


func get_listings_for_peer(peer_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for listing_value in _listings.values():
		var listing := listing_value as Dictionary

		if int(listing.get("owner_peer_id", 0)) == peer_id:
			result.append(listing.duplicate(true))

	result.sort_custom(func(first: Dictionary, second: Dictionary):
		return int(first.get("sequence", 0)) > int(second.get("sequence", 0))
	)
	return result


func get_reserved_instance_ids(peer_id: int) -> Array[String]:
	var result: Array[String] = []

	for listing_value in _listings.values():
		var listing := listing_value as Dictionary

		if int(listing.get("owner_peer_id", 0)) != peer_id:
			continue

		if not _status_reserves_item(str(listing.get("status", ""))):
			continue

		var item_instance_id := str(listing.get("item_instance_id", ""))

		if not item_instance_id.is_empty():
			result.append(item_instance_id)

	return result


func get_all_reserved_instance_ids() -> Array[String]:
	var result: Array[String] = []

	for listing_value in _listings.values():
		var listing := listing_value as Dictionary

		if not _status_reserves_item(str(listing.get("status", ""))):
			continue

		var item_instance_id := str(listing.get("item_instance_id", ""))

		if not item_instance_id.is_empty():
			result.append(item_instance_id)

	return result


func get_wallet_for_peer(peer_id: int) -> int:
	return maxi(int(_wallets.get(peer_id, 0)), 0)


func sync_to_peer(peer_id: int) -> void:
	if (
		not multiplayer.is_server()
		or peer_id <= 0
		or peer_id not in multiplayer.get_peers()
	):
		return

	_receive_market_state.rpc_id(peer_id, get_state_snapshot())


@rpc("any_peer", "call_remote", "reliable")
func _request_publish_listing(
	item_instance_id: String,
	item_resource_path: String,
	asking_price: int
) -> void:
	if not multiplayer.is_server():
		return

	_server_publish_listing(
		multiplayer.get_remote_sender_id(),
		item_instance_id,
		item_resource_path,
		asking_price
	)


@rpc("any_peer", "call_remote", "reliable")
func _request_accept_offer(listing_id: String) -> void:
	if multiplayer.is_server():
		_server_accept_offer(multiplayer.get_remote_sender_id(), listing_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_decline_offer(listing_id: String) -> void:
	if multiplayer.is_server():
		_server_decline_offer(multiplayer.get_remote_sender_id(), listing_id)


@rpc("any_peer", "call_remote", "reliable")
func _request_counter_offer(listing_id: String, counter_price: int) -> void:
	if multiplayer.is_server():
		_server_counter_offer(
			multiplayer.get_remote_sender_id(),
			listing_id,
			counter_price
		)


func _server_publish_listing(
	owner_peer_id: int,
	item_instance_id: String,
	item_resource_path: String,
	asking_price: int
) -> void:
	var normalized_instance_id := item_instance_id.strip_edges()
	var normalized_resource_path := item_resource_path.strip_edges()

	if (
		owner_peer_id <= 0
		or normalized_instance_id.is_empty()
		or normalized_resource_path.is_empty()
		or _is_instance_reserved(normalized_instance_id)
	):
		return

	if not _can_peer_use_terminal(owner_peer_id):
		return

	var player := _find_player(owner_peer_id)
	var player_has_item := (
		player != null
		and player.has_method("server_has_inventory_item")
		and bool(player.call(
			"server_has_inventory_item",
			normalized_instance_id,
			normalized_resource_path
		))
	)
	var van_pickup := _find_van_pickup(
		normalized_instance_id,
		normalized_resource_path
	)

	if not player_has_item and van_pickup == null:
		return

	var loaded_item := load(normalized_resource_path)
	var item_data := loaded_item as ItemData

	if item_data == null or item_data.is_mission_clue:
		return

	var price := clampi(asking_price, 1, 999_999)
	var listing_id := "MK-%08d-%04d" % [
		Time.get_ticks_msec(),
		_next_listing_sequence,
	]
	var listing := {
		"id": listing_id,
		"sequence": _next_listing_sequence,
		"owner_peer_id": owner_peer_id,
		"item_instance_id": normalized_instance_id,
		"item_resource_path": normalized_resource_path,
		"item_id": String(item_data.item_id),
		"name": item_data.display_name,
		"base_value": maxi(item_data.value, 0),
		"asking_price": price,
		"status": STATUS_LISTED,
		"buyer": "",
		"offer_price": 0,
		"counter_price": 0,
		"offer_due_msec": (
			Time.get_ticks_msec()
			+ int(_get_offer_delay_seconds(item_data.value, price) * 1000.0)
		),
	}

	_next_listing_sequence += 1
	_listings[listing_id] = listing
	_publish_state()


func _server_accept_offer(owner_peer_id: int, listing_id: String) -> void:
	if not _can_peer_use_terminal(owner_peer_id):
		return

	var listing := _get_owned_listing(owner_peer_id, listing_id)

	if (
		listing.is_empty()
		or str(listing.get("status", "")) != STATUS_OFFER_RECEIVED
	):
		return

	listing["status"] = STATUS_DELIVERY_REQUIRED
	listing["accepted_at_msec"] = Time.get_ticks_msec()
	_publish_state()


func _server_decline_offer(owner_peer_id: int, listing_id: String) -> void:
	if not _can_peer_use_terminal(owner_peer_id):
		return

	var listing := _get_owned_listing(owner_peer_id, listing_id)

	if (
		listing.is_empty()
		or str(listing.get("status", "")) != STATUS_OFFER_RECEIVED
	):
		return

	listing["status"] = STATUS_DECLINED
	_publish_state()


func _server_counter_offer(
	owner_peer_id: int,
	listing_id: String,
	counter_price: int
) -> void:
	if not _can_peer_use_terminal(owner_peer_id):
		return

	var listing := _get_owned_listing(owner_peer_id, listing_id)

	if (
		listing.is_empty()
		or str(listing.get("status", "")) != STATUS_OFFER_RECEIVED
	):
		return

	listing["counter_price"] = clampi(counter_price, 1, 999_999)
	listing["status"] = STATUS_COUNTER_SENT
	listing["counter_due_msec"] = (
		Time.get_ticks_msec()
		+ int(_rng.randf_range(4.0, 10.0) * 1000.0)
	)
	_publish_state()


func _generate_offer(listing: Dictionary) -> void:
	var asking := maxi(int(listing.get("asking_price", 1)), 1)
	listing["buyer"] = BUYER_NAMES[_rng.randi_range(0, BUYER_NAMES.size() - 1)]
	listing["offer_price"] = maxi(
		int(round(float(asking) * _rng.randf_range(0.72, 1.08))),
		1
	)
	listing["status"] = STATUS_OFFER_RECEIVED


func _resolve_counter_offer(listing: Dictionary) -> void:
	if _rng.randf() < 0.55:
		listing["offer_price"] = int(listing.get("counter_price", 1))

	listing["status"] = STATUS_OFFER_RECEIVED


func _get_offer_delay_seconds(base_value: int, asking_price: int) -> float:
	var base := maxf(float(base_value), 1.0)
	var ratio := float(asking_price) / base
	var wait_min := 8.0
	var wait_max := 25.0

	if ratio <= 0.75:
		wait_min = 3.0
		wait_max = 8.0
	elif ratio <= 1.0:
		wait_min = 7.0
		wait_max = 18.0
	elif ratio <= 1.35:
		wait_min = 15.0
		wait_max = 35.0
	elif ratio <= 1.75:
		wait_min = 25.0
		wait_max = 60.0
	else:
		wait_min = 45.0
		wait_max = 90.0

	return _rng.randf_range(wait_min, wait_max)


func _get_owned_listing(owner_peer_id: int, listing_id: String) -> Dictionary:
	var listing_value: Variant = _listings.get(listing_id, {})

	if not listing_value is Dictionary:
		return {}

	var listing := listing_value as Dictionary

	if int(listing.get("owner_peer_id", 0)) != owner_peer_id:
		return {}

	return listing


func _is_instance_reserved(item_instance_id: String) -> bool:
	for listing_value in _listings.values():
		var listing := listing_value as Dictionary

		if (
			str(listing.get("item_instance_id", "")) == item_instance_id
			and _status_reserves_item(str(listing.get("status", "")))
		):
			return true

	return false


func _status_reserves_item(status: String) -> bool:
	return status in [
		STATUS_LISTED,
		STATUS_OFFER_RECEIVED,
		STATUS_COUNTER_SENT,
		STATUS_DELIVERY_REQUIRED,
	]


func _find_player(peer_id: int) -> Node:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		return null

	var players := current_scene.get_node_or_null("Players")
	return players.get_node_or_null(str(peer_id)) if players != null else null


func _find_van_pickup(
	item_instance_id: String,
	item_resource_path: String
) -> PickupItem:
	var current_scene := get_tree().current_scene

	if current_scene == null:
		return null

	var items_root := current_scene.get_node_or_null(
		"ProceduralLevelGenerator/SpawnedItems"
	)

	if items_root == null:
		return null

	for child in items_root.get_children():
		var pickup := child as PickupItem

		if (
			pickup == null
			or pickup.item_data == null
			or pickup.item_instance_id.strip_edges() != item_instance_id
			or pickup.item_data.resource_path != item_resource_path
			or not _is_point_in_van(pickup.global_position)
		):
			continue

		return pickup

	return null


func _is_point_in_van(point: Vector3) -> bool:
	for zone_node in get_tree().get_nodes_in_group(&"van_item_zone"):
		var zone := zone_node as Area3D

		if zone == null:
			continue

		var collision_shape := zone.get_node_or_null(
			"CollisionShape3D"
		) as CollisionShape3D

		if collision_shape == null:
			continue

		var box := collision_shape.shape as BoxShape3D

		if box == null:
			continue

		var local_point := collision_shape.global_transform.affine_inverse() * point
		var half_size := box.size * 0.5

		if (
			absf(local_point.x) <= half_size.x
			and absf(local_point.y) <= half_size.y
			and absf(local_point.z) <= half_size.z
		):
			return true

	return false


func _can_peer_use_terminal(peer_id: int) -> bool:
	var player := _find_player(peer_id) as Node3D

	if player == null:
		return false

	for terminal_node in get_tree().get_nodes_in_group(&"darknet_terminal"):
		var terminal := terminal_node as Node3D

		if (
			terminal != null
			and player.global_position.distance_to(terminal.global_position)
			<= TERMINAL_USE_DISTANCE
		):
			return true

	return false


func _process_initial_sync(delta: float) -> void:
	if not _initial_sync_pending:
		return

	_sync_retry_time_remaining -= delta

	if _sync_retry_time_remaining > 0.0:
		return

	_sync_retry_time_remaining = 1.0
	_request_market_state.rpc_id(1)


func _publish_state(send_to_peers := true) -> void:
	var snapshot := get_state_snapshot()
	market_state_changed.emit(snapshot)

	if (
		send_to_peers
		and multiplayer.is_server()
		and not multiplayer.get_peers().is_empty()
	):
		_receive_market_state.rpc(snapshot)


@rpc("authority", "call_remote", "reliable")
func _receive_market_state(snapshot: Dictionary) -> void:
	_initial_sync_pending = false
	_listings.clear()

	for listing_value in snapshot.get("listings", []):
		if not listing_value is Dictionary:
			continue

		var listing := (listing_value as Dictionary).duplicate(true)
		var listing_id := str(listing.get("id", ""))

		if not listing_id.is_empty():
			_listings[listing_id] = listing

	_wallets = (snapshot.get("wallets", {}) as Dictionary).duplicate(true)
	market_state_changed.emit(get_state_snapshot())


@rpc("any_peer", "call_remote", "reliable")
func _request_market_state() -> void:
	if not multiplayer.is_server():
		return

	var sender_peer_id := multiplayer.get_remote_sender_id()

	if sender_peer_id > 0:
		sync_to_peer(sender_peer_id)


func _send_sale_completed(
	owner_peer_id: int,
	listing_id: String,
	payout: int,
	wallet: int
) -> void:
	if owner_peer_id == multiplayer.get_unique_id():
		sale_completed.emit(owner_peer_id, listing_id, payout, wallet)
	elif owner_peer_id in multiplayer.get_peers():
		_notify_sale_completed.rpc_id(
			owner_peer_id,
			owner_peer_id,
			listing_id,
			payout,
			wallet
		)


@rpc("authority", "call_remote", "reliable")
func _notify_sale_completed(
	owner_peer_id: int,
	listing_id: String,
	payout: int,
	wallet: int
) -> void:
	sale_completed.emit(owner_peer_id, listing_id, payout, wallet)


func _on_peer_connected(peer_id: int) -> void:
	sync_to_peer(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var changed := false

	for listing_value in _listings.values():
		var listing := listing_value as Dictionary

		if (
			int(listing.get("owner_peer_id", 0)) == peer_id
			and _status_reserves_item(str(listing.get("status", "")))
		):
			listing["status"] = STATUS_CANCELLED
			changed = true

	if changed:
		_publish_state()
