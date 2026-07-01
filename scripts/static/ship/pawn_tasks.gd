extends Node
class_name PawnTaskLogic

const TASK_FIRE: String = "fire"
const TASK_HULL_REPAIR: String = "hull_repair"
const TASK_ROOM_REPAIR: String = "room_repair"
const TASK_STATION: String = "station"
const TASK_BATTLE: String = "battle"
const TASK_ROOM_DESTROY: String = "room_destroy"
const TASK_DOOR_DESTROY: String = "door_destroy"

const TASK_LOCK_AUTO: String = "auto"
const TASK_LOCK_PLAYER: String = "player"

const STATE_IDLE: String = "idle"
const STATE_MOVING: String = "moving"
const STATE_WORKING: String = "working"


static func create_task_orders(
	rooms: Array[Dictionary],
	pawns: Dictionary,
	fires: Dictionary,
	hull_holes: Dictionary,
	owner_starship: String,
	room_integrity_by_room: Dictionary = {},
	room_integrity_max_by_room: Dictionary = {},
	room_power_by_room: Dictionary = {}
) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []
	var target_reservations: Dictionary = {}

	for pawn_id: String in pawns.keys():
		var pawn: Dictionary = pawns[pawn_id]
		var pawn_node: Node2D = pawn["node"]

		if pawn["state"] != STATE_IDLE:
			continue

		var pawn_cell: Vector2i = pawn["cells"][0]

		var room_id: int = get_room_id_by_cell(rooms, pawn_cell)

		if room_id < 0:
			continue

		var task: Dictionary = {}
		var pawn_starship: String = str(pawn_node.get_current_starship())

		if pawn_starship == owner_starship:
			task = get_best_task_for_room(
				rooms,
				pawns,
				fires,
				hull_holes,
				room_id,
				pawn_id,
				pawn_cell,
				target_reservations,
				room_integrity_by_room,
				room_integrity_max_by_room,
				room_power_by_room
			)
		elif starships_are_friends(pawn_starship, owner_starship):
			task = get_best_survival_task_for_room(
				rooms,
				fires,
				hull_holes,
				room_id
			)
		else:
			task = get_room_destroy_task_for_room(
				rooms,
				room_id,
				pawn_cell,
				room_integrity_by_room
			)

		if task.is_empty():
			continue

		if task["type"] == TASK_STATION or task["type"] == TASK_ROOM_REPAIR:
			target_reservations[task["target_cell"]] = true

		orders.append({
			"pawn_id": pawn_id,
			"task": task
		})

	return orders

static func get_room_destroy_task_for_room(
	rooms: Array[Dictionary],
	room_id: int,
	pawn_cell: Vector2i,
	room_integrity_by_room: Dictionary = {}
) -> Dictionary:
	if not room_integrity_by_room.is_empty() and int(room_integrity_by_room.get(room_id, 1)) <= 0:
		return {}

	return {
		"type": TASK_ROOM_DESTROY,
		"priority": 25,
		"room_id": room_id,
		"target_cell": pawn_cell
	}


static func get_best_task_for_room(
	rooms: Array[Dictionary],
	pawns: Dictionary,
	fires: Dictionary,
	hull_holes: Dictionary,
	room_id: int,
	pawn_id: String,
	pawn_cell: Vector2i,
	target_reservations: Dictionary,
	room_integrity_by_room: Dictionary = {},
	room_integrity_max_by_room: Dictionary = {},
	room_power_by_room: Dictionary = {}
) -> Dictionary:
	var fire_task: Dictionary = get_fire_task_for_room(fires, room_id)

	if not fire_task.is_empty():
		return fire_task

	var hull_repair_task: Dictionary = get_hull_repair_task_for_room(
		rooms,
		hull_holes,
		room_id
	)

	if not hull_repair_task.is_empty():
		return hull_repair_task

	var room_repair_task: Dictionary = get_room_repair_task_for_room(
		rooms,
		pawns,
		room_id,
		pawn_id,
		pawn_cell,
		target_reservations,
		room_integrity_by_room,
		room_integrity_max_by_room
	)

	if not room_repair_task.is_empty():
		return room_repair_task

	var station_task: Dictionary = get_station_task_for_room(
		rooms,
		pawns,
		room_id,
		pawn_id,
		target_reservations,
		room_power_by_room
	)

	if not station_task.is_empty():
		return station_task

	return {}


