extends Node


const HUD_SCENE := preload("res://scenes/UI/PlayerHUD.tscn")
const OPTIONS_SCENE := preload("res://scenes/options_menu.tscn")
const CHECK_BOX_PATH := NodePath(
	"PanelContainer/MarginContainer/VBoxContainer/Tabs/Graphics/"
	+ "GraphicsScroll/GraphicsMargin/GraphicsOptions/"
	+ "HudCanvasFiltersRow/HudCanvasFiltersCheckBox"
)


func _ready() -> void:
	var options_menu := OPTIONS_SCENE.instantiate()
	var check_box := options_menu.get_node_or_null(CHECK_BOX_PATH) as CheckBox

	if check_box == null:
		_fail("Graphics is missing the HUD Canvas Filters option.")
		return

	if not options_menu.has_method(
		"_on_hud_canvas_filters_check_box_toggled"
	):
		_fail("HUD Canvas Filters has no toggle handler.")
		return

	var hud := HUD_SCENE.instantiate() as PlayerHUD

	if hud == null:
		_fail("PlayerHUD could not be instantiated.")
		return

	add_child(hud)
	await get_tree().process_frame

	if not hud.is_in_group("player_hud"):
		_fail("PlayerHUD is missing its runtime settings group.")
		return

	hud.set_hud_canvas_filters_enabled(false)

	if hud.are_hud_canvas_filters_enabled():
		_fail("PlayerHUD filters stayed enabled after disabling them.")
		return

	if (
		(hud.get_node("Effects") as CanvasLayer).visible
		or (hud.get_node("Effects2") as CanvasLayer).visible
	):
		_fail("A filtered HUD CanvasLayer stayed visible.")
		return

	if not (hud.get_node("Root") as Control).visible:
		_fail("Disabling filters also hid the regular HUD.")
		return

	hud.flash_damage()
	var damage_flash := hud.get_node(
		"DamageFlash/Flash"
	) as ColorRect

	if not damage_flash.visible or damage_flash.color.a < 0.4:
		_fail("The damage flash did not become visible immediately.")
		return

	if (
		(hud.get_node("Effects") as CanvasLayer).visible
		or (hud.get_node("Effects2") as CanvasLayer).visible
	):
		_fail("The damage flash re-enabled disabled HUD filters.")
		return

	await get_tree().create_timer(0.35).timeout

	if damage_flash.visible or damage_flash.color.a > 0.001:
		_fail("The damage flash did not fade out after one pulse.")
		return

	hud.set_hud_canvas_filters_enabled(true)

	if not hud.are_hud_canvas_filters_enabled():
		_fail("PlayerHUD filters could not be enabled again.")
		return

	options_menu.free()
	hud.queue_free()
	await get_tree().process_frame
	print("HUD_CANVAS_FILTER_SMOKE_TEST_OK")
	get_tree().quit(0)


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)
