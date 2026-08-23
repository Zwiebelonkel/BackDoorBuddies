class_name DarknetMarketUI
extends Control


const LISTING_ROW := preload(
	"res://scenes/UI/market/darknet_listing_row.gd"
)
const TERMINAL_FONT := preload(
	"res://fonts/VCR_OSD_MONO_1.001.ttf"
)
const ACTIVE_STATUSES: Array[String] = [
	"LISTED",
	"OFFER_RECEIVED",
	"COUNTER_SENT",
	"DELIVERY_REQUIRED",
]

@onready var inventory_list: ItemList = (
	$Margin/VBox/MainTabs/SELL/Content/InventoryPanel/Margin/VBox/InventoryList
)
@onready var inventory_count: Label = (
	$Margin/VBox/MainTabs/SELL/Content/InventoryPanel/Margin/VBox/Heading/Count
)
@onready var selected_item_label: Label = (
	$Margin/VBox/MainTabs/SELL/Content/ListingPanel/Margin/VBox/SelectedItem
)
@onready var instance_label: Label = (
	$Margin/VBox/MainTabs/SELL/Content/ListingPanel/Margin/VBox/InstanceId
)
@onready var base_value_label: Label = (
	$Margin/VBox/MainTabs/SELL/Content/ListingPanel/Margin/VBox/BaseValue
)
@onready var price_box: SpinBox = (
	$Margin/VBox/MainTabs/SELL/Content/ListingPanel/Margin/VBox/PriceRow/Price
)
@onready var market_hint: Label = (
	$Margin/VBox/MainTabs/SELL/Content/ListingPanel/Margin/VBox/MarketHint
)
@onready var reserved_hint: Label = (
	$Margin/VBox/MainTabs/SELL/Content/ListingPanel/Margin/VBox/ReservedHint
)
@onready var list_button: Button = (
	$Margin/VBox/MainTabs/SELL/Content/ListingPanel/Margin/VBox/ListButton
)

@onready var listings_container: VBoxContainer = (
	$Margin/VBox/MainTabs/"MY LISTINGS"/Content/ListingsScroll/ListingsContainer
)
@onready var listings_count: Label = (
	$Margin/VBox/MainTabs/"MY LISTINGS"/Content/ListingsHeader/Count
)
@onready var empty_listings: Label = (
	$Margin/VBox/MainTabs/"MY LISTINGS"/Content/EmptyState
)

@onready var inbox_list: ItemList = (
	$Margin/VBox/MainTabs/INBOX/Content/MessagesPanel/Margin/VBox/InboxList
)
@onready var inbox_count: Label = (
	$Margin/VBox/MainTabs/INBOX/Content/MessagesPanel/Margin/VBox/Heading/Count
)
@onready var buyer_label: Label = (
	$Margin/VBox/MainTabs/INBOX/Content/OfferPanel/Margin/VBox/Buyer
)
@onready var buyer_message: RichTextLabel = (
	$Margin/VBox/MainTabs/INBOX/Content/OfferPanel/Margin/VBox/Message
)
@onready var offer_value: Label = (
	$Margin/VBox/MainTabs/INBOX/Content/OfferPanel/Margin/VBox/OfferRow/OfferValue
)
@onready var counter_box: SpinBox = (
	$Margin/VBox/MainTabs/INBOX/Content/OfferPanel/Margin/VBox/CounterRow/Counter
)
@onready var accept_button: Button = (
	$Margin/VBox/MainTabs/INBOX/Content/OfferPanel/Margin/VBox/Buttons/Accept
)
@onready var counter_button: Button = (
	$Margin/VBox/MainTabs/INBOX/Content/OfferPanel/Margin/VBox/Buttons/CounterButton
)
@onready var decline_button: Button = (
	$Margin/VBox/MainTabs/INBOX/Content/OfferPanel/Margin/VBox/Buttons/Decline
)

