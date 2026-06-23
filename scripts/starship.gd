extends Node2D
class_name Starship

signal restart_finish()

signal add_pawn_event(node, uuid)
signal delete_pawn_event(node, uuid)

signal room_hp_changed(room_id: int, hp: float)
signal room_hp_depleted(room_id: int)

@export var pawns2spawn: Array[Dictionary] = [{"race": "human", "starship": "enemy_team_1"}, {"race": "human", "starship": "enemy_team_1"}]

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
@export var oxygen_no_oxygen_hatching_alpha: float = 0.85
@export var oxygen_no_oxygen_hatching_spacing_px: int = 12
@export var oxygen_no_oxygen_hatching_line_width_px: int = 4
@export var oxygen_recheck_interval: float = 0.25
@export var oxygen_no_oxygen_threshold: float = 1.0
@export var oxygen_no_oxygen_hatching_fade_speed: float = 6.0

var oxygen_pawn_consumption: Dictionary = {}
@onready var oxygen_overlay_layer: Node2D = foundation_layer
var oxygen_by_room: Dictionary = {}
var oxygen_room_areas: Dictionary = {}
var oxygen_door_links: Array[Dictionary] = []
var oxygen_consumption: Dictionary = {}
var oxygen_room_polygons: Dictionary = {}
var oxygen_no_oxygen_hatching_texture: Texture2D
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

var doors_level: int = 0
var fortress_doors_levels_map: Array = [0.7, 0.4, 0.2, 0.1] # определяет, с какой вероятностью распространиться огонь
var health_doors_levels_map: Array = [20, 40, 60, 80] # урон который должна впитать дверь прежде чем открыться
var cooldown_doors_levels_map: Array = [8, 5, 3, 2] # время в секундах сколько дверь нельзя будет закрыть
var color_doors_levess_map: Array = [Color.GRAY, Color.BLUE, Color.GOLD, Color.RED]

@export var pawn_battle_enabled: bool = true
@export var pawn_battle_recheck_interval: float = 0.15
@export var pawn_battle_damage_interval: float = 1.0

var pawn_battle_recheck_timer: float = 0.0
var pawn_battle_attack_timers: Dictionary = {}

@export var pawn_battle_melee_visual_offset_px: float = 0.0

@export var room_hp_enabled: bool = true
@export var room_hp_max: float = 100.0
@export var room_fire_damage_per_second: float = 8.0
@export var room_hostile_pawn_damage_per_second: float = 4.0

var room_hp_by_room: Dictionary = {}
var depleted_room_ids: Dictionary = {}

var door_hp_by_key: Dictionary = {}
var door_close_cooldowns: Dictionary = {}
var door_destroy_attack_timers: Dictionary = {}

@export var door_hp_visual_enabled: bool = true
@export var door_hp_visual_min_period: float = 0.12
@export var door_hp_visual_max_period: float = 0.85
@export var door_hp_visual_max_alpha: float = 0.55
@export var door_hp_visual_speed_smoothing: float = 8.0

@export var room_station_hp_visual_enabled: bool = true
@export var room_station_hp_visual_min_period: float = 0.12
@export var room_station_hp_visual_max_period: float = 0.85
@export var room_station_hp_visual_max_alpha: float = 0.55
@export var room_station_hp_visual_speed_smoothing: float = 8.0

var door_hp_visual_time: float = 0.0
var door_cells_by_key: Dictionary = {}
var door_hp_visuals_by_key: Dictionary = {}
var door_hp_visual_phases_by_key: Dictionary = {}
var door_hp_visual_frequencies_by_key: Dictionary = {}
var door_hp_visual_layer: Node2D
var active_door_attack_keys_this_tick: Dictionary = {}

var room_station_hp_visual_layers_by_room: Dictionary = {}
var room_station_hp_visual_phases_by_room: Dictionary = {}
var room_station_hp_visual_frequencies_by_room: Dictionary = {}


func _ready() -> void:
	restart()

func _process(delta: float) -> void:
	if oxygen_enabled:
		process_oxygen(delta)
	
	if room_hp_enabled:
		process_room_hp(delta)
		_process_room_station_hp_visuals(delta)
	
	_process_door_close_cooldowns(delta)
	_process_door_hp_visuals(delta)
	
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
	setup_room_hp()
	_setup_doors_runtime_state()
	_apply_door_recolor_shader()
	
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
	pawn.position = _cell_to_pawn_parent_position(available_cells[0])
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
	var is_hostile: bool = not _pawn_is_friendly_to_ship(pawn_id)

	var task: Dictionary = pawns[pawn_id]["task"]

	if not task.has("opened_doors"):
		task["opened_doors"] = {}

	if action == "open_door" and is_hostile:
		var hostile_current_state: String = DoorManager.get_door_state(
			foundation_layer,
			door_cells
		)

		if hostile_current_state == DoorManager.DOOR_STATE_OPEN:
			_continue_pawn_move_after_action(pawn_id, next_step_index)
			return

		_start_door_destroy_task_from_movement(
			pawn_id,
			step,
			door_key,
			next_step_index
		)
		return

	if action == "close_door" and is_hostile:
		_continue_pawn_move_after_action(pawn_id, next_step_index)
		return

	match action:
		"open_door":
			var current_open_state: String = DoorManager.get_door_state(
				foundation_layer,
				door_cells
			)

			var need_open: bool = current_open_state != DoorManager.DOOR_STATE_OPEN

			if need_open:
				task["opened_doors"][door_key] = true

				DoorManager.set_door_state(
					foundation_layer,
					door_cells,
					DoorManager.DOOR_STATE_OPEN
				)

				await get_tree().create_timer(time2change_door_state).timeout

		"close_door":
			if not task["opened_doors"].has(door_key):
				_continue_pawn_move_after_action(pawn_id, next_step_index)
				return

			if _door_close_is_blocked(door_key):
				task["opened_doors"].erase(door_key)
				_continue_pawn_move_after_action(pawn_id, next_step_index)
				return

			var current_close_state: String = DoorManager.get_door_state(
				foundation_layer,
				door_cells
			)

			if current_close_state != DoorManager.DOOR_STATE_CLOSED:
				DoorManager.set_door_state(
					foundation_layer,
					door_cells,
					DoorManager.DOOR_STATE_CLOSED
				)

				await get_tree().create_timer(time2change_door_state).timeout

			task["opened_doors"].erase(door_key)

	_continue_pawn_move_after_action(pawn_id, next_step_index)

func _set_pawn_task_animation(pawn_id: String) -> void:
	var pawn: Node2D = pawns[pawn_id]["node"]
	var task: Dictionary = pawns[pawn_id]["task"]
	var task_type: String = task.get("type", "")

	var look_vector: Vector2 = _get_pawn_task_look_vector(pawn_id, task)

	pawn.update_direction_by_vector(look_vector)

	match task_type:
		PawnTaskLogic.TASK_BATTLE:
			pawn.set_animation(pawn.direction, _get_battle_animation_name(pawn_id, task))
		PawnTaskLogic.TASK_FIRE:
			pawn.set_animation(pawn.direction, "extinguishing")
		PawnTaskLogic.TASK_HULL_REPAIR:
			pawn.set_animation(pawn.direction, "repair")
		PawnTaskLogic.TASK_STATION:
			pawn.set_animation(pawn.direction, "station")
		PawnTaskLogic.TASK_ROOM_DESTROY:
			pawn.set_animation(pawn.direction, "sabotage")
		PawnTaskLogic.TASK_DOOR_DESTROY:
			pawn.set_animation(pawn.direction, _get_door_destroy_animation_name(task))


