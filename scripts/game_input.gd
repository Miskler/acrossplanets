extends Node2D


var selected_pawn_uuids: Dictionary = {}

var under_mouse: PhysicsPointQueryParameters2D

var is_mouse_left_down: bool = false
var is_drag_selecting: bool = false
var drag_start_global: Vector2 = Vector2.ZERO
var drag_current_global: Vector2 = Vector2.ZERO
var drag_threshold_px: float = 6.0


func _ready() -> void:
	under_mouse = PhysicsPointQueryParameters2D.new()
	under_mouse.collide_with_areas = true
	under_mouse.collide_with_bodies = false
	under_mouse.collision_mask = 0xFFFFFFFF
	
	get_parent().connect("restart_finish", _finish_init)


func _finish_init() -> void:
	for room: Dictionary in get_parent().rooms:
		var room_id: int = int(room.get("room_id", -1))
		var polygons: Array = room.get("polygons", [])
		
		var area: Area2D = Area2D.new()
		area.add_to_group("room")
		area.set_meta("room", str(room_id))
		area.name = "RoomClickArea_%s" % room_id
		area.input_pickable = true
		area.collision_layer = 1
		area.collision_mask = 0
		
		add_child(area)
		
		area.position = Vector2.ZERO
		
		for source_polygon: PackedVector2Array in polygons:
			var collision_polygon: CollisionPolygon2D = CollisionPolygon2D.new()
			collision_polygon.name = "RoomPolygon"
			collision_polygon.polygon = source_polygon
			collision_polygon.disabled = false
			
			area.add_child(collision_polygon)
	
	create_door_areas(get_parent().foundation_layer, self)


static func create_door_areas(
	tile_layer: TileMapLayer,
	parent: Node
) -> Array[Area2D]:
	var result: Array[Area2D] = []
	var door_cells: Dictionary = {}
	
	for cell: Vector2i in tile_layer.get_used_cells():
		if tile_layer.get_cell_tile_data(cell).get_custom_data("path") == "door":
			door_cells[cell] = true
	
	var visited: Dictionary = {}
	var dirs: Array[Vector2i] = [
		Vector2i.RIGHT,
		Vector2i.LEFT,
		Vector2i.DOWN,
		Vector2i.UP
	]
	
	var tile_size: Vector2 = Vector2(tile_layer.tile_set.tile_size)
	
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
		
		var min_cell: Vector2i = group[0]
		var max_cell: Vector2i = group[0]
		
		for cell: Vector2i in group:
			min_cell.x = mini(min_cell.x, cell.x)
			min_cell.y = mini(min_cell.y, cell.y)
			max_cell.x = maxi(max_cell.x, cell.x)
			max_cell.y = maxi(max_cell.y, cell.y)
		
		var shape: RectangleShape2D = RectangleShape2D.new()
		shape.size = Vector2(
			float(max_cell.x - min_cell.x + 1) * tile_size.x,
			float(max_cell.y - min_cell.y + 1) * tile_size.y
		)
		
		var min_pos: Vector2 = tile_layer.map_to_local(min_cell)
		var max_pos: Vector2 = tile_layer.map_to_local(max_cell)
		var center_pos: Vector2 = (min_pos + max_pos) * 0.5
		
		var collision: CollisionShape2D = CollisionShape2D.new()
		collision.shape = shape
		collision.position = center_pos
		
		var area: Area2D = Area2D.new()
		area.name = "DoorArea"
		area.add_to_group("door")
		area.input_pickable = true
		area.collision_layer = 1
		area.collision_mask = 0
		
		parent.add_child(area)
		area.add_child(collision)
		
		area.set_meta("door_cells", group)
		
		result.append(area)
	
	return result


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		
		if mouse_event.pressed:
			is_mouse_left_down = true
			is_drag_selecting = false
			drag_start_global = get_global_mouse_position()
			drag_current_global = drag_start_global
			queue_redraw()
			return
		
		is_mouse_left_down = false
		
		if is_drag_selecting:
			select_pawns_in_rect(_get_drag_global_rect())
			is_drag_selecting = false
			queue_redraw()
			return
		
		queue_redraw()
		_click_select_or_action()
		return
	
	if event is InputEventMouseMotion:
		if not is_mouse_left_down:
			return
		
		drag_current_global = get_global_mouse_position()
		
		if drag_start_global.distance_to(drag_current_global) >= drag_threshold_px:
			is_drag_selecting = true
		
		if is_drag_selecting:
			queue_redraw()


