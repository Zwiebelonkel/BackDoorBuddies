extends Node

const IDLE_ANIMATION := &"Idle"
const WALK_ANIMATION := &"Walk"
const RUN_ANIMATION := &"Running"
const WAVE_ANIMATION := &"Waving"

const UAL_LIBRARY_NAME := &"ual"
const CROUCH_IDLE_ANIMATION := &"ual/Crouch_Idle"
const CROUCH_WALK_ANIMATION := &"ual/Crouch_Fwd"
const SPRINT_ANIMATION := &"ual/Sprint"
const JUMP_ANIMATION := &"ual/Jump"
const DRIVING_ANIMATION := &"ual/Driving"
const PISTOL_IDLE_ANIMATION := &"ual/Pistol_Idle"
const SWORD_IDLE_ANIMATION := &"ual/Sword_Idle"

const PISTOL_ITEM_PATH := "res://resources/items/1911.tres"
const SNIPER_ITEM_PATH := "res://resources/items/sniper.tres"
const KNIFE_ITEM_PATH := "res://resources/items/knife.tres"

const UAL_SCENE: PackedScene = preload(
	"res://Animations/Universal Animation Library[Standard]/Unreal-Godot/UAL1_Standard.glb"
)

const LOCOMOTION_ANIMATIONS: Array[StringName] = [
	IDLE_ANIMATION,
	WALK_ANIMATION,
	RUN_ANIMATION,
	CROUCH_IDLE_ANIMATION,
	CROUCH_WALK_ANIMATION,
	SPRINT_ANIMATION,
	JUMP_ANIMATION,
	DRIVING_ANIMATION,
	PISTOL_IDLE_ANIMATION,
	SWORD_IDLE_ANIMATION,
]

const LOOPING_ANIMATIONS: Array[StringName] = [
	IDLE_ANIMATION,
	WALK_ANIMATION,
	RUN_ANIMATION,
	CROUCH_IDLE_ANIMATION,
	CROUCH_WALK_ANIMATION,
	SPRINT_ANIMATION,
	DRIVING_ANIMATION,
	PISTOL_IDLE_ANIMATION,
	SWORD_IDLE_ANIMATION,
]

@export_node_path("CharacterBody3D") var player_path := NodePath("..")
@export_node_path("Node3D") var model_root_path := NodePath("../playerModell")
@export_range(0.0, 1.0, 0.01) var transition_duration := 0.2
@export_range(0.0, 2.0, 0.05) var movement_threshold := 0.15

static var _shared_ual_library: AnimationLibrary

var _player: FPSController
var _animation_player: AnimationPlayer
var _locomotion_animation := IDLE_ANIMATION
var _active_action: StringName = &""
var _queued_action: StringName = &""
var _ragdoll_active := false


func _ready() -> void:
	_player = get_node_or_null(player_path) as FPSController
	call_deferred("_setup_animation_player")


func _process(_delta: float) -> void:
	if (
		_ragdoll_active
		or _player == null
		or not _player.is_multiplayer_authority()
	):
		return

	set_locomotion_state(_get_local_locomotion_animation())


func set_locomotion_state(animation_name: StringName) -> void:
	var valid_animation := _sanitize_locomotion_animation(animation_name)
	var locomotion_changed := _locomotion_animation != valid_animation

	_locomotion_animation = valid_animation

	if not _active_action.is_empty():
		if _active_action == WAVE_ANIMATION and valid_animation != IDLE_ANIMATION:
			_active_action = &""
			_play_animation(_locomotion_animation)

		return

	if locomotion_changed:
		_play_animation(_locomotion_animation)


func get_locomotion_state() -> StringName:
	return _locomotion_animation


func play_wave() -> void:
	if _locomotion_animation != IDLE_ANIMATION:
		return

	play_action(WAVE_ANIMATION)


func play_action(animation_name: StringName) -> void:
	if _ragdoll_active or not _is_valid_action_animation(animation_name):
		return

	if _animation_player == null:
		_queued_action = animation_name
		return

	if not _animation_player.has_animation(animation_name):
		push_warning("Player-Animation '%s' fehlt." % animation_name)
		return

	_active_action = animation_name
	_queued_action = &""
	_play_animation(animation_name, true)


func has_animation(animation_name: StringName) -> bool:
	return (
		_animation_player != null
		and _animation_player.has_animation(animation_name)
	)


func get_ual_animation_names() -> PackedStringArray:
	var result := PackedStringArray()

	if _animation_player == null:
		return result

	for animation_name in _animation_player.get_animation_list():
		if String(animation_name).begins_with("%s/" % UAL_LIBRARY_NAME):
			result.append(String(animation_name))

	return result


func set_ragdoll_active(active: bool) -> void:
	_ragdoll_active = active
	_active_action = &""
	_queued_action = &""

	if _animation_player == null:
		return

	if active:
		_animation_player.stop()
	else:
		_play_animation(_locomotion_animation, true)


