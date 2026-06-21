extends Node2D
class_name Starship

signal restart_finish()

signal add_pawn_event(node, uuid)
signal delete_pawn_event(node, uuid)

@export var pawns2spawn: Array[Dictionary] = [{"race": "human"}, {"race": "human"}, {"race": "human", "starship": "enemy_team_1"}, {"race": "human", "starship": "enemy_team_1"}]

@onready var foundation_layer = $Foundation
@onready var stations_layer = $Stations
@onready var technical_layer = $Technical
@onready var icons_layer = $Icons
@onready var pawns_layer = $Pawns
@onready var fire_layer = $Fire
const SAMPLES_PER_TILE: int = 1

var time2change_door_state = 0.2

var starship_uuid: String = ""

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

@export var pawn_environment_damage_enabled: bool = true
@export var pawn_environment_damage_interval: float = 1.0

@export var pawn_no_oxygen_damage: int = 6
@export var pawn_fire_room_damage: int = 3

var pawn_environment_damage_timer: float = 0.0

@export var pawn_task_enabled: bool = true
@export var pawn_task_recheck_interval: float = 0.25
@export var hull_repair_seconds_per_step: float = 4.0

var pawn_task_recheck_timer: float = 0.0

var hull_holes: Dictionary = {}
var hull_repair_progress: Dictionary = {}

var fortress_doors_level: int = 0
var fortress_doors_levels_map: Array = [0.7, 0.4, 0.2, 0.1]

@export var pawn_battle_enabled: bool = true
@export var pawn_battle_recheck_interval: float = 0.15
@export var pawn_battle_damage_interval: float = 1.0

var pawn_battle_recheck_timer: float = 0.0
var pawn_battle_attack_timers: Dictionary = {}


func _ready() -> void:
	restart()

func _process(delta: float) -> void:
	if oxygen_enabled:
		process_oxygen(delta)
	
	if pawn_environment_damage_enabled:
		_process_pawn_environment_damage(delta)
	
	if pawn_task_enabled:
		process_pawn_tasks(delta)
		_process_station_workers(delta)

func restart() -> void:
	starship_uuid = NodeUUID.uuid_v4()
	technical_layer.hide()
	rooms = recalc_rooms()
	setup_oxygen()
	
	hull_holes = HullRepairLogic.collect_hull_holes(foundation_layer)
	hull_repair_progress = {}
	
	for pawn_key in pawns.keys():
		emit_signal("delete_pawn_event", pawns[pawn_key]["node"], pawn_key)
		pawns[pawn_key]["node"].queue_free()
	for pawn in pawns_layer.get_children():
		pawn.queue_free()
	pawns = {}
	for pawn in pawns2spawn:
		add_pawn(pawn["race"], pawn.get("starship", starship_uuid))
	
	emit_signal("restart_finish")

func add_pawn(race: String, starship: String = starship_uuid) -> bool:
	var available_cells: Array[Vector2i] = dynamically_available_cells()
	
	if available_cells.size() < 1:
		return false
	
	var pawn = load("res://scenes/pawn.tscn").instantiate()
	pawn.position = foundation_layer.map_to_local(available_cells[0])
	pawns_layer.add_child(pawn)
	pawn.starship = starship
	pawn.set_race(race)
	pawn.set_animation("down", "standing")
	var uuid = NodeUUID.uuid_v4()
	pawn.set_meta("uuid", uuid)
	
	pawn.connect("movement_action_required", _on_pawn_action_required.bind(uuid))
	pawn.connect("movement_finished", _on_pawn_movement_finished.bind(uuid))
	pawn.connect("dead", _on_pawn_dead.bind(uuid))
	
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

