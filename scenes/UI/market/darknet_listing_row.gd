class_name DarknetListingRow
extends PanelContainer


const STATUS_COLORS := {
	"LISTED": Color(0.20, 0.72, 0.34, 1.0),
	"OFFER_RECEIVED": Color(1.0, 0.66, 0.18, 1.0),
	"COUNTER_SENT": Color(0.25, 0.66, 1.0, 1.0),
	"DELIVERY_REQUIRED": Color(1.0, 0.28, 0.16, 1.0),
	"SOLD": Color(0.35, 1.0, 0.52, 1.0),
	"DECLINED": Color(0.52, 0.55, 0.53, 1.0),
	"CANCELLED": Color(0.52, 0.55, 0.53, 1.0),
}

const STATUS_LABELS := {
	"LISTED": "ONLINE",
	"OFFER_RECEIVED": "ANGEBOT",
	"COUNTER_SENT": "COUNTER",
	"DELIVERY_REQUIRED": "LIEFERN",
	"SOLD": "VERKAUFT",
	"DECLINED": "ABGELEHNT",
	"CANCELLED": "ABGEBROCHEN",
}

var listing: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(0.0, 68.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(data: Dictionary) -> void:
	listing = data.duplicate(true)
	var status := str(data.get("status", "UNKNOWN"))
	var accent: Color = STATUS_COLORS.get(
		status,
		Color(0.25, 0.6, 0.32, 1.0)
	)
	add_theme_stylebox_override("panel", _make_panel_style(accent, status))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 2)
	row.add_child(left)

	var title := Label.new()
	title.text = str(data.get("name", "UNBEKANNT"))
	title.add_theme_color_override("font_color", Color(0.72, 1.0, 0.78))
	title.add_theme_font_size_override("font_size", 16)
	left.add_child(title)

	var detail := Label.new()
	detail.text = _build_detail_text(data, status)
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.add_theme_color_override("font_color", Color(0.28, 0.55, 0.34))
	detail.add_theme_font_size_override("font_size", 11)
	left.add_child(detail)

	var prices := VBoxContainer.new()
	prices.alignment = BoxContainer.ALIGNMENT_CENTER
	prices.custom_minimum_size.x = 132.0
	row.add_child(prices)

	var price := Label.new()
	var offer_price := int(data.get("offer_price", 0))
	price.text = (
		"OFFER  $%d" % offer_price
		if offer_price > 0
		else "ASK  $%d" % int(data.get("asking_price", 0))
	)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.add_theme_color_override("font_color", accent)
	price.add_theme_font_size_override("font_size", 15)
	prices.add_child(price)

	if offer_price > 0:
		var asking := Label.new()
		asking.text = "ASK  $%d" % int(data.get("asking_price", 0))
		asking.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		asking.add_theme_color_override("font_color", Color(0.32, 0.48, 0.36))
		asking.add_theme_font_size_override("font_size", 10)
		prices.add_child(asking)

	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(112.0, 32.0)
	chip.add_theme_stylebox_override("panel", _make_chip_style(accent))
	row.add_child(chip)

	var status_label := Label.new()
	status_label.text = str(STATUS_LABELS.get(status, status))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", accent)
	status_label.add_theme_font_size_override("font_size", 12)
	chip.add_child(status_label)


func _build_detail_text(data: Dictionary, status: String) -> String:
	var instance_id := str(data.get("item_instance_id", "--------"))
	var short_id := instance_id.right(8).to_upper()
	var buyer := str(data.get("buyer", ""))
	var detail := "ITEM #%s  //  %s" % [short_id, status]

	if not buyer.is_empty():
		detail += "  //  %s" % buyer

	return detail


func _make_panel_style(accent: Color, status: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.012, 0.03, 0.018, 0.96)
	style.border_width_left = 3
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3

	if status == "DELIVERY_REQUIRED":
		style.bg_color = Color(0.11, 0.018, 0.012, 0.96)
		style.shadow_color = Color(1.0, 0.12, 0.02, 0.18)
		style.shadow_size = 5

	return style


func _make_chip_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.r, accent.g, accent.b, 0.1)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(accent.r, accent.g, accent.b, 0.75)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style
