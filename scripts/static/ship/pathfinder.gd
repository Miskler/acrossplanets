extends RefCounted
class_name ShipPathfinder

enum PathKind {
	BLOCKED,
	FLOOR,
	DOOR
}

const PATH_CUSTOM_DATA_NAME: StringName = &"path"

const PATH_FLOOR_VALUE: String = "floor"
const PATH_FLOOR_MAIN_VALUE: String = "floor_main"
const PATH_DOOR_VALUE: String = "door"

const DOOR_NAVIGATION_LAYER: int = 1

const CAUSE_TILEMAP_IS_NULL: String = "TileMapLayer is null"
const CAUSE_TILESET_IS_NULL: String = "TileSet is null"
const CAUSE_FROM_IS_NOT_FLOOR: String = "Start cell is not floor"
const CAUSE_TO_IS_NOT_FLOOR: String = "Target cell is not floor"
const CAUSE_NO_PATH: String = "There is no path"


static func calculate(
	tile_layer: TileMapLayer,
	from_cell: Vector2i,
	to_cell: Vector2i,
	door_margin_px: float = 0.3
) -> Dictionary:
	var result: Dictionary = {
		"valid": true,
		"errors": [],
		"from_cell": from_cell,
		"to_cell": to_cell,
		"cell_path": [],
		"points": PackedVector2Array(),
		"steps": []
	}

	if tile_layer == null:
		result["valid"] = false
		result["errors"].append({
			"cell": Vector2i.ZERO,
			"cause": CAUSE_TILEMAP_IS_NULL
		})
		return result

	if tile_layer.tile_set == null:
		result["valid"] = false
		result["errors"].append({
			"cell": Vector2i.ZERO,
			"cause": CAUSE_TILESET_IS_NULL
		})
		return result

	var from_kind: int = _get_cell_path_kind(tile_layer, from_cell)
	var to_kind: int = _get_cell_path_kind(tile_layer, to_cell)

	if from_kind != PathKind.FLOOR:
		result["valid"] = false
		result["errors"].append({
			"cell": from_cell,
			"cause": CAUSE_FROM_IS_NOT_FLOOR
		})

	if to_kind != PathKind.FLOOR:
		result["valid"] = false
		result["errors"].append({
			"cell": to_cell,
			"cause": CAUSE_TO_IS_NOT_FLOOR
		})

	if not result["valid"]:
		return result

	var path_cells_by_kind: Dictionary = _collect_path_cells(tile_layer)
	var astar: AStarGrid2D = _build_astar(tile_layer, path_cells_by_kind)

	if not astar.is_in_boundsv(from_cell) or not astar.is_in_boundsv(to_cell):
		result["valid"] = false
		result["errors"].append({
			"cell": to_cell,
			"cause": CAUSE_NO_PATH
		})
		return result

	if astar.is_point_solid(from_cell) or astar.is_point_solid(to_cell):
		result["valid"] = false
		result["errors"].append({
			"cell": to_cell,
			"cause": CAUSE_NO_PATH
		})
		return result

	var raw_path: Array[Vector2i] = astar.get_id_path(from_cell, to_cell)

	if raw_path.is_empty():
		result["valid"] = false
		result["errors"].append({
			"cell": to_cell,
			"cause": CAUSE_NO_PATH
		})
		return result

	result["cell_path"] = raw_path

	var controls: Dictionary = _build_control_points(
		tile_layer,
		raw_path,
		path_cells_by_kind,
		door_margin_px
	)

	result["points"] = controls["points"]
	result["steps"] = controls["steps"]

	return result


static func calculate_from_global(
	tile_layer: TileMapLayer,
	from_global_position: Vector2,
	to_global_position: Vector2,
	door_margin_px: float = 0.5
) -> Dictionary:
	var from_cell: Vector2i = tile_layer.local_to_map(
		tile_layer.to_local(from_global_position)
	)

	var to_cell: Vector2i = tile_layer.local_to_map(
		tile_layer.to_local(to_global_position)
	)

	return calculate(
		tile_layer,
		from_cell,
		to_cell,
		door_margin_px
	)


static func _collect_path_cells(tile_layer: TileMapLayer) -> Dictionary:
	var result: Dictionary = {}
	var used_cells: Array[Vector2i] = tile_layer.get_used_cells()

	for cell: Vector2i in used_cells:
		var kind: int = _get_cell_path_kind(tile_layer, cell)

		if kind == PathKind.FLOOR or kind == PathKind.DOOR:
			result[cell] = kind

	return result