@onready var wallet_label: Label = (
	$Margin/VBox/Header/HeaderMargin/HBox/WalletBox/Margin/VBox/Wallet
)
@onready var connection_dot: Label = (
	$Margin/VBox/StatusStrip/Margin/HBox/ConnectionDot
)
@onready var connection_label: Label = (
	$Margin/VBox/StatusStrip/Margin/HBox/Connection
)
@onready var delivery_state_label: Label = (
	$Margin/VBox/StatusStrip/Margin/HBox/DeliveryState
)
@onready var delivery_banner: PanelContainer = $Margin/VBox/DeliveryBanner
@onready var delivery_title: Label = (
	$Margin/VBox/DeliveryBanner/Margin/HBox/Copy/Title
)
@onready var delivery_detail: Label = (
	$Margin/VBox/DeliveryBanner/Margin/HBox/Copy/Detail
)
@onready var delivery_payout: Label = (
	$Margin/VBox/DeliveryBanner/Margin/HBox/Payout
)
@onready var log: RichTextLabel = $Margin/VBox/BottomLog/Margin/Log

var _player: Node = null
var _market_manager: Node = null
var _inventory_entries: Array[Dictionary] = []
var _local_item_entries: Array[Dictionary] = []
var _use_local_items := false
var _listings: Array[Dictionary] = []
var _selected_instance_id := ""
var _selected_offer_id := ""
var _status_cache: Dictionary = {}
var _pulse_time := 0.0
var _has_initial_market_state := false


func _ready() -> void:
	theme = _create_terminal_theme()
	var delivery_style := _style(
		Color(0.15, 0.027, 0.012, 0.98),
		Color(1.0, 0.29, 0.12, 0.96),
		2
	)
	delivery_style.border_width_left = 4
	delivery_style.shadow_color = Color(1.0, 0.16, 0.04, 0.22)
	delivery_style.shadow_size = 7
	delivery_banner.add_theme_stylebox_override("panel", delivery_style)
	inventory_list.item_selected.connect(_on_inventory_selected)
	inbox_list.item_selected.connect(_on_offer_selected)
	list_button.pressed.connect(_publish_listing)
	price_box.value_changed.connect(_refresh_market_hint)
	accept_button.pressed.connect(_accept_offer)
	decline_button.pressed.connect(_decline_offer)
	counter_button.pressed.connect(_send_counter)
	_clear_item_view()
	_clear_offer_view()
	_update_connection_state()
	delivery_banner.visible = false
	_write_log("relay online // waiting for authenticated user")
	call_deferred("_auto_bind")


func _process(delta: float) -> void:
	_pulse_time += delta
	var pulse := 0.65 + 0.35 * sin(_pulse_time * 3.8)
	var relay_online := (
		is_instance_valid(_player)
		and is_instance_valid(_market_manager)
	)
	connection_dot.modulate = (
		Color(0.35, 1.0, 0.48, pulse)
		if relay_online
		else Color(1.0, 0.28, 0.17, pulse)
	)

	if delivery_banner.visible:
		delivery_banner.self_modulate = Color(1.0, 1.0, 1.0, 0.92 + pulse * 0.08)


func bind_player(player: Node) -> void:
	if _player == player:
		_refresh_inventory()
		_update_connection_state()
		return

	_disconnect_player()
	_player = player

	if is_instance_valid(_player) and _player.has_signal("inventory_changed"):
		var callback := Callable(self, "_on_inventory_changed")

		if not _player.is_connected("inventory_changed", callback):
			_player.connect("inventory_changed", callback)

	_refresh_inventory()
	_refresh_market_view()
	_update_connection_state()


func bind_local_items(entries: Array[Dictionary]) -> void:
	_local_item_entries.clear()

	for entry in entries:
		_local_item_entries.append(entry.duplicate(true))

	_use_local_items = true
	_refresh_inventory()


