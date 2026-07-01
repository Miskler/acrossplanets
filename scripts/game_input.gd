extends Node2D

@onready var icons_layer = $"../Icons"
@onready var hint_layer = $"../Hint"

var selected_pawn_uuids: Dictionary = {}

var under_mouse: PhysicsPointQueryParameters2D

var is_mouse_left_down: bool = false
var is_drag_selecting: bool = false
var is_showing_all_rooms: bool = false
var drag_start_global: Vector2 = Vector2.ZERO
var drag_current_global: Vector2 = Vector2.ZERO
var drag_threshold_px: float = 6.0

var hovered_room_id: int = -1

var room_hover_polygons_by_id: Dictionary = {}
var room_hover_alpha_by_id: Dictionary = {}
var room_hover_tweens: Dictionary = {}
var room_icon_tweens: Dictionary = {}
var room_hover_colors_by_id: Dictionary = {}

var room_hover_tween_time: float = 0.12
var room_hover_fill_alpha: float = 0.22
var room_hover_outline_alpha: float = 0.9
var room_hover_pawn_under_mouse_alpha_factor: float = 0.45
var is_hover_room_dimmed_by_pawn: bool = false
var room_hover_hole_enabled: bool = false
var room_hover_hole_global_position: Vector2 = Vector2.ZERO
var room_hover_hole_radius_px: float = 28.0
var room_hover_hole_softness_px: float = 1.5
var room_hover_hole_target_enabled: bool = false
var room_hover_hole_progress: float = 0.0
var room_hover_hole_tween: Tween
var room_hover_hole_position_tween: Tween
var room_hover_hole_move_time: float = 0.08
var room_hover_hole_position_snap_distance_px: float = 1.0

var room_hover_hole_show_time: float = 0.20
var room_hover_hole_hide_time: float = 0.18

var room_hover_hole_material: ShaderMaterial
var room_icon_hole_materials_by_id: Dictionary = {}



func _ready() -> void:
	under_mouse = PhysicsPointQueryParameters2D.new()
	under_mouse.collide_with_areas = true
	under_mouse.collide_with_bodies = false
	under_mouse.collision_mask = 0xFFFFFFFF
	
	_setup_room_hover_hole_material()
	
	icons_layer.connect("restart_finish", _finish_init)

func _process(_delta: float) -> void:
	_update_room_hover()
	_update_room_hover_hole_materials()
	_update_hint_layer()


func _update_hint_layer() -> void:
	hint_layer.position = get_local_mouse_position() + Vector2(10, 10)
	hint_layer.render(get_info_at_global_position(get_global_mouse_position()))


func _finish_init() -> void:
	for room: Dictionary in get_parent().rooms:
		var room_id: int = int(room.get("room_id", -1))
		var polygons: Array = room.get("polygons", [])
		
		var room_kind: String = str(room["kind"])
		room_hover_colors_by_id[room_id] = Color(icons_layer.icons_main_colors.get(room_kind, Color.BLACK))
		
		room_hover_polygons_by_id[room_id] = polygons
		
		var icon: CanvasItem = icons_layer.get_node_or_null("RoomIcon_%s" % room_id)
		if icon != null:
			icon.visible = false
			icon.modulate.a = 0.0
			_setup_room_icon_hole_material(room_id, icon)
		
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
	if event.is_action_pressed("show_all_rooms"):
		is_showing_all_rooms = true
		_set_all_rooms_visible(true)
		return
	
	if event.is_action_released("show_all_rooms"):
		is_showing_all_rooms = false
		_set_all_rooms_visible(false)
		_update_room_hover()
		return
	
	if event.is_action_pressed("select"):
		is_mouse_left_down = true
		is_drag_selecting = false
		drag_start_global = get_global_mouse_position()
		drag_current_global = drag_start_global
		queue_redraw()
		return
	
	if event.is_action_released("select"):
		is_mouse_left_down = false
		
		if is_drag_selecting:
			select_pawns_in_rect(_get_drag_global_rect())
			is_drag_selecting = false
			queue_redraw()
			return
		
		queue_redraw()
		_click_select()
		return
	
	if event.is_action_pressed("goto"):
		if is_mouse_left_down:
			return
		
		_click_goto()
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
	_draw_room_hover()
	
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

func _click_select() -> void:
	under_mouse.position = get_global_mouse_position()
	var mouse_position: Vector2 = get_global_mouse_position()
	var hits: Array[Dictionary] = get_world_2d().direct_space_state.intersect_point(under_mouse)
	var pawn: Area2D = _get_closest_visible_pawn_from_hits(hits, mouse_position)
	
	if pawn != null:
		pawn_selected(pawn, pawn.get_meta("uuid"))
		return
	
	for hit: Dictionary in hits:
		var collider: Object = hit.get("collider", null)
		
		if collider == null:
			continue
		
		if collider.is_in_group("door"):
			door_selected(collider, collider.get_meta("door_cells"))
			return


