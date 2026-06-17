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
				elif collider.is_in_group("room"):
					rooms.append(collider)
			if not rooms.is_empty():
				room_selected(rooms[0], int(rooms[0].get_meta("room")))

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
