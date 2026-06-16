extends RefCounted
class_name ShipRoomSpecialization

const TYPE_CUSTOM_DATA_NAME: StringName = &"type"
const KIND_CUSTOM_DATA_NAME: StringName = &"kind"

const STATION_TYPE_VALUE: String = "station"

const CAUSE_ROOM_MUST_HAVE_ONE_KIND: String = "Room must have exactly one kind"
const CAUSE_ROOM_MUST_HAVE_ONE_STATION: String = "Room must contain exactly one station"
const CAUSE_KIND_USED_BY_MULTIPLE_ROOMS: String = "Kind is used by multiple rooms"

static func validate(
	station_layer: TileMapLayer,
	rooms: Array,
	room_polygon_space: CanvasItem = null,
	type_custom_data_name: StringName = TYPE_CUSTOM_DATA_NAME,
	kind_custom_data_name: StringName = KIND_CUSTOM_DATA_NAME,
	station_type_value: String = STATION_TYPE_VALUE
) -> Dictionary:
	var result: Dictionary = {
		"valid": true,
		"errors": [],
		"rooms": []
	}

	if station_layer == null:
		result["valid"] = false
		result["errors"].append({
			"room_id": -1,
			"cause": "Station TileMapLayer is null"
		})
		return result

	if station_layer.tile_set == null:
		result["valid"] = false
		result["errors"].append({
			"room_id": -1,
			"cause": "Station TileSet is null"
		})
		return result

	if room_polygon_space == null:
		room_polygon_space = station_layer

	var station_cells: Array[Vector2i] = station_layer.get_used_cells()

	var kind_to_room_ids: Dictionary = {}

	for room_id: int in range(rooms.size()):
		var polygons: Array[PackedVector2Array] = _extract_room_polygons(rooms[room_id])

		var room_cells: Array[Vector2i] = _find_cells_intersecting_room(
			station_layer,
			room_polygon_space,
			station_cells,
			polygons
		)

		var kind_values: Array[String] = []
		var missing_kind_cells: Array[Vector2i] = []
		var station_cells_in_room: Array[Vector2i] = []

		for cell: Vector2i in room_cells:
			var kind_value: String = _get_custom_data_string(
				station_layer,
				cell,
				kind_custom_data_name
			)

			if kind_value == "":
				missing_kind_cells.append(cell)
			elif not kind_values.has(kind_value):
				kind_values.append(kind_value)

			var type_value: String = _get_custom_data_string(
				station_layer,
				cell,
				type_custom_data_name
			)

			if type_value == station_type_value:
				station_cells_in_room.append(cell)

		var room_kind: Variant = null

		if kind_values.size() == 1 and missing_kind_cells.is_empty():
			room_kind = kind_values[0]

			var kind_key: String = str(room_kind)
			var kind_room_ids: Array = kind_to_room_ids.get(kind_key, [])
			kind_room_ids.append(room_id)
			kind_to_room_ids[kind_key] = kind_room_ids

		var station_cell: Variant = null

		if station_cells_in_room.size() == 1:
			station_cell = station_cells_in_room[0]

		result["rooms"].append({
			"room_id": room_id,
			"cells": room_cells,
			"cell_count": room_cells.size(),
			"kind": room_kind,
			"kinds": kind_values,
			"missing_kind_cells": missing_kind_cells,
			"station_count": station_cells_in_room.size(),
			"station_cell": station_cell,
			"station_cells": station_cells_in_room
		})

		if room_cells.size() > 0:
			if kind_values.size() != 1 or not missing_kind_cells.is_empty():
				result["valid"] = false
				result["errors"].append({
					"room_id": room_id,
					"cause": CAUSE_ROOM_MUST_HAVE_ONE_KIND,
					"kinds": kind_values,
					"missing_kind_cells": missing_kind_cells
				})

			if station_cells_in_room.size() != 1:
				result["valid"] = false
				result["errors"].append({
					"room_id": room_id,
					"cause": CAUSE_ROOM_MUST_HAVE_ONE_STATION,
					"station_count": station_cells_in_room.size(),
					"station_cells": station_cells_in_room
				})

	for kind_variant: Variant in kind_to_room_ids.keys():
		var kind: String = str(kind_variant)
		var room_ids: Array = kind_to_room_ids[kind]

		if room_ids.size() <= 1:
			continue

		result["valid"] = false
		result["errors"].append({
			"room_id": -1,
			"cause": CAUSE_KIND_USED_BY_MULTIPLE_ROOMS,
			"kind": kind,
			"room_ids": room_ids
		})

	return result

