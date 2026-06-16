extends RefCounted
class_name ShipRoomAccess

const CONNECTOR_NAVIGATION_LAYER: int = 1
const FLOOR_NAVIGATION_LAYER: int = 2
const BLOCKING_WALL_NAVIGATION_LAYERS: Array[int] = [0]

const CAUSE_ROOM_BARRICADED: String = "The room is barricaded"
const CAUSE_SHIP_BARRICADED: String = "The ship is barricaded"


static func validate(
	tile_layer: TileMapLayer,
	rooms: Array,
	samples_per_tile: int = 2
) -> Dictionary:
	var result: Dictionary = {
		"valid": true,
		"errors": []
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

	samples_per_tile = maxi(samples_per_tile, 1)

	var tile_set: TileSet = tile_layer.tile_set
	var navigation_layers_count: int = tile_set.get_navigation_layers_count()

	if navigation_layers_count <= FLOOR_NAVIGATION_LAYER:
		result["valid"] = false
		result["errors"].append({
			"room_id": -1,
			"cause": "TileSet has less than 3 navigation layers"
		})
		return result

	var connector_points: Dictionary = {}
	var floor_points: Dictionary = {}
	var blocking_wall_points: Dictionary = {}

	_collect_navigation_mask(
		tile_layer,
		[CONNECTOR_NAVIGATION_LAYER],
		samples_per_tile,
		connector_points
	)

	_collect_navigation_mask(
		tile_layer,
		[FLOOR_NAVIGATION_LAYER],
		samples_per_tile,
		floor_points
	)

	_collect_navigation_mask(
		tile_layer,
		BLOCKING_WALL_NAVIGATION_LAYERS,
		samples_per_tile,
		blocking_wall_points
	)

	var room_polygons_by_id: Dictionary = _extract_room_polygons_by_id(rooms)
	var room_point_to_room_id: Dictionary = _assign_floor_points_to_rooms(
		floor_points,
		room_polygons_by_id,
		tile_layer,
		samples_per_tile
	)

	var connector_components: Array[Dictionary] = _build_connector_components(
		connector_points,
		room_point_to_room_id,
		floor_points,
		blocking_wall_points
	)

	var room_has_connector: Dictionary = {}

	for room_id: int in range(rooms.size()):
		room_has_connector[room_id] = false

	var ship_has_space_access: bool = false

	for component: Dictionary in connector_components:
		var adjacent_room_ids: Array[int] = component["adjacent_room_ids"]
		var adjacent_to_space: bool = component["adjacent_to_space"]

		if adjacent_to_space and not adjacent_room_ids.is_empty():
			ship_has_space_access = true

		for room_id: int in adjacent_room_ids:
			room_has_connector[room_id] = true

	for room_id: int in range(rooms.size()):
		var has_connector: bool = bool(room_has_connector.get(room_id, false))

		if not has_connector:
			result["valid"] = false
			result["errors"].append({
				"room_id": room_id,
				"cause": CAUSE_ROOM_BARRICADED
			})

	if rooms.size() > 0 and not ship_has_space_access:
		result["valid"] = false
		result["errors"].append({
			"room_id": -1,
			"cause": CAUSE_SHIP_BARRICADED
		})

	return result


static func _extract_room_polygons_by_id(rooms: Array) -> Dictionary:
	var room_polygons_by_id: Dictionary = {}

	for room_id: int in range(rooms.size()):
		var room_variant: Variant = rooms[room_id]

		if typeof(room_variant) != TYPE_DICTIONARY:
			room_polygons_by_id[room_id] = []
			continue

		var room: Dictionary = room_variant
		var raw_polygons: Variant = room.get("polygons", [])

		if typeof(raw_polygons) != TYPE_ARRAY:
			room_polygons_by_id[room_id] = []
			continue

		var polygons_array: Array = raw_polygons
		var polygons: Array[PackedVector2Array] = []

		for polygon_variant: Variant in polygons_array:
			if typeof(polygon_variant) != TYPE_PACKED_VECTOR2_ARRAY:
				continue

			var polygon: PackedVector2Array = polygon_variant

			if polygon.size() >= 3:
				polygons.append(polygon)

		room_polygons_by_id[room_id] = polygons

	return room_polygons_by_id


static func _assign_floor_points_to_rooms(
	floor_points: Dictionary,
	room_polygons_by_id: Dictionary,
	tile_layer: TileMapLayer,
	samples_per_tile: int
) -> Dictionary:
	var room_point_to_room_id: Dictionary = {}

	for point_variant: Variant in floor_points.keys():
		var point: Vector2i = point_variant
		var local_center: Vector2 = sample_cell_center_to_layer_local_pos(
			point,
			tile_layer,
			samples_per_tile
		)

		var room_id: int = _find_room_id_for_local_point(
			local_center,
			room_polygons_by_id
		)

		if room_id >= 0:
			room_point_to_room_id[point] = room_id

	return room_point_to_room_id


static func _find_room_id_for_local_point(
	local_point: Vector2,
	room_polygons_by_id: Dictionary
) -> int:
	for room_id_variant: Variant in room_polygons_by_id.keys():
		var room_id: int = int(room_id_variant)
		var polygons: Array = room_polygons_by_id[room_id]

		for polygon_variant: Variant in polygons:
			var polygon: PackedVector2Array = polygon_variant

			if Geometry2D.is_point_in_polygon(local_point, polygon):
				return room_id

	return -1


static func _build_connector_components(
	connector_points: Dictionary,
	room_point_to_room_id: Dictionary,
	floor_points: Dictionary,
	blocking_wall_points: Dictionary
) -> Array[Dictionary]:
	var components: Array[Dictionary] = []
	var visited: Dictionary = {}

	var dirs: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	for start_variant: Variant in connector_points.keys():
		var start: Vector2i = start_variant

		if visited.has(start):
			continue

		var queue: Array[Vector2i] = [start]
		var read_index: int = 0

		var adjacent_room_ids_set: Dictionary = {}
		var adjacent_to_space: bool = false

		visited[start] = true

		while read_index < queue.size():
			var point: Vector2i = queue[read_index]
			read_index += 1

			for dir: Vector2i in dirs:
				var neighbor: Vector2i = point + dir

				if connector_points.has(neighbor):
					if not visited.has(neighbor):
						visited[neighbor] = true
						queue.append(neighbor)

					continue

				if room_point_to_room_id.has(neighbor):
					var room_id: int = int(room_point_to_room_id[neighbor])
					adjacent_room_ids_set[room_id] = true
					continue

				if floor_points.has(neighbor):
					continue

				if blocking_wall_points.has(neighbor):
					continue

				# Пустота рядом с navigation_layer_1 считается космосом.
				adjacent_to_space = true

		var adjacent_room_ids: Array[int] = []

		for room_id_variant: Variant in adjacent_room_ids_set.keys():
			adjacent_room_ids.append(int(room_id_variant))

		components.append({
			"adjacent_room_ids": adjacent_room_ids,
			"adjacent_to_space": adjacent_to_space
		})

	return components


static func _collect_navigation_mask(
	tile_layer: TileMapLayer,
	navigation_layer_ids: Array[int],
	samples_per_tile: int,
	output_points: Dictionary
) -> void:
	var tile_set: TileSet = tile_layer.tile_set
	var navigation_layers_count: int = tile_set.get_navigation_layers_count()
	var used_cells: Array[Vector2i] = tile_layer.get_used_cells()

	for cell: Vector2i in used_cells:
		var tile_data: TileData = tile_layer.get_cell_tile_data(cell)

		if tile_data == null:
			continue

		var alternative_tile: int = tile_layer.get_cell_alternative_tile(cell)

		var flip_h: bool = (alternative_tile & TileSetAtlasSource.TRANSFORM_FLIP_H) != 0
		var flip_v: bool = (alternative_tile & TileSetAtlasSource.TRANSFORM_FLIP_V) != 0
		var transpose: bool = (alternative_tile & TileSetAtlasSource.TRANSFORM_TRANSPOSE) != 0

		for navigation_layer_id: int in navigation_layer_ids:
			if navigation_layer_id < 0 or navigation_layer_id >= navigation_layers_count:
				continue

			var navigation_polygon: NavigationPolygon = tile_data.get_navigation_polygon(
				navigation_layer_id,
				flip_h,
				flip_v,
				transpose
			)

			if navigation_polygon == null:
				continue

			_rasterize_navigation_polygon(
				navigation_polygon,
				cell,
				tile_set.tile_size,
				samples_per_tile,
				output_points
			)


static func _rasterize_navigation_polygon(
	navigation_polygon: NavigationPolygon,
	cell: Vector2i,
	tile_size: Vector2i,
	samples_per_tile: int,
	output_points: Dictionary
) -> void:
	var vertices: PackedVector2Array = navigation_polygon.get_vertices()
	var polygon_count: int = navigation_polygon.get_polygon_count()

	if polygon_count > 0 and not vertices.is_empty():
		for polygon_index: int in range(polygon_count):
			var polygon_indices: PackedInt32Array = navigation_polygon.get_polygon(polygon_index)

			if polygon_indices.size() < 3:
				continue

			var polygon_points: PackedVector2Array = PackedVector2Array()

			for vertex_index: int in polygon_indices:
				if vertex_index < 0 or vertex_index >= vertices.size():
					continue

				polygon_points.append(vertices[vertex_index])

			if polygon_points.size() >= 3:
				_rasterize_local_polygon(
					polygon_points,
					cell,
					tile_size,
					samples_per_tile,
					output_points
				)

		return

	var outline_count: int = navigation_polygon.get_outline_count()

	for outline_index: int in range(outline_count):
		var outline_points: PackedVector2Array = navigation_polygon.get_outline(outline_index)

		if outline_points.size() < 3:
			continue

		_rasterize_local_polygon(
			outline_points,
			cell,
			tile_size,
			samples_per_tile,
			output_points
		)


static func _rasterize_local_polygon(
	polygon_points: PackedVector2Array,
	cell: Vector2i,
	tile_size: Vector2i,
	samples_per_tile: int,
	output_points: Dictionary
) -> void:
	var step_x: float = float(tile_size.x) / float(samples_per_tile)
	var step_y: float = float(tile_size.y) / float(samples_per_tile)

	var half_tile_size: Vector2 = Vector2(
		float(tile_size.x) * 0.5,
		float(tile_size.y) * 0.5
	)

	for sy: int in range(samples_per_tile):
		for sx: int in range(samples_per_tile):
			var local_point: Vector2 = Vector2(
				(float(sx) + 0.5) * step_x - half_tile_size.x,
				(float(sy) + 0.5) * step_y - half_tile_size.y
			)

			if Geometry2D.is_point_in_polygon(local_point, polygon_points):
				var sample_pos: Vector2i = Vector2i(
					cell.x * samples_per_tile + sx,
					cell.y * samples_per_tile + sy
				)

				output_points[sample_pos] = true


static func sample_cell_center_to_layer_local_pos(
	sample_cell: Vector2i,
	tile_layer: TileMapLayer,
	samples_per_tile: int
) -> Vector2:
	var tile_size: Vector2 = Vector2(tile_layer.tile_set.tile_size)
	var sample_size: Vector2 = tile_size / float(samples_per_tile)

	var vertex_pos: Vector2 = sample_vertex_to_layer_local_pos(
		sample_cell,
		tile_layer,
		samples_per_tile
	)

	return vertex_pos + sample_size * 0.5


static func sample_vertex_to_layer_local_pos(
	sample_vertex: Vector2i,
	tile_layer: TileMapLayer,
	samples_per_tile: int
) -> Vector2:
	var tile_size: Vector2 = Vector2(tile_layer.tile_set.tile_size)
	var sample_size: Vector2 = tile_size / float(samples_per_tile)

	var cell: Vector2i = Vector2i(
		floori(float(sample_vertex.x) / float(samples_per_tile)),
		floori(float(sample_vertex.y) / float(samples_per_tile))
	)

	var sample_in_cell: Vector2i = Vector2i(
		_positive_mod(sample_vertex.x, samples_per_tile),
		_positive_mod(sample_vertex.y, samples_per_tile)
	)

	var cell_top_left: Vector2 = tile_layer.map_to_local(cell) - tile_size * 0.5

	return cell_top_left + Vector2(sample_in_cell) * sample_size


static func _positive_mod(value: int, divider: int) -> int:
	var result: int = value % divider

	if result < 0:
		result += divider

	return result
