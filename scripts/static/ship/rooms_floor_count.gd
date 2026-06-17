extends RefCounted
class_name ShipRoomFloors

const PATH_CUSTOM_DATA_NAME: StringName = &"path"
const TECH_TYPE_CUSTOM_DATA_NAME: StringName = &"type"

const FLOOR_VALUE: String = "floor"
const MAIN_FLOOR_VALUE: String = "main_floor"

const CAUSE_NO_FLOOR: String = "There is no floor"
const CAUSE_TOO_MANY_MAIN_FLOOR: String = "There is more than one main_floor"


static func validate(
	tile_layer: TileMapLayer,
	technical_layer: TileMapLayer,
	rooms: Array,
	exclusion_layers: Array[TileMapLayer] = [],
	room_polygon_space: CanvasItem = null,
	path_custom_data_name: StringName = PATH_CUSTOM_DATA_NAME,
	floor_value: String = FLOOR_VALUE,
	tech_type_custom_data_name: StringName = TECH_TYPE_CUSTOM_DATA_NAME,
	main_floor_value: String = MAIN_FLOOR_VALUE
) -> Dictionary:
	var result: Dictionary = {
		"valid": true,
		"errors": [],
		"rooms": []
	}

	if tile_layer == null:
		result["valid"] = false
		result["errors"].append({
			"room_id": -1,
			"cause": "TileMapLayer is null"
		})
		return result

	if tile_layer.tile_set == null:
		result["valid"] = false
		result["errors"].append({
			"room_id": -1,
			"cause": "TileSet is null"
		})
		return result

	if technical_layer == null:
		result["valid"] = false
		result["errors"].append({
			"room_id": -1,
			"cause": "Technical TileMapLayer is null"
		})
		return result

	if technical_layer.tile_set == null:
		result["valid"] = false
		result["errors"].append({
			"room_id": -1,
			"cause": "Technical TileSet is null"
		})
		return result

	if room_polygon_space == null:
		room_polygon_space = tile_layer

	var floor_cells: Array[Vector2i] = _collect_cells_by_custom_data(
		tile_layer,
		path_custom_data_name,
		floor_value
	)

	var main_floor_cells: Array[Vector2i] = _collect_cells_by_custom_data(
		technical_layer,
		tech_type_custom_data_name,
		main_floor_value
	)

	for room_id: int in range(rooms.size()):
		var room: Dictionary = rooms[room_id]
		var polygons: Array = room.get("polygons", [])

		var room_floor_candidates: Array[Vector2i] = _get_cells_in_room(
			tile_layer,
			room_polygon_space,
			floor_cells,
			polygons
		)

		var room_floor_cells: Array[Vector2i] = []
		var excluded_floor_cells: Array[Vector2i] = []

		_split_floor_cells_by_exclusion(
			tile_layer,
			room_floor_candidates,
			exclusion_layers,
			room_floor_cells,
			excluded_floor_cells
		)

		print(main_floor_cells)
		var room_main_floor_cells: Array[Vector2i] = _get_main_floor_cells_in_room_by_coordinates(
			room_floor_cells,
			main_floor_cells
		)

		var floor_count: int = room_floor_cells.size()
		var main_floor_count: int = room_main_floor_cells.size()

		var floor_main: Variant = null

		if main_floor_count == 1:
			floor_main = room_main_floor_cells[0]

		result["rooms"].append({
			"room_id": room_id,
			"floor_count": floor_count,
			"floor_cells": room_floor_cells,
			"excluded_floor_cells": excluded_floor_cells,
			"floor_main": floor_main,
			"main_floor_count": main_floor_count,
			"main_floor_cells": room_main_floor_cells
		})

		if floor_count <= 0:
			result["valid"] = false
			result["errors"].append({
				"room_id": room_id,
				"cause": CAUSE_NO_FLOOR
			})

		if main_floor_count > 1:
			result["valid"] = false
			result["errors"].append({
				"room_id": room_id,
				"cause": CAUSE_TOO_MANY_MAIN_FLOOR,
				"main_floor_cells": room_main_floor_cells
			})

	return result

static func _get_main_floor_cells_in_room_by_coordinates(
	room_floor_cells: Array[Vector2i],
	main_floor_cells: Array[Vector2i]
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	var room_floor_set: Dictionary = {}

	for cell: Vector2i in room_floor_cells:
		room_floor_set[cell] = true

	for cell: Vector2i in main_floor_cells:
		if room_floor_set.has(cell):
			result.append(cell)

	return result


static func _collect_cells_by_custom_data(
	tile_layer: TileMapLayer,
	custom_data_name: StringName,
	expected_value: String
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var used_cells: Array[Vector2i] = tile_layer.get_used_cells()
	var data_name: String = String(custom_data_name)

	for cell: Vector2i in used_cells:
		var tile_data: TileData = tile_layer.get_cell_tile_data(cell)

		if tile_data == null:
			continue

		if not tile_data.has_custom_data(data_name):
			continue

		var raw_value: Variant = tile_data.get_custom_data(data_name)

		if raw_value == null:
			continue

		var value: String = str(raw_value)

		if value == expected_value:
			result.append(cell)

	return result


static func _get_cells_in_room(
	cell_layer: TileMapLayer,
	room_polygon_space: CanvasItem,
	cells: Array[Vector2i],
	polygons: Array
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	for cell: Vector2i in cells:
		if _is_cell_inside_room(
			cell_layer,
			room_polygon_space,
			cell,
			polygons
		):
			result.append(cell)

	return result


static func _is_cell_inside_room(
	cell_layer: TileMapLayer,
	room_polygon_space: CanvasItem,
	cell: Vector2i,
	polygons: Array
) -> bool:
	var point: Vector2 = _get_cell_center_in_room_space(
		cell_layer,
		room_polygon_space,
		cell
	)

	for polygon_variant: Variant in polygons:
		if typeof(polygon_variant) != TYPE_PACKED_VECTOR2_ARRAY:
			continue

		var polygon: PackedVector2Array = polygon_variant

		if polygon.size() < 3:
			continue

		if Geometry2D.is_point_in_polygon(point, polygon):
			return true

	return false

static func _get_cell_center_in_room_space(
	cell_layer: TileMapLayer,
	room_polygon_space: CanvasItem,
	cell: Vector2i
) -> Vector2:
	var local_center: Vector2 = cell_layer.map_to_local(cell)
	var global_center: Vector2 = cell_layer.to_global(local_center)
	return room_polygon_space.to_local(global_center)

static func _split_floor_cells_by_exclusion(
	tile_layer: TileMapLayer,
	room_floor_candidates: Array[Vector2i],
	exclusion_layers: Array[TileMapLayer],
	room_floor_cells: Array[Vector2i],
	excluded_floor_cells: Array[Vector2i]
) -> void:
	for cell: Vector2i in room_floor_candidates:
		var excluded: bool = _is_cell_occupied_in_any_layer(cell, exclusion_layers)

		if excluded:
			excluded_floor_cells.append(cell)
		else:
			room_floor_cells.append(cell)

static func _is_cell_occupied_in_any_layer(
	cell: Vector2i,
	layers: Array[TileMapLayer]
) -> bool:
	for layer: TileMapLayer in layers:
		if layer == null:
			continue

		if layer.get_cell_source_id(cell) != -1:
			return true

	return false