func _set_pawn_task_animation(pawn_id: String) -> void:
	var pawn: Node2D = pawns[pawn_id]["node"]
	var task: Dictionary = pawns[pawn_id]["task"]
	var task_type: String = task.get("type", "")

	var look_vector: Vector2 = _get_pawn_task_look_vector(pawn_id, task)

	pawn.update_direction_by_vector(look_vector)

	match task_type:
		PawnTaskLogic.TASK_BATTLE:
			pawn.set_animation(
				pawn.direction,
				_get_battle_animation_name(pawn_id, task)
			)
		PawnTaskLogic.TASK_FIRE:
			pawn.set_animation(pawn.direction, "extinguishing")
		PawnTaskLogic.TASK_HULL_REPAIR:
			pawn.set_animation(pawn.direction, "repair")
		PawnTaskLogic.TASK_STATION:
			pawn.set_animation(pawn.direction, "station")


func _get_pawn_task_look_vector(
	pawn_id: String,
	task: Dictionary
) -> Vector2:
	var pawn_cell: Vector2i = foundation_layer.local_to_map(
		pawns[pawn_id]["node"].position
	)

	var task_type: String = task.get("type", "")

	match task_type:
		PawnTaskLogic.TASK_BATTLE:
			return _get_vector_to_battle_target(pawn_id, task)
		PawnTaskLogic.TASK_FIRE:
			return _get_vector_to_task_target(pawn_cell, task)
		PawnTaskLogic.TASK_HULL_REPAIR:
			return _get_vector_to_task_target(pawn_cell, task)
		PawnTaskLogic.TASK_STATION:
			var room_id: int = int(task["room_id"])
			var station_cell: Vector2i = rooms[room_id]["station_cell"]
			var cell_delta: Vector2i = station_cell - pawn_cell
			
			if cell_delta == Vector2i.ZERO:
				return Vector2.UP

			return Vector2(cell_delta).normalized()

	return Vector2.DOWN


func _get_vector_to_task_target(
	pawn_cell: Vector2i,
	task: Dictionary
) -> Vector2:
	var target_cell: Vector2i = task["target_cell"]
	var cell_delta: Vector2i = target_cell - pawn_cell

	if cell_delta == Vector2i.ZERO:
		return Vector2.UP

	return Vector2(cell_delta).normalized()

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
		if not after_move_task.has("lock"):
			after_move_task["lock"] = movement_task.get(
				"lock",
				PawnTaskLogic.TASK_LOCK_AUTO
			)

		pawns[pawn_id]["state"] = PawnTaskLogic.STATE_WORKING
		pawns[pawn_id]["task"] = after_move_task

		_set_pawn_task_animation(pawn_id)
		return

	pawns[pawn_id]["state"] = PawnTaskLogic.STATE_IDLE
	pawns[pawn_id]["task"] = {}

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

func _process_pawn_environment_damage(delta: float) -> void:
	pawn_environment_damage_timer += delta
	
	if pawn_environment_damage_timer < pawn_environment_damage_interval:
		return
	
	var ticks: int = int(pawn_environment_damage_timer / pawn_environment_damage_interval)
	pawn_environment_damage_timer -= ticks * pawn_environment_damage_interval
	
	for i in range(ticks):
		_apply_pawn_environment_damage()


func _apply_pawn_environment_damage() -> void:
	var fire_rooms: Dictionary = _get_fire_rooms()
	
	for pawn_id: String in pawns.keys():
		var pawn_data: Dictionary = pawns[pawn_id]
		var pawn_node: Node2D = pawn_data["node"]
		
		var pawn_cell: Vector2i = foundation_layer.local_to_map(pawn_node.position)
		var room_id: int = cell_to_room(pawn_cell)
		
		if room_id < 0:
			continue
		
		var room_oxygen: int = int(oxygen_by_room[room_id])
		var damage_value: float = 0.0
		
		if room_oxygen < pawn_node.min_oxygen:
			damage_value += float(pawn_no_oxygen_damage) * pawn_node.no_oxygen_damage_factor
		
		if room_oxygen > pawn_node.max_oxygen:
			damage_value += float(pawn_no_oxygen_damage) * pawn_node.no_oxygen_damage_factor
		
		if fire_rooms.has(room_id):
			damage_value += float(pawn_fire_room_damage) * pawn_node.fire_room_damage_factor
		
		var final_damage: int = roundi(damage_value)
		
		if final_damage > 0:
			pawn_node.damage(final_damage)