func _click_goto() -> void:
	if selected_pawn_uuids.is_empty():
		return
	
	under_mouse.position = get_global_mouse_position()
	var hits: Array[Dictionary] = get_world_2d().direct_space_state.intersect_point(under_mouse)
	
	var rooms: Array = []
	
	for hit: Dictionary in hits:
		var collider: Object = hit.get("collider", null)
		
		if collider == null:
			continue
		
		if collider.is_in_group("pawn"):
			return
		
		if collider.is_in_group("room"):
			rooms.append(collider)
	
	if not rooms.is_empty():
		room_selected(rooms[0], int(rooms[0].get_meta("room")))

func _get_pawn_under_mouse() -> Area2D:
	under_mouse.position = get_global_mouse_position()
	var mouse_position: Vector2 = get_global_mouse_position()
	var hits: Array[Dictionary] = get_world_2d().direct_space_state.intersect_point(under_mouse)
	return _get_closest_visible_pawn_from_hits(hits, mouse_position)


func _get_closest_visible_pawn_from_hits(hits: Array[Dictionary], global_position: Vector2) -> Area2D:
	var closest_pawn: Area2D = null
	var closest_distance_sq: float = INF
	
	for hit: Dictionary in hits:
		var collider: Object = hit.get("collider", null)
		
		if collider == null:
			continue
		
		if not collider.is_in_group("pawn"):
			continue
		
		var pawn_id: String = str(collider.get_meta("uuid"))
		
		if not get_parent().pawns.has(pawn_id):
			continue
		
		if not get_parent()._pawn_is_visible_to_player(pawn_id):
			continue
		
		var pawn_area: Area2D = collider as Area2D
		var distance_sq: float = pawn_area.global_position.distance_squared_to(global_position)
		
		if closest_pawn == null or distance_sq < closest_distance_sq:
			closest_pawn = pawn_area
			closest_distance_sq = distance_sq
	
	return closest_pawn

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
		var pawn = get_parent().pawns.get(uuid)
		if pawn != null:
			pawn["node"].set_selected(false)
	
	selected_pawn_uuids.clear()


func door_selected(
	_area: Area2D,
	cells: Array
) -> void:
	get_parent().request_player_toggle_door(cells)


func room_selected(
	_area: Area2D,
	room: int
) -> void:
	if selected_pawn_uuids.is_empty():
		return
	
	for uuid_variant: Variant in selected_pawn_uuids.keys():
		var uuid: String = str(uuid_variant)
		var available_cells: Array[Vector2i] = get_parent().dynamically_available_cells(
			room,
			true,
			false,
			true,
			uuid
		)
		
		if available_cells.is_empty():
			return
		
		var selected_cell: Vector2i = available_cells[0]
		var target_cell: Vector2i = get_parent().get_player_room_target_cell(
			uuid,
			selected_cell
		)

		var ignore_pawns_on_target: bool = target_cell != selected_cell

		get_parent().pawn_to_cell(
			uuid,
			target_cell,
			{},
			ignore_pawns_on_target,
			PawnTaskLogic.TASK_LOCK_PLAYER
		)


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

func _update_room_hover() -> void:
	var raw_room_id: int = _get_room_id_under_mouse()
	var pawn_under_mouse: Area2D = _get_pawn_under_mouse()
	
	var need_hole: bool = raw_room_id != -1 and pawn_under_mouse != null
	
	if need_hole:
		_set_room_hover_hole(true, pawn_under_mouse.global_position)
	else:
		_set_room_hover_hole(false, room_hover_hole_global_position)
	
	if is_showing_all_rooms:
		return
	
	if selected_pawn_uuids.is_empty():
		if hovered_room_id != -1:
			_set_room_hovered(hovered_room_id, false)
			hovered_room_id = -1
		
		return
	
	var room_id: int = raw_room_id
	
	if room_id != -1 and _is_only_selected_room(room_id):
		room_id = -1
	
	if hovered_room_id == room_id:
		return
	
	if hovered_room_id != -1:
		_set_room_hovered(hovered_room_id, false)
	
	hovered_room_id = room_id
	
	if hovered_room_id != -1:
		_set_room_hovered(hovered_room_id, true)

func _get_selected_pawn_room_ids() -> Dictionary:
	var result: Dictionary = {}
	var tile_layer: TileMapLayer = get_parent().foundation_layer
	
	for uuid_variant: Variant in selected_pawn_uuids.keys():
		var uuid: String = str(uuid_variant)
		var pawn_obj = get_parent().pawns.get(uuid)
		if pawn_obj == null:
			continue
		var pawn: Node2D = pawn_obj["node"]
		
		var cell: Vector2i = tile_layer.local_to_map(tile_layer.to_local(pawn.global_position))
		var room_id: int = get_parent().cell_to_room(cell)
		
		if room_id == -1:
			continue
		
		result[room_id] = true
	
	return result