func bind_market_manager(manager: Node) -> void:
	if _market_manager == manager:
		_refresh_market_view()
		return

	_disconnect_market_manager()
	_market_manager = manager

	if is_instance_valid(_market_manager):
		var state_callback := Callable(self, "_on_market_state_changed")
		var sale_callback := Callable(self, "_on_sale_completed")

		if (
			_market_manager.has_signal("market_state_changed")
			and not _market_manager.is_connected(
				"market_state_changed",
				state_callback
			)
		):
			_market_manager.connect(
				"market_state_changed",
				state_callback
			)

		if (
			_market_manager.has_signal("sale_completed")
			and not _market_manager.is_connected(
				"sale_completed",
				sale_callback
			)
		):
			_market_manager.connect("sale_completed", sale_callback)

	_refresh_market_view()
	_update_connection_state()


func _auto_bind() -> void:
	if not is_instance_valid(_market_manager):
		bind_market_manager(
			get_tree().get_first_node_in_group(&"darknet_market_manager")
		)

	if not is_instance_valid(_player):
		bind_player(
			get_tree().get_first_node_in_group(&"local_player_controller")
		)


func _on_inventory_changed(
	_items: Array[ItemData],
	_selected_index: int
) -> void:
	_refresh_inventory()


func _on_market_state_changed(_snapshot: Dictionary) -> void:
	_refresh_market_view()


func _on_sale_completed(
	owner_peer_id: int,
	listing_id: String,
	payout: int,
	wallet: int
) -> void:
	if owner_peer_id != _get_local_peer_id():
		return

	_write_log(
		"[color=#5dff78]sale complete[/color] // %s // +$%d // wallet $%d"
		% [_short_id(listing_id), payout, wallet]
	)


func _refresh_inventory() -> void:
	var previous_instance_id := _selected_instance_id
	_inventory_entries.clear()
	inventory_list.clear()
	_selected_instance_id = ""

	if not is_instance_valid(_player):
		inventory_list.add_item("KEIN SPIELER VERBUNDEN")
		inventory_list.set_item_disabled(0, true)
		inventory_count.text = "0"
		_clear_item_view()
		return

	var reserved_ids := _get_reserved_instance_ids()

	if _use_local_items:
		for source_entry in _local_item_entries:
			var instance_id := str(source_entry.get("instance_id", ""))

			if instance_id.is_empty():
				continue

			var entry := source_entry.duplicate(true)
			var reserved := instance_id in reserved_ids
			entry["reserved"] = reserved
			_inventory_entries.append(entry)
			_add_inventory_list_entry(entry, "VAN", previous_instance_id)
	else:
		var item_value: Variant = _player.get("inventory")
		var items: Array = item_value as Array if item_value is Array else []
		var instance_ids := _get_player_instance_ids()

		for slot_index in range(items.size()):
			var item_data := items[slot_index] as ItemData

			if item_data == null or item_data.is_mission_clue:
				continue

			var instance_id := (
				instance_ids[slot_index]
				if slot_index < instance_ids.size()
				else ""
			)

			if instance_id.is_empty():
				continue

			var entry := {
				"slot_index": slot_index,
				"instance_id": instance_id,
				"resource_path": item_data.resource_path,
				"name": item_data.display_name,
				"value": maxi(item_data.value, 0),
				"icon": item_data.icon,
				"source": "PLAYER",
				"reserved": instance_id in reserved_ids,
			}
			_inventory_entries.append(entry)
			_add_inventory_list_entry(
				entry,
				"SLOT %d" % (slot_index + 1),
				previous_instance_id
			)

	inventory_count.text = str(_inventory_entries.size())

	if _inventory_entries.is_empty():
		inventory_list.add_item(
			"KEINE WARE IM VAN"
			if _use_local_items
			else "KEINE VERKÄUFLICHE WARE"
		)
		inventory_list.set_item_disabled(0, true)

	if _selected_instance_id.is_empty():
		_clear_item_view()
	else:
		_show_inventory_entry(_find_inventory_entry(_selected_instance_id))


