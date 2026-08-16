class_name ItemData
extends Resource

@export_group("Identifikation")
@export var item_id: StringName
@export var display_name: String = "Unbekanntes Item"
@export_multiline var description: String = ""

@export_group("World Model")
@export var world_model: PackedScene
@export var icon: Texture2D
@export var model_scale: Vector3 = Vector3.ONE
@export var model_rotation_degrees: Vector3 = Vector3.ZERO
@export var model_offset: Vector3 = Vector3.ZERO

@export_group("Held Model")
@export var held_model: PackedScene
@export var held_scale: Vector3 = Vector3.ONE
@export var held_rotation_degrees: Vector3 = Vector3.ZERO
@export var held_offset: Vector3 = Vector3.ZERO

@export_group("Gameplay")
@export_range(0, 100_000, 1) var value: int = 0
@export_range(0.0, 100.0, 0.05) var weight: float = 1.0
@export var is_large_item: bool = false
@export var stackable: bool = false
@export var max_stack: int = 1

@export_group("Mission Hint")
@export var is_mission_clue: bool = false
@export var target_clue_type: StringName = &""

@export_group("Pickup")
@export var interaction_text: String = "Aufheben"
@export var pickup_sound: AudioStream
