extends Node

signal session_started
signal session_cleared
signal mission_started(mission_number: int, difficulty_level: int)
signal mission_completed(completed_missions: int)
signal mission_failed(remaining_chances: int)
signal chances_changed(remaining_chances: int)
signal difficulty_changed(difficulty_level: int, multiplier: float)
signal session_state_changed(snapshot: Dictionary)
signal target_profile_generated(profile: Dictionary, required_clues: int)
signal target_clue_revealed(
	clue_type: StringName,
	value: String,
	revealed_clues: int,
	required_clues: int
)
signal target_progress_changed(revealed_clues: int, required_clues: int)

const INITIAL_CHANCES := 3
const DIFFICULTY_STEP := 0.15
const BASE_MAXIMUM_ROOMS := 30
const MAXIMUM_DIFFICULTY_ROOMS := 50
const ROOMS_PER_DIFFICULTY_LEVEL := 4
const BASE_CAMERA_CHANCE := 0.2
const MAXIMUM_CAMERA_CHANCE := 0.65
const CAMERA_CHANCE_PER_DIFFICULTY_LEVEL := 0.07
const BASE_MINIMUM_CAMERAS := 1
const MAXIMUM_MINIMUM_CAMERAS := 6
const BASE_MAXIMUM_CAMERAS := 4
const MAXIMUM_MAXIMUM_CAMERAS := 12
const TARGET_ATTRIBUTE_ORDER: Array[StringName] = [
	&"age",
	&"hair",
	&"height",
	&"skin_tone",
]
const TARGET_AGES: Array[String] = [
	"23",
	"28",
	"34",
	"41",
	"47",
	"55",
]
const TARGET_HAIR_COLORS: Array[String] = [
	"SCHWARZ",
	"BRAUN",
	"BLOND",
	"ROT",
	"GRAU",
]
const TARGET_HEIGHTS: Array[String] = [
	"165 CM",
	"172 CM",
	"178 CM",
	"184 CM",
	"191 CM",
]
const TARGET_SKIN_TONES: Array[String] = [
	"HELL",
	"MITTEL",
	"DUNKEL",
]

var session_active := false
var remaining_chances := INITIAL_CHANCES
var current_mission_number := 0
var completed_missions := 0
var difficulty_level := 1
var mission_in_progress := false
var last_mission_result := &"none"
var target_code := "----"
var target_profile: Dictionary = {}
var required_target_clues: Array[StringName] = []
var revealed_target_clues: Array[StringName] = []


func start_new_session() -> void:
	if not _can_change_authoritative_state():
		return

	session_active = true
	remaining_chances = INITIAL_CHANCES
	current_mission_number = 0
	completed_missions = 0
	difficulty_level = 1
	mission_in_progress = false
	last_mission_result = &"none"
	_clear_target_profile()

	session_started.emit()
	chances_changed.emit(remaining_chances)
	difficulty_changed.emit(difficulty_level, get_difficulty_multiplier())
	_publish_state()


func clear_session() -> void:
	session_active = false
	remaining_chances = INITIAL_CHANCES
	current_mission_number = 0
	completed_missions = 0
	difficulty_level = 1
	mission_in_progress = false
	last_mission_result = &"none"
	_clear_target_profile()

	session_cleared.emit()
	session_state_changed.emit(get_state_snapshot())


func begin_mission() -> bool:
	if not _can_change_authoritative_state():
		return false

	if not session_active:
		start_new_session()

	if mission_in_progress or remaining_chances <= 0:
		return false

	current_mission_number = completed_missions + 1
	difficulty_level = maxi(current_mission_number, 1)
	mission_in_progress = true
	last_mission_result = &"none"
	_generate_target_profile()

	mission_started.emit(current_mission_number, difficulty_level)
	target_profile_generated.emit(
		target_profile.duplicate(true),
		required_target_clues.size()
	)
	target_progress_changed.emit(0, required_target_clues.size())
	difficulty_changed.emit(difficulty_level, get_difficulty_multiplier())
	_publish_state()
	return true


func complete_mission() -> bool:
	if not _can_change_authoritative_state() or not mission_in_progress:
		return false

	mission_in_progress = false
	completed_missions += 1
	last_mission_result = &"completed"

	mission_completed.emit(completed_missions)
	_publish_state()
	return true