func _add_inventory_list_entry(
	entry: Dictionary,
	location_label: String,
	previous_instance_id: String
) -> void:
	var instance_id := str(entry.get("instance_id", ""))
	var reserved := bool(entry.get("reserved", false))
	var suffix := "  [RESERVIERT]" if reserved else ""
	var display_text := "%s  //  %s  //  $%d%s" % [
		location_label,
		str(entry.get("name", "ITEM")).to_upper(),
		maxi(int(entry.get("value", 0)), 0),
		suffix,
	]
	var icon := entry.get("icon") as Texture2D
	var list_index := inventory_list.add_item(display_text, icon)
	inventory_list.set_item_metadata(list_index, entry)
	inventory_list.set_item_disabled(list_index, reserved)

	if reserved:
		inventory_list.set_item_custom_fg_color(
			list_index,
			Color(0.36, 0.43, 0.38)
		)

	if instance_id == previous_instance_id and not reserved:
		inventory_list.select(list_index)
		_selected_instance_id = instance_id


func _on_inventory_selected(index: int) -> void:
	var metadata: Variant = inventory_list.get_item_metadata(index)

	if not metadata is Dictionary:
		return

	var entry := metadata as Dictionary

	if bool(entry.get("reserved", false)):
		return

	_selected_instance_id = str(entry.get("instance_id", ""))
	_show_inventory_entry(entry)

	if (
		str(entry.get("source", "")) == "PLAYER"
		and is_instance_valid(_player)
		and _player.has_method("select_inventory_item")
	):
		_player.call("select_inventory_item", int(entry.get("slot_index", -1)))


func _show_inventory_entry(entry: Dictionary) -> void:
	if entry.is_empty():
		_clear_item_view()
		return

	selected_item_label.text = str(entry.get("name", "UNBEKANNT")).to_upper()
	instance_label.text = "INSTANCE  #%s" % _short_id(
		str(entry.get("instance_id", ""))
	)
	base_value_label.text = "BASISWERT  $%d" % int(entry.get("value", 0))
	price_box.value = maxi(int(entry.get("value", 1)), 1)
	reserved_hint.visible = bool(entry.get("reserved", false))
	_refresh_market_hint(price_box.value)
	_update_list_button_state()


func _clear_item_view() -> void:
	_selected_instance_id = ""
	selected_item_label.text = "KEIN ITEM AUSGEWÄHLT"
	instance_label.text = "INSTANCE  #--------"
	base_value_label.text = "BASISWERT  $0"
	market_hint.text = "MARKTINTERESSE  ---"
	reserved_hint.visible = false
	_update_list_button_state()


func _refresh_market_hint(_value: float) -> void:
	var entry := _find_inventory_entry(_selected_instance_id)

	if entry.is_empty():
		market_hint.text = "MARKTINTERESSE  ---"
		return

	var base := maxf(float(entry.get("value", 1)), 1.0)
	var ratio := float(price_box.value) / base

	if ratio <= 0.75:
		market_hint.text = "MARKTINTERESSE  EXTREM // SCHNELLE OFFERS"
		market_hint.modulate = Color(0.35, 1.0, 0.48)
	elif ratio <= 1.0:
		market_hint.text = "MARKTINTERESSE  HOCH"
		market_hint.modulate = Color(0.35, 1.0, 0.48)
	elif ratio <= 1.35:
		market_hint.text = "MARKTINTERESSE  NORMAL"
		market_hint.modulate = Color(0.72, 0.9, 0.74)
	elif ratio <= 1.75:
		market_hint.text = "MARKTINTERESSE  NIEDRIG"
		market_hint.modulate = Color(1.0, 0.66, 0.18)
	else:
		market_hint.text = "MARKTINTERESSE  SEHR NIEDRIG // LANGE WARTEZEIT"
		market_hint.modulate = Color(1.0, 0.38, 0.2)


func _publish_listing() -> void:
	var entry := _find_inventory_entry(_selected_instance_id)

	if (
		entry.is_empty()
		or bool(entry.get("reserved", false))
		or not is_instance_valid(_market_manager)
		or not _market_manager.has_method("request_publish_listing")
	):
		_write_log("request rejected // item or secure relay unavailable")
		return

	_market_manager.call(
		"request_publish_listing",
		str(entry.get("instance_id", "")),
		str(entry.get("resource_path", "")),
		int(price_box.value)
	)
	list_button.disabled = true
	_write_log(
		"listing request // %s // ask $%d"
		% [str(entry.get("name", "ITEM")), int(price_box.value)]
	)