func _get_pawn_task_look_vector(
	pawn_id: String,
	task: Dictionary
) -> Vector2:
	var pawn_cell: Vector2i = _pawn_position_to_foundation_cell(pawn_id)

	var task_type: String = task.get("type", "")

	match task_type:
		PawnTaskLogic.TASK_BATTLE:
			return _get_vector_to_battle_target(pawn_id, task)
		PawnTaskLogic.TASK_FIRE:
			return _get_vector_to_task_target(pawn_cell, task)
		PawnTaskLogic.TASK_HULL_REPAIR:
			return _get_vector_to_task_target(pawn_cell, task)
		PawnTaskLogic.TASK_ROOM_DESTROY:
			return Vector2.UP
		PawnTaskLogic.TASK_DOOR_DESTROY:
			return _get_vector_to_door_task(pawn_id, task)
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


func _continue_pawn_move_after_action(
	pawn_id: String,
	next_step_index: int
) -> void:
	pawns[pawn_id]["task"]["next_step_index"] = next_step_index

	pawns[pawn_id]["node"].move_by_steps_until_action(
		pawns[pawn_id]["task"]["steps"],
		next_step_index
	)


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

		if after_move_task.get("type", "") == PawnTaskLogic.TASK_BATTLE:
			_update_battle_visual_offsets()

		_set_pawn_task_animation(pawn_id)
		return

	_set_pawn_idle(pawn_id)

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
	
	oxygen_no_oxygen_hatching_texture = OxygenLogic.create_diagonal_hatching_texture(
		oxygen_no_oxygen_hatching_spacing_px,
		oxygen_no_oxygen_hatching_line_width_px,
		Color(1.0, 0.35, 0.12, 1.0)
	)
	
	oxygen_room_polygons = OxygenLogic.create_room_oxygen_polygons(
		rooms,
		foundation_layer,
		oxygen_overlay_layer,
		oxygen_no_oxygen_hatching_texture
	)
	
	OxygenLogic.update_room_oxygen_polygons(
		oxygen_room_polygons,
		oxygen_by_room,
		1.0,
		oxygen_visual_max_alpha,
		oxygen_no_oxygen_hatching_alpha,
		oxygen_no_oxygen_threshold,
		oxygen_no_oxygen_hatching_fade_speed
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
		delta,
		oxygen_visual_max_alpha,
		oxygen_no_oxygen_hatching_alpha,
		oxygen_no_oxygen_threshold,
		oxygen_no_oxygen_hatching_fade_speed
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
		
		var pawn_cell: Vector2i = pawn_data["cells"][0]
		var room_id: int = cell_to_room(pawn_cell)
		
		if room_id < 0:
			continue
		
		var room_oxygen: float = float(oxygen_by_room[room_id])
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
		
		if float(oxygen_by_room[room_index]) <= oxygen_no_oxygen_threshold:
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
	push_error("Нужно настроить оверлеи для рендера кислорода")


func process_pawn_tasks(delta: float) -> void:
	if pawn_battle_enabled:
		_process_battle_tasks(delta)

	_process_door_destroy_workers(delta)
	_restore_idle_door_hp()
	active_door_attack_keys_this_tick = {}
	_cleanup_hostile_utility_workers()
	_interrupt_station_workers_for_room_tasks()
	_cleanup_finished_tasks()
	_apply_fire_workers()
	_process_hull_repair_workers(delta)

	pawn_task_recheck_timer += delta

	if pawn_task_recheck_timer < pawn_task_recheck_interval:
		return

	pawn_task_recheck_timer = 0.0
	_assign_idle_pawn_tasks()

func _cleanup_hostile_utility_workers() -> void:
	for pawn_id: String in pawns.keys():
		if _pawn_is_friendly_to_ship(pawn_id):
			continue
		
		var pawn: Dictionary = pawns[pawn_id]
		
		if pawn["state"] != PawnTaskLogic.STATE_WORKING:
			continue
		
		var task: Dictionary = pawn["task"]
		var task_type: String = task.get("type", "")
		
		match task_type:
			PawnTaskLogic.TASK_FIRE:
				_set_pawn_idle(pawn_id)
			PawnTaskLogic.TASK_HULL_REPAIR:
				_set_pawn_idle(pawn_id)
			PawnTaskLogic.TASK_STATION:
				_set_pawn_idle(pawn_id)

func _setup_doors_runtime_state() -> void:
	door_hp_by_key = {}
	door_close_cooldowns = {}
	door_destroy_attack_timers = {}
	door_cells_by_key = {}
	active_door_attack_keys_this_tick = {}
	door_hp_visual_time = 0.0
	door_hp_visual_phases_by_key = {}
	door_hp_visual_frequencies_by_key = {}
	_ensure_door_hp_visual_layer()
	_clear_door_hp_visuals()


func _ensure_door_hp_visual_layer() -> void:
	if is_instance_valid(door_hp_visual_layer):
		return

	door_hp_visual_layer = Node2D.new()
	door_hp_visual_layer.name = "DoorHpVisualLayer"
	door_hp_visual_layer.z_index = 1000
	door_hp_visual_layer.z_as_relative = false
	foundation_layer.add_child(door_hp_visual_layer)


func _clear_door_hp_visuals() -> void:
	if is_instance_valid(door_hp_visual_layer):
		for child: Node in door_hp_visual_layer.get_children():
			child.queue_free()

	door_hp_visuals_by_key = {}
	door_hp_visual_phases_by_key = {}
	door_hp_visual_frequencies_by_key = {}


func _remember_door_cells(door_key: String, door_cells: Array) -> void:
	var stored_cells: Array[Vector2i] = []

	for cell_variant: Variant in door_cells:
		stored_cells.append(cell_variant)

	door_cells_by_key[door_key] = stored_cells


func _remove_door_hp_visual(door_key: String) -> void:
	if door_hp_visuals_by_key.has(door_key):
		for visual_variant: Variant in door_hp_visuals_by_key[door_key]:
			var visual: Node = visual_variant

			if is_instance_valid(visual):
				visual.queue_free()

		door_hp_visuals_by_key.erase(door_key)

	door_hp_visual_phases_by_key.erase(door_key)
	door_hp_visual_frequencies_by_key.erase(door_key)


func _ensure_door_hp_visual(door_key: String) -> void:
	if door_hp_visuals_by_key.has(door_key):
		return

	if not door_cells_by_key.has(door_key):
		return

	_ensure_door_hp_visual_layer()

	var tile_size: Vector2 = Vector2(foundation_layer.tile_set.tile_size)
	var half_size: Vector2 = tile_size * 0.5
	var visuals: Array[Polygon2D] = []

	for cell: Vector2i in door_cells_by_key[door_key]:
		var visual: Polygon2D = Polygon2D.new()
		visual.name = "DoorHpVisual_" + str(cell.x) + "_" + str(cell.y)
		visual.position = foundation_layer.map_to_local(cell)
		visual.polygon = PackedVector2Array([
			Vector2(-half_size.x, -half_size.y),
			Vector2(half_size.x, -half_size.y),
			Vector2(half_size.x, half_size.y),
			Vector2(-half_size.x, half_size.y)
		])
		visual.color = Color(0.0, 0.0, 0.0, 0.0)
		visual.z_index = 1000
		visual.z_as_relative = false
		door_hp_visual_layer.add_child(visual)
		visuals.append(visual)

	door_hp_visuals_by_key[door_key] = visuals
	door_hp_visual_phases_by_key[door_key] = 0.0
	door_hp_visual_frequencies_by_key[door_key] = 1.0 / door_hp_visual_max_period


func _process_door_hp_visuals(delta: float) -> void:
	if not door_hp_visual_enabled:
		_clear_door_hp_visuals()
		return

	door_hp_visual_time += delta

	for door_key: String in door_hp_by_key.keys():
		var max_hp: float = _get_current_door_max_hp()
		var hp: float = clampf(float(door_hp_by_key[door_key]), 0.0, max_hp)

		if hp >= max_hp:
			_remove_door_hp_visual(door_key)
			continue

		if not door_cells_by_key.has(door_key):
			_remove_door_hp_visual(door_key)
			continue

		var door_cells: Array = door_cells_by_key[door_key]

		if DoorManager.get_door_state(foundation_layer, door_cells) == DoorManager.DOOR_STATE_OPEN:
			_remove_door_hp_visual(door_key)
			continue

		_ensure_door_hp_visual(door_key)

		if not door_hp_visuals_by_key.has(door_key):
			continue

		var hp_ratio: float = clampf(hp / max_hp, 0.0, 1.0)
		var damage_ratio: float = 1.0 - hp_ratio
		var period: float = lerpf(door_hp_visual_min_period, door_hp_visual_max_period, hp_ratio)
		var target_frequency: float = 1.0 / period
		var current_frequency: float = float(door_hp_visual_frequencies_by_key.get(door_key, target_frequency))
		current_frequency = lerpf(
			current_frequency,
			target_frequency,
			clampf(delta * door_hp_visual_speed_smoothing, 0.0, 1.0)
		)
		door_hp_visual_frequencies_by_key[door_key] = current_frequency

		var phase: float = float(door_hp_visual_phases_by_key.get(door_key, 0.0))
		phase = fmod(phase + delta * current_frequency, 1.0)
		door_hp_visual_phases_by_key[door_key] = phase

		var pulse: float = (1.0 - cos(phase * TAU)) * 0.5
		var alpha: float = pulse * door_hp_visual_max_alpha * clampf(0.35 + damage_ratio * 0.65, 0.0, 1.0)

		for visual_variant: Variant in door_hp_visuals_by_key[door_key]:
			var visual: Polygon2D = visual_variant

			if is_instance_valid(visual):
				visual.color = Color(0.0, 0.0, 0.0, alpha)


func _apply_door_recolor_shader() -> void:
	var material: Material = foundation_layer.material

	if material is ShaderMaterial:
		var shader_material: ShaderMaterial = material as ShaderMaterial
		shader_material.set_shader_parameter("to_color", _get_current_door_color())


func _get_current_door_color() -> Color:
	return color_doors_levess_map[
		clampi(doors_level, 0, color_doors_levess_map.size() - 1)
	]


func _get_current_door_max_hp() -> float:
	return float(health_doors_levels_map[
		clampi(doors_level, 0, health_doors_levels_map.size() - 1)
	])


func _get_current_door_close_cooldown() -> float:
	return float(cooldown_doors_levels_map[
		clampi(doors_level, 0, cooldown_doors_levels_map.size() - 1)
	])


func _door_close_is_blocked(door_key: String) -> bool:
	return float(door_close_cooldowns.get(door_key, 0.0)) > 0.0


func _process_door_close_cooldowns(delta: float) -> void:
	for door_key: String in door_close_cooldowns.keys():
		var next_time: float = float(door_close_cooldowns[door_key]) - delta

		if next_time <= 0.0:
			door_close_cooldowns.erase(door_key)
			continue

		door_close_cooldowns[door_key] = next_time


func request_player_toggle_door(door_cells: Array) -> void:
	var door_key: String = _door_cells_key(door_cells)
	var current_state: String = DoorManager.get_door_state(foundation_layer, door_cells)
	var target_state: String = DoorManager.DOOR_STATE_OPEN

	if current_state == DoorManager.DOOR_STATE_OPEN:
		target_state = DoorManager.DOOR_STATE_CLOSED

	if target_state == DoorManager.DOOR_STATE_CLOSED and _door_close_is_blocked(door_key):
		return

	await get_tree().create_timer(time2change_door_state).timeout

	current_state = DoorManager.get_door_state(foundation_layer, door_cells)

	if current_state == target_state:
		return

	if target_state == DoorManager.DOOR_STATE_CLOSED and _door_close_is_blocked(door_key):
		return

	DoorManager.set_door_state(
		foundation_layer,
		door_cells,
		target_state
	)


func _get_first_closed_door_step_index(steps: Array[Dictionary]) -> int:
	for i: int in range(steps.size()):
		var step: Dictionary = steps[i]

		if step.get("action", "") != "open_door":
			continue

		var door_cells: Array = step.get("door_cells", [])

		if DoorManager.get_door_state(foundation_layer, door_cells) == DoorManager.DOOR_STATE_CLOSED:
			return i

	return -1


func _start_door_destroy_task_from_movement(
	pawn_id: String,
	step: Dictionary,
	door_key: String,
	next_step_index: int
) -> void:
	var door_source_cell: Vector2i = step["from_cell"]

	_start_door_destroy_task(
		pawn_id,
		step,
		door_key,
		next_step_index,
		door_source_cell,
		door_source_cell
	)


func _start_door_destroy_task_from_planned_movement(
	pawn_id: String,
	step: Dictionary,
	door_key: String,
	next_step_index: int,
	pawn_source_cell: Vector2i
) -> void:
	var door_source_cell: Vector2i = step["from_cell"]

	_start_door_destroy_task(
		pawn_id,
		step,
		door_key,
		next_step_index,
		pawn_source_cell,
		door_source_cell
	)


func _start_door_destroy_task(
	pawn_id: String,
	step: Dictionary,
	door_key: String,
	next_step_index: int,
	pawn_source_cell: Vector2i,
	door_source_cell: Vector2i
) -> void:
	var movement_task: Dictionary = pawns[pawn_id]["task"]
	var door_cells: Array = step["door_cells"]
	_remember_door_cells(door_key, door_cells)
	var assignment: Dictionary = _choose_door_destroy_assignment(
		pawn_id,
		step,
		door_key,
		pawn_source_cell,
		door_source_cell
	)

	var door_task: Dictionary = {
		"type": PawnTaskLogic.TASK_DOOR_DESTROY,
		"priority": 2000,
		"door_cells": door_cells,
		"door_key": door_key,
		"target_cell": movement_task["target_cell"],
		"reserved_target_cell": movement_task["target_cell"],
		"steps": movement_task["steps"],
		"next_step_index": next_step_index,
		"after_move_task": movement_task.get("after_move_task", {}),
		"lock": PawnTaskLogic.TASK_LOCK_PLAYER,
		"door_source_cell": door_source_cell,
		"door_attack_mode": assignment["mode"],
		"door_attack_cell": assignment["cell"],
		"door_attack_point": assignment["pawn_position"]
	}

	if assignment.get("needs_move", false):
		_move_pawn_to_door_destroy_position(pawn_id, pawn_source_cell, assignment, door_task)
		return

	pawns[pawn_id]["cells"] = [assignment["cell"]]
	pawns[pawn_id]["node"].position = assignment["pawn_position"]
	pawns[pawn_id]["state"] = PawnTaskLogic.STATE_WORKING
	pawns[pawn_id]["task"] = door_task

	_set_pawn_task_animation(pawn_id)


func _choose_door_destroy_assignment(
	pawn_id: String,
	step: Dictionary,
	door_key: String,
	pawn_source_cell: Vector2i,
	door_source_cell: Vector2i
) -> Dictionary:
	var pawn_node: Node2D = pawns[pawn_id]["node"]
	var melee_damage: int = int(pawn_node.impact_force)
	var remote_damage: int = int(pawn_node.impact_force_remotely)
	var approaches: Array = step.get("door_approaches", [])

	if melee_damage > remote_damage:
		var melee_assignment: Dictionary = _get_free_door_melee_assignment(
			pawn_id,
			door_key,
			approaches,
			pawn_source_cell
		)

		if not melee_assignment.is_empty():
			return melee_assignment

	var remote_assignment: Dictionary = _get_door_remote_assignment(
		pawn_id,
		step,
		door_key,
		pawn_source_cell,
		door_source_cell,
		approaches
	)

	if not remote_assignment.is_empty():
		return remote_assignment

	if melee_damage > 0:
		var fallback_melee_assignment: Dictionary = _get_free_door_melee_assignment(
			pawn_id,
			door_key,
			approaches,
			pawn_source_cell
		)

		if not fallback_melee_assignment.is_empty():
			return fallback_melee_assignment

	return _get_door_wait_assignment(pawn_id, pawn_source_cell)


func _get_free_door_melee_assignment(
	pawn_id: String,
	door_key: String,
	approaches: Array,
	pawn_source_cell: Vector2i
) -> Dictionary:
	for approach_variant: Variant in approaches:
		var approach: Dictionary = approach_variant
		var approach_cell: Vector2i = approach["cell"]

		if _door_attack_cell_is_reserved_by_friendly(pawn_id, door_key, approach_cell):
			continue

		return {
			"mode": "melee",
			"cell": approach_cell,
			"path_point": approach["point"],
			"pawn_position": _path_point_to_pawn_parent_position(approach["point"]),
			"needs_move": approach_cell != pawn_source_cell
		}

	return {}


func _get_door_remote_assignment(
	pawn_id: String,
	step: Dictionary,
	door_key: String,
	pawn_source_cell: Vector2i,
	door_source_cell: Vector2i,
	approaches: Array
) -> Dictionary:
	# Важно: позицию обстрела выбираем в комнате, из которой путь подходит
	# именно к ЭТОЙ двери, а не в комнате, где пешка находится сейчас.
	# Иначе при цепочке дверей ranged-пешка может остаться у прошлой двери
	# и стрелять через несколько комнат.
	var room_id: int = cell_to_room(door_source_cell)

	if room_id < 0:
		return {}

	var available_cells: Array[Vector2i] = dynamically_available_cells(
		room_id,
		false,
		false,
		true,
		pawn_id
	)

	var approach_cells: Dictionary = {}

	for approach_variant: Variant in approaches:
		var approach: Dictionary = approach_variant
		approach_cells[approach["cell"]] = true

	var door_center: Vector2 = _get_door_cells_center(step["door_cells"])
	var best_cell: Vector2i = Vector2i.ZERO
	var best_distance: float = 1.0e30
	var found: bool = false

	for cell: Vector2i in available_cells:
		if approach_cells.has(cell):
			continue

		var distance: float = foundation_layer.map_to_local(cell).distance_squared_to(door_center)

		if not found or distance < best_distance:
			found = true
			best_distance = distance
			best_cell = cell

	if not found:
		for cell: Vector2i in available_cells:
			var fallback_distance: float = foundation_layer.map_to_local(cell).distance_squared_to(door_center)

			if not found or fallback_distance < best_distance:
				found = true
				best_distance = fallback_distance
				best_cell = cell

	if found:
		var best_path_point: Vector2 = _cell_to_path_point(best_cell)

		return {
			"mode": "remote",
			"cell": best_cell,
			"path_point": best_path_point,
			"pawn_position": _path_point_to_pawn_parent_position(best_path_point),
			"needs_move": best_cell != pawn_source_cell
		}

	# Исключение: комната перед дверью полностью занята.
	# Дистанционная атака из текущей позиции разрешена только если пешка
	# УЖЕ находится в комнате перед этой конкретной дверью.
	# Если она осталась в предыдущей комнате, она может только ждать открытия двери,
	# но не имеет права наносить ей урон.
	if cell_to_room(pawn_source_cell) != room_id:
		return {}

	var current_pawn_position: Vector2 = pawns[pawn_id]["node"].position

	return {
		"mode": "remote",
		"cell": pawn_source_cell,
		"path_point": pawns_layer.to_global(current_pawn_position),
		"pawn_position": current_pawn_position,
		"needs_move": false
	}


func _get_door_wait_assignment(
	pawn_id: String,
	pawn_source_cell: Vector2i
) -> Dictionary:
	var current_pawn_position: Vector2 = pawns[pawn_id]["node"].position

	return {
		"mode": "wait",
		"cell": pawn_source_cell,
		"path_point": pawns_layer.to_global(current_pawn_position),
		"pawn_position": current_pawn_position,
		"needs_move": false
	}


func _door_attack_cell_is_reserved_by_friendly(
	pawn_id: String,
	door_key: String,
	cell: Vector2i
) -> bool:
	var pawn_starship: String = pawns[pawn_id]["node"].get_current_starship()

	for other_id: String in pawns.keys():
		if other_id == pawn_id:
			continue

		if not pawns[other_id]["node"].control_is_available(pawn_starship):
			continue

		var other: Dictionary = pawns[other_id]
		var other_task: Dictionary = other["task"]

		if other["state"] == PawnTaskLogic.STATE_WORKING:
			if other_task.get("type", "") == PawnTaskLogic.TASK_DOOR_DESTROY:
				if other_task.get("door_key", "") == door_key:
					if other_task.get("door_attack_cell", Vector2i.ZERO) == cell:
						return true

		if other["state"] == PawnTaskLogic.STATE_MOVING:
			var after_move_task: Dictionary = other_task.get("after_move_task", {})

			if after_move_task.get("type", "") == PawnTaskLogic.TASK_DOOR_DESTROY:
				if after_move_task.get("door_key", "") == door_key:
					if other_task.get("target_cell", Vector2i.ZERO) == cell:
						return true

	return false


func _move_pawn_to_door_destroy_position(
	pawn_id: String,
	pawn_source_cell: Vector2i,
	assignment: Dictionary,
	door_task: Dictionary
) -> void:
	var attack_cell: Vector2i = assignment["cell"]
	var attack_path_point: Vector2 = assignment["path_point"]
	var blocked_cells: Dictionary = _get_blocked_cells_for_pawn_path(pawn_id, attack_cell)
	var raw_path_data: Dictionary = ShipPathfinder.calculate(
		foundation_layer,
		rooms,
		pawn_source_cell,
		attack_cell,
		10,
		blocked_cells
	)
	var path_data: Dictionary = raw_path_data

	var steps: Array[Dictionary] = []

	if path_data["valid"]:
		steps = path_data["steps"]

		if not steps.is_empty() and steps[0].get("action", "") == "start":
			steps[0]["point"] = pawns_layer.to_global(pawns[pawn_id]["node"].position)
	else:
		# Нельзя превращать ошибку маршрута к позиции обстрела в стрельбу
		# через несколько комнат. Исключительный ranged-fallback из текущей
		# клетки разрешен только если пешка уже находится в комнате перед этой дверью.
		var pawn_source_room_id: int = cell_to_room(pawn_source_cell)
		var door_source_room_id: int = cell_to_room(door_task["door_source_cell"])

		if pawn_source_room_id != door_source_room_id:
			push_warning("Door attack position path invalid: " + str(path_data["errors"]))
			pawns[pawn_id]["cells"] = [pawn_source_cell]
			_set_pawn_idle(pawn_id)
			return

		door_task["door_attack_mode"] = "remote"
		door_task["door_attack_cell"] = pawn_source_cell
		door_task["door_attack_point"] = pawns[pawn_id]["node"].position

		pawns[pawn_id]["cells"] = [pawn_source_cell]
		pawns[pawn_id]["state"] = PawnTaskLogic.STATE_WORKING
		pawns[pawn_id]["task"] = door_task

		_set_pawn_task_animation(pawn_id)
		return

	if steps.is_empty():
		steps.append({
			"cell": pawn_source_cell,
			"kind": "floor",
			"action": "start",
			"point": pawns_layer.to_global(pawns[pawn_id]["node"].position)
		})

	var last_step: Dictionary = steps[steps.size() - 1]

	if not last_step.has("point") or last_step["point"].distance_to(attack_path_point) > 0.001:
		steps.append({
			"cell": attack_cell,
			"from_cell": attack_cell,
			"kind": "floor",
			"action": "move",
			"point": attack_path_point
		})

	pawns[pawn_id]["state"] = PawnTaskLogic.STATE_MOVING
	pawns[pawn_id]["cells"] = [attack_cell]
	pawns[pawn_id]["task"] = {
		"steps": steps,
		"next_step_index": 0,
		"target_cell": attack_cell,
		"reserved_target_cell": door_task["reserved_target_cell"],
		"after_move_task": door_task,
		"lock": PawnTaskLogic.TASK_LOCK_PLAYER
	}

	pawns[pawn_id]["node"].move_by_steps_until_action(steps, 0)


func _process_door_destroy_workers(delta: float) -> void:
	for pawn_id: String in pawns.keys():
		if not pawns.has(pawn_id):
			continue

		var pawn: Dictionary = pawns[pawn_id]

		if pawn["state"] != PawnTaskLogic.STATE_WORKING:
			continue

		var task: Dictionary = pawn["task"]

		if task.get("type", "") != PawnTaskLogic.TASK_DOOR_DESTROY:
			continue

		var door_cells: Array = task["door_cells"]
		var door_key: String = task["door_key"]

		pawn["node"].position = task.get("door_attack_point", pawn["node"].position)

		if DoorManager.get_door_state(foundation_layer, door_cells) == DoorManager.DOOR_STATE_OPEN:
			_resume_pawn_movement_after_destroyed_door(pawn_id)
			continue

		if not _door_destroy_worker_can_damage(pawn_id, task):
			door_destroy_attack_timers[pawn_id] = 0.0
			continue

		active_door_attack_keys_this_tick[door_key] = true

		var timer: float = float(door_destroy_attack_timers.get(pawn_id, 0.0))
		timer += delta

		if timer < pawn_battle_damage_interval:
			door_destroy_attack_timers[pawn_id] = timer
			continue

		var hits: int = int(timer / pawn_battle_damage_interval)
		timer -= float(hits) * pawn_battle_damage_interval
		door_destroy_attack_timers[pawn_id] = timer

		_set_pawn_task_animation(pawn_id)

		for i in range(hits):
			var damage: int = _get_door_destroy_damage(pawn_id, task)

			if damage <= 0:
				continue

			if _damage_door(door_key, damage):
				_break_door(task)
				_resume_all_pawns_waiting_for_door(door_key)
				break


func _door_destroy_worker_can_damage(
	pawn_id: String,
	task: Dictionary
) -> bool:
	var mode: String = task.get("door_attack_mode", "remote")

	if mode == "wait":
		return false

	var door_source_cell: Vector2i = task.get("door_source_cell", Vector2i.ZERO)
	var door_attack_cell: Vector2i = task.get("door_attack_cell", door_source_cell)
	var door_source_room_id: int = cell_to_room(door_source_cell)

	if door_source_room_id < 0:
		return false

	if cell_to_room(door_attack_cell) != door_source_room_id:
		return false

	if mode == "melee":
		return int(pawns[pawn_id]["node"].impact_force) > 0

	return int(pawns[pawn_id]["node"].impact_force_remotely) > 0


func _get_door_destroy_damage(
	pawn_id: String,
	task: Dictionary
) -> int:
	if not _door_destroy_worker_can_damage(pawn_id, task):
		return 0

	if task.get("door_attack_mode", "remote") == "melee":
		return int(pawns[pawn_id]["node"].impact_force)

	return int(pawns[pawn_id]["node"].impact_force_remotely)


func _damage_door(
	door_key: String,
	damage: int
) -> bool:
	var hp: float = _get_door_hp(door_key)
	hp = maxf(hp - float(damage), 0.0)
	door_hp_by_key[door_key] = hp
	_ensure_door_hp_visual(door_key)

	return hp <= 0.0


func _restore_idle_door_hp() -> void:
	var max_hp: float = _get_current_door_max_hp()

	for door_key: String in door_hp_by_key.keys():
		if active_door_attack_keys_this_tick.has(door_key):
			continue

		var hp: float = float(door_hp_by_key[door_key])

		if hp >= max_hp:
			continue

		if not door_cells_by_key.has(door_key):
			door_hp_by_key[door_key] = max_hp
			_remove_door_hp_visual(door_key)
			continue

		var door_cells: Array = door_cells_by_key[door_key]

		if DoorManager.get_door_state(foundation_layer, door_cells) == DoorManager.DOOR_STATE_OPEN:
			door_hp_by_key[door_key] = max_hp
			_remove_door_hp_visual(door_key)
			continue

		door_hp_by_key[door_key] = max_hp
		_remove_door_hp_visual(door_key)


func _get_door_hp(door_key: String) -> float:
	if not door_hp_by_key.has(door_key):
		door_hp_by_key[door_key] = _get_current_door_max_hp()

	return float(door_hp_by_key[door_key])


func _break_door(task: Dictionary) -> void:
	var door_cells: Array = task["door_cells"]
	var door_key: String = task["door_key"]

	DoorManager.set_door_state(
		foundation_layer,
		door_cells,
		DoorManager.DOOR_STATE_OPEN
	)

	door_hp_by_key[door_key] = _get_current_door_max_hp()
	_remove_door_hp_visual(door_key)
	door_cells_by_key.erase(door_key)
	door_close_cooldowns[door_key] = _get_current_door_close_cooldown()


func _resume_all_pawns_waiting_for_door(door_key: String) -> void:
	var pawn_ids: Array = pawns.keys()

	for pawn_id: String in pawn_ids:
		if not pawns.has(pawn_id):
			continue

		var pawn: Dictionary = pawns[pawn_id]

		if pawn["state"] != PawnTaskLogic.STATE_WORKING:
			continue

		var task: Dictionary = pawn["task"]

		if task.get("type", "") != PawnTaskLogic.TASK_DOOR_DESTROY:
			continue

		if task.get("door_key", "") != door_key:
			continue

		_resume_pawn_movement_after_destroyed_door(pawn_id)


func _resume_pawn_movement_after_destroyed_door(pawn_id: String) -> void:
	var door_task: Dictionary = pawns[pawn_id]["task"]
	var target_cell: Vector2i = door_task["target_cell"]
	var after_move_task: Dictionary = door_task.get("after_move_task", {})
	var attack_cell: Vector2i = door_task.get("door_attack_cell", pawns[pawn_id]["cells"][0])

	door_destroy_attack_timers.erase(pawn_id)

	# После выламывания двери нельзя продолжать старый массив steps с open_door-индекса:
	# ranged-пешка могла стоять далеко от двери, а старый путь предполагает, что она уже
	# находится у open_door-точки. Поэтому строим новый маршрут от её фактической
	# логической клетки атаки к зарезервированной конечной клетке.
	pawns[pawn_id]["cells"] = [attack_cell]
	pawns[pawn_id]["node"].position = _cell_to_pawn_parent_position(attack_cell)
	pawns[pawn_id]["task"] = {}

	pawn_to_cell(
		pawn_id,
		target_cell,
		after_move_task,
		false,
		PawnTaskLogic.TASK_LOCK_PLAYER
	)

func _get_door_destroy_animation_name(task: Dictionary) -> String:
	var mode: String = task.get("door_attack_mode", "remote")

	if mode == "wait":
		return "standing"

	if mode == "melee":
		return "battle"

	return "battle_remotely"


func _get_vector_to_door_task(
	pawn_id: String,
	task: Dictionary
) -> Vector2:
	var pawn_position: Vector2 = pawns[pawn_id]["node"].position
	var door_position: Vector2 = _get_door_cells_center_pawn_parent(task["door_cells"])
	var delta: Vector2 = door_position - pawn_position

	if delta.length_squared() <= 0.01:
		return Vector2.UP

	return delta.normalized()


func _get_door_cells_center(door_cells: Array) -> Vector2:
	var door_position: Vector2 = Vector2.ZERO

	for door_cell: Vector2i in door_cells:
		door_position += foundation_layer.map_to_local(door_cell)

	return door_position / float(door_cells.size())


func _get_door_cells_center_pawn_parent(door_cells: Array) -> Vector2:
	var door_position: Vector2 = Vector2.ZERO

	for door_cell: Vector2i in door_cells:
		door_position += _cell_to_pawn_parent_position(door_cell)

	return door_position / float(door_cells.size())


func _convert_path_data_points_to_pawn_parent(path_data: Dictionary) -> Dictionary:
	# ВАЖНО: точки pathfinder-а оставляем в той же системе координат,
	# в которой их ожидает Pawn.move_by_steps_until_action().
	# Для прямой записи в pawn.position используется отдельная конвертация
	# через _path_point_to_pawn_parent_position().
	return path_data


func _steps_to_points_from_steps(steps: Array[Dictionary]) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()

	for step: Dictionary in steps:
		if not step.has("point"):
			continue

		result.append(step["point"])

	return result


func _cell_to_pawn_parent_position(cell: Vector2i) -> Vector2:
	return _path_point_to_pawn_parent_position(_cell_to_path_point(cell))


func _cell_to_path_point(cell: Vector2i) -> Vector2:
	return foundation_layer.to_global(
		foundation_layer.map_to_local(cell)
	)


func _path_point_to_pawn_parent_position(path_point: Vector2) -> Vector2:
	return pawns_layer.to_local(path_point)


func _pawn_position_to_foundation_cell(pawn_id: String) -> Vector2i:
	var pawn_global_position: Vector2 = pawns_layer.to_global(
		pawns[pawn_id]["node"].position
	)
	var foundation_local_position: Vector2 = foundation_layer.to_local(
		pawn_global_position
	)

	return foundation_layer.local_to_map(foundation_local_position)



func _process_station_workers(delta: float) -> void:
	for pawn_id: String in pawns.keys():
		if not _pawn_is_friendly_to_ship(pawn_id):
			continue
		
		var pawn: Dictionary = pawns[pawn_id]
		
		if pawn["state"] != "working":
			continue

		var task: Dictionary = pawn["task"]

		if task.get("type", "") != PawnTaskLogic.TASK_STATION:
			continue

		var room_id: int = task["room_id"]
		
		#print("Пешка занята станцией в комнате "+str(task["room_id"]))

		# тут уже эффект станции:
		# генерация энергии, управление пушками, лечение, производство и т.д.
		
		#print("Пешка занята станцией в комнате "+str(task["room_id"]))

		# тут уже эффект станции:
		# генерация энергии, управление пушками, лечение, производство и т.д.

func _assign_idle_pawn_tasks() -> void:
	var orders: Array[Dictionary] = PawnTaskLogic.create_task_orders(
		foundation_layer,
		rooms,
		pawns,
		fires,
		hull_holes,
		starship_uuid
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

			PawnTaskLogic.TASK_ROOM_DESTROY:
				_start_pawn_work(pawn_id, task)


func _start_pawn_work(pawn_id: String, task: Dictionary) -> void:
	pawns[pawn_id]["state"] = "working"
	pawns[pawn_id]["task"] = task

	_set_pawn_task_animation(pawn_id)


func _start_station_task(pawn_id: String, task: Dictionary) -> void:
	var pawn_cell: Vector2i = _pawn_position_to_foundation_cell(pawn_id)

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
		PawnTaskLogic.TASK_FIRE,
		starship_uuid
	)

	for fire_cell: Vector2i in fires.keys():
		var fire: Node = fires[fire_cell]["node"]
		var workers: int = int(workers_by_fire.get(fire_cell, 0))

		fire.extinguish_fire(workers > 0)
		fire.set_time_scale(workers)


func _process_hull_repair_workers(delta: float) -> void:
	var workers_by_hole: Dictionary = PawnTaskLogic.count_workers_by_target(
		pawns,
		PawnTaskLogic.TASK_HULL_REPAIR,
		starship_uuid
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
		clampi(doors_level, 0, fortress_doors_levels_map.size() - 1)
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
		ignore_pawns_on_target,
		true,
		pawn_id
	)

	if not target_cell in available_cells:
		push_warning("Target cell for moving not available: " + str(target_cell))
		return

	var source_cell: Vector2i = _pawn_position_to_foundation_cell(pawn_id)
	pawns[pawn_id]["node"].position = _cell_to_pawn_parent_position(source_cell)

	pawns[pawn_id]["cells"] = [target_cell]
	pawns[pawn_id]["state"] = PawnTaskLogic.STATE_MOVING

	var blocked_cells: Dictionary = _get_blocked_cells_for_pawn_path(pawn_id, target_cell)
	var raw_path_data: Dictionary = ShipPathfinder.calculate(
		foundation_layer,
		rooms,
		source_cell,
		target_cell,
		10,
		blocked_cells
	)
	var path_data: Dictionary = raw_path_data

	if not path_data["valid"]:
		push_warning("Path invalid: " + str(path_data["errors"]))
		pawns[pawn_id]["cells"] = [source_cell]
		_set_pawn_idle(pawn_id)
		return

	var movement_task: Dictionary = {
		"steps": path_data["steps"],
		"next_step_index": 0,
		"target_cell": target_cell,
		"after_move_task": after_move_task,
		"lock": task_lock
	}

	pawns[pawn_id]["task"] = movement_task

	if not _pawn_is_friendly_to_ship(pawn_id):
		var first_closed_door_step_index: int = _get_first_closed_door_step_index(path_data["steps"])

		if first_closed_door_step_index >= 0:
			var door_step: Dictionary = path_data["steps"][first_closed_door_step_index]
			var door_key: String = _door_cells_key(door_step["door_cells"])

			_start_door_destroy_task_from_planned_movement(
				pawn_id,
				door_step,
				door_key,
				first_closed_door_step_index + 1,
				source_cell
			)
			return

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

	if door_destroy_attack_timers.has(pawn_id):
		door_destroy_attack_timers.erase(pawn_id)

	_reset_pawn_visual_position(pawn_id)

	var pawn: Node2D = pawns[pawn_id]["node"]
	pawn.set_animation(pawn.direction, "standing")

	_update_battle_visual_offsets()

func cell_to_room(cell: Vector2i) -> int:
	for room: Dictionary in rooms:
		if cell in room["floor_cells"]:
			return int(room["room_id"])
	
	return -1

func _get_pawn_reserved_cells_for_availability(pawn_id: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	for cell: Vector2i in pawns[pawn_id]["cells"]:
		result.append(cell)

	var task: Dictionary = pawns[pawn_id]["task"]

	if task.has("reserved_target_cell"):
		var reserved_cell: Vector2i = task["reserved_target_cell"]

		if not reserved_cell in result:
			result.append(reserved_cell)

	return result


func _get_blocked_cells_for_pawn_path(
	pawn_id: String,
	allowed_target_cell: Vector2i
) -> Dictionary:
	# Пешки не являются стенами для pathfinder-а.
	# Они запрещают только ВЫБОР конечной/рабочей клетки через
	# dynamically_available_cells() и _door_attack_cell_is_reserved_by_friendly(),
	# но маршрут может проходить через клетки союзников.
	# Иначе после выламывания двери один союзник в узком проходе может сделать
	# зарезервированную цель формально недостижимой, хотя по игровой логике
	# пешки должны разойтись/пройти сквозь занятые логические клетки.
	return {}


func dynamically_available_cells(
	room_id: int = -1,
	main_floor_priority: bool = true,
	ignore_pawns: bool = false,
	ignore_fires: bool = true,
	pawn_id: String = ""
) -> Array[Vector2i]:
	var exclude_cells: Dictionary = {}

	if not ignore_pawns:
		if pawn_id == "":
			for other_id: String in pawns.keys():
				for cell: Vector2i in _get_pawn_reserved_cells_for_availability(other_id):
					exclude_cells[cell] = true
		else:
			var pawn_starship: String = pawns[pawn_id]["node"].get_current_starship()

			for other_id: String in pawns.keys():
				if other_id == pawn_id:
					continue

				if not pawns[other_id]["node"].control_is_available(pawn_starship):
					continue

				for cell: Vector2i in _get_pawn_reserved_cells_for_availability(other_id):
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
		var visual_delta: Vector2 = (
			pawns[target_pawn_id]["node"].position
			- pawns[pawn_id]["node"].position
		)

		if visual_delta.length_squared() > 0.01:
			return visual_delta.normalized()

		return Vector2.DOWN

	return Vector2(cell_delta).normalized()

func _process_battle_tasks(delta: float) -> void:
	pawn_battle_recheck_timer += delta

	if pawn_battle_recheck_timer >= pawn_battle_recheck_interval:
		pawn_battle_recheck_timer = 0.0
		_refresh_battle_tasks()
		_update_battle_visual_offsets()

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

	_update_battle_visual_offsets()
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

		for other_cell: Vector2i in _get_pawn_reserved_cells_for_availability(other_id):
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
			_set_pawn_idle(pawn_id)
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

	_set_pawn_idle(pawn_id)
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

		_set_pawn_idle(other_id)
		pawn_battle_attack_timers.erase(other_id)

	pawn_battle_attack_timers.erase(pawn_id)
	door_destroy_attack_timers.erase(pawn_id)

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
				var other_cell: Vector2i = _pawn_position_to_foundation_cell(other_id)

				if other_cell == target_cell:
					return true

	return false

func _reset_pawn_visual_position(pawn_id: String) -> void:
	if not pawns.has(pawn_id):
		return

	if pawns[pawn_id]["cells"].is_empty():
		return

	var cell: Vector2i = pawns[pawn_id]["cells"][0]
	pawns[pawn_id]["node"].position = foundation_layer.map_to_local(cell)


func _get_melee_visual_offset_radius() -> float:
	if pawn_battle_melee_visual_offset_px > 0.0:
		return pawn_battle_melee_visual_offset_px

	var tile_size: Vector2i = foundation_layer.tile_set.tile_size
	return float(min(tile_size.x, tile_size.y)) * 0.22


func _get_melee_visual_offset(
	index: int,
	count: int,
	radius: float
) -> Vector2:
	if count <= 1:
		return Vector2.ZERO

	if count == 2:
		if index == 0:
			return Vector2.LEFT * radius

		return Vector2.RIGHT * radius

	var angle: float = -PI * 0.5 + TAU * float(index) / float(count)
	return Vector2(cos(angle), sin(angle)) * radius


func _add_pawn_to_melee_visual_group(
	groups: Dictionary,
	cell: Vector2i,
	pawn_id: String
) -> void:
	if not groups.has(cell):
		groups[cell] = []

	var group: Array = groups[cell]

	if pawn_id in group:
		return

	group.append(pawn_id)
	groups[cell] = group


func _update_battle_visual_offsets() -> void:
	var groups: Dictionary = {}
	var offset_pawn_ids: Dictionary = {}

	for pawn_id: String in pawns.keys():
		var pawn: Dictionary = pawns[pawn_id]

		if pawn["state"] != PawnTaskLogic.STATE_WORKING:
			continue

		var task: Dictionary = pawn["task"]

		if task.get("type", "") != PawnTaskLogic.TASK_BATTLE:
			continue

		var target_pawn_id: String = task.get("target_pawn_id", "")

		if not _battle_target_is_valid(pawn_id, target_pawn_id):
			continue

		if not _battle_is_melee(pawn_id, target_pawn_id):
			continue

		var cell: Vector2i = pawn["cells"][0]

		_add_pawn_to_melee_visual_group(groups, cell, pawn_id)
		_add_pawn_to_melee_visual_group(groups, cell, target_pawn_id)

	var radius: float = _get_melee_visual_offset_radius()

	for cell: Vector2i in groups.keys():
		var group: Array = groups[cell]
		group.sort()

		if group.size() < 2:
			continue

		var center: Vector2 = foundation_layer.map_to_local(cell)

		for index: int in range(group.size()):
			var pawn_id: String = group[index]

			if not pawns.has(pawn_id):
				continue

			var offset: Vector2 = _get_melee_visual_offset(
				index,
				group.size(),
				radius
			)

			pawns[pawn_id]["node"].position = center + offset
			offset_pawn_ids[pawn_id] = true

	for pawn_id: String in pawns.keys():
		if offset_pawn_ids.has(pawn_id):
			continue

		if pawns[pawn_id]["state"] == PawnTaskLogic.STATE_MOVING:
			continue

		var visual_task: Dictionary = pawns[pawn_id]["task"]

		if pawns[pawn_id]["state"] == PawnTaskLogic.STATE_WORKING:
			if visual_task.get("type", "") == PawnTaskLogic.TASK_DOOR_DESTROY:
				pawns[pawn_id]["node"].position = visual_task.get(
					"door_attack_point",
					pawns[pawn_id]["node"].position
				)
				continue

		_reset_pawn_visual_position(pawn_id)

func _interrupt_station_workers_for_room_tasks() -> bool:
	var interrupted: bool = false

	for pawn_id: String in pawns.keys():
		var pawn: Dictionary = pawns[pawn_id]

		if pawn["state"] != PawnTaskLogic.STATE_WORKING:
			continue

		var task: Dictionary = pawn["task"]

		if task.get("type", "") != PawnTaskLogic.TASK_STATION:
			continue

		var room_id: int = int(task["room_id"])

		if not (_room_has_fire(room_id) or _room_has_hull_hole(room_id)):
			continue

		_set_pawn_idle(pawn_id)
		interrupted = true

	return interrupted

func _room_has_fire(room_id: int) -> bool:
	for fire_data: Dictionary in fires.values():
		var fire: Node2D = fire_data["node"]

		if int(fire.get_meta("room")) == room_id:
			return true

	return false

func _room_has_hull_hole(room_id: int) -> bool:
	var room: Dictionary = rooms[room_id]

	for hole_cell: Vector2i in hull_holes.keys():
		if hole_cell in room["floor_cells"]:
			return true

	return false

func setup_room_hp() -> void:
	room_hp_by_room = {}
	depleted_room_ids = {}
	_setup_room_station_hp_visuals()
	
	for room_id: int in range(rooms.size()):
		room_hp_by_room[room_id] = room_hp_max


func _setup_room_station_hp_visuals() -> void:
	_clear_room_station_hp_visuals()
	room_station_hp_visual_phases_by_room = {}
	room_station_hp_visual_frequencies_by_room = {}


func _clear_room_station_hp_visuals() -> void:
	for layer_variant: Variant in room_station_hp_visual_layers_by_room.values():
		var layer: Node = layer_variant

		if is_instance_valid(layer):
			layer.queue_free()

	room_station_hp_visual_layers_by_room = {}


func _remove_room_station_hp_visual(room_id: int) -> void:
	if room_station_hp_visual_layers_by_room.has(room_id):
		var layer: Node = room_station_hp_visual_layers_by_room[room_id]

		if is_instance_valid(layer):
			layer.queue_free()

		room_station_hp_visual_layers_by_room.erase(room_id)

	room_station_hp_visual_phases_by_room.erase(room_id)
	room_station_hp_visual_frequencies_by_room.erase(room_id)


func _ensure_room_station_hp_visual(room_id: int) -> void:
	if room_station_hp_visual_layers_by_room.has(room_id):
		return

	var layer: TileMapLayer = TileMapLayer.new()
	layer.name = "RoomStationHpVisual_" + str(room_id)
	layer.tile_set = stations_layer.tile_set
	layer.position = Vector2.ZERO
	layer.z_index = 1
	layer.z_as_relative = true
	layer.modulate = Color(0.0, 0.0, 0.0, 0.0)

	var has_tiles: bool = false

	for cell: Vector2i in rooms[room_id]["cells"]:
		var source_id: int = stations_layer.get_cell_source_id(cell)

		if source_id < 0:
			continue

		layer.set_cell(
			cell,
			source_id,
			stations_layer.get_cell_atlas_coords(cell),
			stations_layer.get_cell_alternative_tile(cell)
		)
		has_tiles = true

	if not has_tiles:
		layer.queue_free()
		return

	stations_layer.add_child(layer)
	room_station_hp_visual_layers_by_room[room_id] = layer
	room_station_hp_visual_phases_by_room[room_id] = 0.0
	room_station_hp_visual_frequencies_by_room[room_id] = 1.0 / room_station_hp_visual_max_period


func _process_room_station_hp_visuals(delta: float) -> void:
	if not room_station_hp_visual_enabled:
		_clear_room_station_hp_visuals()
		return

	for room_id: int in range(rooms.size()):
		var hp: float = clampf(float(room_hp_by_room.get(room_id, room_hp_max)), 0.0, room_hp_max)

		if hp >= room_hp_max:
			_remove_room_station_hp_visual(room_id)
			continue

		_ensure_room_station_hp_visual(room_id)

		if not room_station_hp_visual_layers_by_room.has(room_id):
			continue

		var hp_ratio: float = clampf(hp / room_hp_max, 0.0, 1.0)
		var damage_ratio: float = 1.0 - hp_ratio
		var period: float = lerpf(
			room_station_hp_visual_min_period,
			room_station_hp_visual_max_period,
			hp_ratio
		)
		var target_frequency: float = 1.0 / period
		var current_frequency: float = float(
			room_station_hp_visual_frequencies_by_room.get(room_id, target_frequency)
		)
		current_frequency = lerpf(
			current_frequency,
			target_frequency,
			clampf(delta * room_station_hp_visual_speed_smoothing, 0.0, 1.0)
		)
		room_station_hp_visual_frequencies_by_room[room_id] = current_frequency

		var phase: float = float(room_station_hp_visual_phases_by_room.get(room_id, 0.0))
		phase = fmod(phase + delta * current_frequency, 1.0)
		room_station_hp_visual_phases_by_room[room_id] = phase

		var pulse: float = (1.0 - cos(phase * TAU)) * 0.5
		var alpha: float = pulse * room_station_hp_visual_max_alpha * clampf(
			0.35 + damage_ratio * 0.65,
			0.0,
			1.0
		)
		var layer: CanvasItem = room_station_hp_visual_layers_by_room[room_id]
		layer.modulate = Color(0.0, 0.0, 0.0, alpha)


func process_room_hp(delta: float) -> void:
	var damage_by_room: Dictionary = _get_room_damage_by_room()
	
	for room_id: int in range(rooms.size()):
		if damage_by_room.has(room_id):
			var current_hp: float = float(room_hp_by_room[room_id])
			var damage: float = float(damage_by_room[room_id]) * delta
			var next_hp: float = maxf(current_hp - damage, 0.0)
			
			room_hp_by_room[room_id] = next_hp
			emit_signal("room_hp_changed", room_id, next_hp)
			
			if next_hp <= 0.0 and not depleted_room_ids.has(room_id):
				depleted_room_ids[room_id] = true
				emit_signal("room_hp_depleted", room_id)
				_on_room_hp_depleted(room_id)
			
			continue
		
		if float(room_hp_by_room[room_id]) != room_hp_max:
			room_hp_by_room[room_id] = room_hp_max
			depleted_room_ids.erase(room_id)
			emit_signal("room_hp_changed", room_id, room_hp_max)


func _get_room_damage_by_room() -> Dictionary:
	var result: Dictionary = {}
	
	for fire_data: Dictionary in fires.values():
		var fire: Node2D = fire_data["node"]
		var room_id: int = int(fire.get_meta("room"))
		
		_add_room_damage(result, room_id, room_fire_damage_per_second)
	
	for pawn_id: String in pawns.keys():
		if _pawn_is_friendly_to_ship(pawn_id):
			continue
		
		var pawn: Dictionary = pawns[pawn_id]
		
		if pawn["state"] != PawnTaskLogic.STATE_WORKING:
			continue
		
		var task: Dictionary = pawn["task"]
		
		if task.get("type", "") != PawnTaskLogic.TASK_ROOM_DESTROY:
			continue
		
		var pawn_cell: Vector2i = _pawn_position_to_foundation_cell(pawn_id)
		var current_room_id: int = cell_to_room(pawn_cell)
		var task_room_id: int = int(task["room_id"])
		
		if current_room_id != task_room_id:
			continue
		
		_add_room_damage(
			result,
			task_room_id,
			room_hostile_pawn_damage_per_second
		)
	
	return result


func _add_room_damage(
	damage_by_room: Dictionary,
	room_id: int,
	damage_per_second: float
) -> void:
	damage_by_room[room_id] = (
		float(damage_by_room.get(room_id, 0.0))
		+ damage_per_second
	)

func _pawn_is_friendly_to_ship(pawn_id: String) -> bool:
	return pawns[pawn_id]["node"].control_is_available(starship_uuid)

func _on_room_hp_depleted(room_id: int) -> void:
	pass
