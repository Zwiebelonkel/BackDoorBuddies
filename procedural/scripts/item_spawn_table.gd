class_name ItemSpawnTable
extends Resource


@export var entries: Array[ItemSpawnEntry] = []


func pick_entry(rng: RandomNumberGenerator) -> ItemSpawnEntry:
	if rng == null:
		push_error("ItemSpawnTable requires a RandomNumberGenerator.")
		return null

	var total_weight: float = 0.0
	var fallback: ItemSpawnEntry = null

	for entry in entries:
		if not _is_valid_entry(entry):
			continue

		total_weight += entry.weight
		fallback = entry

	if total_weight <= 0.0:
		return null

	var roll := rng.randf_range(0.0, total_weight)
	var current_weight: float = 0.0

	for entry in entries:
		if not _is_valid_entry(entry):
			continue

		current_weight += entry.weight

		if roll <= current_weight:
			return entry

	return fallback


func _is_valid_entry(entry: ItemSpawnEntry) -> bool:
	return (
		entry != null
		and entry.item_scene != null
		and entry.weight > 0.0
	)