func _is_only_selected_room(room_id: int) -> bool:
	var selected_room_ids: Dictionary = _get_selected_pawn_room_ids()
	
	if selected_room_ids.size() != 1:
		return false
	
	return room_id in selected_room_ids

func _get_room_id_under_mouse() -> int:
	under_mouse.position = get_global_mouse_position()
	var hits: Array[Dictionary] = get_world_2d().direct_space_state.intersect_point(under_mouse)
	
	for hit: Dictionary in hits:
		var collider: Object = hit.get("collider", null)
		
		if collider == null:
			continue
		
		if collider.is_in_group("room"):
			return int(collider.get_meta("room"))
	
	return -1

func _set_all_rooms_visible(to_visible: bool) -> void:
	if to_visible:
		for room_id_variant: Variant in room_hover_polygons_by_id.keys():
			var room_id: int = int(room_id_variant)
			_set_room_hovered(room_id, true)
		
		return
	
	var room_id_under_mouse: int = _get_room_id_under_mouse()
	hovered_room_id = room_id_under_mouse
	
	for room_id_variant: Variant in room_hover_polygons_by_id.keys():
		var hide_room_id: int = int(room_id_variant)
		
		if hide_room_id == room_id_under_mouse:
			continue
		
		_set_room_hovered(hide_room_id, false)

func _set_room_hovered(room_id: int, hovered: bool) -> void:
	_set_room_area_hovered(room_id, hovered)
	_set_room_icon_hovered(room_id, hovered)


func _set_room_area_hovered(room_id: int, hovered: bool) -> void:
	if room_hover_tweens.has(room_id):
		room_hover_tweens[room_id].kill()
	
	var from_alpha: float = float(room_hover_alpha_by_id.get(room_id, 0.0))
	var to_alpha: float = 1.0 if hovered else 0.0
	
	var tween: Tween = create_tween()
	room_hover_tweens[room_id] = tween
	
	tween.tween_method(
		func(value: float) -> void:
			room_hover_alpha_by_id[room_id] = value
			queue_redraw(),
		from_alpha,
		to_alpha,
		room_hover_tween_time
	)
	
	tween.finished.connect(
		func() -> void:
			room_hover_tweens.erase(room_id)
			
			if not hovered:
				room_hover_alpha_by_id.erase(room_id)
			
			queue_redraw()
	)


func _set_room_icon_hovered(room_id: int, hovered: bool) -> void:
	var icon: CanvasItem = icons_layer.get_node_or_null("RoomIcon_%s" % room_id)
	
	if icon == null:
		return
	
	if room_icon_tweens.has(room_id):
		room_icon_tweens[room_id].kill()
	
	if hovered:
		icon.visible = true
	
	var tween: Tween = create_tween()
	room_icon_tweens[room_id] = tween
	
	tween.tween_property(
		icon,
		"modulate:a",
		1.0 if hovered else 0.0,
		room_hover_tween_time
	)
	
	tween.finished.connect(
		func() -> void:
			room_icon_tweens.erase(room_id)
			
			if not hovered:
				icon.visible = false
	)


func _draw_room_hover() -> void:
	for room_id_variant: Variant in room_hover_alpha_by_id.keys():
		var room_id: int = int(room_id_variant)
		
		var hover_alpha: float = float(room_hover_alpha_by_id.get(room_id, 0.0))
		
		if hover_alpha <= 0.0:
			continue
		
		var main_color: Color = room_hover_colors_by_id[room_id]
		
		var fill_color: Color = Color(
			main_color.r,
			main_color.g,
			main_color.b,
			room_hover_fill_alpha * hover_alpha
		)
		
		var outline_color: Color = Color(
			main_color.r,
			main_color.g,
			main_color.b,
			room_hover_outline_alpha * hover_alpha
		)
		
		for polygon: PackedVector2Array in room_hover_polygons_by_id[room_id]:
			draw_colored_polygon(polygon, fill_color)
			draw_polyline(_closed_polygon(polygon), outline_color, 2.0, true)