func _get_fire_rooms() -> Dictionary:
	var result: Dictionary = {}
	
	for fire_data: Dictionary in fires.values():
		var fire: Node2D = fire_data["node"]
		var room_id: int = int(fire.get_meta("room"))
		result[room_id] = true
	
	return result

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
	if pawn_battle_enabled:
		_process_battle_tasks(delta)

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
		
		#print("Пешка занята станцией в комнате "+str(task["room_id"]))

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

	_set_pawn_task_animation(pawn_id)


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
		_set_pawn_idle(pawn_id)


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
		
		_set_pawn_idle(pawn_id)

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
	after_move_task: Dictionary = {},
	ignore_pawns_on_target: bool = false,
	task_lock: String = PawnTaskLogic.TASK_LOCK_AUTO
) -> void:
	var available_cells: Array[Vector2i] = dynamically_available_cells(
		-1,
		true,
		ignore_pawns_on_target
	)

	if not target_cell in available_cells:
		push_warning("Target cell for moving not available: " + str(target_cell))
		return

	var source_cell: Vector2i = foundation_layer.local_to_map(
		pawns[pawn_id]["node"].position
	)

	pawns[pawn_id]["cells"] = [target_cell]
	pawns[pawn_id]["state"] = PawnTaskLogic.STATE_MOVING

	var path_data: Dictionary = ShipPathfinder.calculate(
		foundation_layer,
		rooms,
		source_cell,
		target_cell
	)

	if not path_data["valid"]:
		push_warning("Path invalid: " + str(path_data["errors"]))
		pawns[pawn_id]["cells"] = [source_cell]
		pawns[pawn_id]["state"] = PawnTaskLogic.STATE_IDLE
		return

	pawns[pawn_id]["task"] = {
		"steps": path_data["steps"],
		"next_step_index": 0,
		"target_cell": target_cell,
		"after_move_task": after_move_task,
		"lock": task_lock
	}

	pawns[pawn_id]["node"].move_by_steps_until_action(
		path_data["steps"],
		0
	)

func _set_pawn_idle(pawn_id: String) -> void:
	if not pawns.has(pawn_id):
		return

	pawns[pawn_id]["state"] = PawnTaskLogic.STATE_IDLE
	pawns[pawn_id]["task"] = {}

	if pawn_battle_attack_timers.has(pawn_id):
		pawn_battle_attack_timers.erase(pawn_id)

	var pawn: Node2D = pawns[pawn_id]["node"]
	pawn.set_animation(pawn.direction, "standing")

func cell_to_room(cell: Vector2i) -> int:
	for room: Dictionary in rooms:
		if cell in room["floor_cells"]:
			return int(room["room_id"])
	
	return -1

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

func _get_battle_animation_name(
	pawn_id: String,
	task: Dictionary
) -> String:
	var target_pawn_id: String = task.get("target_pawn_id", "")

	if target_pawn_id == "":
		return "battle_remotely"

	if not pawns.has(target_pawn_id):
		return "battle_remotely"

	if _battle_is_melee(pawn_id, target_pawn_id):
		return "battle"

	return "battle_remotely"


func _get_vector_to_battle_target(
	pawn_id: String,
	task: Dictionary
) -> Vector2:
	var target_pawn_id: String = task.get("target_pawn_id", "")

	if not pawns.has(target_pawn_id):
		return Vector2.DOWN

	var pawn_cell: Vector2i = pawns[pawn_id]["cells"][0]
	var target_cell: Vector2i = pawns[target_pawn_id]["cells"][0]

	var cell_delta: Vector2i = target_cell - pawn_cell

	if cell_delta == Vector2i.ZERO:
		return Vector2.DOWN

	return Vector2(cell_delta).normalized()

func _process_battle_tasks(delta: float) -> void:
	pawn_battle_recheck_timer += delta

	if pawn_battle_recheck_timer >= pawn_battle_recheck_interval:
		pawn_battle_recheck_timer = 0.0
		_refresh_battle_tasks()

	_apply_battle_damage(delta)

