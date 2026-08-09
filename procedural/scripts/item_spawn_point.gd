class_name ItemSpawnPoint
extends Marker3D


@export var spawn_enabled: bool = true
@export var spawn_table: ItemSpawnTable

@export_group("Surface Placement")
@export var snap_to_surface: bool = true

@export_flags_3d_physics
var surface_collision_mask: int = 1

@export_range(0.0, 5.0, 0.05)
var ray_start_height: float = 0.5

@export_range(0.1, 10.0, 0.05)
var ray_distance: float = 2.0

@export_group("Rotation")
@export var random_y_rotation: bool = true