static func _extract_room_polygons(room_variant: Variant) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []

	if typeof(room_variant) != TYPE_DICTIONARY:
		return result

	var room: Dictionary = room_variant
	var raw_polygons: Variant = room.get("polygons", [])

	if typeof(raw_polygons) != TYPE_ARRAY:
		return result

	var polygons: Array = raw_polygons

	for polygon_variant: Variant in polygons:
		if typeof(polygon_variant) != TYPE_PACKED_VECTOR2_ARRAY:
			continue

		var polygon: PackedVector2Array = polygon_variant

		if polygon.size() >= 3:
			result.append(polygon)

	return result


static func _find_cells_intersecting_room(
	station_layer: TileMapLayer,
	room_polygon_space: CanvasItem,
	station_cells: Array[Vector2i],
	room_polygons: Array[PackedVector2Array]
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	if room_polygons.is_empty():
		return result

	for cell: Vector2i in station_cells:
		var cell_polygon: PackedVector2Array = _get_cell_polygon_in_room_space(
			station_layer,
			room_polygon_space,
			cell
		)

		if _cell_polygon_intersects_room_polygons(cell_polygon, room_polygons):
			result.append(cell)

	return result


static func _get_cell_polygon_in_room_space(
	station_layer: TileMapLayer,
	room_polygon_space: CanvasItem,
	cell: Vector2i
) -> PackedVector2Array:
	var tile_size: Vector2 = Vector2(station_layer.tile_set.tile_size)
	var half_size: Vector2 = tile_size * 0.5
	var center: Vector2 = station_layer.map_to_local(cell)

	var local_points: PackedVector2Array = PackedVector2Array([
		center + Vector2(-half_size.x, -half_size.y),
		center + Vector2(half_size.x, -half_size.y),
		center + Vector2(half_size.x, half_size.y),
		center + Vector2(-half_size.x, half_size.y)
	])

	var result: PackedVector2Array = PackedVector2Array()

	for local_point: Vector2 in local_points:
		var global_point: Vector2 = station_layer.to_global(local_point)
		var room_local_point: Vector2 = room_polygon_space.to_local(global_point)
		result.append(room_local_point)

	return result


static func _cell_polygon_intersects_room_polygons(
	cell_polygon: PackedVector2Array,
	room_polygons: Array[PackedVector2Array]
) -> bool:
	for room_polygon: PackedVector2Array in room_polygons:
		if _polygons_intersect(cell_polygon, room_polygon):
			return true

	return false


static func _polygons_intersect(
	a: PackedVector2Array,
	b: PackedVector2Array
) -> bool:
	if a.size() < 3 or b.size() < 3:
		return false

	for point: Vector2 in a:
		if Geometry2D.is_point_in_polygon(point, b):
			return true

	for point: Vector2 in b:
		if Geometry2D.is_point_in_polygon(point, a):
			return true

	for i: int in range(a.size()):
		var a_from: Vector2 = a[i]
		var a_to: Vector2 = a[(i + 1) % a.size()]

		for j: int in range(b.size()):
			var b_from: Vector2 = b[j]
			var b_to: Vector2 = b[(j + 1) % b.size()]

			var intersection: Variant = Geometry2D.segment_intersects_segment(
				a_from,
				a_to,
				b_from,
				b_to
			)

			if intersection != null:
				return true

	return false


static func _get_custom_data_string(
	tile_layer: TileMapLayer,
	cell: Vector2i,
	custom_data_name: StringName
) -> String:
	var tile_data: TileData = tile_layer.get_cell_tile_data(cell)

	if tile_data == null:
		return ""

	var data_name: String = String(custom_data_name)

	if not tile_data.has_custom_data(data_name):
		return ""

	var raw_value: Variant = tile_data.get_custom_data(data_name)

	if raw_value == null:
		return ""

	return str(raw_value)
