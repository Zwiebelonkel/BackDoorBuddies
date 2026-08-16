class_name SurveillanceCamera
extends Node3D


@onready var feed_camera: Camera3D = $FeedCamera

var camera_id: int = 0
var room_generation_index: int = -1
var room_id: StringName = &"room"
var pan_degrees: float = 0.0

@export_range(0.0, 120.0, 1.0)
var maximum_pan_degrees: float = 70.0


func configure(
	new_camera_id: int,
	new_room_generation_index: int,
	new_room_id: StringName
) -> void:
	camera_id = new_camera_id
	room_generation_index = new_room_generation_index
	room_id = new_room_id


func get_feed_transform() -> Transform3D:
	if feed_camera == null:
		return global_transform

	return feed_camera.global_transform


func get_feed_fov() -> float:
	return feed_camera.fov if feed_camera != null else 78.0


func get_display_name() -> String:
	var room_name := String(room_id).replace("_", " ").to_upper()
	return "KAMERA %02d  |  %s" % [camera_id, room_name]


func pan_by_degrees(delta_degrees: float) -> void:
	var next_pan := clampf(
		pan_degrees + delta_degrees,
		-maximum_pan_degrees,
		maximum_pan_degrees
	)
	var applied_delta := next_pan - pan_degrees

	if is_zero_approx(applied_delta):
		return

	pan_degrees = next_pan
	rotate_object_local(Vector3.UP, deg_to_rad(applied_delta))
