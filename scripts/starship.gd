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
const SAMPLES_PER_TILE: int = 1

var time2change_door_state = 0.2

var rooms: Array[Dictionary] = []
var pawns: Dictionary = {}

func _ready() -> void:
	restart()

func restart() -> void:
	technical_layer.hide()
	rooms = recalc_rooms()
	
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
	
	var wait: bool = {"open_door": "open", "close_door": "closed"}[action] == DoorManager.get_door_state(foundation_layer, step["door_cells"])
	await get_tree().create_timer(time2change_door_state).timeout
	
	match action:
		"open_door":
			wait = DoorManager.set_door_state(
				foundation_layer,
				step["door_cells"],
				"open"
			)
		"close_door":
			wait = DoorManager.set_door_state(
				foundation_layer,
				step["door_cells"],
				"closed"
			)
	
	pawns[pawn_id]["task"]["next_step_index"] = next_step_index
	
	pawns[pawn_id]["node"].move_by_steps_until_action(
		pawns[pawn_id]["task"]["steps"],
		next_step_index
	)

func _on_pawn_movement_finished(pawn_id: String) -> void:
	var target_cell: Vector2i = pawns[pawn_id]["task"]["target_cell"]
	
	pawns[pawn_id]["cells"] = [target_cell]
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

func pawn_to_cell(pawn_id: String, target_cell: Vector2i) -> void:
	var available_cells: Array[Vector2i] = dynamically_available_cells()
	if not target_cell in available_cells:
		push_warning("Target cell for moving not available: "+str(target_cell))
		return
	
	var source_cell: Vector2i = foundation_layer.local_to_map(pawns[pawn_id]["node"].position)
	
	pawns[pawn_id]["cells"] = [source_cell, target_cell]
	pawns[pawn_id]["state"] = "moving"
	
	var path_data: Dictionary = ShipPathfinder.calculate(
		foundation_layer,
		rooms,
		source_cell,
		target_cell
	)
	
	if not path_data["valid"]:
		push_warning("Path invalid: " + str(path_data["errors"]))
		return
	
	pawns[pawn_id]["task"] = {
		"steps": path_data["steps"],
		"next_step_index": 0,
		"target_cell": target_cell
	}
	
	pawns[pawn_id]["node"].move_by_steps_until_action(
		path_data["steps"],
		0
	)

func dynamically_available_cells(room_id: int = -1) -> Array[Vector2i]:
	var exclude_cells: Dictionary = {}
	for pawn in pawns.values():
		for cell: Vector2i in pawn["cells"]:
			exclude_cells[cell] = true
	var available_cells: Array[Vector2i] = []
	var id = 0
	for room: Dictionary in rooms:
		if room_id >= 0:
			if id != room_id:
				id += 1
				continue
		var floor_main = room["floor_main"]
		if floor_main != null and not exclude_cells.has(floor_main):
			available_cells.append(floor_main)
		for cell: Vector2i in room["floor_cells"]:
			if cell == floor_main:
				continue
			if exclude_cells.has(cell):
				continue
			available_cells.append(cell)
	return available_cells
