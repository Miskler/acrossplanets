extends Node
class_name DoorManager

const doors_antonym: Dictionary = {
	"horizontal": {
		2: [
			[Vector2i(1, 0), Vector2i(3, 0)],
			[Vector2i(2, 0), Vector2i(4, 0)]
		]
	}, "vertical": {
		2: [
			[Vector2i(0, 1), Vector2i(0, 3)],
			[Vector2i(0, 2), Vector2i(0, 4)]
		]
	}
}

const DOOR_STATE_DATA_NAME: StringName = &"state"

const DOOR_STATE_OPEN: String = "open"
const DOOR_STATE_CLOSED: String = "closed"


static func get_door_state(layer: TileMapLayer, cells: Array[Vector2i]) -> String:
	var tile_data: TileData = layer.get_cell_tile_data(cells[0])
	return str(tile_data.get_custom_data(String(DOOR_STATE_DATA_NAME)))

static func set_door_state(
	layer: TileMapLayer,
	cells: Array[Vector2i],
	target_state: String
) -> bool:
	var current_state: String = get_door_state(layer, cells)

	if current_state == target_state:
		return true

	toggle_door(layer, cells)
	return false

static func toggle_door(layer: TileMapLayer, cells: Array[Vector2i]) -> void:
	var direction: String = "horizontal"
	
	if cells.size() >= 2 and cells[0].x == cells[1].x:
		direction = "vertical"
	
	var size: int = cells.size()
	
	for cell: Vector2i in cells:
		toggle_door_cell(layer, cell, direction, size)

static func toggle_door_cell(
	layer: TileMapLayer,
	cell: Vector2i,
	direction: String,
	size: int
) -> void:
	var source_id: int = layer.get_cell_source_id(cell)
	var atlas: Vector2i = layer.get_cell_atlas_coords(cell)
	var alt: int = layer.get_cell_alternative_tile(cell)
	
	layer.set_cell(
		cell,
		source_id,
		get_door_antonym(atlas, direction, size),
		alt
	)

static func get_door_antonym(
	atlas: Vector2i,
	direction: String,
	size: int
) -> Vector2i:
	for pair in doors_antonym[direction][size]:
		if pair[0] == atlas:
			return pair[1]
		if pair[1] == atlas:
			return pair[0]
	
	return atlas
