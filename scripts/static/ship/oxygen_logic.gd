extends RefCounted
class_name OxygenLogic


const PATH_DATA: String = "path"
const STATE_DATA: String = "state"
const IMPACT_DATA: String = "impact"

const PATH_FLOOR: String = "floor"
const PATH_DOOR: String = "door"
const STATE_HOLE: String = "hole"


static func create_room_oxygen(
	rooms: Array[Dictionary],
	default_oxygen: float = 100.0
) -> Dictionary:
	var result: Dictionary = {}
	
	for room_index: int in range(rooms.size()):
		var room: Dictionary = rooms[room_index]
		var room_id: int = _room_id(room, room_index)
		result[room_id] = default_oxygen
	
	return result

static func collect_pawn_consumption(
	foundation_layer: TileMapLayer,
	rooms: Array[Dictionary],
	pawns: Dictionary
) -> Dictionary:
	var result: Dictionary = {}
	var room_by_cell: Dictionary = build_room_cell_index(rooms)
	
	for pawn_data: Dictionary in pawns.values():
		var pawn_node: Node2D = pawn_data["node"]
		var cell: Vector2i = foundation_layer.local_to_map(pawn_node.position)
		
		if not room_by_cell.has(cell):
			continue
		
		var room_id: int = int(room_by_cell[cell])
		var consumption: float = pawn_node.oxygen_consumption
		
		result[room_id] = float(result.get(room_id, 0.0)) + consumption
	
	return result


static func calculate_room_areas(
	rooms: Array[Dictionary],
	tile_size: Vector2i
) -> Dictionary:
	var result: Dictionary = {}
	var tile_area: float = float(tile_size.x * tile_size.y)
	
	for room_index: int in range(rooms.size()):
		var room: Dictionary = rooms[room_index]
		var room_id: int = _room_id(room, room_index)
		var polygons: Array = room["polygons"]
		
		var area_in_tiles: float = 0.0
		
		for polygon: PackedVector2Array in polygons:
			area_in_tiles += _polygon_area(polygon) / tile_area
		
		if area_in_tiles <= 0.0:
			area_in_tiles = float(room["floor_cells"].size())
		
		result[room_id] = maxf(area_in_tiles, 1.0)
	
	return result


static func create_room_oxygen_polygons(
	rooms: Array[Dictionary],
	source_space: CanvasItem,
	target_parent: CanvasItem
) -> Dictionary:
	for child: Node in target_parent.get_children():
		child.queue_free()
	
	var result: Dictionary = {}
	
	for room_index: int in range(rooms.size()):
		var room: Dictionary = rooms[room_index]
		var room_id: int = _room_id(room, room_index)
		var source_polygons: Array = room["polygons"]
		var polygon_nodes: Array[Polygon2D] = []
		
		for source_polygon: PackedVector2Array in source_polygons:
			var polygon: PackedVector2Array = PackedVector2Array()
			
			for source_point: Vector2 in source_polygon:
				var global_point: Vector2 = source_space.to_global(source_point)
				var local_point: Vector2 = target_parent.to_local(global_point)
				polygon.append(local_point)
			
			var polygon_node: Polygon2D = Polygon2D.new()
			polygon_node.name = "OxygenRoom_%s" % room_id
			polygon_node.polygon = polygon
			polygon_node.color = Color(1.0, 0.0, 0.0, 0.0)
			
			target_parent.add_child(polygon_node)
			polygon_nodes.append(polygon_node)
		
		result[room_id] = polygon_nodes
	
	return result


static func update_room_oxygen_polygons(
	polygons_by_room: Dictionary,
	oxygen_by_room: Dictionary,
	max_alpha: float = 0.65
) -> void:
	for room_id_variant: Variant in polygons_by_room.keys():
		var room_id: int = int(room_id_variant)
		var oxygen: float = float(oxygen_by_room.get(room_id, 100.0))
		var danger: float = clampf((100.0 - oxygen) / 100.0, 0.0, 1.0)
		
		var color: Color = Color(
			1.0,
			0.05 + 0.15 * oxygen / 100.0,
			0.02,
			pow(danger, 1.35) * max_alpha
		)
		
		var polygons: Array = polygons_by_room[room_id]
		
		for polygon_variant: Variant in polygons:
			var polygon_node: Polygon2D = polygon_variant
			polygon_node.color = color


static func build_room_cell_index(
	rooms: Array[Dictionary]
) -> Dictionary:
	var result: Dictionary = {}
	
	for room_index: int in range(rooms.size()):
		var room: Dictionary = rooms[room_index]
		var room_id: int = _room_id(room, room_index)
		
		for cell: Vector2i in room["floor_cells"]:
			result[cell] = room_id
	
	return result