func _refresh_market_view() -> void:
	_listings.clear()

	if (
		is_instance_valid(_market_manager)
		and _market_manager.has_method("get_listings_for_peer")
	):
		var result: Variant = _market_manager.call(
			"get_listings_for_peer",
			_get_local_peer_id()
		)

		if result is Array:
			for listing_value in result:
				if listing_value is Dictionary:
					_listings.append(
						(listing_value as Dictionary).duplicate(true)
					)

	_track_listing_transitions()
	_refresh_inventory()
	_refresh_listings()
	_refresh_inbox()
	_refresh_delivery_banner()
	_refresh_wallet()
	_update_connection_state()
	_has_initial_market_state = true


func _refresh_listings() -> void:
	for child in listings_container.get_children():
		child.free()

	var active_count := 0

	for listing in _listings:
		var status := str(listing.get("status", ""))

		if status in ACTIVE_STATUSES:
			active_count += 1

		var row := LISTING_ROW.new() as DarknetListingRow
		row.setup(listing)
		listings_container.add_child(row)

	listings_count.text = "%d AKTIV  //  %d GESAMT" % [
		active_count,
		_listings.size(),
	]
	empty_listings.visible = _listings.is_empty()


func _refresh_inbox() -> void:
	var previous_offer_id := _selected_offer_id
	_selected_offer_id = ""
	inbox_list.clear()
	var offers: Array[Dictionary] = []

	for listing in _listings:
		if str(listing.get("status", "")) == "OFFER_RECEIVED":
			offers.append(listing)

	inbox_count.text = str(offers.size())

	for listing in offers:
		var list_index := inbox_list.add_item(
			"%s\n%s  //  $%d" % [
				str(listing.get("buyer", "ANON")).to_upper(),
				str(listing.get("name", "ITEM")).to_upper(),
				int(listing.get("offer_price", 0)),
			]
		)
		var listing_id := str(listing.get("id", ""))
		inbox_list.set_item_metadata(list_index, listing_id)

		if listing_id == previous_offer_id:
			inbox_list.select(list_index)
			_selected_offer_id = listing_id

	if offers.is_empty():
		inbox_list.add_item("KEINE UNGELESENEN OFFERS")
		inbox_list.set_item_disabled(0, true)
		_clear_offer_view()
	elif _selected_offer_id.is_empty():
		_clear_offer_view()
	else:
		_show_offer(_find_listing(_selected_offer_id))


func _on_offer_selected(index: int) -> void:
	var metadata: Variant = inbox_list.get_item_metadata(index)

	if not metadata is String:
		return

	_selected_offer_id = str(metadata)
	_show_offer(_find_listing(_selected_offer_id))


func _show_offer(listing: Dictionary) -> void:
	if listing.is_empty():
		_clear_offer_view()
		return

	var buyer := str(listing.get("buyer", "ANON"))
	var item_name := str(listing.get("name", "ITEM"))
	var payout := int(listing.get("offer_price", 0))
	buyer_label.text = "%s  //  VERIFIED ROUTE" % buyer.to_upper()
	offer_value.text = "$%d" % payout
	counter_box.value = maxi(int(listing.get("asking_price", payout)), 1)
	buyer_message.text = (
		"[color=#55ff75]ENCRYPTED MESSAGE[/color]\n\n"
		+ "Ich will [color=#d8ffe0]%s[/color].\n"
		+ "Mein Preis: [color=#ffb52f]$%d[/color].\n\n"
		+ "Bei Zustimmung Ware physisch in die markierte Zone legen."
	) % [item_name, payout]
	accept_button.disabled = false
	counter_button.disabled = false
	decline_button.disabled = false


func _clear_offer_view() -> void:
	_selected_offer_id = ""
	buyer_label.text = "KEINE NACHRICHT AUSGEWÄHLT"
	buyer_message.text = "Wähle links eine eingehende Offer aus."
	offer_value.text = "$0"
	accept_button.disabled = true
	counter_button.disabled = true
	decline_button.disabled = true


