extends Node2D
class_name Starship

signal restart_finish()

signal add_pawn_event(node, uuid)
signal delete_pawn_event(node, uuid)

@export var pawns2spawn: Array[Dictionary] = [{"race": "human"}, {"race": "human"}]

@onready var foundation_layer = $Foundation
@onready var stations_layer = $Stations
@onready var technical_layer = $Technical
@onready var icons_layer = $Icons
@onready var pawns_layer = $Pawns
@onready var fire_layer = $Fire
const SAMPLES_PER_TILE: int = 1

var time2change_door_state = 0.2

var rooms: Array[Dictionary] = []
var pawns: Dictionary = {}
var fires: Dictionary = {}

@export var oxygen_enabled: bool = true
@export var oxygen_default_percent: float = 100.0

# Главная переменная самовосстановления кислорода.
# Можно менять динамически прямо во время игры.
@export var oxygen_air_production_per_second: float = 200.0

# Скорость выравнивания кислорода через открытую дверь.
@export var oxygen_door_flow_per_second: float = 0.65

# Потеря кислорода через открытую дверь в космос / никуда.
@export var oxygen_exterior_loss_per_second: float = 38.0

# Потеря кислорода от пробоин.
# Реальная потеря = oxygen_hole_loss_per_impact * impact.
@export var oxygen_hole_loss_per_impact: float = 10.0

@export var oxygen_visual_max_alpha: float = 0.65
@export var oxygen_recheck_interval: float = 0.25

var oxygen_pawn_consumption: Dictionary = {}
var oxygen_overlay_layer: Node2D
var oxygen_by_room: Dictionary = {}
var oxygen_room_areas: Dictionary = {}
var oxygen_door_links: Array[Dictionary] = []
var oxygen_consumption: Dictionary = {}
var oxygen_room_polygons: Dictionary = {}
var oxygen_recheck_timer: float = 0.0

@export var pawn_task_enabled: bool = true
@export var pawn_task_recheck_interval: float = 0.25
@export var hull_repair_seconds_per_step: float = 4.0

var pawn_task_recheck_timer: float = 0.0

var hull_holes: Dictionary = {}
var hull_repair_progress: Dictionary = {}

var fortress_doors_level: int = 0
var fortress_doors_levels_map: Array = [0.7, 0.4, 0.2, 0.1]


func _ready() -> void:
	restart()

func _process(delta: float) -> void:
	if oxygen_enabled:
		process_oxygen(delta)
	
	if pawn_task_enabled:
		process_pawn_tasks(delta)
		_process_station_workers(delta)

func restart() -> void:
	technical_layer.hide()
	rooms = recalc_rooms()
	setup_oxygen()
	
	hull_holes = HullRepairLogic.collect_hull_holes(foundation_layer)
	hull_repair_progress = {}
	
	setup_icons()
	
	for pawn_key in pawns.keys():
		emit_signal("delete_pawn_event", pawns[pawn_key]["node"], pawn_key)
		pawns[pawn_key]["node"].queue_free()
	for pawn in pawns_layer.get_children():
		pawn.queue_free()
	pawns = {}
	for pawn in pawns2spawn:
		add_pawn(pawn["race"])
	
	emit_signal("restart_finish")

func add_pawn(race: String) -> bool:
	var available_cells: Array[Vector2i] = dynamically_available_cells()
	
	if available_cells.size() < 1:
		return false
	
	var pawn = load("res://scenes/pawn.tscn").instantiate()
	pawn.set_race(race)
	pawn.position = foundation_layer.map_to_local(available_cells[0])
	pawns_layer.add_child(pawn)
	var uuid = NodeUUID.uuid_v4()
	pawn.set_meta("uuid", uuid)
	
	pawn.connect("movement_action_required", _on_pawn_action_required.bind(uuid))
	pawn.connect("movement_finished", _on_pawn_movement_finished.bind(uuid))
	
	pawns[uuid] = {
		"node": pawn,
		"cells": [available_cells[0]],
		"state": "idle",
		"task": {}
	}
	emit_signal("add_pawn_event", pawn, uuid)
	return true