func fail_mission() -> bool:
	if not _can_change_authoritative_state() or not mission_in_progress:
		return false

	mission_in_progress = false
	remaining_chances = maxi(remaining_chances - 1, 0)
	last_mission_result = &"failed"

	mission_failed.emit(remaining_chances)
	chances_changed.emit(remaining_chances)
	_publish_state()
	return true


func has_active_session() -> bool:
	return session_active


func is_session_over() -> bool:
	return session_active and remaining_chances <= 0


func get_difficulty_multiplier() -> float:
	return 1.0 + float(maxi(difficulty_level - 1, 0)) * DIFFICULTY_STEP


func get_target_room_count() -> int:
	return mini(
		BASE_MAXIMUM_ROOMS
		+ maxi(difficulty_level - 1, 0) * ROOMS_PER_DIFFICULTY_LEVEL,
		MAXIMUM_DIFFICULTY_ROOMS
	)


func get_surveillance_camera_chance() -> float:
	return minf(
		BASE_CAMERA_CHANCE
		+ float(maxi(difficulty_level - 1, 0))
		* CAMERA_CHANCE_PER_DIFFICULTY_LEVEL,
		MAXIMUM_CAMERA_CHANCE
	)


func get_minimum_surveillance_cameras() -> int:
	return mini(
		BASE_MINIMUM_CAMERAS + maxi(difficulty_level - 1, 0) / 2,
		MAXIMUM_MINIMUM_CAMERAS
	)


func get_maximum_surveillance_cameras() -> int:
	return mini(
		BASE_MAXIMUM_CAMERAS + maxi(difficulty_level - 1, 0),
		MAXIMUM_MAXIMUM_CAMERAS
	)


func get_required_target_clue_count() -> int:
	if not required_target_clues.is_empty():
		return required_target_clues.size()

	return clampi(
		difficulty_level + 1,
		2,
		TARGET_ATTRIBUTE_ORDER.size()
	)


func get_required_target_clues() -> Array[StringName]:
	return required_target_clues.duplicate()


func get_revealed_target_clues() -> Array[StringName]:
	return revealed_target_clues.duplicate()


func is_target_clue_required(clue_type: StringName) -> bool:
	return clue_type in required_target_clues


func is_target_clue_revealed(clue_type: StringName) -> bool:
	return clue_type in revealed_target_clues


func get_target_attribute_value(clue_type: StringName) -> String:
	if clue_type not in revealed_target_clues:
		return "???"

	return str(target_profile.get(clue_type, "???"))


func is_target_identified() -> bool:
	return (
		not required_target_clues.is_empty()
		and revealed_target_clues.size() >= required_target_clues.size()
	)


func reveal_target_clue(clue_type: StringName) -> bool:
	if (
		not _can_change_authoritative_state()
		or not mission_in_progress
		or clue_type not in required_target_clues
		or clue_type in revealed_target_clues
	):
		return false

	revealed_target_clues.append(clue_type)
	var value := str(target_profile.get(clue_type, "???"))

	target_clue_revealed.emit(
		clue_type,
		value,
		revealed_target_clues.size(),
		required_target_clues.size()
	)
	target_progress_changed.emit(
		revealed_target_clues.size(),
		required_target_clues.size()
	)
	_publish_state()
	return true


func get_state_snapshot() -> Dictionary:
	return {
		"session_active": session_active,
		"remaining_chances": remaining_chances,
		"current_mission_number": current_mission_number,
		"completed_missions": completed_missions,
		"difficulty_level": difficulty_level,
		"mission_in_progress": mission_in_progress,
		"last_mission_result": String(last_mission_result),
		"target_code": target_code,
		"target_profile": target_profile.duplicate(true),
		"required_target_clues": _string_name_array_to_strings(
			required_target_clues
		),
		"revealed_target_clues": _string_name_array_to_strings(
			revealed_target_clues
		),
	}


