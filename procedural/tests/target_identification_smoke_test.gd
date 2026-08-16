extends Node

const TEST_SEED := 515151

@onready var generator: ProceduralLevelGenerator = $ProceduralLevelGenerator
@onready var clue_tracker: TargetClueTracker = $TargetClueTracker


func _ready() -> void:
	var exit_code := await _run_test()
	get_tree().quit(exit_code)


func _run_test() -> int:
	SessionManager.clear_session()
	SessionManager.start_new_session()

	if not SessionManager.begin_mission():
		return _fail("A target mission could not be started.")

	await generator.generate_level(TEST_SEED, true)

	var clues: Array[PickupItem] = []

	for child in generator.items_root.get_children():
		var pickup := child as PickupItem

		if (
			pickup != null
			and pickup.item_data != null
			and pickup.item_data.is_mission_clue
		):
			clues.append(pickup)

	if clues.size() != SessionManager.get_required_target_clue_count():
		return _fail("The generated map has an incorrect target clue count.")

	var age_clue := _find_clue(clues, &"age")
	var hair_clue := _find_clue(clues, &"hair")

	if age_clue == null or hair_clue == null:
		return _fail("The prototype age or hair note is missing.")

	var target_display := $Hall/Van/TargetDisplay
	var target_viewport := target_display.get_node("SubViewport") as SubViewport
	var age_value := target_display.get_node(
		"SubViewport/Interface/Margin/Content/Attributes/AgeValue"
	) as Label
	var hair_value := target_display.get_node(
		"SubViewport/Interface/Margin/Content/Attributes/HairValue"
	) as Label
	var progress := target_display.get_node(
		"SubViewport/Interface/Margin/Content/ProgressLabel"
	) as Label
	var status := target_display.get_node(
		"SubViewport/Interface/Margin/Content/StatusLabel"
	) as Label

	if (
		target_viewport == null
		or target_viewport.size != Vector2i(512, 512)
		or age_value.text != "???"
		or hair_value.text != "???"
	):
		return _fail("The TARGET display does not begin with hidden data.")

	var cargo_area := $Hall/Van/CargoArea as Area3D
	age_clue.global_position = cargo_area.global_position
	clue_tracker.refresh_clues()
	await get_tree().process_frame

	if (
		not SessionManager.is_target_clue_revealed(&"age")
		or age_value.text != SessionManager.get_target_attribute_value(&"age")
		or hair_value.text != "???"
		or progress.text != "IDENTIFIZIERUNG  1 / 2"
	):
		return _fail("The age note was not analyzed by the van.")

	hair_clue.global_position = cargo_area.global_position
	clue_tracker.refresh_clues()
	await get_tree().process_frame

	if (
		not SessionManager.is_target_identified()
		or hair_value.text == "???"
		or status.text != "ZIEL IDENTIFIZIERT"
	):
		return _fail("The completed dossier was not shown on the TARGET display.")

	print("TARGET_IDENTIFICATION_SMOKE_TEST_OK")
	return 0


func _find_clue(
	clues: Array[PickupItem],
	clue_type: StringName
) -> PickupItem:
	for clue in clues:
		if clue.item_data.target_clue_type == clue_type:
			return clue

	return null


func _fail(message: String) -> int:
	push_error("TARGET_IDENTIFICATION_SMOKE_TEST_FAILED: " + message)
	return 1