func _on_pawn_action_required(
	step: Dictionary,
	next_step_index: int,
	pawn_id: String
) -> void:
	var action: String = step["action"]
	var door_cells: Array = step["door_cells"]
	var door_key: String = _door_cells_key(door_cells)

	var task: Dictionary = pawns[pawn_id]["task"]

	if not task.has("opened_doors"):
		task["opened_doors"] = {}

	match action:
		"open_door":
			var current_state: String = DoorManager.get_door_state(
				foundation_layer,
				door_cells
			)

			var need_open: bool = current_state != "open"

			if need_open:
				task["opened_doors"][door_key] = true

				DoorManager.set_door_state(
					foundation_layer,
					door_cells,
					"open"
				)

				await get_tree().create_timer(time2change_door_state).timeout

		"close_door":
			if not task["opened_doors"].has(door_key):
				pawns[pawn_id]["task"]["next_step_index"] = next_step_index
				pawns[pawn_id]["node"].move_by_steps_until_action(
					pawns[pawn_id]["task"]["steps"],
					next_step_index
				)
				return

			var current_state: String = DoorManager.get_door_state(
				foundation_layer,
				door_cells
			)

			if current_state != "closed":
				DoorManager.set_door_state(
					foundation_layer,
					door_cells,
					"closed"
				)

				await get_tree().create_timer(time2change_door_state).timeout

			task["opened_doors"].erase(door_key)

	pawns[pawn_id]["task"]["next_step_index"] = next_step_index

	pawns[pawn_id]["node"].move_by_steps_until_action(
		pawns[pawn_id]["task"]["steps"],
		next_step_index
	)

func _door_cells_key(door_cells: Array) -> String:
	var result: PackedStringArray = []

	for cell: Vector2i in door_cells:
		result.append("%d:%d" % [cell.x, cell.y])

	result.sort()

	return "|".join(result)

func _on_pawn_movement_finished(pawn_id: String) -> void:
	var movement_task: Dictionary = pawns[pawn_id]["task"]
	var target_cell: Vector2i = movement_task["target_cell"]

	pawns[pawn_id]["cells"] = [target_cell]

	var after_move_task: Dictionary = movement_task.get("after_move_task", {})

	if not after_move_task.is_empty():
		pawns[pawn_id]["state"] = "working"
		pawns[pawn_id]["task"] = after_move_task
		return

	pawns[pawn_id]["state"] = "idle"
	pawns[pawn_id]["task"] = {}

static func add_room_kind_icon(
	room: Dictionary,
	room_polygon_space: CanvasItem,
	target_parent: CanvasItem,
	icon_size: Vector2,
	icon_dir: String = "res://assets/consoles/icons/",
) -> TextureRect:
	if room_polygon_space == null:
		push_warning("room_polygon_space is null")
		return null

	if target_parent == null:
		push_warning("target_parent is null")
		return null

	var kind: Variant = room.get("kind", null)
	var kind_string: String = str(kind)
	var icon_path: String = icon_dir.path_join(kind_string + ".png")

	if not ResourceLoader.exists(icon_path):
		push_warning("Icon not found: " + icon_path)
		return null

	var texture: Texture2D = load(icon_path) as Texture2D

	if texture == null:
		push_warning("Failed to load icon: " + icon_path)
		return null

	var polygons: Array = room.get("polygons", [])
	var room_center_local: Vector2 = _get_room_polygons_center(polygons)
	var room_center_global: Vector2 = room_polygon_space.to_global(room_center_local)
	var icon_center_position: Vector2 = target_parent.to_local(room_center_global)

	var icon: TextureRect = TextureRect.new()
	icon.name = "RoomIcon_%s_%s" % [
		str(room.get("room_id", -1)),
		kind_string
	]

	# Центрируем TextureRect относительно центра комнаты.
	icon.position = icon_center_position - icon_size * 0.5

	# Godot 4 TextureRect.
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Фиксированный размер.
	icon.size = icon_size
	
	icon.texture = texture

	target_parent.add_child(icon)

	return icon

