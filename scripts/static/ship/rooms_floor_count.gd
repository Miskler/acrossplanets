extends RefCounted
class_name ShipRoomFloors

const PATH_CUSTOM_DATA_NAME: StringName = &"path"

const FLOOR_VALUE: String = "floor"
const FLOOR_MAIN_VALUE: String = "floor_main"

const CAUSE_NO_FLOOR: String = "There is no floor"
const CAUSE_TOO_MANY_FLOOR_MAIN: String = "There is more than one floor_main"


static func validate(
	tile_layer: TileMapLayer,
	rooms: Array,
	path_custom_data_name: StringName = PATH_CUSTOM_DATA_NAME,
	floor_value: String = FLOOR_VALUE,
	floor_main_value: String = FLOOR_MAIN_VALUE
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

	var floor_cells: Array[Vector2i] = []
	var floor_main_cells: Array[Vector2i] = []

	_collect_floor_cells(
		tile_layer,
		path_custom_data_name,
		floor_value,
		floor_main_value,
		floor_cells,
		floor_main_cells
	)

	for room_id: int in range(rooms.size()):
		var room: Dictionary = rooms[room_id]
		var polygons: Array = room.get("polygons", [])

		var room_floor_cells: Array[Vector2i] = _get_cells_in_room(
			tile_layer,
			floor_cells,
			polygons
		)

		var room_floor_main_cells: Array[Vector2i] = _get_cells_in_room(
			tile_layer,
			floor_main_cells,
			polygons
		)

		var floor_count: int = room_floor_cells.size() + room_floor_main_cells.size()
		var floor_main_count: int = room_floor_main_cells.size()

		var floor_main: Variant = null

		if floor_main_count == 1:
			floor_main = room_floor_main_cells[0]

		var all_floor_cells: Array[Vector2i] = []
		all_floor_cells.append_array(room_floor_cells)
		all_floor_cells.append_array(room_floor_main_cells)

		result["rooms"].append({
			"room_id": room_id,
			"floor_count": floor_count,
			"floor_cells": all_floor_cells,
			"floor_main": floor_main
		})

		if floor_count <= 0:
			result["valid"] = false
			result["errors"].append({
				"room_id": room_id,
				"cause": CAUSE_NO_FLOOR
			})

		if floor_main_count > 1:
			result["valid"] = false
			result["errors"].append({
				"room_id": room_id,
				"cause": CAUSE_TOO_MANY_FLOOR_MAIN
			})

	return result


static func _collect_floor_cells(
	tile_layer: TileMapLayer,
	path_custom_data_name: StringName,
	floor_value: String,
	floor_main_value: String,
	floor_cells: Array[Vector2i],
	floor_main_cells: Array[Vector2i]
) -> void:
	var used_cells: Array[Vector2i] = tile_layer.get_used_cells()
	var data_name: String = String(path_custom_data_name)

	for cell: Vector2i in used_cells:
		var tile_data: TileData = tile_layer.get_cell_tile_data(cell)

		if tile_data == null:
			continue

		if not tile_data.has_custom_data(data_name):
			continue

		var raw_value: Variant = tile_data.get_custom_data(data_name)
		var value: String = str(raw_value)

		if value == floor_value:
			floor_cells.append(cell)
			continue

		if value == floor_main_value:
			floor_main_cells.append(cell)
			continue


static func _get_cells_in_room(
	tile_layer: TileMapLayer,
	cells: Array[Vector2i],
	polygons: Array
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	for cell: Vector2i in cells:
		if _is_cell_inside_room(tile_layer, cell, polygons):
			result.append(cell)

	return result


static func _is_cell_inside_room(
	tile_layer: TileMapLayer,
	cell: Vector2i,
	polygons: Array
) -> bool:
	var points_to_check: PackedVector2Array = _get_cell_check_points(
		tile_layer,
		cell
	)

	for polygon_variant: Variant in polygons:
		if typeof(polygon_variant) != TYPE_PACKED_VECTOR2_ARRAY:
			continue

		var polygon: PackedVector2Array = polygon_variant

		if polygon.size() < 3:
			continue

		for point: Vector2 in points_to_check:
			if Geometry2D.is_point_in_polygon(point, polygon):
				return true

	return false


static func _get_cell_check_points(
	tile_layer: TileMapLayer,
	cell: Vector2i
) -> PackedVector2Array:
	var tile_size: Vector2 = Vector2(tile_layer.tile_set.tile_size)
	var center: Vector2 = tile_layer.map_to_local(cell)

	var quarter: Vector2 = tile_size * 0.25

	return PackedVector2Array([
		center,
		center + Vector2(-quarter.x, -quarter.y),
		center + Vector2(quarter.x, -quarter.y),
		center + Vector2(quarter.x, quarter.y),
		center + Vector2(-quarter.x, quarter.y)
	])
