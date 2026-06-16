extends RefCounted
class_name ShipRooms

const WALL_NAVIGATION_LAYERS: Array[int] = [0, 1]
const FLOOR_NAVIGATION_LAYER: int = 2

const CAUSE_FLOOR_NOT_COVERED_BY_WALLS: String = "The floor is not covered by walls"


static func validate(
	tile_layer: TileMapLayer,
	samples_per_tile: int = 2
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
			"pos": Vector2i.ZERO,
			"cause": "TileMapLayer is null"
		})
		return result

	if tile_layer.tile_set == null:
		result["valid"] = false
		result["errors"].append({
			"room_id": -1,
			"pos": Vector2i.ZERO,
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
			"pos": Vector2i.ZERO,
			"cause": "TileSet has less than 3 navigation layers"
		})
		return result

	var floor_points: Dictionary = {}
	var wall_points: Dictionary = {}

	_collect_navigation_mask(
		tile_layer,
		WALL_NAVIGATION_LAYERS,
		samples_per_tile,
		wall_points
	)

	_collect_navigation_mask(
		tile_layer,
		[FLOOR_NAVIGATION_LAYER],
		samples_per_tile,
		floor_points
	)

	var floor_point_to_room_id: Dictionary = {}

	result["rooms"] = _find_room_polygons(
		floor_points,
		tile_layer,
		samples_per_tile,
		floor_point_to_room_id
	)

	_validate_floor_boundaries(
		floor_points,
		wall_points,
		samples_per_tile,
		floor_point_to_room_id,
		result
	)

	return result


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


static func _validate_floor_boundaries(
	floor_points: Dictionary,
	wall_points: Dictionary,
	samples_per_tile: int,
	floor_point_to_room_id: Dictionary,
	result: Dictionary
) -> void:
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	var reported_tile_errors: Dictionary = {}

	for point_variant: Variant in floor_points.keys():
		var point: Vector2i = point_variant

		for dir: Vector2i in dirs:
			var neighbor: Vector2i = point + dir

			if floor_points.has(neighbor):
				continue

			if wall_points.has(neighbor):
				continue

			var tile_pos: Vector2i = _sample_to_tile(point, samples_per_tile)
			var room_id: int = int(floor_point_to_room_id.get(point, -1))

			var error_key: String = str(room_id) + ":" + str(tile_pos)

			if reported_tile_errors.has(error_key):
				continue

			reported_tile_errors[error_key] = true

			result["valid"] = false
			result["errors"].append({
				"room_id": room_id,
				"pos": tile_pos,
				"sample_pos": point,
				"cause": CAUSE_FLOOR_NOT_COVERED_BY_WALLS
			})

			break

static func _find_room_polygons(
	floor_points: Dictionary,
	tile_layer: TileMapLayer,
	samples_per_tile: int,
	floor_point_to_room_id: Dictionary
) -> Array[Dictionary]:
	var rooms: Array[Dictionary] = []
	var visited: Dictionary = {}

	var dirs: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	for start_variant: Variant in floor_points.keys():
		var start: Vector2i = start_variant

		if visited.has(start):
			continue

		var room_id: int = rooms.size()

		var component: Dictionary = {}
		var queue: Array[Vector2i] = [start]

		visited[start] = true
		component[start] = true
		floor_point_to_room_id[start] = room_id

		var read_index: int = 0

		while read_index < queue.size():
			var point: Vector2i = queue[read_index]
			read_index += 1

			for dir: Vector2i in dirs:
				var next: Vector2i = point + dir

				if visited.has(next):
					continue

				if not floor_points.has(next):
					continue

				visited[next] = true
				component[next] = true
				floor_point_to_room_id[next] = room_id
				queue.append(next)

		var polygons: Array[PackedVector2Array] = _component_to_layer_local_polygons(
			component,
			tile_layer,
			samples_per_tile
		)

		rooms.append({
			"room_id": room_id,
			"polygons": polygons,
			"sample_cells_count": component.size()
		})

	return rooms

