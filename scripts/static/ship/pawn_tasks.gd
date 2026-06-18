extends Node
class_name PawnTaskLogic

const TASK_FIRE: String = "fire"
const TASK_HULL_REPAIR: String = "hull_repair"
const TASK_STATION: String = "station"

const STATE_IDLE: String = "idle"
const STATE_MOVING: String = "moving"
const STATE_WORKING: String = "working"


static func create_task_orders(
	foundation_layer: TileMapLayer,
	rooms: Array[Dictionary],
	pawns: Dictionary,
	fires: Dictionary,
	hull_holes: Dictionary
) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	var station_reservations: Dictionary = {}

	for pawn_id: String in pawns.keys():
		var pawn: Dictionary = pawns[pawn_id]

		if pawn["state"] != STATE_IDLE:
			continue

		var pawn_cell: Vector2i = foundation_layer.local_to_map(
			pawn["node"].position
		)

		var room_id: int = get_room_id_by_cell(rooms, pawn_cell)

		if room_id < 0:
			continue

		var task: Dictionary = get_best_task_for_room(
			rooms,
			pawns,
			fires,
			hull_holes,
			room_id,
			pawn_id,
			station_reservations
		)

		if task.is_empty():
			continue

		if task["type"] == TASK_STATION:
			station_reservations[task["target_cell"]] = true

		orders.append({
			"pawn_id": pawn_id,
			"task": task
		})

	return orders


static func get_best_task_for_room(
	rooms: Array[Dictionary],
	pawns: Dictionary,
	fires: Dictionary,
	hull_holes: Dictionary,
	room_id: int,
	pawn_id: String,
	station_reservations: Dictionary
) -> Dictionary:
	var fire_task: Dictionary = get_fire_task_for_room(fires, room_id)

	if not fire_task.is_empty():
		return fire_task

	var repair_task: Dictionary = get_hull_repair_task_for_room(
		rooms,
		hull_holes,
		room_id
	)

	if not repair_task.is_empty():
		return repair_task

	var station_task: Dictionary = get_station_task_for_room(
		rooms,
		pawns,
		room_id,
		pawn_id,
		station_reservations
	)

	if not station_task.is_empty():
		return station_task

	return {}


static func get_fire_task_for_room(
	fires: Dictionary,
	room_id: int
) -> Dictionary:
	for fire_cell: Vector2i in fires.keys():
		var fire: Node = fires[fire_cell]["node"]

		if int(fire.get_meta("room")) != room_id:
			continue

		return {
			"type": TASK_FIRE,
			"priority": 100,
			"room_id": room_id,
			"target_cell": fire_cell
		}

	return {}


static func get_hull_repair_task_for_room(
	rooms: Array[Dictionary],
	hull_holes: Dictionary,
	room_id: int
) -> Dictionary:
	var room: Dictionary = rooms[room_id]

	for hole_cell: Vector2i in hull_holes.keys():
		if hole_cell in room["floor_cells"]:
			return {
				"type": TASK_HULL_REPAIR,
				"priority": 50,
				"room_id": room_id,
				"target_cell": hole_cell
			}

	return {}


static func get_station_task_for_room(
	rooms: Array[Dictionary],
	pawns: Dictionary,
	room_id: int,
	pawn_id: String,
	station_reservations: Dictionary
) -> Dictionary:
	var room: Dictionary = rooms[room_id]

	if not room.has("kind"):
		return {}

	if room.get("kind", null) == null:
		return {}

	var main_cell: Variant = room["floor_main"]

	if main_cell == null:
		return {}

	var target_cell: Vector2i = main_cell

	if station_reservations.has(target_cell):
		return {}

	if is_cell_reserved_by_other_pawn(pawns, target_cell, pawn_id):
		return {}

	return {
		"type": TASK_STATION,
		"priority": 10,
		"room_id": room_id,
		"target_cell": target_cell
	}


static func count_workers_by_target(
	pawns: Dictionary,
	task_type: String
) -> Dictionary:
	var result: Dictionary = {}

	for pawn: Dictionary in pawns.values():
		if pawn["state"] != STATE_WORKING:
			continue

		var task: Dictionary = pawn["task"]

		if task.get("type", "") != task_type:
			continue

		var target_cell: Vector2i = task["target_cell"]

		if not result.has(target_cell):
			result[target_cell] = 0

		result[target_cell] += 1

	return result


static func get_invalid_worker_ids(
	pawns: Dictionary,
	fires: Dictionary,
	hull_holes: Dictionary
) -> Array[String]:
	var result: Array[String] = []

	for pawn_id: String in pawns.keys():
		var pawn: Dictionary = pawns[pawn_id]

		if pawn["state"] != STATE_WORKING:
			continue

		var task: Dictionary = pawn["task"]
		var task_type: String = task.get("type", "")
		var target_cell: Vector2i = task["target_cell"]

		match task_type:
			TASK_FIRE:
				if not fires.has(target_cell):
					result.append(pawn_id)

			TASK_HULL_REPAIR:
				if not hull_holes.has(target_cell):
					result.append(pawn_id)

	return result


static func get_room_id_by_cell(
	rooms: Array[Dictionary],
	cell: Vector2i
) -> int:
	for room_id: int in range(rooms.size()):
		if cell in rooms[room_id]["floor_cells"]:
			return room_id

	return -1


static func is_cell_reserved_by_other_pawn(
	pawns: Dictionary,
	cell: Vector2i,
	ignored_pawn_id: String
) -> bool:
	for pawn_id: String in pawns.keys():
		if pawn_id == ignored_pawn_id:
			continue

		var pawn: Dictionary = pawns[pawn_id]

		for pawn_cell: Vector2i in pawn["cells"]:
			if pawn_cell == cell:
				return true

	return false