static func _get_cell_path_kind(
	tile_layer: TileMapLayer,
	cell: Vector2i
) -> int:
	var tile_data: TileData = tile_layer.get_cell_tile_data(cell)

	if tile_data == null:
		return PathKind.BLOCKED

	var data_name: String = String(PATH_CUSTOM_DATA_NAME)

	if not tile_data.has_custom_data(data_name):
		return PathKind.BLOCKED

	var raw_value: Variant = tile_data.get_custom_data(data_name)

	if raw_value == null:
		return PathKind.BLOCKED

	var value: String = str(raw_value)

	match value:
		PATH_FLOOR_VALUE, PATH_FLOOR_MAIN_VALUE:
			return PathKind.FLOOR
		PATH_DOOR_VALUE, "closed_door", "door_closed":
			return PathKind.DOOR
		_:
			return PathKind.BLOCKED


static func _build_astar(
	tile_layer: TileMapLayer,
	path_cells_by_kind: Dictionary
) -> AStarGrid2D:
	var astar: AStarGrid2D = AStarGrid2D.new()
	var used_rect: Rect2i = tile_layer.get_used_rect()

	astar.region = used_rect
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER

	var tile_size: Vector2i = tile_layer.tile_set.tile_size
	astar.cell_size = Vector2(float(tile_size.x), float(tile_size.y))

	astar.update()

	var min_x: int = used_rect.position.x
	var min_y: int = used_rect.position.y
	var max_x: int = used_rect.position.x + used_rect.size.x
	var max_y: int = used_rect.position.y + used_rect.size.y

	for y: int in range(min_y, max_y):
		for x: int in range(min_x, max_x):
			var cell: Vector2i = Vector2i(x, y)
			var solid: bool = not path_cells_by_kind.has(cell)

			astar.set_point_solid(cell, solid)

	return astar


static func _build_control_points(
	tile_layer: TileMapLayer,
	cell_path: Array[Vector2i],
	path_cells_by_kind: Dictionary,
	door_margin_px: float
) -> Dictionary:
	var points: PackedVector2Array = PackedVector2Array()
	var steps: Array[Dictionary] = []

	if cell_path.is_empty():
		return {
			"points": points,
			"steps": steps
		}

	var start_cell: Vector2i = cell_path[0]
	var start_point: Vector2 = _cell_center_global(tile_layer, start_cell)

	_append_step(
		points,
		steps,
		start_point,
		{
			"cell": start_cell,
			"kind": "floor",
			"action": "start"
		}
	)

	for i: int in range(1, cell_path.size()):
		var previous_cell: Vector2i = cell_path[i - 1]
		var current_cell: Vector2i = cell_path[i]

		var previous_kind: int = int(path_cells_by_kind.get(previous_cell, PathKind.BLOCKED))
		var current_kind: int = int(path_cells_by_kind.get(current_cell, PathKind.BLOCKED))

		if current_kind == PathKind.DOOR:
			if previous_kind == PathKind.FLOOR:
				var enter_point: Vector2 = _door_side_point_global(
					tile_layer,
					current_cell,
					previous_cell,
					door_margin_px
				)

				_append_step(
					points,
					steps,
					enter_point,
					{
						"cell": current_cell,
						"from_cell": previous_cell,
						"kind": "door_enter",
						"action": "open_door"
					}
				)

			if i + 1 < cell_path.size():
				var next_cell: Vector2i = cell_path[i + 1]
				var next_kind: int = int(path_cells_by_kind.get(next_cell, PathKind.BLOCKED))

				if next_kind == PathKind.FLOOR:
					var exit_point: Vector2 = _door_side_point_global(
						tile_layer,
						current_cell,
						next_cell,
						door_margin_px
					)

					_append_step(
						points,
						steps,
						exit_point,
						{
							"cell": current_cell,
							"to_cell": next_cell,
							"kind": "door_exit",
							"action": "close_door"
						}
					)

			continue

		if current_kind == PathKind.FLOOR:
			var floor_point: Vector2 = _cell_center_global(
				tile_layer,
				current_cell
			)

			_append_step(
				points,
				steps,
				floor_point,
				{
					"cell": current_cell,
					"from_cell": previous_cell,
					"kind": "floor",
					"action": "move"
				}
			)

	return {
		"points": points,
		"steps": steps
	}

static func _door_side_point_global(
	tile_layer: TileMapLayer,
	door_cell: Vector2i,
	side_cell: Vector2i,
	door_margin_px: float
) -> Vector2:
	var bounds: Rect2 = _door_navigation_local_bounds(tile_layer, door_cell)

	if bounds.size == Vector2.ZERO:
		return _door_fallback_side_point_global(
			tile_layer,
			door_cell,
			side_cell,
			door_margin_px
		)

	var direction_from_door_to_side: Vector2i = side_cell - door_cell

	var local_point: Vector2 = bounds.position + bounds.size * 0.5

	if abs(direction_from_door_to_side.x) > abs(direction_from_door_to_side.y):
		if direction_from_door_to_side.x < 0:
			local_point.x = bounds.position.x - door_margin_px
		else:
			local_point.x = bounds.position.x + bounds.size.x + door_margin_px
	else:
		if direction_from_door_to_side.y < 0:
			local_point.y = bounds.position.y - door_margin_px
		else:
			local_point.y = bounds.position.y + bounds.size.y + door_margin_px

	var cell_local_center: Vector2 = tile_layer.map_to_local(door_cell)

	return tile_layer.to_global(cell_local_center + local_point)

