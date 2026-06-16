extends Node2D

func _ready() -> void:
	var layer: TileMapLayer = $Foundation
	var samples_per_tile: int = 2
	
	var validation: Dictionary = ShipRooms.validate(layer, samples_per_tile)
	
	var floor_validation: Dictionary = ShipRoomFloors.validate(
		layer,
		validation["rooms"]
	)
	
	#print(floor_validation)
	
	var station_data: Dictionary = ShipRoomSpecialization.validate(
		$Stations,
		validation["rooms"],
		$Foundation
	)

	print(station_data)
	print()
	for error in station_data["errors"]:
		print(error["cause"])
	
	for ac in validation["errors"]:
		if ac["room_id"] > 0:
			validation["rooms"][ac["room_id"]]["nowall"] = true
	
	var access_validation: Dictionary = ShipRoomAccess.validate(
		layer,
		validation["rooms"],
		samples_per_tile
	)
	for ac in access_validation["errors"]:
		if ac["room_id"] > 0:
			validation["rooms"][ac["room_id"]]["barricaded"] = true
	
	for room: Dictionary in validation["rooms"]:
		var polygons: Array[PackedVector2Array] = room["polygons"]
		
		for points: PackedVector2Array in polygons:
			var polygon: Polygon2D = Polygon2D.new()
			if room.get("nowall", false) and room.get("barricaded", false):
				polygon.color = Color(0.0, 0.0, 1.0, 0.502)
			elif room.get("nowall", false):
				polygon.color = Color(1.0, 0.0, 0.0, 0.502)
			elif room.get("barricaded", false):
				polygon.color = Color(0.779, 0.437, 0.0, 0.502)
			else:
				polygon.color = Color(0.0, 1.0, 0.0, 0.5)
			polygon.polygon = points
			
			layer.add_child(polygon)
	
	var path_data: Dictionary = ShipPathfinder.calculate(
		$Foundation,
		Vector2i(-3, -2),
		Vector2i(2, 2)
	)
	#print()
	#print(path_data)

	draw_debug_path(path_data)

@onready var debug_path_node: Node2D = $GameInput


func draw_debug_path(path_data: Dictionary) -> void:
	if debug_path_node != null:
		debug_path_node.queue_free()

	debug_path_node = Node2D.new()
	debug_path_node.name = "DebugPath"
	add_child(debug_path_node)

	if not path_data.get("valid", false):
		print("Path is invalid: ", path_data.get("errors", []))
		return

	var points: PackedVector2Array = path_data.get("points", PackedVector2Array())

	if points.size() < 1:
		return

	var line: Line2D = Line2D.new()
	line.width = 3.0
	line.default_color = Color(1.0, 0.0, 0.0, 0.85)
	debug_path_node.add_child(line)

	for global_point: Vector2 in points:
		line.add_point(debug_path_node.to_local(global_point))

		var marker: ColorRect = ColorRect.new()
		marker.color = Color(1.0, 1.0, 0.0, 0.9)
		marker.size = Vector2(6, 6)
		marker.position = debug_path_node.to_local(global_point) - marker.size * 0.5
		debug_path_node.add_child(marker)