static func _get_room_polygons_center(polygons: Array) -> Vector2:
	var has_point: bool = false
	var min_point: Vector2 = Vector2.ZERO
	var max_point: Vector2 = Vector2.ZERO

	for polygon_variant: Variant in polygons:
		if typeof(polygon_variant) != TYPE_PACKED_VECTOR2_ARRAY:
			continue

		var polygon: PackedVector2Array = polygon_variant

		for point: Vector2 in polygon:
			if not has_point:
				has_point = true
				min_point = point
				max_point = point
			else:
				min_point.x = minf(min_point.x, point.x)
				min_point.y = minf(min_point.y, point.y)
				max_point.x = maxf(max_point.x, point.x)
				max_point.y = maxf(max_point.y, point.y)

	if not has_point:
		return Vector2.ZERO

	return min_point + (max_point - min_point) * 0.5

func recalc_rooms() -> Array[Dictionary]:
	var rooms_data: Dictionary = ShipRooms.validate(foundation_layer, SAMPLES_PER_TILE)
	
	var floor_data: Dictionary = ShipRoomFloors.validate(
		foundation_layer,
		technical_layer,
		rooms_data["rooms"],
		[stations_layer]
	)
	
	for id in range(floor_data["rooms"].size()):
		rooms_data["rooms"][id].merge(floor_data["rooms"][id])
	
	var specialization_data: Dictionary = ShipRoomSpecialization.validate(
		stations_layer,
		rooms_data["rooms"],
		foundation_layer
	)
	
	for id in range(specialization_data["rooms"].size()):
		rooms_data["rooms"][id].merge(specialization_data["rooms"][id])
	
	return rooms_data["rooms"]

func setup_oxygen() -> void:
	_ensure_oxygen_overlay_layer()
	
	oxygen_by_room = OxygenLogic.create_room_oxygen(
		rooms,
		oxygen_default_percent
	)
	
	oxygen_room_areas = OxygenLogic.calculate_room_areas(
		rooms,
		foundation_layer.tile_set.tile_size
	)
	
	oxygen_door_links = OxygenLogic.collect_door_links(
		foundation_layer,
		rooms
	)
	
	_recalculate_oxygen_consumption()
	
	oxygen_room_polygons = OxygenLogic.create_room_oxygen_polygons(
		rooms,
		foundation_layer,
		oxygen_overlay_layer
	)
	
	OxygenLogic.update_room_oxygen_polygons(
		oxygen_room_polygons,
		oxygen_by_room,
		oxygen_visual_max_alpha
	)

func process_oxygen(delta: float) -> void:
	oxygen_recheck_timer += delta
	
	if oxygen_recheck_timer >= oxygen_recheck_interval:
		oxygen_recheck_timer = 0.0
		_recalculate_oxygen_consumption()
	
	oxygen_by_room = OxygenLogic.process_oxygen_tick(
		oxygen_by_room,
		oxygen_room_areas,
		oxygen_door_links,
		oxygen_consumption,
		foundation_layer,
		delta,
		oxygen_air_production_per_second,
		oxygen_door_flow_per_second,
		oxygen_exterior_loss_per_second
	)
	
	_process_fire_oxygen_starvation()
	
	OxygenLogic.update_room_oxygen_polygons(
		oxygen_room_polygons,
		oxygen_by_room,
		oxygen_visual_max_alpha
	)

func _process_fire_oxygen_starvation() -> void:
	for fire_data: Dictionary in fires.values():
		var fire: Node2D = fire_data["node"]
		var room_index: int = int(fire.get_meta("room"))
		
		if int(oxygen_by_room[room_index]) <= 0:
			fire.oxygen_starvation()

func _recalculate_oxygen_consumption() -> void:
	oxygen_consumption = OxygenLogic.create_consumption_by_room(rooms)
	
	OxygenLogic.add_pawn_consumption(
		oxygen_consumption,
		foundation_layer,
		rooms,
		pawns
	)
	
	OxygenLogic.add_fire_consumption(
		oxygen_consumption,
		rooms,
		fires
	)
	
	OxygenLogic.add_hole_consumption(
		oxygen_consumption,
		foundation_layer,
		rooms,
		oxygen_hole_loss_per_impact
	)

func _ensure_oxygen_overlay_layer() -> void:
	if oxygen_overlay_layer != null:
		return
	
	oxygen_overlay_layer = Node2D.new()
	oxygen_overlay_layer.name = "OxygenOverlay"
	oxygen_overlay_layer.z_index = 20
	
	add_child(oxygen_overlay_layer)


