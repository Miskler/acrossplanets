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
		result[room_index] = default_oxygen
	
	return result


static func create_consumption_by_room(
	rooms: Array[Dictionary]
) -> Dictionary:
	var result: Dictionary = {}
	
	for room_index: int in range(rooms.size()):
		result[room_index] = 0.0
	
	return result


static func add_pawn_consumption(
	consumption_by_room: Dictionary,
	foundation_layer: TileMapLayer,
	rooms: Array[Dictionary],
	pawns: Dictionary
) -> void:
	var room_by_cell: Dictionary = build_room_cell_index(rooms)
	
	for pawn_data: Dictionary in pawns.values():
		var pawn_node: Node2D = pawn_data["node"]
		var cell: Vector2i = foundation_layer.local_to_map(pawn_node.position)
		if not room_by_cell.has(cell):
			continue
		var room_index: int = int(room_by_cell[cell])
		
		consumption_by_room[room_index] = (
			float(consumption_by_room[room_index])
			+ pawn_node.oxygen_consumption
		)


static func add_fire_consumption(
	consumption_by_room: Dictionary,
	rooms: Array[Dictionary],
	fires: Dictionary
) -> void:
	var room_by_cell: Dictionary = build_room_cell_index(rooms)
	
	for fire_cell: Vector2i in fires.keys():
		var fire_node: Node2D = fires[fire_cell]["node"]
		var room_index: int = int(room_by_cell[fire_cell])
		
		consumption_by_room[room_index] = (
			float(consumption_by_room[room_index])
			+ fire_node.oxygen_consumption
		)


static func add_hole_consumption(
	consumption_by_room: Dictionary,
	foundation_layer: TileMapLayer,
	rooms: Array[Dictionary],
	hole_loss_per_impact: float
) -> void:
	var room_by_cell: Dictionary = build_room_cell_index(rooms)
	
	for cell: Vector2i in foundation_layer.get_used_cells():
		var tile_data: TileData = foundation_layer.get_cell_tile_data(cell)
		
		if tile_data.get_custom_data(PATH_DATA) != PATH_FLOOR:
			continue
		
		if tile_data.get_custom_data(STATE_DATA) != STATE_HOLE:
			continue
		
		var room_index: int = int(room_by_cell[cell])
		var impact: float = float(tile_data.get_custom_data(IMPACT_DATA))
		
		consumption_by_room[room_index] = (
			float(consumption_by_room[room_index])
			+ impact * hole_loss_per_impact
		)


static func calculate_room_areas(
	rooms: Array[Dictionary],
	tile_size: Vector2i
) -> Dictionary:
	var result: Dictionary = {}
	var tile_area: float = float(tile_size.x * tile_size.y)
	
	for room_index: int in range(rooms.size()):
		var room: Dictionary = rooms[room_index]
		var polygons: Array = room["polygons"]
		
		var area_in_tiles: float = 0.0
		
		for polygon: PackedVector2Array in polygons:
			area_in_tiles += _polygon_area(polygon) / tile_area
		
		if area_in_tiles <= 0.0:
			area_in_tiles = float(room["floor_cells"].size())
		
		result[room_index] = maxf(area_in_tiles, 1.0)
	
	return result

static func create_room_oxygen_polygons(
	rooms: Array[Dictionary],
	source_space: CanvasItem,
	target_parent: CanvasItem,
	hatching_texture: Texture2D
) -> Dictionary:
	for child: Node in target_parent.get_children():
		child.queue_free()
	
	var result: Dictionary = {}
	
	for room_index: int in range(rooms.size()):
		var room: Dictionary = rooms[room_index]
		var source_polygons: Array = room["polygons"]
		var fill_nodes: Array[Polygon2D] = []
		var hatch_nodes: Array[Polygon2D] = []
		
		for source_polygon: PackedVector2Array in source_polygons:
			var polygon: PackedVector2Array = PackedVector2Array()
			
			for source_point: Vector2 in source_polygon:
				var global_point: Vector2 = source_space.to_global(source_point)
				var local_point: Vector2 = target_parent.to_local(global_point)
				polygon.append(local_point)
			
			var fill_node: Polygon2D = Polygon2D.new()
			fill_node.name = "OxygenRoomFill_%s" % room_index
			fill_node.polygon = polygon
			fill_node.color = Color(1.0, 0.0, 0.0, 0.0)
			target_parent.add_child(fill_node)
			fill_nodes.append(fill_node)
			
			var hatch_node: Polygon2D = Polygon2D.new()
			hatch_node.name = "OxygenRoomHatch_%s" % room_index
			hatch_node.polygon = polygon
			hatch_node.texture = hatching_texture
			hatch_node.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
			hatch_node.texture_offset = Vector2.ZERO
			hatch_node.texture_rotation = 0.0
			hatch_node.texture_scale = Vector2.ONE
			hatch_node.color = Color(1.0, 1.0, 1.0, 0.0)
			hatch_node.visible = false
			hatch_node.set_meta("fade_alpha", 0.0)
			target_parent.add_child(hatch_node)
			hatch_nodes.append(hatch_node)
		
		result[room_index] = {
			"fill": fill_nodes,
			"hatch": hatch_nodes
		}
	
	return result

