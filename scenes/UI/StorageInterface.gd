class_name StorageInterface
extends CanvasLayer


const PLAYER_SLOT_COUNT := 4
const STORAGE_SLOT_COUNT := 15
const EMPTY_SLOT_COLOR := Color(0.42, 0.5, 0.44, 1.0)
const FILLED_SLOT_COLOR := Color(0.82, 0.96, 0.85, 1.0)
const SLOT_KIND_INVENTORY := &"inventory"
const SLOT_KIND_STORAGE := &"storage"
const TRANSFER_DRAG_TYPE := &"van_storage_item"

@onready var inventory_grid: GridContainer = (
	$Root/Window/Margin/Layout/Content/InventoryPanel/Margin/Section/InventoryGrid
)
@onready var storage_grid: GridContainer = (
	$Root/Window/Margin/Layout/Content/StoragePanel/Margin/Section/StorageGrid
)
@onready var inventory_count: Label = (
	$Root/Window/Margin/Layout/Content/InventoryPanel/Margin/Section/Header/Count
)
@onready var storage_count: Label = (
	$Root/Window/Margin/Layout/Content/StoragePanel/Margin/Section/Header/Count
)
@onready var store_button: Button = (
	$Root/Window/Margin/Layout/Content/Actions/StoreButton
)
@onready var take_button: Button = (
	$Root/Window/Margin/Layout/Content/Actions/TakeButton
)
@onready var close_button: Button = (
	$Root/Window/Margin/Layout/Header/CloseButton
)
@onready var status_label: Label = $Root/Window/Margin/Layout/Status

var _cabinet: Node3D = null
var _player: Node3D = null
var _inventory_buttons: Array[Button] = []
var _storage_buttons: Array[Button] = []
var _selected_inventory_instance_id := ""
var _selected_storage_instance_id := ""


func _ready() -> void:
	_create_slot_buttons()
	store_button.pressed.connect(_store_selected_item)
	take_button.pressed.connect(_take_selected_item)
	close_button.pressed.connect(_close_requested)
	visible = false


func _input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return

	# Das Storage-Fenster ist modal. ESC wird bereits in der normalen
	# Input-Phase verbraucht, bevor das Pause-Menü `_unhandled_input` erhält.
	get_viewport().set_input_as_handled()
	_close_requested()


func open_interface(cabinet: Node3D, player: Node3D) -> void:
	_unbind_sources()
	_cabinet = cabinet
	_player = player
	_selected_inventory_instance_id = ""
	_selected_storage_instance_id = ""
	_bind_sources()
	visible = true
	status_label.text = "ITEM AUSWÄHLEN UND TRANSFERIEREN"
	_refresh()


func close_interface(player: Node3D = null) -> void:
	if player != null and is_instance_valid(_player) and player != _player:
		return

	visible = false
	_selected_inventory_instance_id = ""
	_selected_storage_instance_id = ""
	_unbind_sources()
	_cabinet = null
	_player = null


func is_open_for(player: Node3D) -> bool:
	return visible and is_instance_valid(_player) and _player == player


func _create_slot_buttons() -> void:
	for slot_index in range(PLAYER_SLOT_COUNT):
		var button := _create_slot_button(
			slot_index,
			SLOT_KIND_INVENTORY
		)
		button.pressed.connect(
			_on_inventory_slot_pressed.bind(slot_index)
		)
		inventory_grid.add_child(button)
		_inventory_buttons.append(button)

	for slot_index in range(STORAGE_SLOT_COUNT):
		var button := _create_slot_button(
			slot_index,
			SLOT_KIND_STORAGE
		)
		button.pressed.connect(
			_on_storage_slot_pressed.bind(slot_index)
		)
		storage_grid.add_child(button)
		_storage_buttons.append(button)


func _create_slot_button(
	slot_index: int,
	slot_kind: StringName
) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(112.0, 104.0)
	button.toggle_mode = true
	button.clip_text = true
	button.text = "%02d\nLEER" % (slot_index + 1)
	button.tooltip_text = "Leerer Platz"
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", EMPTY_SLOT_COLOR)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.gui_input.connect(
		_on_slot_gui_input.bind(button, slot_kind, slot_index)
	)
	button.set_drag_forwarding(
		_get_slot_drag_data.bind(button, slot_kind),
		_can_drop_slot_data.bind(slot_kind),
		_drop_slot_data.bind(slot_kind)
	)
	return button