static func collect_hole_impacts(
	foundation_layer: TileMapLayer,
	rooms: Array[Dictionary]
) -> Dictionary:
	var result: Dictionary = {}
	var room_by_cell: Dictionary = build_room_cell_index(rooms)
	
	for cell: Vector2i in foundation_layer.get_used_cells():
		if not room_by_cell.has(cell):
			continue
		
		var tile_data: TileData = foundation_layer.get_cell_tile_data(cell)
		
		if tile_data.get_custom_data(PATH_DATA) != PATH_FLOOR:
			continue
		
		if tile_data.get_custom_data(STATE_DATA) != STATE_HOLE:
			continue
		
		var room_id: int = int(room_by_cell[cell])
		var impact: float = float(tile_data.get_custom_data(IMPACT_DATA))
		
		result[room_id] = float(result.get(room_id, 0.0)) + impact
	
	return result


static func collect_door_links(
	foundation_layer: TileMapLayer,
	rooms: Array[Dictionary]
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var room_by_cell: Dictionary = build_room_cell_index(rooms)
	var door_groups: Array[Array] = _collect_door_groups(foundation_layer)
	var dirs: Array[Vector2i] = [
		Vector2i.RIGHT,
		Vector2i.LEFT,
		Vector2i.DOWN,
		Vector2i.UP
	]
	
	for door_group: Array in door_groups:
		var room_ids_set: Dictionary = {}
		
		for door_cell_variant: Variant in door_group:
			var door_cell: Vector2i = door_cell_variant
			
			for dir: Vector2i in dirs:
				var side_cell: Vector2i = door_cell + dir
				
				if _array_has_cell(door_group, side_cell):
					continue
				
				if room_by_cell.has(side_cell):
					room_ids_set[int(room_by_cell[side_cell])] = true
		
		var room_ids: Array[int] = []
		
		for room_id_variant: Variant in room_ids_set.keys():
			room_ids.append(int(room_id_variant))
		
		result.append({
			"door_cells": door_group,
			"room_ids": room_ids,
			"door_size": door_group.size(),
			"exterior": room_ids.size() < 2
		})
	
	return result

static func _distribute_produced_air(
	air_by_room: Dictionary,
	room_areas: Dictionary,
	produced_air: float
) -> void:
	var remaining_air: float = produced_air
	
	while remaining_air > 0.001:
		var room_ids: Array[int] = []
		
		for room_id_variant: Variant in air_by_room.keys():
			var room_id: int = int(room_id_variant)
			var area: float = float(room_areas[room_id])
			var max_air: float = 100.0 * area
			var current_air: float = float(air_by_room[room_id])
			
			if current_air < max_air - 0.001:
				room_ids.append(room_id)
		
		if room_ids.is_empty():
			return
		
		var share: float = remaining_air / float(room_ids.size())
		var used_air: float = 0.0
		
		for room_id: int in room_ids:
			var area: float = float(room_areas[room_id])
			var max_air: float = 100.0 * area
			var current_air: float = float(air_by_room[room_id])
			var deficit: float = max_air - current_air
			
			var added_air: float = minf(share, deficit)
			
			air_by_room[room_id] = current_air + added_air
			used_air += added_air
		
		if used_air <= 0.001:
			return
		
		remaining_air -= used_air

static func process_oxygen_tick(
	oxygen_by_room: Dictionary,
	room_areas: Dictionary,
	door_links: Array[Dictionary],
	hole_impacts: Dictionary,
	pawn_consumption_by_room: Dictionary,
	foundation_layer: TileMapLayer,
	delta: float,
	air_production_per_second: float,
	door_flow_per_second: float,
	exterior_loss_per_second: float,
	hole_loss_per_impact: float
) -> Dictionary:
	var air_by_room: Dictionary = {}
	
	for room_id_variant: Variant in oxygen_by_room.keys():
		var room_id: int = int(room_id_variant)
		var oxygen: float = clampf(float(oxygen_by_room[room_id]), 0.0, 100.0)
		var area: float = float(room_areas[room_id])
		
		air_by_room[room_id] = oxygen * area
	
	for door_link: Dictionary in door_links:
		var door_cells: Array = door_link["door_cells"]
		var door_state: String = DoorManager.get_door_state(
			foundation_layer,
			door_cells
		)
		
		if door_state != "open":
			continue
		
		var room_ids: Array = door_link["room_ids"]
		var door_size: int = int(door_link["door_size"])
		
		if room_ids.size() >= 2:
			_equalize_rooms(
				air_by_room,
				room_areas,
				room_ids,
				delta,
				door_flow_per_second,
				door_size
			)
		elif room_ids.size() == 1:
			var room_id: int = int(room_ids[0])
			var leak: float = exterior_loss_per_second * float(door_size) * delta
			air_by_room[room_id] = maxf(0.0, float(air_by_room[room_id]) - leak)
	
	for room_id_variant: Variant in hole_impacts.keys():
		var room_id: int = int(room_id_variant)
		
		if not air_by_room.has(room_id):
			continue
		
		var impact: float = float(hole_impacts[room_id])
		var leak: float = hole_loss_per_impact * impact * delta
		
		air_by_room[room_id] = maxf(0.0, float(air_by_room[room_id]) - leak)
	
	for room_id_variant: Variant in pawn_consumption_by_room.keys():
		var room_id: int = int(room_id_variant)
		var consumption: float = float(pawn_consumption_by_room[room_id]) * delta
		
		air_by_room[room_id] = maxf(
			0.0,
			float(air_by_room[room_id]) - consumption
		)
	
	var produced_air: float = air_production_per_second * delta
	
	if produced_air > 0.0:
		_distribute_produced_air(
			air_by_room,
			room_areas,
			produced_air
		)
	
	var result: Dictionary = {}
	
	for room_id_variant: Variant in air_by_room.keys():
		var room_id: int = int(room_id_variant)
		var area: float = float(room_areas[room_id])
		var oxygen: float = float(air_by_room[room_id]) / area
		
		result[room_id] = clampf(oxygen, 0.0, 100.0)
	
	return result


static func _equalize_rooms(
	air_by_room: Dictionary,
	room_areas: Dictionary,
	room_ids: Array,
	delta: float,
	door_flow_per_second: float,
	door_size: int
) -> void:
	var total_air: float = 0.0
	var total_area: float = 0.0
	
	for room_id_variant: Variant in room_ids:
		var room_id: int = int(room_id_variant)
		
		total_air += float(air_by_room[room_id])
		total_area += float(room_areas[room_id])
	
	var target_oxygen: float = total_air / total_area
	var flow: float = clampf(
		door_flow_per_second * float(door_size) * delta,
		0.0,
		1.0
	)
	
	for room_id_variant: Variant in room_ids:
		var room_id: int = int(room_id_variant)
		var area: float = float(room_areas[room_id])
		var current_air: float = float(air_by_room[room_id])
		var target_air: float = target_oxygen * area
		
		air_by_room[room_id] = lerpf(current_air, target_air, flow)


static func _collect_door_groups(
	foundation_layer: TileMapLayer
) -> Array[Array]:
	var result: Array[Array] = []
	var door_cells: Dictionary = {}
	
	for cell: Vector2i in foundation_layer.get_used_cells():
		var tile_data: TileData = foundation_layer.get_cell_tile_data(cell)
		
		if tile_data.get_custom_data(PATH_DATA) == PATH_DOOR:
			door_cells[cell] = true
	
	var visited: Dictionary = {}
	var dirs: Array[Vector2i] = [
		Vector2i.RIGHT,
		Vector2i.LEFT,
		Vector2i.DOWN,
		Vector2i.UP
	]
	
	for start_variant: Variant in door_cells.keys():
		var start: Vector2i = start_variant
		
		if visited.has(start):
			continue
		
		var group: Array[Vector2i] = []
		var queue: Array[Vector2i] = [start]
		visited[start] = true
		
		var read_index: int = 0
		
		while read_index < queue.size():
			var cell: Vector2i = queue[read_index]
			read_index += 1
			
			group.append(cell)
			
			for dir: Vector2i in dirs:
				var next: Vector2i = cell + dir
				
				if visited.has(next):
					continue
				
				if not door_cells.has(next):
					continue
				
				visited[next] = true
				queue.append(next)
		
		result.append(group)
	
	return result


static func _array_has_cell(
	cells: Array,
	target_cell: Vector2i
) -> bool:
	for cell_variant: Variant in cells:
		var cell: Vector2i = cell_variant
		
		if cell == target_cell:
			return true
	
	return false


static func _polygon_area(
	polygon: PackedVector2Array
) -> float:
	var area: float = 0.0
	
	for i: int in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		
		area += a.x * b.y - b.x * a.y
	
	return absf(area) * 0.5


static func _room_id(
	room: Dictionary,
	fallback_id: int
) -> int:
	return int(room.get("room_id", fallback_id))