static func _door_fallback_side_point_global(
	tile_layer: TileMapLayer,
	door_cell: Vector2i,
	side_cell: Vector2i,
	door_margin_px: float
) -> Vector2:
	var tile_size: Vector2 = Vector2(tile_layer.tile_set.tile_size)
	var half_size: Vector2 = tile_size * 0.5

	var direction_from_door_to_side: Vector2i = side_cell - door_cell

	var local_point: Vector2 = Vector2.ZERO

	if abs(direction_from_door_to_side.x) > abs(direction_from_door_to_side.y):
		if direction_from_door_to_side.x < 0:
			local_point.x = -half_size.x - door_margin_px
		else:
			local_point.x = half_size.x + door_margin_px
	else:
		if direction_from_door_to_side.y < 0:
			local_point.y = -half_size.y - door_margin_px
		else:
			local_point.y = half_size.y + door_margin_px

	var cell_local_center: Vector2 = tile_layer.map_to_local(door_cell)

	return tile_layer.to_global(cell_local_center + local_point)

static func _append_step(
	points: PackedVector2Array,
	steps: Array[Dictionary],
	point: Vector2,
	step: Dictionary
) -> void:
	if points.size() > 0:
		var last_point: Vector2 = points[points.size() - 1]

		if last_point.distance_to(point) < 0.001:
			return

	points.append(point)

	var full_step: Dictionary = step.duplicate()
	full_step["point"] = point
	steps.append(full_step)


static func _cell_center_global(
	tile_layer: TileMapLayer,
	cell: Vector2i
) -> Vector2:
	var local_position: Vector2 = tile_layer.map_to_local(cell)
	return tile_layer.to_global(local_position)


static func _door_navigation_local_bounds(
	tile_layer: TileMapLayer,
	door_cell: Vector2i
) -> Rect2:
	var points: PackedVector2Array = _get_navigation_local_points(
		tile_layer,
		door_cell,
		DOOR_NAVIGATION_LAYER
	)

	if points.is_empty():
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	return _points_bounds(points)


static func _get_navigation_local_points(
	tile_layer: TileMapLayer,
	cell: Vector2i,
	navigation_layer_id: int
) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()

	var tile_set: TileSet = tile_layer.tile_set
	var navigation_layers_count: int = tile_set.get_navigation_layers_count()

	if navigation_layer_id < 0 or navigation_layer_id >= navigation_layers_count:
		return result

	var tile_data: TileData = tile_layer.get_cell_tile_data(cell)

	if tile_data == null:
		return result

	var alternative_tile: int = tile_layer.get_cell_alternative_tile(cell)

	var flip_h: bool = (alternative_tile & TileSetAtlasSource.TRANSFORM_FLIP_H) != 0
	var flip_v: bool = (alternative_tile & TileSetAtlasSource.TRANSFORM_FLIP_V) != 0
	var transpose: bool = (alternative_tile & TileSetAtlasSource.TRANSFORM_TRANSPOSE) != 0

	var navigation_polygon: NavigationPolygon = tile_data.get_navigation_polygon(
		navigation_layer_id,
		flip_h,
		flip_v,
		transpose
	)

	if navigation_polygon == null:
		return result

	var vertices: PackedVector2Array = navigation_polygon.get_vertices()
	var polygon_count: int = navigation_polygon.get_polygon_count()

	if polygon_count > 0 and not vertices.is_empty():
		for polygon_index: int in range(polygon_count):
			var polygon_indices: PackedInt32Array = navigation_polygon.get_polygon(polygon_index)

			for vertex_index: int in polygon_indices:
				if vertex_index < 0 or vertex_index >= vertices.size():
					continue

				result.append(vertices[vertex_index])

		return result

	var outline_count: int = navigation_polygon.get_outline_count()

	for outline_index: int in range(outline_count):
		var outline: PackedVector2Array = navigation_polygon.get_outline(outline_index)

		for point: Vector2 in outline:
			result.append(point)

	return result


static func _points_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	var min_point: Vector2 = points[0]
	var max_point: Vector2 = points[0]

	for point: Vector2 in points:
		min_point.x = minf(min_point.x, point.x)
		min_point.y = minf(min_point.y, point.y)
		max_point.x = maxf(max_point.x, point.x)
		max_point.y = maxf(max_point.y, point.y)

	return Rect2(
		min_point,
		max_point - min_point
	)
