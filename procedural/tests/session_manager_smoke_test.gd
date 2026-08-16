extends Node

const MISSION_INTRO_SCENE := preload(
	"res://scenes/UI/MissionIntro.tscn"
)


func _ready() -> void:
	var exit_code := _run_test()
	get_tree().quit(exit_code)


func _run_test() -> int:
	SessionManager.clear_session()
	SessionManager.start_new_session()

	if (
		not SessionManager.has_active_session()
		or SessionManager.remaining_chances != 3
		or SessionManager.completed_missions != 0
		or SessionManager.difficulty_level != 1
	):
		return _fail("A new session does not contain the expected defaults.")

	if not SessionManager.begin_mission():
		return _fail("The first mission could not be started.")

	if (
		SessionManager.current_mission_number != 1
		or SessionManager.difficulty_level != 1
	):
		return _fail("The first mission has incorrect progression values.")

	if (
		SessionManager.get_required_target_clue_count() != 2
		or SessionManager.target_profile.size() != 4
		or SessionManager.target_code == "----"
	):
		return _fail("The first mission has no generated hidden target profile.")

	if not SessionManager.reveal_target_clue(&"age"):
		return _fail("A required target clue could not be revealed.")

	if SessionManager.get_target_attribute_value(&"age") == "???":
		return _fail("A revealed target clue remained hidden.")

	if not SessionManager.complete_mission():
		return _fail("The first mission could not be completed.")

	if not SessionManager.begin_mission():
		return _fail("The second mission could not be started.")

	if (
		SessionManager.current_mission_number != 2
		or SessionManager.difficulty_level != 2
		or not is_equal_approx(
			SessionManager.get_difficulty_multiplier(),
			1.15
		)
	):
		return _fail("Difficulty did not increase for the second mission.")

	if (
		SessionManager.get_required_target_clue_count() != 3
		or not SessionManager.get_revealed_target_clues().is_empty()
	):
		return _fail("Target clue requirements did not scale or reset.")

	if not SessionManager.fail_mission():
		return _fail("A failed mission was not registered.")

	if SessionManager.remaining_chances != 2:
		return _fail("A failed mission did not consume exactly one chance.")

	if not SessionManager.begin_mission():
		return _fail("The failed mission could not be retried.")

	if (
		SessionManager.current_mission_number != 2
		or SessionManager.difficulty_level != 2
	):
		return _fail("A retry incorrectly advanced mission progression.")

	if (
		SessionManager.get_target_room_count() != 34
		or not is_equal_approx(
			SessionManager.get_surveillance_camera_chance(),
			0.27
		)
		or SessionManager.get_minimum_surveillance_cameras() != 1
		or SessionManager.get_maximum_surveillance_cameras() != 5
	):
		return _fail("Difficulty level two has incorrect world modifiers.")

	var intro := MISSION_INTRO_SCENE.instantiate() as MissionIntro
	add_child(intro)

	var prompt := intro.get_node(
		"Root/TerminalCenter/Terminal/Padding/Content/PromptText"
	) as Label
	var chances := intro.get_node(
		"Root/TerminalCenter/Terminal/Padding/Content/ChancesRow/ChancesText"
	) as Label
	var third_square := intro.get_node(
		"Root/TerminalCenter/Terminal/Padding/Content/ChancesRow/Chance3"
	) as PanelContainer

	if (
		prompt.text != "> AUFTRAG 02 // GEFAHRENSTUFE 02_"
		or chances.text != "2 CHANCEN VERBLEIBEN"
		or third_square.visible
	):
		intro.free()
		return _fail("The mission intro does not reflect session state.")

	intro.free()

	print("SESSION_MANAGER_SMOKE_TEST_OK")
	return 0


func _fail(message: String) -> int:
	push_error("SESSION_MANAGER_SMOKE_TEST_FAILED: " + message)
	return 1