func process_pawn_tasks(delta: float) -> void:
	_cleanup_finished_tasks()
	_apply_fire_workers()
	_process_hull_repair_workers(delta)

	pawn_task_recheck_timer += delta

	if pawn_task_recheck_timer < pawn_task_recheck_interval:
		return

	pawn_task_recheck_timer = 0.0
	_assign_idle_pawn_tasks()

func _process_station_workers(delta: float) -> void:
	for pawn: Dictionary in pawns.values():
		if pawn["state"] != "working":
			continue

		var task: Dictionary = pawn["task"]

		if task.get("type", "") != PawnTaskLogic.TASK_STATION:
			continue

		var room_id: int = task["room_id"]
		
		print("Пешка занята станцией в комнате "+str(task["room_id"]))

		# тут уже эффект станции:
		# генерация энергии, управление пушками, лечение, производство и т.д.

func _assign_idle_pawn_tasks() -> void:
	var orders: Array[Dictionary] = PawnTaskLogic.create_task_orders(
		foundation_layer,
		rooms,
		pawns,
		fires,
		hull_holes
	)

	for order: Dictionary in orders:
		var pawn_id: String = order["pawn_id"]
		var task: Dictionary = order["task"]

		if not pawns.has(pawn_id):
			continue

		if pawns[pawn_id]["state"] != "idle":
			continue

		match task["type"]:
			PawnTaskLogic.TASK_FIRE:
				_start_pawn_work(pawn_id, task)

			PawnTaskLogic.TASK_HULL_REPAIR:
				_start_pawn_work(pawn_id, task)

			PawnTaskLogic.TASK_STATION:
				_start_station_task(pawn_id, task)


func _start_pawn_work(pawn_id: String, task: Dictionary) -> void:
	pawns[pawn_id]["state"] = "working"
	pawns[pawn_id]["task"] = task


func _start_station_task(pawn_id: String, task: Dictionary) -> void:
	var pawn_cell: Vector2i = foundation_layer.local_to_map(
		pawns[pawn_id]["node"].position
	)

	var target_cell: Vector2i = task["target_cell"]

	if pawn_cell == target_cell:
		_start_pawn_work(pawn_id, task)
		return

	pawn_to_cell(pawn_id, target_cell, task)


func _cleanup_finished_tasks() -> void:
	var invalid_worker_ids: Array[String] = PawnTaskLogic.get_invalid_worker_ids(
		pawns,
		fires,
		hull_holes
	)

	for pawn_id: String in invalid_worker_ids:
		pawns[pawn_id]["state"] = "idle"
		pawns[pawn_id]["task"] = {}


func _apply_fire_workers() -> void:
	var workers_by_fire: Dictionary = PawnTaskLogic.count_workers_by_target(
		pawns,
		PawnTaskLogic.TASK_FIRE
	)

	for fire_cell: Vector2i in fires.keys():
		var fire: Node = fires[fire_cell]["node"]
		var workers: int = int(workers_by_fire.get(fire_cell, 0))

		fire.extinguish_fire(workers > 0)
		fire.set_time_scale(workers)


func _process_hull_repair_workers(delta: float) -> void:
	var workers_by_hole: Dictionary = PawnTaskLogic.count_workers_by_target(
		pawns,
		PawnTaskLogic.TASK_HULL_REPAIR
	)

	var finished_cells: Array[Vector2i] = HullRepairLogic.process_hull_repair(
		foundation_layer,
		hull_holes,
		hull_repair_progress,
		workers_by_hole,
		delta,
		hull_repair_seconds_per_step
	)

	for finished_cell: Vector2i in finished_cells:
		_finish_workers_on_target(
			PawnTaskLogic.TASK_HULL_REPAIR,
			finished_cell
		)


func _finish_workers_on_target(
	task_type: String,
	target_cell: Vector2i
) -> void:
	for pawn_id: String in pawns.keys():
		var pawn: Dictionary = pawns[pawn_id]

		if pawn["state"] != "working":
			continue

		var task: Dictionary = pawn["task"]

		if task.get("type", "") != task_type:
			continue

		if task["target_cell"] != target_cell:
			continue

		pawns[pawn_id]["state"] = "idle"
		pawns[pawn_id]["task"] = {}


