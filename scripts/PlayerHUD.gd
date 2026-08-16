class_name PlayerHUD
extends CanvasLayer

const PERFORMANCE_UPDATE_INTERVAL := 0.25

@onready var slots: Array[PanelContainer] = [
	$Root/InventoryBar/Slot1,
	$Root/InventoryBar/Slot2,
	$Root/InventoryBar/Slot3,
	$Root/InventoryBar/Slot4
]
@onready var interaction_label: Label = $InteractionUI/Label
@onready var weight_label: Label = $Root/StatusPanel/StatusContent/WeightLabel
@onready var inventory_value_label: Label = $Root/StatusPanel/StatusContent/InventoryValueLabel
@onready var health_label: Label = $Root/StatusPanel/StatusContent/HealthLabel
@onready var health_bar: ProgressBar = $Root/StatusPanel/StatusContent/HealthBar
@onready var stamina_label: Label = $Root/StatusPanel/StatusContent/StaminaLabel
@onready var stamina_bar: ProgressBar = $Root/StatusPanel/StatusContent/StaminaBar
@onready var fps_label: Label = $Root/PerformancePanel/PerformanceContent/FPSLabel
@onready var ping_label: Label = $Root/PerformancePanel/PerformanceContent/PingLabel

var _performance_update_remaining := 0.0


func _ready() -> void:
	clear_inventory_display()
	interaction_label.visible = false
	_update_performance_display()


func _process(delta: float) -> void:
	_performance_update_remaining -= delta

	if _performance_update_remaining > 0.0:
		return

	_performance_update_remaining = PERFORMANCE_UPDATE_INTERVAL
	_update_performance_display()


func _update_performance_display() -> void:
	fps_label.text = "FPS  %d" % Engine.get_frames_per_second()

	var ping_ms := Networking.get_server_ping_ms()

	if ping_ms < 0:
		ping_label.text = "PING  -- MS"
		ping_label.modulate = Color(0.65, 0.7, 0.66, 1.0)
		return

	ping_label.text = "PING  %d MS" % ping_ms

	if ping_ms <= 80:
		ping_label.modulate = Color(0.65, 1.0, 0.7, 1.0)
	elif ping_ms <= 150:
		ping_label.modulate = Color(1.0, 0.86, 0.42, 1.0)
	else:
		ping_label.modulate = Color(1.0, 0.42, 0.35, 1.0)


func bind_player(player: FPSController) -> void:
	if player == null:
		return

	if not player.inventory_changed.is_connected(_on_inventory_changed):
		player.inventory_changed.connect(_on_inventory_changed)

	if not player.stamina_changed.is_connected(_on_stamina_changed):
		player.stamina_changed.connect(_on_stamina_changed)

	if not player.health_changed.is_connected(_on_health_changed):
		player.health_changed.connect(_on_health_changed)

	_on_inventory_changed(
		player.inventory,
		player.selected_inventory_index
	)
	_on_stamina_changed(player.current_stamina, player.maximum_stamina)
	_on_health_changed(player.current_health, player.maximum_health)


func _on_inventory_changed(
	items: Array[ItemData],
	selected_index: int
) -> void:
	for index in range(slots.size()):
		var slot := slots[index]

		var icon := slot.get_node(
			"VBoxContainer/Icon"
		) as TextureRect
		var item_name := slot.get_node(
			"VBoxContainer/ItemName"
		) as Label

		if index < items.size() and items[index] != null:
			icon.texture = items[index].icon
			icon.visible = items[index].icon != null
			item_name.text = items[index].display_name
			slot.tooltip_text = items[index].display_name
		else:
			icon.texture = null
			icon.visible = false
			item_name.text = ""
			slot.tooltip_text = ""

		_update_slot_style(slot, index == selected_index)

	_update_weight_display(items)
	_update_inventory_value_display(items)


func _update_weight_display(items: Array[ItemData]) -> void:
	var total_weight := 0.0

	for item in items:
		if item != null:
			total_weight += maxf(item.weight, 0.0)

	weight_label.text = "GEWICHT  %.2f KG" % total_weight


func _update_inventory_value_display(items: Array[ItemData]) -> void:
	var total_value := 0

	for item in items:
		if item != null:
			total_value += maxi(item.value, 0)

	inventory_value_label.text = "WERT  $%d" % total_value


func _on_stamina_changed(current: float, maximum: float) -> void:
	stamina_bar.max_value = maxf(maximum, 1.0)
	stamina_bar.value = clampf(current, 0.0, stamina_bar.max_value)
	stamina_label.text = "STAMINA  %d / %d" % [
		roundi(current),
		roundi(maximum)
	]


func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maxf(maximum, 1.0)
	health_bar.value = clampf(current, 0.0, health_bar.max_value)
	health_label.text = "LEBEN  %d / %d" % [
		roundi(current),
		roundi(maximum)
	]


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
		var item_name := slot.get_node(
			"VBoxContainer/ItemName"
		) as Label

		icon.texture = null
		icon.visible = false
		item_name.text = ""
		slot.tooltip_text = ""
		slot.modulate = Color(0.55, 0.62, 0.57, 1.0)