func _on_slot_gui_input(
	event: InputEvent,
	button: Button,
	slot_kind: StringName,
	slot_index: int
) -> void:
	if (
		not event is InputEventMouseButton
		or event.button_index != MOUSE_BUTTON_LEFT
		or not event.pressed
		or not event.double_click
	):
		return

	var instance_id := str(button.get_meta(&"item_instance_id", ""))

	if instance_id.is_empty():
		button.button_pressed = false
		return

	button.accept_event()

	if slot_kind == SLOT_KIND_INVENTORY:
		_on_inventory_slot_pressed(slot_index)
		_store_selected_item()
	elif slot_kind == SLOT_KIND_STORAGE:
		_on_storage_slot_pressed(slot_index)
		_take_selected_item()


func _get_slot_drag_data(
	_at_position: Vector2,
	button: Button,
	source_kind: StringName
) -> Variant:
	var instance_id := str(button.get_meta(&"item_instance_id", ""))

	if instance_id.is_empty():
		return null

	var preview := Button.new()
	preview.custom_minimum_size = Vector2(180.0, 58.0)
	preview.text = button.text.replace("\n", "  ")
	preview.icon = button.icon
	preview.disabled = true
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.set_drag_preview(preview)

	return {
		"drag_type": TRANSFER_DRAG_TYPE,
		"source_kind": source_kind,
		"item_instance_id": instance_id,
		"item_resource_path": str(
			button.get_meta(&"item_resource_path", "")
		),
	}


func _can_drop_slot_data(
	_at_position: Vector2,
	data: Variant,
	target_kind: StringName
) -> bool:
	if not data is Dictionary:
		return false

	var drag_data := data as Dictionary
	var source_kind := StringName(str(drag_data.get("source_kind", "")))
	var instance_id := str(drag_data.get("item_instance_id", ""))

	if (
		StringName(str(drag_data.get("drag_type", "")))
		!= TRANSFER_DRAG_TYPE
		or source_kind == target_kind
		or instance_id.is_empty()
	):
		return false

	if target_kind == SLOT_KIND_STORAGE:
		return (
			source_kind == SLOT_KIND_INVENTORY
			and not _find_inventory_item_path(instance_id).is_empty()
			and _get_storage_size() < STORAGE_SLOT_COUNT
		)

	if target_kind == SLOT_KIND_INVENTORY:
		return (
			source_kind == SLOT_KIND_STORAGE
			and _storage_contains(instance_id)
			and _get_inventory_size() < PLAYER_SLOT_COUNT
		)

	return false


func _drop_slot_data(
	at_position: Vector2,
	data: Variant,
	target_kind: StringName
) -> void:
	if not _can_drop_slot_data(at_position, data, target_kind):
		return

	var drag_data := data as Dictionary
	var source_kind := StringName(str(drag_data.get("source_kind", "")))
	var instance_id := str(drag_data.get("item_instance_id", ""))

	if (
		source_kind == SLOT_KIND_INVENTORY
		and target_kind == SLOT_KIND_STORAGE
	):
		_selected_inventory_instance_id = instance_id
		_selected_storage_instance_id = ""
		_store_selected_item()
	elif (
		source_kind == SLOT_KIND_STORAGE
		and target_kind == SLOT_KIND_INVENTORY
	):
		_selected_storage_instance_id = instance_id
		_selected_inventory_instance_id = ""
		_take_selected_item()


func _bind_sources() -> void:
	if is_instance_valid(_player) and _player.has_signal("inventory_changed"):
		var callback := Callable(self, "_on_inventory_changed")

		if not _player.is_connected("inventory_changed", callback):
			_player.connect("inventory_changed", callback)

	if is_instance_valid(_cabinet):
		var storage_callback := Callable(self, "_on_storage_changed")
		var failure_callback := Callable(self, "_on_operation_failed")

		if not _cabinet.is_connected("storage_changed", storage_callback):
			_cabinet.connect("storage_changed", storage_callback)

		if not _cabinet.is_connected("operation_failed", failure_callback):
			_cabinet.connect("operation_failed", failure_callback)