func setup_icons():
	for child in icons_layer.get_children():
		child.queue_free()
	var tile_size: Vector2 = Vector2(foundation_layer.tile_set.tile_size)
	var icon_size: Vector2 = tile_size * 1.5
	for room in rooms:
		add_room_kind_icon(
			room,
			foundation_layer,
			icons_layer,
			icon_size
		)

func fire_to_room(room_id: int) -> bool:
	var available_cells = dynamically_available_cells(room_id, false, true, false)
	if available_cells.is_empty():
		return false
	
	if oxygen_by_room[room_id] < 30:
		return false
	
	var fire = load("res://scenes/fire.tscn").instantiate()
	fire.set_health(2)
	fire.set_meta("room", room_id)
	fire.set_meta("cell", available_cells[0])
	fire.position = foundation_layer.map_to_local(available_cells[0])
	fire.connect("fire_spreading", fire_spreading)
	fire.connect("fire_out", fire_out)
	fires[available_cells[0]] = {"node": fire}
	fire_layer.add_child(fire)
	
	return true

func fire_spreading(fire: Node2D) -> void:
	var room_index: int = int(fire.get_meta("room", -1))
	
	if fire_to_room(room_index):
		return
	
	var chance: float = fortress_doors_levels_map[
		clampi(fortress_doors_level, 0, fortress_doors_levels_map.size() - 1)
	]
	if randf() > chance:
		return
	
	var neighbors: Array[int] = ShipPathfinder.get_neighbor_room_indexes(
		foundation_layer,
		rooms,
		room_index
	)
	
	neighbors.shuffle()
	for neighbor_room_index: int in neighbors:
		if fire_to_room(neighbor_room_index):
			return

func fire_out(fire: Node2D) -> void:
	fires.erase(fire.get_meta("cell"))

func pawn_to_cell(
	pawn_id: String,
	target_cell: Vector2i,
	after_move_task: Dictionary = {}
) -> void:
	var available_cells: Array[Vector2i] = dynamically_available_cells()

	if not target_cell in available_cells:
		push_warning("Target cell for moving not available: " + str(target_cell))
		return

	var source_cell: Vector2i = foundation_layer.local_to_map(
		pawns[pawn_id]["node"].position
	)

	pawns[pawn_id]["cells"] = [target_cell]
	pawns[pawn_id]["state"] = "moving"

	var path_data: Dictionary = ShipPathfinder.calculate(
		foundation_layer,
		rooms,
		source_cell,
		target_cell
	)

	if not path_data["valid"]:
		push_warning("Path invalid: " + str(path_data["errors"]))
		pawns[pawn_id]["cells"] = [source_cell]
		pawns[pawn_id]["state"] = "idle"
		return

	pawns[pawn_id]["task"] = {
		"steps": path_data["steps"],
		"next_step_index": 0,
		"target_cell": target_cell,
		"after_move_task": after_move_task
	}

	pawns[pawn_id]["node"].move_by_steps_until_action(
		path_data["steps"],
		0
	)

func dynamically_available_cells(
	room_id: int = -1,
	main_floor_priority: bool = true,
	ignore_pawns: bool = false,
	ignore_fires: bool = true
) -> Array[Vector2i]:
	var exclude_cells: Dictionary = {}
	if not ignore_pawns:
		for pawn in pawns.values():
			for cell: Vector2i in pawn["cells"]:
				exclude_cells[cell] = true
	if not ignore_fires:
		for fire_cell in fires.keys():
			exclude_cells[fire_cell] = true
	
	var available_cells: Array[Vector2i] = []
	var id = -1
	for room: Dictionary in rooms:
		if room_id >= 0:
			id += 1
			if id != room_id:
				continue
		
		var floor_main = room["floor_main"]
		if main_floor_priority and floor_main != null and not exclude_cells.has(floor_main):
			available_cells.append(floor_main)
		for cell: Vector2i in room["floor_cells"]:
			if main_floor_priority and cell == floor_main:
				continue
			if exclude_cells.has(cell):
				continue
			available_cells.append(cell)
	
	return available_cells