func _accept_offer() -> void:
	_request_offer_action("request_accept_offer")


func _decline_offer() -> void:
	_request_offer_action("request_decline_offer")


func _send_counter() -> void:
	if not _can_request_offer_action("request_counter_offer"):
		return

	_market_manager.call(
		"request_counter_offer",
		_selected_offer_id,
		int(counter_box.value)
	)
	_set_offer_buttons_disabled(true)
	_write_log("counter transmitted // $%d" % int(counter_box.value))


func _request_offer_action(method_name: String) -> void:
	if not _can_request_offer_action(method_name):
		return

	_market_manager.call(method_name, _selected_offer_id)
	_set_offer_buttons_disabled(true)


func _can_request_offer_action(method_name: String) -> bool:
	return (
		not _selected_offer_id.is_empty()
		and is_instance_valid(_market_manager)
		and _market_manager.has_method(method_name)
	)


func _set_offer_buttons_disabled(disabled: bool) -> void:
	accept_button.disabled = disabled
	counter_button.disabled = disabled
	decline_button.disabled = disabled


func _refresh_delivery_banner() -> void:
	var pending: Array[Dictionary] = []

	for listing in _listings:
		if str(listing.get("status", "")) == "DELIVERY_REQUIRED":
			pending.append(listing)

	delivery_banner.visible = not pending.is_empty()
	delivery_state_label.text = (
		"%d LIEFERUNG AUSSTEHEND" % pending.size()
		if not pending.is_empty()
		else "KEINE AKTIVE LIEFERUNG"
	)
	delivery_state_label.modulate = (
		Color(1.0, 0.36, 0.2)
		if not pending.is_empty()
		else Color(0.28, 0.58, 0.34)
	)

	if pending.is_empty():
		return

	var listing := pending[0]
	delivery_title.text = "PREIS BESTÄTIGT // WARE JETZT LIEFERN"
	delivery_detail.text = (
		"%s  //  ITEM #%s  //  TERMINAL MIT [ESC/E] VERLASSEN, DANN [G] IN DIE MARKIERTE ZONE"
		% [
			str(listing.get("name", "ITEM")).to_upper(),
			_short_id(str(listing.get("item_instance_id", ""))),
		]
	)
	delivery_payout.text = "$%d\nPENDING" % int(
		listing.get("offer_price", 0)
	)


func _refresh_wallet() -> void:
	var wallet := 0

	if (
		is_instance_valid(_market_manager)
		and _market_manager.has_method("get_wallet_for_peer")
	):
		wallet = int(_market_manager.call(
			"get_wallet_for_peer",
			_get_local_peer_id()
		))

	wallet_label.text = "$%d" % maxi(wallet, 0)


func _track_listing_transitions() -> void:
	var next_cache: Dictionary = {}

	for listing in _listings:
		var listing_id := str(listing.get("id", ""))
		var status := str(listing.get("status", ""))
		var previous_status := str(_status_cache.get(listing_id, ""))
		next_cache[listing_id] = status

		if status == previous_status:
			continue

		if not _has_initial_market_state and previous_status.is_empty():
			if status == "DELIVERY_REQUIRED":
				_equip_instance(str(listing.get("item_instance_id", "")))
			continue

		match status:
			"LISTED":
				_write_log("listing online // %s" % listing.get("name", "ITEM"))
			"OFFER_RECEIVED":
				_write_log(
					"[color=#ffb52f]incoming offer[/color] // %s // $%d"
					% [listing.get("buyer", "ANON"), listing.get("offer_price", 0)]
				)
			"COUNTER_SENT":
				_write_log("counter routed through dead channel")
			"DELIVERY_REQUIRED":
				_write_log(
					"[color=#ff5a38]price accepted[/color] // physical delivery required"
				)
				_equip_instance(str(listing.get("item_instance_id", "")))
			"DECLINED":
				_write_log("offer declined // reservation released")
			"SOLD":
				_write_log("item authenticated in drop zone")

	_status_cache = next_cache