static func create_diagonal_hatching_texture(
	spacing_px: int = 12,
	line_width_px: int = 4,
	line_color: Color = Color(1.0, 0.35, 0.12, 1.0)
) -> Texture2D:
	var size: int = maxi(spacing_px, 2)
	var width: int = clampi(line_width_px, 1, size)
	var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	
	for y: int in range(size):
		for x: int in range(size):
			var diagonal_index: int = (x - y + size) % size
			
			if diagonal_index < width:
				image.set_pixel(x, y, line_color)
	
	return ImageTexture.create_from_image(image)

static func update_room_oxygen_polygons(
	polygons_by_room: Dictionary,
	oxygen_by_room: Dictionary,
	delta: float,
	max_alpha: float = 0.65,
	no_oxygen_hatching_alpha: float = 0.85,
	no_oxygen_threshold: float = 0.5,
	no_oxygen_hatching_fade_speed: float = 6.0
) -> void:
	for room_index: int in polygons_by_room.keys():
		var oxygen: float = float(oxygen_by_room[room_index])
		var danger: float = clampf((100.0 - oxygen) / 100.0, 0.0, 1.0)
		
		var fill_color: Color = Color(
			1.0,
			0.05 + 0.15 * oxygen / 100.0,
			0.02,
			pow(danger, 1.35) * max_alpha
		)
		
		var room_layers: Dictionary = polygons_by_room[room_index]
		var fill_nodes: Array = room_layers["fill"]
		var hatch_nodes: Array = room_layers["hatch"]
		
		for fill_node: Polygon2D in fill_nodes:
			fill_node.color = fill_color
		
		var target_hatch_alpha: float = 0.0
		
		if oxygen <= no_oxygen_threshold:
			target_hatch_alpha = no_oxygen_hatching_alpha
		
		for hatch_node: Polygon2D in hatch_nodes:
			var current_alpha: float = float(hatch_node.get_meta("fade_alpha", 0.0))
			var next_alpha: float = move_toward(
				current_alpha,
				target_hatch_alpha,
				no_oxygen_hatching_fade_speed * delta
			)
			
			hatch_node.set_meta("fade_alpha", next_alpha)
			hatch_node.visible = next_alpha > 0.001
			hatch_node.color = Color(1.0, 1.0, 1.0, next_alpha)


static func build_room_cell_index(
	rooms: Array[Dictionary]
) -> Dictionary:
	var result: Dictionary = {}
	
	for room_index: int in range(rooms.size()):
		var room: Dictionary = rooms[room_index]
		
		for cell: Vector2i in room["floor_cells"]:
			result[cell] = room_index
	
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
		var room_indexes_set: Dictionary = {}
		
		for door_cell: Vector2i in door_group:
			for dir: Vector2i in dirs:
				var side_cell: Vector2i = door_cell + dir
				
				if _array_has_cell(door_group, side_cell):
					continue
				
				if room_by_cell.has(side_cell):
					room_indexes_set[int(room_by_cell[side_cell])] = true
		
		var room_indexes: Array[int] = []
		
		for room_index: int in room_indexes_set.keys():
			room_indexes.append(room_index)
		
		result.append({
			"door_cells": door_group,
			"room_ids": room_indexes,
			"door_size": door_group.size(),
			"exterior": room_indexes.size() < 2
		})
	
	return result