func _draw() -> void:
	if not is_drag_selecting:
		return
	
	var rect: Rect2 = _get_drag_local_rect()
	
	draw_rect(
		rect,
		Color(0.3, 0.6, 1.0, 0.18),
		true
	)
	
	draw_rect(
		rect,
		Color(0.3, 0.6, 1.0, 0.9),
		false,
		2.0
	)


func _click_select_or_action() -> void:
	under_mouse.position = get_global_mouse_position()
	var hits: Array[Dictionary] = get_world_2d().direct_space_state.intersect_point(under_mouse)
	
	var rooms: Array = []
	
	for hit: Dictionary in hits:
		var collider: Object = hit.get("collider", null)
		
		if collider.is_in_group("pawn"):
			pawn_selected(collider, collider.get_meta("uuid"))
			return
		
		if collider.is_in_group("door"):
			door_selected(collider, collider.get_meta("door_cells"))
			return
		
		if collider.is_in_group("room"):
			rooms.append(collider)
	
	if not rooms.is_empty():
		room_selected(rooms[0], int(rooms[0].get_meta("room")))


func _get_drag_global_rect() -> Rect2:
	var min_pos: Vector2 = Vector2(
		minf(drag_start_global.x, drag_current_global.x),
		minf(drag_start_global.y, drag_current_global.y)
	)
	
	var max_pos: Vector2 = Vector2(
		maxf(drag_start_global.x, drag_current_global.x),
		maxf(drag_start_global.y, drag_current_global.y)
	)
	
	return Rect2(min_pos, max_pos - min_pos)


func _get_drag_local_rect() -> Rect2:
	var start_local: Vector2 = to_local(drag_start_global)
	var current_local: Vector2 = to_local(drag_current_global)
	
	var min_pos: Vector2 = Vector2(
		minf(start_local.x, current_local.x),
		minf(start_local.y, current_local.y)
	)
	
	var max_pos: Vector2 = Vector2(
		maxf(start_local.x, current_local.x),
		maxf(start_local.y, current_local.y)
	)
	
	return Rect2(min_pos, max_pos - min_pos)


func select_pawns_in_rect(global_rect: Rect2) -> void:
	clear_pawn_selection()
	
	for pawn: Area2D in get_tree().get_nodes_in_group("pawn"):
		if not global_rect.has_point(pawn.global_position):
			continue
		
		var uuid: String = str(pawn.get_meta("uuid"))
		
		selected_pawn_uuids[uuid] = true
		
		get_parent().pawns[uuid]["node"].set_selected(true)


func clear_pawn_selection() -> void:
	for uuid_variant: Variant in selected_pawn_uuids.keys():
		var uuid: String = str(uuid_variant)
		get_parent().pawns[uuid]["node"].set_selected(false)
	
	selected_pawn_uuids.clear()


func door_selected(
	_area: Area2D,
	cells: Array
) -> void:
	await get_tree().create_timer(get_parent().time2change_door_state).timeout
	DoorManager.toggle_door(get_parent().foundation_layer, cells)


func room_selected(
	area: Area2D,
	room: int
) -> void:
	if selected_pawn_uuids.is_empty():
		return
	
	var available_cells: Array[Vector2i] = get_parent().dynamically_available_cells(room)
	
	if available_cells.is_empty():
		return
	
	var cell_index: int = 0
	
	for uuid_variant: Variant in selected_pawn_uuids.keys():
		if cell_index >= available_cells.size():
			return
		
		var uuid: String = str(uuid_variant)
		
		get_parent().pawn_to_cell(
			uuid,
			available_cells[cell_index]
		)
		
		cell_index += 1


func pawn_selected(
	pawn: Area2D,
	uuid: String
) -> void:
	var deselect: bool = selected_pawn_uuids.size() == 1 and selected_pawn_uuids.has(uuid)
	
	clear_pawn_selection()
	
	if deselect:
		return
	
	selected_pawn_uuids[uuid] = true
	
	pawn.set_selected(true)
