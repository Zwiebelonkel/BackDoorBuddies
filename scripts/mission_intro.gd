class_name MissionIntro
extends CanvasLayer

signal sequence_finished

@export_range(0.0, 2.0, 0.05) var fade_in_duration := 0.2
@export_range(0.0, 2.0, 0.05) var status_reveal_duration := 0.55
@export_range(0.0, 2.0, 0.05) var mission_reveal_duration := 0.7
@export_range(0.0, 5.0, 0.05) var hold_duration := 1.4
@export_range(0.0, 2.0, 0.05) var fade_out_duration := 0.35

@onready var root: Control = $Root
@onready var terminal: PanelContainer = $Root/TerminalCenter/Terminal
@onready var status_text: Label = (
	$Root/TerminalCenter/Terminal/Padding/Content/StatusText
)
@onready var prompt_text: Label = (
	$Root/TerminalCenter/Terminal/Padding/Content/PromptText
)
@onready var mission_text: Label = (
	$Root/TerminalCenter/Terminal/Padding/Content/MissionText
)
@onready var chances_text: Label = (
	$Root/TerminalCenter/Terminal/Padding/Content/ChancesRow/ChancesText
)
@onready var chance_squares: Array[PanelContainer] = [
	$Root/TerminalCenter/Terminal/Padding/Content/ChancesRow/Chance1,
	$Root/TerminalCenter/Terminal/Padding/Content/ChancesRow/Chance2,
	$Root/TerminalCenter/Terminal/Padding/Content/ChancesRow/Chance3,
]
@onready var footer_text: Label = (
	$Root/TerminalCenter/Terminal/Padding/Content/FooterText
)

var _playing := true
var _finished := false


func _ready() -> void:
	_configure_session_content()
	root.modulate = Color.WHITE
	terminal.modulate.a = 0.0

	for label in [
		status_text,
		prompt_text,
		mission_text,
		chances_text,
		footer_text,
	]:
		label.visible = false

	for square in chance_squares:
		square.modulate.a = 0.0
		square.scale = Vector2(0.55, 0.55)

	call_deferred("_play_sequence")


func is_playing() -> bool:
	return _playing


func has_finished() -> bool:
	return _finished


func _configure_session_content() -> void:
	var remaining := clampi(
		SessionManager.remaining_chances,
		0,
		chance_squares.size()
	)
	var mission_number := maxi(
		SessionManager.current_mission_number,
		1
	)
	var difficulty := maxi(SessionManager.difficulty_level, 1)

	prompt_text.text = "> AUFTRAG %02d // GEFAHRENSTUFE %02d_" % [
		mission_number,
		difficulty,
	]
	chances_text.text = (
		"1 CHANCE VERBLEIBT"
		if remaining == 1
		else "%d CHANCEN VERBLEIBEN" % remaining
	)

	for index in range(chance_squares.size()):
		chance_squares[index].visible = index < remaining


func _play_sequence() -> void:
	await get_tree().process_frame

	for square in chance_squares:
		if not square.visible:
			continue

		square.pivot_offset = square.size * 0.5

	var terminal_fade := create_tween()
	terminal_fade.tween_property(
		terminal,
		"modulate:a",
		1.0,
		fade_in_duration
	)
	await terminal_fade.finished

	await _reveal_label(status_text, status_reveal_duration)
	await _wait(0.12)
	await _reveal_label(prompt_text, 0.25)
	await _reveal_label(mission_text, mission_reveal_duration)
	await _wait(0.16)
	await _reveal_label(chances_text, 0.4)

	for square in chance_squares:
		if not square.visible:
			continue

		var square_tween := create_tween().set_parallel(true)
		square_tween.tween_property(
			square,
			"modulate:a",
			1.0,
			0.12
		)
		square_tween.tween_property(
			square,
			"scale",
			Vector2.ONE,
			0.12
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await square_tween.finished
		await _wait(0.08)

	await _reveal_label(footer_text, 0.35)
	await _wait(hold_duration)

	var fade_out := create_tween()
	fade_out.tween_property(root, "modulate:a", 0.0, fade_out_duration)
	await fade_out.finished

	visible = false
	_playing = false
	_finished = true
	sequence_finished.emit()


func _reveal_label(label: Label, duration: float) -> void:
	label.visible = true
	label.visible_ratio = 0.0

	if duration <= 0.0:
		label.visible_ratio = 1.0
		return

	var reveal := create_tween()
	reveal.tween_property(label, "visible_ratio", 1.0, duration)
	await reveal.finished


func _wait(duration: float) -> void:
	if duration <= 0.0:
		return

	await get_tree().create_timer(duration).timeout