func get_player_room_target_cell(
	pawn_id: String,
	selected_cell: Vector2i
) -> Vector2i:
	var room_id: int = cell_to_room(selected_cell)

	if room_id < 0:
		return selected_cell

	var pawn_node: Node2D = pawns[pawn_id]["node"]

	var melee_damage: int = int(pawn_node.impact_force)
	var remote_damage: int = int(pawn_node.impact_force_remotely)

	if melee_damage <= remote_damage:
		return selected_cell

	var target_pawn_id: String = PawnTaskLogic.get_nearest_enemy_pawn_id_in_room(
		rooms,
		pawns,
		pawn_id,
		room_id
	)

	if target_pawn_id == "":
		return selected_cell

	if pawns[target_pawn_id]["state"] == PawnTaskLogic.STATE_MOVING:
		return selected_cell

	var target_cell: Vector2i = pawns[target_pawn_id]["cells"][0]

	if _friendly_pawn_already_approaches_battle_target(
		pawn_id,
		target_pawn_id,
		target_cell
	):
		return selected_cell

	return target_cell

func _refresh_battle_tasks() -> void:
	var orders: Array[Dictionary] = PawnTaskLogic.create_battle_task_orders(
		rooms,
		pawns
	)

	var battle_pawn_ids: Dictionary = {}

	for order: Dictionary in orders:
		var pawn_id: String = order["pawn_id"]
		var task: Dictionary = order["task"]

		battle_pawn_ids[pawn_id] = true

		if not pawns.has(pawn_id):
			continue

		_start_or_update_battle_task(pawn_id, task)

	for pawn_id: String in pawns.keys():
		if battle_pawn_ids.has(pawn_id):
			continue

		_stop_battle_if_needed(pawn_id)

func _start_or_update_battle_task(
	pawn_id: String,
	task: Dictionary
) -> void:
	if _pawn_has_player_lock(pawn_id):
		return

	if _is_moving_to_battle(pawn_id):
		return

	var target_pawn_id: String = task["target_pawn_id"]

	var pawn_cell: Vector2i = pawns[pawn_id]["cells"][0]
	var target_cell: Vector2i = pawns[target_pawn_id]["cells"][0]

	task["target_cell"] = target_cell
	task["lock"] = PawnTaskLogic.TASK_LOCK_AUTO

	if pawn_cell == target_cell:
		_set_battle_working(pawn_id, task)
		return

	var approacher_id: String = _get_battle_pair_approacher(
		pawn_id,
		target_pawn_id
	)

	if approacher_id == pawn_id:
		if not _friendly_pawn_already_approaches_battle_target(
			pawn_id,
			target_pawn_id,
			target_cell
		):
			pawn_battle_attack_timers.erase(pawn_id)

			pawn_to_cell(
				pawn_id,
				target_cell,
				task,
				true,
				PawnTaskLogic.TASK_LOCK_AUTO
			)

			return

	_set_battle_working(pawn_id, task)

func _set_battle_working(
	pawn_id: String,
	task: Dictionary
) -> void:
	var current_task: Dictionary = pawns[pawn_id]["task"]

	if current_task.get("type", "") != PawnTaskLogic.TASK_BATTLE:
		pawn_battle_attack_timers.erase(pawn_id)
	elif current_task.get("target_pawn_id", "") != task["target_pawn_id"]:
		pawn_battle_attack_timers.erase(pawn_id)

	task["lock"] = PawnTaskLogic.TASK_LOCK_AUTO

	pawns[pawn_id]["state"] = PawnTaskLogic.STATE_WORKING
	pawns[pawn_id]["task"] = task

	_set_pawn_task_animation(pawn_id)


func _is_already_moving_to_battle_cell(
	pawn_id: String,
	target_pawn_id: String,
	target_cell: Vector2i
) -> bool:
	if pawns[pawn_id]["state"] != PawnTaskLogic.STATE_MOVING:
		return false

	var task: Dictionary = pawns[pawn_id]["task"]
	var after_move_task: Dictionary = task.get("after_move_task", {})

	if after_move_task.get("type", "") != PawnTaskLogic.TASK_BATTLE:
		return false

	if after_move_task.get("target_pawn_id", "") != target_pawn_id:
		return false

	return task.get("target_cell", Vector2i.ZERO) == target_cell