func _unbind_sources() -> void:
	if is_instance_valid(_player) and _player.has_signal("inventory_changed"):
		var callback := Callable(self, "_on_inventory_changed")

		if _player.is_connected("inventory_changed", callback):
			_player.disconnect("inventory_changed", callback)

	if is_instance_valid(_cabinet):
		var storage_callback := Callable(self, "_on_storage_changed")
		var failure_callback := Callable(self, "_on_operation_failed")

		if _cabinet.is_connected("storage_changed", storage_callback):
			_cabinet.disconnect("storage_changed", storage_callback)

		if _cabinet.is_connected("operation_failed", failure_callback):
			_cabinet.disconnect("operation_failed", failure_callback)


func _refresh() -> void:
	_refresh_inventory_slots()
	_refresh_storage_slots()
	_refresh_actions()


func _refresh_inventory_slots() -> void:
	var items: Array = []
	var instance_ids: Array[String] = []

	if is_instance_valid(_player):
		var inventory_value: Variant = _player.get("inventory")

		if inventory_value is Array:
			items = inventory_value

		if _player.has_method("get_inventory_instance_ids"):
			var id_value: Variant = _player.call("get_inventory_instance_ids")

			if id_value is Array:
				for id in id_value:
					instance_ids.append(str(id))

	inventory_count.text = "%d / %d" % [items.size(), PLAYER_SLOT_COUNT]

	for slot_index in range(_inventory_buttons.size()):
		var button := _inventory_buttons[slot_index]
		var data := items[slot_index] as ItemData if slot_index < items.size() else null
		var instance_id := (
			instance_ids[slot_index]
			if slot_index < instance_ids.size()
			else ""
		)
		_update_slot_button(button, slot_index, data, instance_id)
		button.button_pressed = (
			not instance_id.is_empty()
			and instance_id == _selected_inventory_instance_id
		)

	if (
		not _selected_inventory_instance_id.is_empty()
		and _selected_inventory_instance_id not in instance_ids
	):
		_selected_inventory_instance_id = ""


func _refresh_storage_slots() -> void:
	var entries: Array[Dictionary] = []

	if is_instance_valid(_cabinet):
		var entries_value: Variant = _cabinet.call("get_storage_entries")

		if entries_value is Array:
			entries.assign(entries_value)

	storage_count.text = "%d / %d" % [entries.size(), STORAGE_SLOT_COUNT]
	var instance_ids: Array[String] = []

	for slot_index in range(_storage_buttons.size()):
		var button := _storage_buttons[slot_index]
		var data: ItemData = null
		var instance_id := ""

		if slot_index < entries.size():
			var entry := entries[slot_index]
			data = entry.get("item_data") as ItemData
			instance_id = str(entry.get("item_instance_id", ""))
			instance_ids.append(instance_id)

		_update_slot_button(button, slot_index, data, instance_id)
		button.button_pressed = (
			not instance_id.is_empty()
			and instance_id == _selected_storage_instance_id
		)

	if (
		not _selected_storage_instance_id.is_empty()
		and _selected_storage_instance_id not in instance_ids
	):
		_selected_storage_instance_id = ""


func _update_slot_button(
	button: Button,
	slot_index: int,
	data: ItemData,
	instance_id: String
) -> void:
	button.set_meta(&"item_instance_id", instance_id)
	button.set_meta(
		&"item_resource_path",
		data.resource_path if data != null else ""
	)
	# Leere Buttons bleiben aktiv, damit sie als Drop-Ziele funktionieren.
	button.disabled = false
	button.icon = data.icon if data != null else null
	button.text = (
		"%02d\n%s" % [slot_index + 1, data.display_name]
		if data != null
		else "%02d\nLEER" % (slot_index + 1)
	)
	button.tooltip_text = (
		"%s\n%.2f kg  |  $%d" % [
			data.display_name,
			data.weight,
			data.value,
		]
		if data != null
		else "Leerer Platz"
	)
	button.add_theme_color_override(
		"font_color",
		FILLED_SLOT_COLOR if data != null else EMPTY_SLOT_COLOR
	)