static func get_best_survival_task_for_room(
	rooms: Array[Dictionary],
	fires: Dictionary,
	hull_holes: Dictionary,
	room_id: int
) -> Dictionary:
	var fire_task: Dictionary = get_fire_task_for_room(fires, room_id)

	if not fire_task.is_empty():
		return fire_task

	var hull_repair_task: Dictionary = get_hull_repair_task_for_room(
		rooms,
		hull_holes,
		room_id
	)

	if not hull_repair_task.is_empty():
		return hull_repair_task

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


static func get_room_repair_task_for_room(
	rooms: Array[Dictionary],
	pawns: Dictionary,
	room_id: int,
	pawn_id: String,
	pawn_cell: Vector2i,
	target_reservations: Dictionary,
	room_integrity_by_room: Dictionary,
	room_integrity_max_by_room: Dictionary
) -> Dictionary:
	if room_integrity_by_room.is_empty():
		return {}

	var integrity: int = int(room_integrity_by_room.get(room_id, 0))
	var integrity_max: int = int(room_integrity_max_by_room.get(room_id, 0))

	if integrity >= integrity_max:
		return {}

	var target_cell: Vector2i = get_room_repair_target_cell_for_pawn(
		rooms,
		pawns,
		room_id,
		pawn_id,
		pawn_cell,
		target_reservations
	)

	if target_cell == Vector2i(-999999, -999999):
		return {}

	return {
		"type": TASK_ROOM_REPAIR,
		"priority": 30,
		"room_id": room_id,
		"target_cell": target_cell,
		"reserved_target_cell": target_cell
	}


static func get_room_repair_target_cell_for_pawn(
	rooms: Array[Dictionary],
	pawns: Dictionary,
	room_id: int,
	pawn_id: String,
	pawn_cell: Vector2i,
	target_reservations: Dictionary
) -> Vector2i:
	var room: Dictionary = rooms[room_id]
	var station_cell: Vector2i = room.get("station_cell", pawn_cell)
	var best_cell: Vector2i = Vector2i(-999999, -999999)
	var best_score: int = 2147483647
	var candidates: Array[Vector2i] = []
	var main_cell: Variant = room["floor_main"]

	if main_cell != null:
		candidates.append(main_cell)

	for cell: Vector2i in room["floor_cells"]:
		if cell in candidates:
			continue

		candidates.append(cell)

	for cell: Vector2i in candidates:
		if target_reservations.has(cell):
			continue

		if is_cell_reserved_by_other_pawn(pawns, cell, pawn_id):
			continue

		var station_distance: int = absi(cell.x - station_cell.x) + absi(cell.y - station_cell.y)
		var pawn_distance: int = absi(cell.x - pawn_cell.x) + absi(cell.y - pawn_cell.y)
		var score: int = station_distance * 1000 + pawn_distance

		if score < best_score:
			best_score = score
			best_cell = cell

	return best_cell

static func get_station_task_for_room(
	rooms: Array[Dictionary],
	pawns: Dictionary,
	room_id: int,
	pawn_id: String,
	target_reservations: Dictionary,
	room_power_by_room: Dictionary = {}
) -> Dictionary:
	var room: Dictionary = rooms[room_id]

	if not room.has("kind"):
		return {}

	if room.get("kind", null) == null:
		return {}

	if not room_power_by_room.is_empty() and int(room_power_by_room.get(room_id, 0)) <= 0:
		return {}

	var main_cell: Variant = room["floor_main"]

	if main_cell == null:
		return {}

	var target_cell: Vector2i = main_cell

	if target_reservations.has(target_cell):
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
	task_type: String,
	owner_starship: String = ""
) -> Dictionary:
	var result: Dictionary = {}

	for pawn: Dictionary in pawns.values():
		var pawn_node: Node2D = pawn["node"]
		
		if owner_starship != "":
			var pawn_starship: String = str(pawn_node.get_current_starship())

			if not starships_are_friends(pawn_starship, owner_starship):
				continue
		
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