func _closed_polygon(polygon: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = polygon.duplicate()
	
	if result.size() > 0:
		result.append(result[0])
	
	return result


func _setup_room_hover_hole_material() -> void:
	room_hover_hole_material = load("res://scripts/hole_in_room.material")
	material = room_hover_hole_material


func _setup_room_icon_hole_material(room_id: int, icon: CanvasItem) -> void:
	var shader_material: ShaderMaterial = load("res://scripts/hole_in_room.material")
	icon.material = shader_material
	room_icon_hole_materials_by_id[room_id] = shader_material

func _update_room_hover_hole_materials() -> void:
	var hole_center_screen: Vector2 = Vector2.ZERO
	
	if room_hover_hole_enabled:
		hole_center_screen = get_viewport().get_canvas_transform() * room_hover_hole_global_position
	
	_update_hole_material(
		room_hover_hole_material,
		hole_center_screen
	)
	
	for shader_material_variant: Variant in room_icon_hole_materials_by_id.values():
		var shader_material: ShaderMaterial = shader_material_variant
		
		_update_hole_material(
			shader_material,
			hole_center_screen
		)


func _update_hole_material(
	shader_material: ShaderMaterial,
	hole_center_screen: Vector2
) -> void:
	if shader_material == null:
		return
	
	shader_material.set_shader_parameter("hole_progress", room_hover_hole_progress)
	shader_material.set_shader_parameter("hole_center_screen", hole_center_screen)
	shader_material.set_shader_parameter("hole_radius_px", room_hover_hole_radius_px)
	shader_material.set_shader_parameter("hole_softness_px", room_hover_hole_softness_px)

func _set_room_hover_hole(
	enabled: bool,
	gposition: Vector2
) -> void:
	if enabled:
		_set_room_hover_hole_position(gposition)
	
	if room_hover_hole_target_enabled == enabled:
		return
	
	room_hover_hole_target_enabled = enabled
	
	if room_hover_hole_tween != null:
		room_hover_hole_tween.kill()
	
	var from_progress: float = room_hover_hole_progress
	var to_progress: float = 1.0 if enabled else 0.0
	var tween_time: float = room_hover_hole_show_time if enabled else room_hover_hole_hide_time
	
	room_hover_hole_enabled = true
	
	room_hover_hole_tween = create_tween()
	room_hover_hole_tween.set_trans(Tween.TRANS_SINE)
	room_hover_hole_tween.set_ease(Tween.EASE_OUT)
	
	room_hover_hole_tween.tween_method(
		func(value: float) -> void:
			room_hover_hole_progress = value,
		from_progress,
		to_progress,
		tween_time
	)
	
	room_hover_hole_tween.finished.connect(
		func() -> void:
			if not room_hover_hole_target_enabled:
				room_hover_hole_enabled = false
				room_hover_hole_progress = 0.0
			
			room_hover_hole_tween = null
	)

func _set_room_hover_hole_position(gposition: Vector2) -> void:
	if room_hover_hole_progress <= 0.001 and not room_hover_hole_enabled:
		room_hover_hole_global_position = gposition
		return
	
	if room_hover_hole_global_position.distance_to(gposition) <= room_hover_hole_position_snap_distance_px:
		room_hover_hole_global_position = gposition
		return
	
	if room_hover_hole_position_tween != null:
		room_hover_hole_position_tween.kill()
	
	var from_position: Vector2 = room_hover_hole_global_position
	var to_position: Vector2 = gposition
	
	room_hover_hole_position_tween = create_tween()
	room_hover_hole_position_tween.set_trans(Tween.TRANS_SINE)
	room_hover_hole_position_tween.set_ease(Tween.EASE_OUT)
	
	room_hover_hole_position_tween.tween_method(
		func(value: Vector2) -> void:
			room_hover_hole_global_position = value,
		from_position,
		to_position,
		room_hover_hole_move_time
	)
	
	room_hover_hole_position_tween.finished.connect(
		func() -> void:
			room_hover_hole_position_tween = null
	)


func get_info_at_global_position(global_position: Vector2) -> Dictionary:
	var hits: Array[Dictionary] = _get_info_hits_at_global_position(global_position)
	
	for hit: Dictionary in hits:
		var collider: Object = hit.get("collider", null)
		
		if collider == null:
			continue
		
		if collider.is_in_group("door"):
			return {
				"type": "door",
				"info": get_door_info(collider.get_meta("door_cells"))
			}
	
	var pawn: Area2D = _get_closest_visible_pawn_from_hits(hits, global_position)
	
	if pawn != null:
		var pawn_id: String = str(pawn.get_meta("uuid"))
		return {
			"type": "pawn",
			"info": get_pawn_info(pawn_id)
		}
	
	for hit: Dictionary in hits:
		var collider: Object = hit.get("collider", null)
		
		if collider == null:
			continue
		
		if collider.is_in_group("room"):
			return {
				"type": "room",
				"info": get_room_info(int(collider.get_meta("room")))
			}
	
	return {}


func get_pawn_info(pawn_id: String) -> Dictionary:
	var starship: Node = get_parent()
	var pawn_data: Dictionary = starship.pawns[pawn_id]
	var pawn_node: Node2D = pawn_data["node"]
	
	return {
		"pawn_name": str(pawn_data.get("pawn_name", pawn_node.get_meta("pawn_name", ""))),
		"health": int(pawn_node.health),
		"current_task": _get_pawn_current_task_name(pawn_id),
		"health_balance": {
			"income": {
				"aid_station": _get_pawn_aid_station_health_income(pawn_id)
			},
			"loss": {
				"fire": _get_pawn_fire_health_loss(pawn_id),
				"pawns": _get_pawn_battle_health_loss(pawn_id),
				"oxygen": _get_pawn_oxygen_health_loss(pawn_id)
			}
		}
	}



func _get_door_fortress_percent(door_key: String) -> float:
	var starship: Node = get_parent()
	var max_hp: float = _get_current_door_max_hp_for_info()
	var fortress: float = float(starship.door_hp_by_key.get(door_key, max_hp))
	
	if max_hp <= 0.0:
		return 100.0
	
	return clampf(fortress / max_hp * 100.0, 0.0, 100.0)


func _get_room_fortress_percent(room_id: int) -> float:
	var starship: Node = get_parent()
	var fortress: float = float(starship.room_fortitude_by_room.get(room_id, starship.room_fortitude_max))
	var max_fortress: float = float(starship.room_fortitude_max)
	var extra_fortress: float = float(starship.room_repair_fortitude_extra)
	
	if max_fortress <= 0.0:
		return 100.0
	
	if fortress <= max_fortress:
		return clampf(fortress / max_fortress * 100.0, 0.0, 100.0)
	
	if extra_fortress <= 0.0:
		return 100.0
	
	return clampf(100.0 + (fortress - max_fortress) / extra_fortress * 100.0, 100.0, 200.0)

func get_door_info(door_cells: Array) -> Dictionary:
	var starship: Node = get_parent()
	var door_key: String = _info_door_cells_key(door_cells)
	var cooldown: float = float(starship.door_close_cooldowns.get(door_key, 0.0))
	var is_open: bool = DoorManager.get_door_state(
		starship.foundation_layer,
		door_cells
	) == DoorManager.DOOR_STATE_OPEN
	
	return {
		"hidden": false,
		"level": int(starship.doors_level),
		"fortress": _get_door_fortress_percent(door_key),
		"open": is_open,
		"broken": cooldown > 0.0,
		"cooldown": cooldown
	}


func get_room_info(room_id: int) -> Dictionary:
	var starship: Node = get_parent()
	var room: Dictionary = starship.rooms[room_id]

	if not starship._room_is_visible_to_player(room_id):
		return _get_hidden_room_info(room_id, str(room["kind"]), _get_room_air_capacity(room_id))

	var oxygen_balance: Dictionary = _get_room_oxygen_balance(room_id)

	return {
		"hidden": false,
		"specialization": str(room["kind"]),
		"oxygen": float(starship.oxygen_by_room.get(room_id, 0.0)),
		"air_capacity": _get_room_air_capacity(room_id),
		"holes": _get_room_holes_count(room_id),
		"fires": _get_room_fires_count(room_id),
		"health": {
			"current": int(starship.room_integrity_by_room.get(room_id, 0)),
			"maximum": int(starship.room_integrity_max_by_room.get(room_id, starship.room_integrity_max_default)),
			"fortress": _get_room_fortress_percent(room_id),
			"energy": int(starship.room_current_power_by_room.get(room_id, 0))
		},
		"oxygen_balance": oxygen_balance
	}


func _get_hidden_room_info(room_id: int, specialization: String, air_capacity: float) -> Dictionary:
	var starship: Node = get_parent()
	
	return {
		"hidden": true,
		"specialization": specialization,
		"oxygen": 0.0,
		"air_capacity": air_capacity,
		"holes": 0,
		"fires": 0,
		"health": {
			"current": int(starship.room_integrity_by_room.get(room_id, 0)),
			"maximum": int(starship.room_integrity_max_by_room.get(room_id, starship.room_integrity_max_default)),
			"fortress": _get_room_fortress_percent(room_id),
			"energy": int(starship.room_current_power_by_room.get(room_id, 0))
		},
		"oxygen_balance": _get_empty_room_oxygen_balance()
	}


func _get_empty_room_oxygen_balance() -> Dictionary:
	return {
		"income": {
			"starship": 0.0,
			"doors": 0.0,
			"pawns": 0.0
		},
		"loss": {
			"fires": 0.0,
			"holes": 0.0,
			"doors": 0.0,
			"pawns": 0.0
		}
	}


func _get_info_hits_at_global_position(global_position: Vector2) -> Array[Dictionary]:
	under_mouse.position = global_position
	return get_world_2d().direct_space_state.intersect_point(under_mouse)


func _get_pawn_current_task_name(pawn_id: String) -> String:
	var starship: Node = get_parent()
	var pawn_data: Dictionary = starship.pawns[pawn_id]
	var state: String = str(pawn_data["state"])
	
	if state == PawnTaskLogic.STATE_MOVING:
		return "GOTO"
	
	if state == PawnTaskLogic.STATE_IDLE:
		return "IDLE"
	
	var task: Dictionary = pawn_data["task"]
	var task_type: String = str(task.get("type", ""))
	
	if task_type == "":
		return "IDLE"
	
	return task_type.to_upper()


func _get_pawn_aid_station_health_income(_pawn_id: String) -> float:
	return 0.0


func _get_pawn_fire_health_loss(pawn_id: String) -> float:
	var starship: Node = get_parent()
	var room_id: int = _get_pawn_room_id(pawn_id)
	
	if room_id < 0:
		return 0.0
	
	if _get_room_fires_count(room_id) <= 0:
		return 0.0
	
	return float(starship.pawn_fire_room_damage) * _get_pawn_fire_room_damage_factor_for_info(pawn_id)


func _get_pawn_oxygen_health_loss(pawn_id: String) -> float:
	var starship: Node = get_parent()
	var room_id: int = _get_pawn_room_id(pawn_id)
	
	if room_id < 0:
		return 0.0
	
	var pawn_node: Node2D = starship.pawns[pawn_id]["node"]
	var oxygen: float = float(starship.oxygen_by_room.get(room_id, 100.0))
	
	if oxygen >= pawn_node.min_oxygen and oxygen <= pawn_node.max_oxygen:
		return 0.0
	
	return float(starship.pawn_no_oxygen_damage) * _get_pawn_no_oxygen_damage_factor_for_info(pawn_id)


func _get_pawn_battle_health_loss(pawn_id: String) -> float:
	var starship: Node = get_parent()
	var result: float = 0.0
	var interval: float = maxf(float(starship.pawn_battle_damage_interval), 0.001)
	
	for attacker_id: String in starship.pawns.keys():
		if attacker_id == pawn_id:
			continue
		
		var attacker_data: Dictionary = starship.pawns[attacker_id]
		
		if attacker_data["state"] != PawnTaskLogic.STATE_WORKING:
			continue
		
		var task: Dictionary = attacker_data["task"]
		
		if task.get("type", "") != PawnTaskLogic.TASK_BATTLE:
			continue
		
		if task.get("target_pawn_id", "") != pawn_id:
			continue
		
		if not starship._battle_target_is_valid(attacker_id, pawn_id):
			continue
		
		var base_damage: int = starship._get_battle_damage_value(attacker_id, pawn_id)
		var damage: float = float(base_damage) * _get_pawn_battle_damage_factor_for_info(pawn_id)
		result += damage / interval
	
	return result


func _get_pawn_room_id(pawn_id: String) -> int:
	var starship: Node = get_parent()
	return starship.cell_to_room(starship._pawn_position_to_foundation_cell(pawn_id))


func _get_room_oxygen_balance(room_id: int) -> Dictionary:
	var pawn_balance: Dictionary = _get_room_pawn_oxygen_balance(room_id)
	var door_balance: Dictionary = _get_room_door_oxygen_balance(room_id)
	
	return {
		"income": {
			"starship": _get_room_starship_oxygen_income_max(room_id),
			"doors": float(door_balance["income"]),
			"pawns": float(pawn_balance["income"])
		},
		"loss": {
			"fires": _get_room_fire_oxygen_loss(room_id),
			"holes": _get_room_hole_oxygen_loss(room_id),
			"doors": float(door_balance["loss"]),
			"pawns": float(pawn_balance["loss"])
		}
	}


func _get_room_door_oxygen_balance(room_id: int) -> Dictionary:
	var starship: Node = get_parent()
	var income: float = 0.0
	var loss: float = 0.0
	
	for door_link: Dictionary in starship.oxygen_door_links:
		var room_ids: Array = door_link["room_ids"]
		
		if not (room_id in room_ids):
			continue
		
		var door_cells: Array = door_link["door_cells"]
		var door_state: String = DoorManager.get_door_state(
			starship.foundation_layer,
			door_cells
		)
		
		if door_state != DoorManager.DOOR_STATE_OPEN:
			continue
		
		var door_size: int = int(door_link["door_size"])
		
		if room_ids.size() >= 2:
			var flow: float = clampf(
				float(starship.oxygen_door_flow_per_second) * float(door_size),
				0.0,
				1.0
			)
			var total_air: float = 0.0
			var total_area: float = 0.0
			
			for linked_room_id: int in room_ids:
				var linked_area: float = _get_room_area(linked_room_id)
				var linked_oxygen: float = clampf(float(starship.oxygen_by_room.get(linked_room_id, 0.0)), 0.0, 100.0)
				
				total_air += linked_oxygen * linked_area
				total_area += linked_area
			
			if total_area <= 0.0:
				continue
			
			var room_area: float = _get_room_area(room_id)
			var room_oxygen: float = clampf(float(starship.oxygen_by_room.get(room_id, 0.0)), 0.0, 100.0)
			var current_air: float = room_oxygen * room_area
			var target_oxygen: float = total_air / total_area
			var target_air: float = target_oxygen * room_area
			var next_air: float = lerpf(current_air, target_air, flow)
			var delta_oxygen: float = (next_air - current_air) / room_area
			
			if delta_oxygen > 0.0:
				income += delta_oxygen
			else:
				loss += -delta_oxygen
		elif room_ids.size() == 1:
			var room_area: float = _get_room_area(room_id)
			var exterior_loss: float = (
				float(starship.oxygen_exterior_loss_per_second)
				* float(door_size)
				/ room_area
			)
			loss += exterior_loss
	
	return {
		"income": income,
		"loss": loss
	}


func _get_room_pawn_oxygen_balance(room_id: int) -> Dictionary:
	return {
		"income": _air_to_room_oxygen_percent(room_id, _get_room_pawn_oxygen_income_air(room_id)),
		"loss": _air_to_room_oxygen_percent(room_id, _get_room_pawn_oxygen_loss_air(room_id))
	}


func _get_room_pawn_oxygen_income_air(room_id: int) -> float:
	var starship: Node = get_parent()
	var result: float = 0.0
	
	for pawn_id: String in starship.pawns.keys():
		if _get_pawn_room_id(pawn_id) != room_id:
			continue
		
		var consumption: float = _get_pawn_oxygen_consumption_for_info(pawn_id)
		
		if consumption < 0.0:
			result += -consumption
	
	return result


func _get_room_pawn_oxygen_loss_air(room_id: int) -> float:
	var starship: Node = get_parent()
	var result: float = 0.0
	
	for pawn_id: String in starship.pawns.keys():
		if _get_pawn_room_id(pawn_id) != room_id:
			continue
		
		var consumption: float = _get_pawn_oxygen_consumption_for_info(pawn_id)
		
		if consumption > 0.0:
			result += consumption
	
	return result


func _get_room_fire_oxygen_loss(room_id: int) -> float:
	return _air_to_room_oxygen_percent(room_id, _get_room_fire_oxygen_loss_air(room_id))


func _get_room_fire_oxygen_loss_air(room_id: int) -> float:
	var starship: Node = get_parent()
	var result: float = 0.0
	
	for fire_data: Dictionary in starship.fires.values():
		var fire: Node2D = fire_data["node"]
		
		if int(fire.get_meta("room")) != room_id:
			continue
		
		result += float(fire.oxygen_consumption)
	
	return result


func _get_room_hole_oxygen_loss(room_id: int) -> float:
	return _air_to_room_oxygen_percent(room_id, _get_room_hole_oxygen_loss_air(room_id))


func _get_room_hole_oxygen_loss_air(room_id: int) -> float:
	var starship: Node = get_parent()
	var result: float = 0.0
	var room: Dictionary = starship.rooms[room_id]
	
	for hole_cell: Vector2i in starship.hull_holes.keys():
		if not (hole_cell in room["floor_cells"]):
			continue
		
		var tile_data: TileData = starship.foundation_layer.get_cell_tile_data(hole_cell)
		
		if tile_data == null:
			continue
		
		result += float(tile_data.get_custom_data("impact")) * float(starship.oxygen_hole_loss_per_impact)
	
	return result


func _get_room_starship_oxygen_income(room_id: int) -> float:
	return _get_room_starship_oxygen_income_max(room_id)


func _get_room_starship_oxygen_income_max(room_id: int) -> float:
	var income_by_room: Dictionary = _get_starship_oxygen_income_hypothetical_by_room(room_id)
	return float(income_by_room.get(room_id, 0.0))


func _get_starship_oxygen_income_hypothetical_by_room(forced_room_id: int) -> Dictionary:
	return _get_starship_oxygen_income_with_forced_needy_room(forced_room_id)


func _get_starship_oxygen_income_with_forced_needy_room(forced_room_id: int) -> Dictionary:
	var starship: Node = get_parent()
	var result: Dictionary = {}
	var air_by_room: Dictionary = {}
	
	for current_room_id: int in range(starship.rooms.size()):
		var area: float = _get_room_area(current_room_id)
		var oxygen: float = clampf(float(starship.oxygen_by_room.get(current_room_id, 0.0)), 0.0, 100.0)
		
		air_by_room[current_room_id] = oxygen * area
		result[current_room_id] = 0.0
	
	_apply_door_oxygen_to_air_by_room_for_info(air_by_room)
	
	for current_room_id: int in range(starship.rooms.size()):
		var consumption: float = (
			_get_room_fire_oxygen_loss_air(current_room_id)
			+ _get_room_hole_oxygen_loss_air(current_room_id)
			+ _get_room_pawn_oxygen_loss_air(current_room_id)
			- _get_room_pawn_oxygen_income_air(current_room_id)
		)
		
		air_by_room[current_room_id] = maxf(
			0.0,
			float(air_by_room[current_room_id]) - consumption
		)
	
	var remaining_air: float = maxf(float(starship.oxygen_air_production_per_second), 0.0)
	
	while remaining_air > 0.001:
		var needy_rooms: Array[int] = []
		
		for current_room_id: int in range(starship.rooms.size()):
			var area: float = _get_room_area(current_room_id)
			var max_air: float = 100.0 * area
			var current_air: float = float(air_by_room[current_room_id])
			
			if current_room_id == forced_room_id:
				needy_rooms.append(current_room_id)
			elif current_air < max_air - 0.001:
				needy_rooms.append(current_room_id)
		
		if needy_rooms.is_empty():
			break
		
		var share: float = remaining_air / float(needy_rooms.size())
		var used_air: float = 0.0
		
		for current_room_id: int in needy_rooms:
			var area: float = _get_room_area(current_room_id)
			var max_air: float = 100.0 * area
			var current_air: float = float(air_by_room[current_room_id])
			
			if current_room_id == forced_room_id:
				max_air = current_air + remaining_air
			
			var deficit: float = max_air - current_air
			var added_air: float = minf(share, deficit)
			
			air_by_room[current_room_id] = current_air + added_air
			result[current_room_id] = float(result[current_room_id]) + added_air / area
			used_air += added_air
		
		if used_air <= 0.001:
			break
		
		remaining_air -= used_air
	
	return result


func _apply_door_oxygen_to_air_by_room_for_info(air_by_room: Dictionary) -> void:
	var starship: Node = get_parent()
	
	for door_link: Dictionary in starship.oxygen_door_links:
		var door_cells: Array = door_link["door_cells"]
		var door_state: String = DoorManager.get_door_state(
			starship.foundation_layer,
			door_cells
		)
		
		if door_state != DoorManager.DOOR_STATE_OPEN:
			continue
		
		var room_ids: Array = door_link["room_ids"]
		var door_size: int = int(door_link["door_size"])
		
		if room_ids.size() >= 2:
			var total_air: float = 0.0
			var total_area: float = 0.0
			
			for linked_room_id: int in room_ids:
				total_air += float(air_by_room[linked_room_id])
				total_area += _get_room_area(linked_room_id)
			
			if total_area <= 0.0:
				continue
			
			var target_oxygen: float = total_air / total_area
			var flow: float = clampf(
				float(starship.oxygen_door_flow_per_second) * float(door_size),
				0.0,
				1.0
			)
			
			for linked_room_id: int in room_ids:
				var area: float = _get_room_area(linked_room_id)
				var current_air: float = float(air_by_room[linked_room_id])
				var target_air: float = target_oxygen * area
				
				air_by_room[linked_room_id] = lerpf(current_air, target_air, flow)
		elif room_ids.size() == 1:
			var linked_room_id: int = int(room_ids[0])
			var leak: float = float(starship.oxygen_exterior_loss_per_second) * float(door_size)
			
			air_by_room[linked_room_id] = maxf(
				0.0,
				float(air_by_room[linked_room_id]) - leak
			)


func _get_room_area(room_id: int) -> float:
	return maxf(float(get_parent().oxygen_room_areas.get(room_id, 1.0)), 1.0)


func _get_room_air_capacity(room_id: int) -> float:
	return 100.0 * _get_room_area(room_id)


func _air_to_room_oxygen_percent(room_id: int, air_amount: float) -> float:
	return float(air_amount) / _get_room_area(room_id)


func _get_room_holes_count(room_id: int) -> int:
	var starship: Node = get_parent()
	var result: int = 0
	var room: Dictionary = starship.rooms[room_id]
	
	for hole_cell: Vector2i in starship.hull_holes.keys():
		if hole_cell in room["floor_cells"]:
			result += 1
	
	return result


func _get_room_fires_count(room_id: int) -> int:
	var starship: Node = get_parent()
	var result: int = 0
	
	for fire_data: Dictionary in starship.fires.values():
		var fire: Node2D = fire_data["node"]
		
		if int(fire.get_meta("room")) == room_id:
			result += 1
	
	return result


func _get_current_door_max_hp_for_info() -> float:
	var starship: Node = get_parent()
	var index: int = clampi(
		int(starship.doors_level),
		0,
		starship.health_doors_levels_map.size() - 1
	)
	return float(starship.health_doors_levels_map[index])


func _info_door_cells_key(door_cells: Array) -> String:
	var cells: Array[String] = []
	
	for cell_variant: Variant in door_cells:
		var cell: Vector2i = cell_variant
		cells.append(str(cell.x) + ":" + str(cell.y))
	
	cells.sort()
	return "|".join(cells)


func _get_pawn_oxygen_consumption_for_info(pawn_id: String) -> float:
	return float(get_parent().pawns[pawn_id]["node"].get_oxygen_consumption())


func _get_pawn_no_oxygen_damage_factor_for_info(pawn_id: String) -> float:
	return float(get_parent().pawns[pawn_id]["node"].get_no_oxygen_damage_factor())


func _get_pawn_fire_room_damage_factor_for_info(pawn_id: String) -> float:
	return float(get_parent().pawns[pawn_id]["node"].get_fire_room_damage_factor())


func _get_pawn_battle_damage_factor_for_info(pawn_id: String) -> float:
	return float(get_parent().pawns[pawn_id]["node"].get_battle_damage_factor())