func _equip_instance(item_instance_id: String) -> void:
	if not is_instance_valid(_player):
		return

	var ids := _get_player_instance_ids()
	var slot_index := ids.find(item_instance_id)

	if slot_index >= 0 and _player.has_method("select_inventory_item"):
		_player.call("select_inventory_item", slot_index)


func _update_connection_state() -> void:
	var online := (
		is_instance_valid(_player)
		and is_instance_valid(_market_manager)
	)
	connection_label.text = (
		"SECURE RELAY ONLINE  //  PEER %s  //  SERVER VERIFIED"
		% _get_local_peer_id()
		if online
		else "RELAY OFFLINE  //  AUTHENTICATION REQUIRED"
	)
	connection_label.modulate = (
		Color(0.36, 0.88, 0.46)
		if online
		else Color(1.0, 0.32, 0.2)
	)
	connection_dot.text = "●" if online else "○"
	_update_list_button_state()


func _update_list_button_state() -> void:
	if not is_node_ready() or list_button == null:
		return

	var entry := _find_inventory_entry(_selected_instance_id)
	list_button.disabled = (
		entry.is_empty()
		or bool(entry.get("reserved", false))
		or not is_instance_valid(_market_manager)
	)


func _get_player_instance_ids() -> Array[String]:
	var result: Array[String] = []

	if (
		not is_instance_valid(_player)
		or not _player.has_method("get_inventory_instance_ids")
	):
		return result

	var values: Variant = _player.call("get_inventory_instance_ids")

	if values is Array:
		for value in values:
			result.append(str(value))

	return result


func _get_reserved_instance_ids() -> Array[String]:
	var result: Array[String] = []

	if (
		not is_instance_valid(_market_manager)
		or not _market_manager.has_method("get_reserved_instance_ids")
	):
		return result

	var values: Variant

	if (
		_use_local_items
		and _market_manager.has_method("get_all_reserved_instance_ids")
	):
		values = _market_manager.call("get_all_reserved_instance_ids")
	else:
		values = _market_manager.call(
			"get_reserved_instance_ids",
			_get_local_peer_id()
		)

	if values is Array:
		for value in values:
			result.append(str(value))

	return result


func _find_inventory_entry(item_instance_id: String) -> Dictionary:
	for entry in _inventory_entries:
		if str(entry.get("instance_id", "")) == item_instance_id:
			return entry

	return {}


func _find_listing(listing_id: String) -> Dictionary:
	for listing in _listings:
		if str(listing.get("id", "")) == listing_id:
			return listing

	return {}


func _get_local_peer_id() -> int:
	if is_instance_valid(_player):
		return _player.get_multiplayer_authority()

	return multiplayer.get_unique_id()


func _short_id(value: String) -> String:
	return value.right(8).to_upper() if not value.is_empty() else "--------"


func _write_log(message: String) -> void:
	if log == null:
		return

	log.append_text("\n[color=#2ca94b]>[/color] " + message)


func _disconnect_player() -> void:
	if not is_instance_valid(_player) or not _player.has_signal("inventory_changed"):
		return

	var callback := Callable(self, "_on_inventory_changed")

	if _player.is_connected("inventory_changed", callback):
		_player.disconnect("inventory_changed", callback)


func _disconnect_market_manager() -> void:
	if not is_instance_valid(_market_manager):
		return

	var state_callback := Callable(self, "_on_market_state_changed")
	var sale_callback := Callable(self, "_on_sale_completed")

	if _market_manager.is_connected("market_state_changed", state_callback):
		_market_manager.disconnect("market_state_changed", state_callback)

	if _market_manager.is_connected("sale_completed", sale_callback):
		_market_manager.disconnect("sale_completed", sale_callback)


func _exit_tree() -> void:
	_disconnect_player()
	_disconnect_market_manager()


