extends Node3D


@onready var viewport: SubViewport = $SubViewport
@onready var screen: MeshInstance3D = $MeshInstance3D
@onready var van_value_label: Label = $SubViewport/Interface/Margin/Content/VanValue
@onready var room_value_label: Label = $SubViewport/Interface/Margin/Content/RoomValue

var _tracker: ItemValueTracker
var _bind_time_remaining := 0.0


func _ready() -> void:
	_configure_screen_material()
	_update_values(0, 0)
	call_deferred("_bind_tracker")


func _process(delta: float) -> void:
	if is_instance_valid(_tracker):
		return

	_bind_time_remaining -= delta

	if _bind_time_remaining <= 0.0:
		_bind_time_remaining = 0.5
		_bind_tracker()


func _bind_tracker() -> void:
	if is_instance_valid(_tracker):
		return

	_tracker = get_tree().get_first_node_in_group(
		&"item_value_tracker"
	) as ItemValueTracker

	if _tracker == null:
		return

	if not _tracker.values_changed.is_connected(_update_values):
		_tracker.values_changed.connect(_update_values)

	_update_values(_tracker.van_value, _tracker.generated_room_value)


func _update_values(van_value: int, generated_room_value: int) -> void:
	van_value_label.text = "$%d" % maxi(van_value, 0)
	room_value_label.text = "$%d" % maxi(generated_room_value, 0)


func _configure_screen_material() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_texture = viewport.get_texture()
	material.emission_enabled = true
	material.emission_texture = viewport.get_texture()
	material.emission_energy_multiplier = 1.35
	material.flags_unshaded = true
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	screen.material_override = material
