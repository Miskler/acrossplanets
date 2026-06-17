extends Node2D

var selected_pawn_uuid: String = ""
var under_mouse: PhysicsPointQueryParameters2D

func _ready() -> void:
	under_mouse = PhysicsPointQueryParameters2D.new()
	under_mouse.collide_with_areas = true
	under_mouse.collide_with_bodies = false
	under_mouse.collision_mask = 0xFFFFFFFF
	
	get_parent().connect("restart_finish", _finish_init)

func _finish_init():
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
		parent.add_child(area)
		area.add_child(collision)
		
		area.set_meta("door_cells", group)
		
		result.append(area)
	
	return result

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			under_mouse.position = get_global_mouse_position()
			var hits: Array[Dictionary] = get_world_2d().direct_space_state.intersect_point(under_mouse)
			
			var rooms: Array = []
			for hit: Dictionary in hits:
				var collider: Object = hit.get("collider", null)
				if collider.is_in_group("pawn"):
					pawn_selected(collider, collider.get_meta("uuid"))
					return
				elif collider.is_in_group("door"):
					door_selected(collider, collider.get_meta("door_cells"))
					return
				elif collider.is_in_group("room"):
					rooms.append(collider)
			if not rooms.is_empty():
				room_selected(rooms[0], int(rooms[0].get_meta("room")))

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
	if not selected_pawn_uuid.is_empty():
		var available_cells: Array[Vector2i] = get_parent().dynamically_available_cells(room)
		if available_cells.is_empty():
			return
		get_parent().pawn_to_cell(
			selected_pawn_uuid,
			available_cells[0]
		)

func pawn_selected(
	pawn: Area2D,
	uuid: String
) -> void:
	var deselect: bool = uuid == selected_pawn_uuid
	if not selected_pawn_uuid.is_empty():
		get_parent().pawns[selected_pawn_uuid]["node"].set_selected(false)
		if deselect:
			selected_pawn_uuid = ""
			return
	selected_pawn_uuid = uuid
	pawn.set_selected(true)