func apply_authoritative_snapshot(snapshot: Dictionary) -> void:
	var previous_session_active := session_active
	var previous_chances := remaining_chances
	var previous_completed_missions := completed_missions
	var previous_difficulty := difficulty_level
	var previous_mission_in_progress := mission_in_progress
	var previous_target_code := target_code
	var previous_revealed_clues := revealed_target_clues.duplicate()

	session_active = bool(snapshot.get("session_active", false))
	remaining_chances = clampi(
		int(snapshot.get("remaining_chances", INITIAL_CHANCES)),
		0,
		INITIAL_CHANCES
	)
	current_mission_number = maxi(
		int(snapshot.get("current_mission_number", 0)),
		0
	)
	completed_missions = maxi(
		int(snapshot.get("completed_missions", 0)),
		0
	)
	difficulty_level = maxi(
		int(snapshot.get("difficulty_level", 1)),
		1
	)
	mission_in_progress = bool(
		snapshot.get("mission_in_progress", false)
	)
	last_mission_result = StringName(
		str(snapshot.get("last_mission_result", "none"))
	)
	target_code = str(snapshot.get("target_code", "----"))
	target_profile = (
		snapshot.get("target_profile", {}) as Dictionary
	).duplicate(true)
	required_target_clues = _variant_to_string_name_array(
		snapshot.get("required_target_clues", [])
	)
	revealed_target_clues = _variant_to_string_name_array(
		snapshot.get("revealed_target_clues", [])
	)

	if not previous_session_active and session_active:
		session_started.emit()
	elif previous_session_active and not session_active:
		session_cleared.emit()

	if previous_chances != remaining_chances:
		chances_changed.emit(remaining_chances)

	if previous_difficulty != difficulty_level:
		difficulty_changed.emit(
			difficulty_level,
			get_difficulty_multiplier()
		)

	if not previous_mission_in_progress and mission_in_progress:
		mission_started.emit(current_mission_number, difficulty_level)

		if target_code != previous_target_code:
			target_profile_generated.emit(
				target_profile.duplicate(true),
				required_target_clues.size()
			)
	elif previous_mission_in_progress and not mission_in_progress:
		if (
			last_mission_result == &"completed"
			and completed_missions > previous_completed_missions
		):
			mission_completed.emit(completed_missions)
		elif (
			last_mission_result == &"failed"
			and remaining_chances < previous_chances
		):
			mission_failed.emit(remaining_chances)

	if previous_revealed_clues != revealed_target_clues:
		for clue_type in revealed_target_clues:
			if clue_type in previous_revealed_clues:
				continue

			target_clue_revealed.emit(
				clue_type,
				str(target_profile.get(clue_type, "???")),
				revealed_target_clues.size(),
				required_target_clues.size()
			)

		target_progress_changed.emit(
			revealed_target_clues.size(),
			required_target_clues.size()
		)

	session_state_changed.emit(get_state_snapshot())


func sync_to_peer(peer_id: int) -> void:
	if (
		not multiplayer.is_server()
		or peer_id <= 0
		or peer_id not in multiplayer.get_peers()
	):
		return

	_receive_authoritative_snapshot.rpc_id(peer_id, get_state_snapshot())


func _publish_state() -> void:
	var snapshot := get_state_snapshot()
	session_state_changed.emit(snapshot)

	if multiplayer.is_server() and not multiplayer.get_peers().is_empty():
		_receive_authoritative_snapshot.rpc(snapshot)


@rpc("authority", "call_remote", "reliable")
func _receive_authoritative_snapshot(snapshot: Dictionary) -> void:
	apply_authoritative_snapshot(snapshot)


func _can_change_authoritative_state() -> bool:
	return multiplayer.multiplayer_peer == null or multiplayer.is_server()


func _generate_target_profile() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = (
		int(Time.get_ticks_usec())
		^ (current_mission_number * 1_000_003)
		^ (remaining_chances * 97_409)
	)

	target_code = "K-%04d" % rng.randi_range(1000, 9999)
	target_profile = {
		&"age": TARGET_AGES[rng.randi_range(0, TARGET_AGES.size() - 1)],
		&"hair": TARGET_HAIR_COLORS[
			rng.randi_range(0, TARGET_HAIR_COLORS.size() - 1)
		],
		&"height": TARGET_HEIGHTS[
			rng.randi_range(0, TARGET_HEIGHTS.size() - 1)
		],
		&"skin_tone": TARGET_SKIN_TONES[
			rng.randi_range(0, TARGET_SKIN_TONES.size() - 1)
		],
	}
	required_target_clues.clear()
	revealed_target_clues.clear()

	var clue_count := get_required_target_clue_count()

	for index in range(clue_count):
		required_target_clues.append(TARGET_ATTRIBUTE_ORDER[index])


func _clear_target_profile() -> void:
	target_code = "----"
	target_profile.clear()
	required_target_clues.clear()
	revealed_target_clues.clear()


func _string_name_array_to_strings(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []

	for value in values:
		result.append(String(value))

	return result


func _variant_to_string_name_array(value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []

	if value is Array or value is PackedStringArray:
		for entry in value:
			result.append(StringName(str(entry)))

	return result
