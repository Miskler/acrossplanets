extends Node2D

@export var starship: Starship

func _ready() -> void:
	
	
	var rooms: Dictionary = ShipRooms.validate(starship.foundation_layer, starship.SAMPLES_PER_TILE)
	
	#print()
	#for error in station_data["errors"]:
	#	print(error["cause"])
	
	for ac in rooms["errors"]:
		if ac["room_id"] > 0:
			rooms["rooms"][ac["room_id"]]["nowall"] = true
	
	var access_validation: Dictionary = ShipRoomAccess.validate(
		starship.foundation_layer,
		rooms["rooms"],
		starship.SAMPLES_PER_TILE
	)
	for ac in access_validation["errors"]:
		if ac["room_id"] > 0:
			rooms["rooms"][ac["room_id"]]["barricaded"] = true
	
	for room: Dictionary in rooms["rooms"]:
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
			
			self.add_child(polygon)
	
	var floor_validation: Dictionary = ShipRoomFloors.validate(
		starship.foundation_layer,
		starship.technical_layer,
		rooms["rooms"],
		[starship.stations_layer]
	)
	
	for room in floor_validation["rooms"]:
		for cell in room["floor_cells"]:
			create_cell(cell, Color.GREEN if cell != room["floor_main"] else Color.YELLOW)
		for cell in room["excluded_floor_cells"]:
			create_cell(cell, Color.RED)
	
	var path_data: Dictionary = ShipPathfinder.calculate(
		starship.foundation_layer,
		floor_validation["rooms"],
		floor_validation["rooms"][0]["floor_main"],
		floor_validation["rooms"][-1]["floor_main"]
	)
	
	draw_debug_path(path_data)
	starship.fire_to_room(1)


func create_cell(cell: Vector2i, clr: Color):
	var margin = 4
	var margin_vec = Vector2(margin, margin)
	var real_cell = starship.foundation_layer.map_to_local(cell)
	var node = ReferenceRect.new()
	node.border_width = margin
	node.editor_only = false
	node.border_color = clr
	node.position = real_cell - starship.foundation_layer.tile_set.tile_size / 2.0 + margin_vec / 2.0
	node.size = starship.foundation_layer.tile_set.tile_size - Vector2i(margin_vec)
	add_child(node)

func draw_debug_path(path_data: Dictionary) -> void:
	var debug_path_node = Node2D.new()
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