func _cell_has_friendly_pawn(
	cell: Vector2i,
	pawn_id: String
) -> bool:
	var pawn_starship: String = pawns[pawn_id]["node"].get_current_starship()

	for other_id: String in pawns.keys():
		if other_id == pawn_id:
			continue

		if not pawns[other_id]["node"].control_is_available(pawn_starship):
			continue

		for other_cell: Vector2i in pawns[other_id]["cells"]:
			if other_cell == cell:
				return true

	return false

func _apply_battle_damage(delta: float) -> void:
	var pawn_ids: Array = pawns.keys()

	for pawn_id: String in pawn_ids:
		if not pawns.has(pawn_id):
			continue

		var pawn: Dictionary = pawns[pawn_id]

		if pawn["state"] != PawnTaskLogic.STATE_WORKING:
			continue

		var task: Dictionary = pawn["task"]

		if task.get("type", "") != PawnTaskLogic.TASK_BATTLE:
			continue

		var target_pawn_id: String = task.get("target_pawn_id", "")

		if not _battle_target_is_valid(pawn_id, target_pawn_id):
			pawns[pawn_id]["state"] = PawnTaskLogic.STATE_IDLE
			pawns[pawn_id]["task"] = {}
			pawn_battle_attack_timers.erase(pawn_id)
			continue

		var timer: float = float(pawn_battle_attack_timers.get(pawn_id, 0.0))
		timer += delta

		if timer < pawn_battle_damage_interval:
			pawn_battle_attack_timers[pawn_id] = timer
			continue

		var hits: int = int(timer / pawn_battle_damage_interval)
		timer -= float(hits) * pawn_battle_damage_interval
		pawn_battle_attack_timers[pawn_id] = timer

		_set_pawn_task_animation(pawn_id)

		for i in range(hits):
			if not pawns.has(target_pawn_id):
				break

			var attacker: Node2D = pawns[pawn_id]["node"]
			var target: Node2D = pawns[target_pawn_id]["node"]

			var base_damage: int = _get_battle_damage_value(
				pawn_id,
				target_pawn_id
			)

			if base_damage <= 0:
				continue

			var damage_value: float = float(base_damage) * target.battle_damage_factor
			var final_damage: int = roundi(damage_value)

			if final_damage > 0:
				target.damage(final_damage)


func _get_battle_damage_value(
	pawn_id: String,
	target_pawn_id: String
) -> int:
	if _battle_is_melee(pawn_id, target_pawn_id):
		return int(pawns[pawn_id]["node"].impact_force)

	return int(pawns[pawn_id]["node"].impact_force_remotely)


func _battle_is_melee(
	pawn_id: String,
	target_pawn_id: String
) -> bool:
	return pawns[pawn_id]["cells"][0] == pawns[target_pawn_id]["cells"][0]

func _battle_target_is_valid(
	pawn_id: String,
	target_pawn_id: String
) -> bool:
	if target_pawn_id == "":
		return false

	if not pawns.has(target_pawn_id):
		return false
	
	if pawns[target_pawn_id]["state"] == PawnTaskLogic.STATE_MOVING:
		return false

	if not PawnTaskLogic.pawns_are_enemies(pawns, pawn_id, target_pawn_id):
		return false

	var pawn_room_id: int = cell_to_room(pawns[pawn_id]["cells"][0])
	var target_room_id: int = cell_to_room(pawns[target_pawn_id]["cells"][0])

	if pawn_room_id < 0:
		return false

	return pawn_room_id == target_room_id