func _setup_animation_player() -> void:
	var model_root := get_node_or_null(model_root_path)

	if model_root == null:
		push_warning("Player-Modell für Animationen wurde nicht gefunden.")
		return

	_animation_player = model_root.find_child(
		"AnimationPlayer",
		true,
		false
	) as AnimationPlayer

	if _animation_player == null:
		push_warning("Das Player-Modell besitzt keinen AnimationPlayer.")
		return

	_install_ual_library()
	_configure_loop_modes()

	if not _animation_player.animation_finished.is_connected(
		_on_animation_finished
	):
		_animation_player.animation_finished.connect(_on_animation_finished)

	if not _queued_action.is_empty():
		play_action(_queued_action)
	else:
		_play_animation(_locomotion_animation)


func _install_ual_library() -> void:
	if _animation_player.has_animation_library(UAL_LIBRARY_NAME):
		return

	if _shared_ual_library == null:
		_shared_ual_library = _build_ual_library()

	if _shared_ual_library == null:
		push_warning("Die Universal Animation Library konnte nicht geladen werden.")
		return

	_animation_player.add_animation_library(
		UAL_LIBRARY_NAME,
		_shared_ual_library
	)


func _build_ual_library() -> AnimationLibrary:
	var source_root := UAL_SCENE.instantiate()
	var source_player := source_root.find_child(
		"AnimationPlayer",
		true,
		false
	) as AnimationPlayer

	if source_player == null:
		source_root.free()
		return null

	var library := AnimationLibrary.new()

	for animation_name in source_player.get_animation_list():
		var animation := source_player.get_animation(animation_name)

		if animation == null:
			continue

		var animation_copy := animation.duplicate(true) as Animation
		_normalize_rotation_tracks(animation_copy)
		library.add_animation(
			animation_name,
			animation_copy
		)

	source_root.free()
	return library


func _normalize_rotation_tracks(animation: Animation) -> void:
	for track_index in animation.get_track_count():
		if animation.track_get_type(track_index) != Animation.TYPE_ROTATION_3D:
			continue

		for key_index in animation.track_get_key_count(track_index):
			var rotation := (
				animation.track_get_key_value(track_index, key_index)
				as Quaternion
			)

			if not rotation.is_normalized():
				animation.track_set_key_value(
					track_index,
					key_index,
					rotation.normalized()
				)


func _configure_loop_modes() -> void:
	for animation_name in LOOPING_ANIMATIONS:
		if _animation_player.has_animation(animation_name):
			_animation_player.get_animation(animation_name).loop_mode = (
				Animation.LOOP_LINEAR
			)

	for animation_name in [WAVE_ANIMATION, JUMP_ANIMATION]:
		if _animation_player.has_animation(animation_name):
			_animation_player.get_animation(animation_name).loop_mode = (
				Animation.LOOP_NONE
			)


func _play_animation(animation_name: StringName, restart := false) -> void:
	if _animation_player == null:
		return

	if not _animation_player.has_animation(animation_name):
		push_warning("Player-Animation '%s' fehlt." % animation_name)
		return

	if _animation_player.current_animation == animation_name and not restart:
		return

	_animation_player.play(animation_name, transition_duration)

	if restart:
		_animation_player.seek(0.0, true)


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != _active_action:
		return

	_active_action = &""
	_play_animation(_locomotion_animation)


func _get_local_locomotion_animation() -> StringName:
	if _player.is_driving_vehicle():
		return _available_or_fallback(DRIVING_ANIMATION, IDLE_ANIMATION)

	if not _player.is_on_floor() and absf(_player.velocity.y) > 0.1:
		return _available_or_fallback(JUMP_ANIMATION, IDLE_ANIMATION)

	var horizontal_speed := _player.horizontal_speed()

	if _player.is_crouching():
		if horizontal_speed <= movement_threshold:
			return _available_or_fallback(CROUCH_IDLE_ANIMATION, IDLE_ANIMATION)

		return _available_or_fallback(CROUCH_WALK_ANIMATION, WALK_ANIMATION)

	if horizontal_speed <= movement_threshold:
		var held_idle := _get_held_item_idle_animation()

		if not held_idle.is_empty():
			return held_idle

		return IDLE_ANIMATION

	if _player.is_sprinting():
		return _available_or_fallback(SPRINT_ANIMATION, RUN_ANIMATION)

	return WALK_ANIMATION


func _get_held_item_idle_animation() -> StringName:
	var item_path := _player.equipped_item_resource_path

	if item_path == PISTOL_ITEM_PATH or item_path == SNIPER_ITEM_PATH:
		return _available_or_fallback(PISTOL_IDLE_ANIMATION, IDLE_ANIMATION)

	if item_path == KNIFE_ITEM_PATH:
		return _available_or_fallback(SWORD_IDLE_ANIMATION, IDLE_ANIMATION)

	return &""


func _available_or_fallback(
	animation_name: StringName,
	fallback: StringName
) -> StringName:
	if has_animation(animation_name):
		return animation_name

	return fallback


func _sanitize_locomotion_animation(animation_name: StringName) -> StringName:
	if animation_name in LOCOMOTION_ANIMATIONS and has_animation(animation_name):
		return animation_name

	return IDLE_ANIMATION


func _is_valid_action_animation(animation_name: StringName) -> bool:
	return (
		animation_name == WAVE_ANIMATION
		or String(animation_name).begins_with("%s/" % UAL_LIBRARY_NAME)
	)
