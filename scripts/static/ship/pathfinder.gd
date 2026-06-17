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

static func postprocess_smooth_steps(
	steps: Array[Dictionary],
	corner_radius_px: float = 16.0,
	segments_per_corner: int = 3
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	if steps.size() <= 2:
		for step: Dictionary in steps:
			result.append(step.duplicate(true))
		return result

	segments_per_corner = maxi(segments_per_corner, 1)
	corner_radius_px = maxf(corner_radius_px, 0.0)

	result.append(steps[0].duplicate(true))

	for i: int in range(1, steps.size() - 1):
		var prev_step: Dictionary = steps[i - 1]
		var current_step: Dictionary = steps[i]
		var next_step: Dictionary = steps[i + 1]

		if not _step_has_point(prev_step) or not _step_has_point(current_step) or not _step_has_point(next_step):
			_append_unique_step(result, current_step)
			continue

		if not _can_smooth_step(current_step):
			_append_unique_step(result, current_step)
			continue

		var prev: Vector2 = prev_step["point"]
		var current: Vector2 = current_step["point"]
		var next: Vector2 = next_step["point"]

		var prev_vec: Vector2 = current - prev
		var next_vec: Vector2 = next - current

		var prev_len: float = prev_vec.length()
		var next_len: float = next_vec.length()

		if prev_len < 0.001 or next_len < 0.001:
			_append_unique_step(result, current_step)
			continue

		var prev_dir: Vector2 = prev_vec / prev_len
		var next_dir: Vector2 = next_vec / next_len

		var dot_value: float = clampf(prev_dir.dot(next_dir), -1.0, 1.0)

		if dot_value > 0.999:
			_append_unique_step(result, current_step)
			continue

		var trim: float = minf(
			corner_radius_px,
			minf(prev_len * 0.45, next_len * 0.45)
		)

		var corner_start: Vector2 = current - prev_dir * trim
		var corner_end: Vector2 = current + next_dir * trim

		_append_unique_step(
			result,
			_make_smooth_move_step(current_step, corner_start)
		)

		for segment_index: int in range(1, segments_per_corner + 1):
			var t: float = float(segment_index) / float(segments_per_corner)

			var p: Vector2 = _quadratic_bezier(
				corner_start,
				current,
				corner_end,
				t
			)

			_append_unique_step(
				result,
				_make_smooth_move_step(current_step, p)
			)

	_append_unique_step(result, steps[steps.size() - 1])

	return result

static func _step_has_point(step: Dictionary) -> bool:
	if not step.has("point"):
		return false

	return typeof(step["point"]) == TYPE_VECTOR2


static func _can_smooth_step(step: Dictionary) -> bool:
	var action: String = str(step.get("action", ""))
	var kind: String = str(step.get("kind", ""))

	# Важные логические шаги не трогаем:
	# start, open_door, close_door, door_enter, door_exit.
	if action != "move":
		return false

	if kind != "floor":
		return false

	return true


static func _make_smooth_move_step(
	source_step: Dictionary,
	point: Vector2
) -> Dictionary:
	var step: Dictionary = source_step.duplicate(true)

	step["point"] = point
	step["action"] = "move"
	step["kind"] = "floor"
	step["smooth"] = true

	return step


static func _append_unique_step(
	steps: Array[Dictionary],
	step: Dictionary
) -> void:
	if not _step_has_point(step):
		steps.append(step.duplicate(true))
		return

	var point: Vector2 = step["point"]

	if steps.size() > 0:
		var last_step: Dictionary = steps[steps.size() - 1]

		if _step_has_point(last_step):
			var last_point: Vector2 = last_step["point"]

			if last_point.distance_to(point) < 0.001:
				return

	steps.append(step.duplicate(true))


static func _steps_to_points(
	steps: Array[Dictionary]
) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()

	for step: Dictionary in steps:
		if not _step_has_point(step):
			continue

		points.append(step["point"])

	return points

static func _quadratic_bezier(
	a: Vector2,
	b: Vector2,
	c: Vector2,
	t: float
) -> Vector2:
	var ab: Vector2 = a.lerp(b, t)
	var bc: Vector2 = b.lerp(c, t)

	return ab.lerp(bc, t)


static func _append_unique_point(
	points: PackedVector2Array,
	point: Vector2
) -> void:
	if points.size() > 0:
		var last_point: Vector2 = points[points.size() - 1]

		if last_point.distance_to(point) < 0.001:
			return

	points.append(point)


static func calculate(
	tile_layer: TileMapLayer,
	rooms: Array,
	from_cell: Vector2i,
	to_cell: Vector2i,
	door_margin_px: float = 10
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

	var allowed_floor_cells: Dictionary = _collect_allowed_floor_cells_from_rooms(rooms)

	if not allowed_floor_cells.has(from_cell):
		result["valid"] = false
		result["errors"].append({
			"cell": from_cell,
			"cause": CAUSE_FROM_IS_NOT_FLOOR
		})

	if not allowed_floor_cells.has(to_cell):
		result["valid"] = false
		result["errors"].append({
			"cell": to_cell,
			"cause": CAUSE_TO_IS_NOT_FLOOR
		})

	if not result["valid"]:
		return result

	var path_cells_by_kind: Dictionary = _collect_path_cells(
		tile_layer,
		allowed_floor_cells
	)

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
	
	var raw_steps: Array[Dictionary] = controls["steps"]
	var processed_steps: Array[Dictionary] = postprocess_smooth_steps(raw_steps)
	
	result["steps"] = processed_steps
	result["points"] = _steps_to_points(processed_steps)
	
	return result


static func calculate_from_global(
	tile_layer: TileMapLayer,
	rooms: Array,
	from_global_position: Vector2,
	to_global_position: Vector2,
	door_margin_px: float = 0.3
) -> Dictionary:
	var from_cell: Vector2i = tile_layer.local_to_map(
		tile_layer.to_local(from_global_position)
	)

	var to_cell: Vector2i = tile_layer.local_to_map(
		tile_layer.to_local(to_global_position)
	)

	return calculate(
		tile_layer,
		rooms,
		from_cell,
		to_cell,
		door_margin_px
	)


static func _collect_allowed_floor_cells_from_rooms(
	rooms: Array
) -> Dictionary:
	var result: Dictionary = {}

	for room_variant: Variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue

		var room: Dictionary = room_variant
		var raw_floor_cells: Variant = room.get("floor_cells", [])

		if typeof(raw_floor_cells) != TYPE_ARRAY:
			continue

		var floor_cells: Array = raw_floor_cells

		for cell_variant: Variant in floor_cells:
			if typeof(cell_variant) != TYPE_VECTOR2I:
				continue

			var cell: Vector2i = cell_variant
			result[cell] = true

	return result


static func _collect_path_cells(
	tile_layer: TileMapLayer,
	allowed_floor_cells: Dictionary
) -> Dictionary:
	var result: Dictionary = {}
	var used_cells: Array[Vector2i] = tile_layer.get_used_cells()

	for cell: Vector2i in used_cells:
		var kind: int = _get_cell_path_kind(tile_layer, cell)

		if kind == PathKind.FLOOR:
			if allowed_floor_cells.has(cell):
				result[cell] = PathKind.FLOOR

			continue

		if kind == PathKind.DOOR:
			result[cell] = PathKind.DOOR
			continue

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

	var skipped_cells: Dictionary = {}

	var i: int = 1

	while i < cell_path.size():
		var previous_cell: Vector2i = cell_path[i - 1]
		var current_cell: Vector2i = cell_path[i]
		var current_kind: int = int(path_cells_by_kind.get(current_cell, PathKind.BLOCKED))

		if skipped_cells.has(current_cell):
			i += 1
			continue

		if current_kind == PathKind.DOOR:
			var door_start_index: int = i
			var door_end_index: int = i

			while door_end_index + 1 < cell_path.size():
				var next_path_cell: Vector2i = cell_path[door_end_index + 1]
				var next_path_kind: int = int(path_cells_by_kind.get(next_path_cell, PathKind.BLOCKED))

				if next_path_kind != PathKind.DOOR:
					break

				door_end_index += 1

			var first_door_cell: Vector2i = cell_path[door_start_index]
			var last_door_cell: Vector2i = cell_path[door_end_index]

			var door_group: Array[Vector2i] = _collect_connected_door_group(
				first_door_cell,
				path_cells_by_kind
			)

			var enter_side_cell: Vector2i = cell_path[door_start_index - 1]

			var enter_point: Vector2 = _door_group_side_point_global(
				tile_layer,
				door_group,
				enter_side_cell,
				door_margin_px
			)

			_append_step(
				points,
				steps,
				enter_point,
				{
					"cell": first_door_cell,
					"door_cells": door_group,
					"from_cell": enter_side_cell,
					"kind": "door_enter",
					"action": "open_door"
				}
			)

			if door_end_index + 1 < cell_path.size():
				var exit_side_cell: Vector2i = cell_path[door_end_index + 1]

				var exit_point: Vector2 = _door_group_side_point_global(
					tile_layer,
					door_group,
					exit_side_cell,
					door_margin_px
				)

				_append_step(
					points,
					steps,
					exit_point,
					{
						"cell": last_door_cell,
						"door_cells": door_group,
						"to_cell": exit_side_cell,
						"kind": "door_exit",
						"action": "close_door"
					}
				)

				# ВАЖНО:
				# Первая floor-клетка после двери уже представлена точкой door_exit.
				# Если ещё добавить её центр, получится лишняя перемычка.
				#
				# Но если это конечная клетка пути, центр всё-таки нужен,
				# чтобы пешка дошла именно до выбранной клетки.
				var is_exit_cell_target: bool = exit_side_cell == cell_path[cell_path.size() - 1]

				if not is_exit_cell_target:
					skipped_cells[exit_side_cell] = true

			i = door_end_index + 1
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

		i += 1

	return {
		"points": points,
		"steps": steps
	}


static func _collect_connected_door_group(
	start_cell: Vector2i,
	path_cells_by_kind: Dictionary
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var visited: Dictionary = {}

	var queue: Array[Vector2i] = [start_cell]
	visited[start_cell] = true

	var dirs: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	var read_index: int = 0

	while read_index < queue.size():
		var cell: Vector2i = queue[read_index]
		read_index += 1

		result.append(cell)

		for dir: Vector2i in dirs:
			var next: Vector2i = cell + dir

			if visited.has(next):
				continue

			var kind: int = int(path_cells_by_kind.get(next, PathKind.BLOCKED))

			if kind != PathKind.DOOR:
				continue

			visited[next] = true
			queue.append(next)

	return result


static func _door_group_side_point_global(
	tile_layer: TileMapLayer,
	door_group: Array[Vector2i],
	side_cell: Vector2i,
	door_margin_px: float
) -> Vector2:
	if door_group.is_empty():
		return _cell_center_global(tile_layer, side_cell)

	var bounds: Rect2 = _door_group_navigation_global_bounds(
		tile_layer,
		door_group
	)

	if bounds.size == Vector2.ZERO:
		bounds = _door_group_tile_global_bounds(
			tile_layer,
			door_group
		)

	var door_center: Vector2 = bounds.position + bounds.size * 0.5
	var side_center: Vector2 = _cell_center_global(tile_layer, side_cell)
	var direction_from_door_to_side: Vector2 = side_center - door_center

	var point: Vector2 = door_center

	if abs(direction_from_door_to_side.x) > abs(direction_from_door_to_side.y):
		if direction_from_door_to_side.x < 0.0:
			point.x = bounds.position.x - door_margin_px
		else:
			point.x = bounds.position.x + bounds.size.x + door_margin_px
	else:
		if direction_from_door_to_side.y < 0.0:
			point.y = bounds.position.y - door_margin_px
		else:
			point.y = bounds.position.y + bounds.size.y + door_margin_px

	return point


static func _door_group_navigation_global_bounds(
	tile_layer: TileMapLayer,
	door_group: Array[Vector2i]
) -> Rect2:
	var all_points: PackedVector2Array = PackedVector2Array()

	for door_cell: Vector2i in door_group:
		var local_points: PackedVector2Array = _get_navigation_local_points(
			tile_layer,
			door_cell,
			DOOR_NAVIGATION_LAYER
		)

		var cell_local_center: Vector2 = tile_layer.map_to_local(door_cell)

		for local_point: Vector2 in local_points:
			var layer_local_point: Vector2 = cell_local_center + local_point
			var global_point: Vector2 = tile_layer.to_global(layer_local_point)
			all_points.append(global_point)

	if all_points.is_empty():
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	return _points_bounds(all_points)


static func _door_group_tile_global_bounds(
	tile_layer: TileMapLayer,
	door_group: Array[Vector2i]
) -> Rect2:
	var all_points: PackedVector2Array = PackedVector2Array()
	var tile_size: Vector2 = Vector2(tile_layer.tile_set.tile_size)
	var half_size: Vector2 = tile_size * 0.5

	for door_cell: Vector2i in door_group:
		var center: Vector2 = tile_layer.map_to_local(door_cell)

		var local_points: PackedVector2Array = PackedVector2Array([
			center + Vector2(-half_size.x, -half_size.y),
			center + Vector2(half_size.x, -half_size.y),
			center + Vector2(half_size.x, half_size.y),
			center + Vector2(-half_size.x, half_size.y)
		])

		for local_point: Vector2 in local_points:
			all_points.append(tile_layer.to_global(local_point))

	return _points_bounds(all_points)
	

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
