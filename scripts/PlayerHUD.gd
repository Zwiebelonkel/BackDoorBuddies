class_name PlayerHUD
extends CanvasLayer

@onready var slots: Array[PanelContainer] = [
	$Root/InventoryBar/Slot1,
	$Root/InventoryBar/Slot2,
	$Root/InventoryBar/Slot3,
	$Root/InventoryBar/Slot4
]


func _ready() -> void:
	clear_inventory_display()


func bind_player(player: FPSController) -> void:
	if player == null:
		return

	if not player.inventory_changed.is_connected(_on_inventory_changed):
		player.inventory_changed.connect(_on_inventory_changed)

	_on_inventory_changed(
		player.inventory,
		player.selected_inventory_index
	)


func _on_inventory_changed(
	items: Array[ItemData],
	selected_index: int
) -> void:
	for index in range(slots.size()):
		var slot := slots[index]

		var icon := slot.get_node(
			"VBoxContainer/Icon"
		) as TextureRect

		if index < items.size() and items[index] != null:
			icon.texture = items[index].icon
			icon.visible = items[index].icon != null
			slot.tooltip_text = items[index].display_name
		else:
			icon.texture = null
			icon.visible = false
			slot.tooltip_text = ""

		_update_slot_style(slot, index == selected_index)


func _update_slot_style(
	slot: PanelContainer,
	is_selected: bool
) -> void:
	if is_selected:
		slot.modulate = Color(0.7, 1.0, 0.75, 1.0)
	else:
		slot.modulate = Color(0.55, 0.62, 0.57, 1.0)


func clear_inventory_display() -> void:
	for slot in slots:
		var icon := slot.get_node(
			"VBoxContainer/Icon"
		) as TextureRect

		icon.texture = null
		icon.visible = false
		slot.modulate = Color(0.55, 0.62, 0.57, 1.0)