func _stop_battle_if_needed(pawn_id: String) -> void:
	if not pawns.has(pawn_id):
		return

	if _pawn_has_player_lock(pawn_id):
		return

	var task: Dictionary = pawns[pawn_id]["task"]

	if task.get("type", "") != PawnTaskLogic.TASK_BATTLE:
		return

	pawns[pawn_id]["state"] = PawnTaskLogic.STATE_IDLE
	pawns[pawn_id]["task"] = {}
	pawn_battle_attack_timers.erase(pawn_id)

	pawns[pawn_id]["node"].set_animation(
		pawns[pawn_id]["node"].direction,
		"standing"
	)

func _on_pawn_dead(pawn_id: String) -> void:
	if not pawns.has(pawn_id):
		return

	var pawn_node: Node2D = pawns[pawn_id]["node"]

	for other_id: String in pawns.keys():
		if other_id == pawn_id:
			continue

		var task: Dictionary = pawns[other_id]["task"]

		if task.get("type", "") != PawnTaskLogic.TASK_BATTLE:
			continue

		if task.get("target_pawn_id", "") != pawn_id:
			continue

		pawns[other_id]["state"] = PawnTaskLogic.STATE_IDLE
		pawns[other_id]["task"] = {}
		pawn_battle_attack_timers.erase(other_id)

	pawn_battle_attack_timers.erase(pawn_id)

	emit_signal("delete_pawn_event", pawn_node, pawn_id)

	pawns.erase(pawn_id)
	pawn_node.queue_free()

func _pawn_has_player_lock(pawn_id: String) -> bool:
	if not pawns.has(pawn_id):
		return false

	var task: Dictionary = pawns[pawn_id]["task"]

	return task.get("lock", PawnTaskLogic.TASK_LOCK_AUTO) == PawnTaskLogic.TASK_LOCK_PLAYER

func _get_battle_pair_approacher(
	pawn_id: String,
	target_pawn_id: String
) -> String:
	var pawn_node: Node2D = pawns[pawn_id]["node"]
	var target_node: Node2D = pawns[target_pawn_id]["node"]

	var pawn_melee_gain: int = int(pawn_node.impact_force) - int(pawn_node.impact_force_remotely)
	var target_melee_gain: int = int(target_node.impact_force) - int(target_node.impact_force_remotely)

	if pawn_melee_gain <= 0 and target_melee_gain <= 0:
		return ""

	if pawn_melee_gain > target_melee_gain:
		return pawn_id

	if target_melee_gain > pawn_melee_gain:
		return target_pawn_id

	var ids: Array[String] = [pawn_id, target_pawn_id]
	ids.sort()

	return ids[0]

func _is_moving_to_battle(pawn_id: String) -> bool:
	if pawns[pawn_id]["state"] != PawnTaskLogic.STATE_MOVING:
		return false

	var task: Dictionary = pawns[pawn_id]["task"]
	var after_move_task: Dictionary = task.get("after_move_task", {})

	return after_move_task.get("type", "") == PawnTaskLogic.TASK_BATTLE

func _friendly_pawn_already_approaches_battle_target(
	pawn_id: String,
	target_pawn_id: String,
	target_cell: Vector2i
) -> bool:
	var pawn_starship: String = pawns[pawn_id]["node"].get_current_starship()

	for other_id: String in pawns.keys():
		if other_id == pawn_id:
			continue

		if not pawns[other_id]["node"].control_is_available(pawn_starship):
			continue

		var other: Dictionary = pawns[other_id]
		var other_task: Dictionary = other["task"]

		for other_cell: Vector2i in other["cells"]:
			if other_cell == target_cell:
				return true

		if other["state"] == PawnTaskLogic.STATE_MOVING:
			var after_move_task: Dictionary = other_task.get("after_move_task", {})

			if after_move_task.get("type", "") != PawnTaskLogic.TASK_BATTLE:
				continue

			if after_move_task.get("target_pawn_id", "") == target_pawn_id:
				return true

		if other["state"] == PawnTaskLogic.STATE_WORKING:
			if other_task.get("type", "") != PawnTaskLogic.TASK_BATTLE:
				continue

			if other_task.get("target_pawn_id", "") == target_pawn_id:
				var other_cell: Vector2i = foundation_layer.local_to_map(
					other["node"].position
				)

				if other_cell == target_cell:
					return true

	return false