static func _component_to_layer_local_polygons(
	component: Dictionary,
	tile_layer: TileMapLayer,
	samples_per_tile: int
) -> Array[PackedVector2Array]:
	var sample_polygons: Array[Array] = _component_to_sample_polygons(component)
	var local_polygons: Array[PackedVector2Array] = []

	for sample_polygon: Array in sample_polygons:
		var local_polygon: PackedVector2Array = PackedVector2Array()

		for vertex_variant: Variant in sample_polygon:
			var sample_vertex: Vector2i = vertex_variant

			var local_pos: Vector2 = sample_vertex_to_layer_local_pos(
				sample_vertex,
				tile_layer,
				samples_per_tile
			)

			local_polygon.append(local_pos)

		if local_polygon.size() >= 3:
			local_polygons.append(local_polygon)

	return local_polygons


static func _component_to_sample_polygons(component: Dictionary) -> Array[Array]:
	var edges_by_start: Dictionary = {}

	for point_variant: Variant in component.keys():
		var p: Vector2i = point_variant

		if not component.has(p + Vector2i(0, -1)):
			_add_directed_edge(
				edges_by_start,
				Vector2i(p.x, p.y),
				Vector2i(p.x + 1, p.y)
			)

		if not component.has(p + Vector2i(1, 0)):
			_add_directed_edge(
				edges_by_start,
				Vector2i(p.x + 1, p.y),
				Vector2i(p.x + 1, p.y + 1)
			)

		if not component.has(p + Vector2i(0, 1)):
			_add_directed_edge(
				edges_by_start,
				Vector2i(p.x + 1, p.y + 1),
				Vector2i(p.x, p.y + 1)
			)

		if not component.has(p + Vector2i(-1, 0)):
			_add_directed_edge(
				edges_by_start,
				Vector2i(p.x, p.y + 1),
				Vector2i(p.x, p.y)
			)

	var polygons: Array[Array] = []

	while not edges_by_start.is_empty():
		var keys: Array = edges_by_start.keys()
		var start: Vector2i = keys[0]

		var polygon: Array[Vector2i] = _trace_polygon_from_edges(
			start,
			edges_by_start
		)

		if polygon.size() >= 3:
			var simplified: Array[Vector2i] = _simplify_orthogonal_polygon(polygon)
			polygons.append(simplified)

	return polygons


static func _trace_polygon_from_edges(
	start: Vector2i,
	edges_by_start: Dictionary
) -> Array[Vector2i]:
	var polygon: Array[Vector2i] = [start]
	var current: Vector2i = start

	var guard: int = 0
	var max_guard: int = 100000

	while guard < max_guard:
		guard += 1

		if not edges_by_start.has(current):
			break

		var ends: Array = edges_by_start[current] as Array

		if ends.is_empty():
			edges_by_start.erase(current)
			break

		var next: Vector2i = ends.pop_front()

		if ends.is_empty():
			edges_by_start.erase(current)
		else:
			edges_by_start[current] = ends

		current = next

		if current == start:
			break

		polygon.append(current)

	return polygon


static func _add_directed_edge(
	edges_by_start: Dictionary,
	from_point: Vector2i,
	to_point: Vector2i
) -> void:
	if not edges_by_start.has(from_point):
		edges_by_start[from_point] = []

	var ends: Array = edges_by_start[from_point] as Array
	ends.append(to_point)
	edges_by_start[from_point] = ends


static func _simplify_orthogonal_polygon(points: Array[Vector2i]) -> Array[Vector2i]:
	if points.size() <= 3:
		return points

	var simplified: Array[Vector2i] = []

	for i: int in range(points.size()):
		var prev: Vector2i = points[(i - 1 + points.size()) % points.size()]
		var current: Vector2i = points[i]
		var next: Vector2i = points[(i + 1) % points.size()]

		var dir_a: Vector2i = current - prev
		var dir_b: Vector2i = next - current

		if dir_a == dir_b:
			continue

		simplified.append(current)

	return simplified


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


static func _sample_to_tile(
	sample_pos: Vector2i,
	samples_per_tile: int
) -> Vector2i:
	return Vector2i(
		floori(float(sample_pos.x) / float(samples_per_tile)),
		floori(float(sample_pos.y) / float(samples_per_tile))
	)


static func _positive_mod(value: int, divider: int) -> int:
	var result: int = value % divider

	if result < 0:
		result += divider

	return result