static func count_workers_by_room(
	pawns: Dictionary,
	task_type: String,
	owner_starship: String = ""
) -> Dictionary:
	var result: Dictionary = {}

	for pawn: Dictionary in pawns.values():
		var pawn_node: Node2D = pawn["node"]

		if owner_starship != "":
			var pawn_starship: String = str(pawn_node.get_current_starship())

			if not starships_are_friends(pawn_starship, owner_starship):
				continue

		if pawn["state"] != STATE_WORKING:
			continue

		var task: Dictionary = pawn["task"]

		if task.get("type", "") != task_type:
			continue

		var room_id: int = int(task["room_id"])

		if not result.has(room_id):
			result[room_id] = 0

		result[room_id] += 1

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

		match task_type:
			TASK_FIRE:
				var fire_cell: Vector2i = task["target_cell"]

				if not fires.has(fire_cell):
					result.append(pawn_id)

			TASK_HULL_REPAIR:
				var hole_cell: Vector2i = task["target_cell"]

				if not hull_holes.has(hole_cell):
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

		var task: Dictionary = pawn["task"]

		if task.has("reserved_target_cell"):
			if task["reserved_target_cell"] == cell:
				return true

	return false

static func create_battle_task_orders(
	rooms: Array[Dictionary],
	pawns: Dictionary
) -> Array[Dictionary]:
	var orders: Array[Dictionary] = []

	for pawn_id: String in pawns.keys():
		var pawn: Dictionary = pawns[pawn_id]

		if pawn["state"] == STATE_MOVING:
			continue
		
		var pawn_cell: Vector2i = pawns[pawn_id]["cells"][0]

		var room_id: int = get_room_id_by_cell(rooms, pawn_cell)

		if room_id < 0:
			continue

		var target_pawn_id: String = get_nearest_enemy_pawn_id_in_room(
			rooms,
			pawns,
			pawn_id,
			pawn_cell,
			room_id
		)

		if target_pawn_id == "":
			continue

		var target_cell: Vector2i = pawns[target_pawn_id]["cells"][0]

		orders.append({
			"pawn_id": pawn_id,
			"task": {
				"type": TASK_BATTLE,
				"priority": 1000,
				"room_id": room_id,
				"target_pawn_id": target_pawn_id,
				"target_cell": target_cell
			}
		})

	return orders

static func get_nearest_enemy_pawn_id_in_room(
	rooms: Array[Dictionary],
	pawns: Dictionary,
	pawn_id: String,
	pawn_cell: Vector2i,
	room_id: int
) -> String:

	var nearest_pawn_id: String = ""
	var nearest_distance: int = 2147483647

	for other_id: String in pawns.keys():
		if other_id == pawn_id:
			continue
		
		if pawns[other_id]["state"] == STATE_MOVING:
			continue

		if not pawns_are_enemies(pawns, pawn_id, other_id):
			continue

		var other_cell: Vector2i = pawns[other_id]["cells"][0]

		if get_room_id_by_cell(rooms, other_cell) != room_id:
			continue

		var cell_delta: Vector2i = other_cell - pawn_cell
		var distance: int = cell_delta.x * cell_delta.x + cell_delta.y * cell_delta.y

		if distance < nearest_distance:
			nearest_distance = distance
			nearest_pawn_id = other_id

	return nearest_pawn_id


static func pawns_are_enemies(
	pawns: Dictionary,
	pawn_id: String,
	other_id: String
) -> bool:
	var pawn_starship: String = str(pawns[pawn_id]["node"].get_current_starship())
	var other_starship: String = str(pawns[other_id]["node"].get_current_starship())

	return starships_are_enemies(pawn_starship, other_starship)


static func pawn_belongs_to_starship(
	pawns: Dictionary,
	pawn_id: String,
	starship_uuid: String
) -> bool:
	return str(pawns[pawn_id]["node"].get_current_starship()) == starship_uuid


static func pawn_is_friend_to_starship(
	pawns: Dictionary,
	pawn_id: String,
	starship_uuid: String
) -> bool:
	return starships_are_friends(
		str(pawns[pawn_id]["node"].get_current_starship()),
		starship_uuid
	)


static func starships_are_friends(
	starship_uuid: String,
	other_starship_uuid: String
) -> bool:
	return not starships_are_enemies(starship_uuid, other_starship_uuid)


static func starships_are_enemies(
	starship_uuid: String,
	other_starship_uuid: String
) -> bool:
	if starship_uuid == other_starship_uuid:
		return false

	return (
		_starship_has_enemy(starship_uuid, other_starship_uuid)
		or _starship_has_enemy(other_starship_uuid, starship_uuid)
	)


static func _starship_has_enemy(
	starship_uuid: String,
	other_starship_uuid: String
) -> bool:
	if not GlobalBuffer.starships.has(starship_uuid):
		return false

	var enemies: Array = GlobalBuffer.starships[starship_uuid].get("enemies", [])

	return enemies.has(other_starship_uuid)