func _on_inventory_slot_pressed(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _inventory_buttons.size():
		return

	var button := _inventory_buttons[slot_index]
	var instance_id := str(button.get_meta(&"item_instance_id", ""))

	if instance_id.is_empty():
		button.set_pressed_no_signal(false)
		return

	_selected_inventory_instance_id = instance_id
	_selected_storage_instance_id = ""
	status_label.text = "BEREIT ZUM EINLAGERN"
	_refresh()


func _on_storage_slot_pressed(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _storage_buttons.size():
		return

	var button := _storage_buttons[slot_index]
	var instance_id := str(button.get_meta(&"item_instance_id", ""))

	if instance_id.is_empty():
		button.set_pressed_no_signal(false)
		return

	_selected_storage_instance_id = instance_id
	_selected_inventory_instance_id = ""
	status_label.text = "BEREIT ZUM ENTNEHMEN"
	_refresh()


func _store_selected_item() -> void:
	if (
		not is_instance_valid(_cabinet)
		or not is_instance_valid(_player)
		or _selected_inventory_instance_id.is_empty()
	):
		return

	var item_path := _find_inventory_item_path(
		_selected_inventory_instance_id
	)

	if item_path.is_empty():
		status_label.text = "ITEM NICHT MEHR IM INVENTAR"
		return

	status_label.text = "TRANSFER WIRD GEPRÜFT ..."
	_cabinet.call(
		"request_store_item",
		_player,
		_selected_inventory_instance_id,
		item_path
	)


func _take_selected_item() -> void:
	if (
		not is_instance_valid(_cabinet)
		or not is_instance_valid(_player)
		or _selected_storage_instance_id.is_empty()
	):
		return

	status_label.text = "TRANSFER WIRD GEPRÜFT ..."
	_cabinet.call(
		"request_take_item",
		_player,
		_selected_storage_instance_id
	)


func _find_inventory_item_path(item_instance_id: String) -> String:
	if not is_instance_valid(_player):
		return ""

	var inventory_value: Variant = _player.get("inventory")
	var ids_value: Variant = _player.call("get_inventory_instance_ids")

	if not inventory_value is Array or not ids_value is Array:
		return ""

	for item_index in range(mini(inventory_value.size(), ids_value.size())):
		if str(ids_value[item_index]) != item_instance_id:
			continue

		var data := inventory_value[item_index] as ItemData
		return data.resource_path if data != null else ""

	return ""


func _get_inventory_size() -> int:
	if not is_instance_valid(_player):
		return 0

	var inventory_value: Variant = _player.get("inventory")
	return inventory_value.size() if inventory_value is Array else 0


func _get_storage_size() -> int:
	if not is_instance_valid(_cabinet):
		return 0

	var entries_value: Variant = _cabinet.call("get_storage_entries")
	return entries_value.size() if entries_value is Array else 0


func _storage_contains(item_instance_id: String) -> bool:
	if not is_instance_valid(_cabinet):
		return false

	var entries_value: Variant = _cabinet.call("get_storage_entries")

	if not entries_value is Array:
		return false

	for entry_value in entries_value:
		if (
			entry_value is Dictionary
			and str(entry_value.get("item_instance_id", ""))
			== item_instance_id
		):
			return true

	return false


func _refresh_actions() -> void:
	var storage_size := _get_storage_size()
	var inventory_size := _get_inventory_size()
	store_button.disabled = (
		_selected_inventory_instance_id.is_empty()
		or storage_size >= STORAGE_SLOT_COUNT
	)
	take_button.disabled = (
		_selected_storage_instance_id.is_empty()
		or inventory_size >= PLAYER_SLOT_COUNT
	)


func _on_inventory_changed(
	_items: Array[ItemData],
	_selected_index: int
) -> void:
	_refresh()


func _on_storage_changed() -> void:
	status_label.text = "VAN-LAGER AKTUALISIERT"
	_refresh()


func _on_operation_failed(message: String) -> void:
	status_label.text = message.to_upper()
	_refresh_actions()


func _close_requested() -> void:
	if (
		is_instance_valid(_player)
		and _player.has_method("exit_cabinet_storage")
	):
		_player.call("exit_cabinet_storage")
