class_name ItemSpawnEntry
extends Resource


@export var item_id: StringName = &"item"
@export var item_scene: PackedScene

@export_range(0.0, 1000.0, 0.1)
var weight: float = 1.0

@export_range(0.0, 2.0, 0.001)
var vertical_offset: float = 0.03