static func process_oxygen_tick(
	oxygen_by_room: Dictionary,
	room_areas: Dictionary,
	door_links: Array[Dictionary],
	consumption_by_room: Dictionary,
	foundation_layer: TileMapLayer,
	delta: float,
	air_production_per_second: float,
	door_flow_per_second: float,
	exterior_loss_per_second: float
) -> Dictionary:
	var air_by_room: Dictionary = {}
	
	for room_index: int in oxygen_by_room.keys():
		var oxygen: float = clampf(float(oxygen_by_room[room_index]), 0.0, 100.0)
		var area: float = float(room_areas[room_index])
		
		air_by_room[room_index] = oxygen * area
	
	for door_link: Dictionary in door_links:
		var door_cells: Array = door_link["door_cells"]
		var door_state: String = DoorManager.get_door_state(
			foundation_layer,
			door_cells
		)
		
		if door_state != "open":
			continue
		
		var room_indexes: Array = door_link["room_ids"]
		var door_size: int = int(door_link["door_size"])
		
		if room_indexes.size() >= 2:
			_equalize_rooms(
				air_by_room,
				room_areas,
				room_indexes,
				delta,
				door_flow_per_second,
				door_size
			)
		elif room_indexes.size() == 1:
			var room_index: int = int(room_indexes[0])
			var leak: float = exterior_loss_per_second * float(door_size) * delta
			
			air_by_room[room_index] = maxf(
				0.0,
				float(air_by_room[room_index]) - leak
			)
	
	for room_index: int in consumption_by_room.keys():
		var consumption: float = float(consumption_by_room[room_index]) * delta
		
		air_by_room[room_index] = maxf(
			0.0,
			float(air_by_room[room_index]) - consumption
		)
	
	var produced_air: float = air_production_per_second * delta
	
	if produced_air > 0.0:
		_distribute_produced_air(
			air_by_room,
			room_areas,
			produced_air
		)
	
	var result: Dictionary = {}
	
	for room_index: int in air_by_room.keys():
		var area: float = float(room_areas[room_index])
		var oxygen: float = float(air_by_room[room_index]) / area
		
		result[room_index] = clampf(oxygen, 0.0, 100.0)
	
	return result


static func _distribute_produced_air(
	air_by_room: Dictionary,
	room_areas: Dictionary,
	produced_air: float
) -> void:
	var remaining_air: float = produced_air
	
	while remaining_air > 0.001:
		var room_indexes: Array[int] = []
		
		for room_index: int in air_by_room.keys():
			var area: float = float(room_areas[room_index])
			var max_air: float = 100.0 * area
			var current_air: float = float(air_by_room[room_index])
			
			if current_air < max_air - 0.001:
				room_indexes.append(room_index)
		
		if room_indexes.is_empty():
			return
		
		var share: float = remaining_air / float(room_indexes.size())
		var used_air: float = 0.0
		
		for room_index: int in room_indexes:
			var area: float = float(room_areas[room_index])
			var max_air: float = 100.0 * area
			var current_air: float = float(air_by_room[room_index])
			var deficit: float = max_air - current_air
			var added_air: float = minf(share, deficit)
			
			air_by_room[room_index] = current_air + added_air
			used_air += added_air
		
		if used_air <= 0.001:
			return
		
		remaining_air -= used_air


static func _equalize_rooms(
	air_by_room: Dictionary,
	room_areas: Dictionary,
	room_indexes: Array,
	delta: float,
	door_flow_per_second: float,
	door_size: int
) -> void:
	var total_air: float = 0.0
	var total_area: float = 0.0
	
	for room_index: int in room_indexes:
		total_air += float(air_by_room[room_index])
		total_area += float(room_areas[room_index])
	
	var target_oxygen: float = total_air / total_area
	var flow: float = clampf(
		door_flow_per_second * float(door_size) * delta,
		0.0,
		1.0
	)
	
	for room_index: int in room_indexes:
		var area: float = float(room_areas[room_index])
		var current_air: float = float(air_by_room[room_index])
		var target_air: float = target_oxygen * area
		
		air_by_room[room_index] = lerpf(current_air, target_air, flow)


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
	
	for start: Vector2i in door_cells.keys():
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
	for cell: Vector2i in cells:
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