func _create_terminal_theme() -> Theme:
	var ui_theme := Theme.new()
	ui_theme.default_font = TERMINAL_FONT
	ui_theme.default_font_size = 14
	ui_theme.set_color("font_color", "Label", Color(0.66, 0.88, 0.7))
	ui_theme.set_color("font_color", "Button", Color(0.55, 1.0, 0.64))
	ui_theme.set_color("font_hover_color", "Button", Color(0.82, 1.0, 0.86))
	ui_theme.set_color("font_pressed_color", "Button", Color(0.04, 0.12, 0.06))
	ui_theme.set_color("font_disabled_color", "Button", Color(0.25, 0.36, 0.28))
	ui_theme.set_font_size("font_size", "Button", 14)
	ui_theme.set_constant("outline_size", "Label", 2)
	ui_theme.set_color("font_outline_color", "Label", Color(0.0, 0.0, 0.0, 0.75))

	var panel := _style(Color(0.009, 0.025, 0.014, 0.94), Color(0.08, 0.42, 0.16, 0.72), 1)
	panel.content_margin_left = 8.0
	panel.content_margin_top = 7.0
	panel.content_margin_right = 8.0
	panel.content_margin_bottom = 7.0
	ui_theme.set_stylebox("panel", "PanelContainer", panel)

	var normal := _style(Color(0.018, 0.09, 0.035, 1.0), Color(0.12, 0.65, 0.25, 0.8), 1)
	var hover := _style(Color(0.035, 0.2, 0.07, 1.0), Color(0.35, 1.0, 0.48, 1.0), 2)
	var pressed := _style(Color(0.35, 1.0, 0.48, 1.0), Color(0.58, 1.0, 0.66, 1.0), 2)
	var disabled := _style(Color(0.018, 0.035, 0.022, 0.8), Color(0.12, 0.22, 0.14, 0.6), 1)
	ui_theme.set_stylebox("normal", "Button", normal)
	ui_theme.set_stylebox("hover", "Button", hover)
	ui_theme.set_stylebox("pressed", "Button", pressed)
	ui_theme.set_stylebox("focus", "Button", hover)
	ui_theme.set_stylebox("disabled", "Button", disabled)

	var list_panel := _style(
		Color(0.004, 0.014, 0.008, 0.96),
		Color(0.06, 0.28, 0.11, 0.9),
		1
	)
	var selected := _style(
		Color(0.04, 0.24, 0.08, 0.95),
		Color(0.28, 1.0, 0.42, 1.0),
		2
	)
	var list_focus := _style(
		Color.TRANSPARENT,
		Color(0.12, 0.65, 0.25, 0.55),
		1
	)
	list_focus.draw_center = false
	ui_theme.set_stylebox("panel", "ItemList", list_panel)
	ui_theme.set_stylebox("selected", "ItemList", selected)
	ui_theme.set_stylebox("selected_focus", "ItemList", selected)
	ui_theme.set_stylebox("focus", "ItemList", list_focus)
	ui_theme.set_color("font_color", "ItemList", Color(0.55, 0.85, 0.61))
	ui_theme.set_color("font_selected_color", "ItemList", Color(0.83, 1.0, 0.87))
	ui_theme.set_constant("line_separation", "ItemList", 8)

	var line_edit := _style(Color(0.005, 0.026, 0.012, 1.0), Color(0.12, 0.55, 0.22, 0.9), 1)
	line_edit.content_margin_left = 8.0
	line_edit.content_margin_right = 8.0
	ui_theme.set_stylebox("normal", "LineEdit", line_edit)
	ui_theme.set_stylebox("focus", "LineEdit", hover)
	ui_theme.set_color("font_color", "LineEdit", Color(0.55, 1.0, 0.64))

	ui_theme.set_stylebox("panel", "TabContainer", list_panel)
	ui_theme.set_stylebox("tab_unselected", "TabContainer", normal)
	ui_theme.set_stylebox("tab_hovered", "TabContainer", hover)
	ui_theme.set_stylebox("tab_selected", "TabContainer", selected)
	ui_theme.set_color("font_selected_color", "TabContainer", Color(0.65, 1.0, 0.72))
	ui_theme.set_color("font_unselected_color", "TabContainer", Color(0.3, 0.58, 0.36))
	ui_theme.set_font_size("font_size", "TabContainer", 14)
	return ui_theme


func _style(
	background: Color,
	border: Color,
	border_width: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.border_color = border
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style
