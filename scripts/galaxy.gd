extends GraphEdit

@onready var sector_sample: Control = get_node("*Sector")
@onready var sector_background_sample: Control = get_node("*BackgroudSector")
@onready var connection_sample: Control = get_node("*Connector")


func _ready() -> void:
	sector_sample.hide()
	connection_sample.hide()
	
	var arm_count = 2
	var sectors_per_arm = 40
	var galaxy_seed = -1
	var sectors_spacing = 20
	var total_turns = 0.4
	var arm_waveness = 0.18
	
	var data = ClusterGenerator.generate_spiral_galaxy(
		arm_count,
		sectors_per_arm,
		galaxy_seed,
		sectors_spacing,
		total_turns,
		arm_waveness
	)
	var connections_data = GalaxyConnector.generate_connections(data["sectors"], arm_count, 100)
	var not_for_render = GalaxyConnector.find_sectors_not_connected_to_center(data["sectors"], connections_data)
	
	var positions = process_positions(data["sectors"])
	
	var dist = 64
	for sector in data.sectors:
		var pos = Vector2(sector.position.x, sector.position.y)
		# Добавляем несколько фоновых точек вокруг
		for i in range(4):
			var offset = Vector2(randf_range(-dist, dist), randf_range(-dist, dist))
			create_sector(
				sector_background_sample,
				sector["id"]+"_back"+str(i),
				pos + offset
			)
	
	for connection in connections_data:
		if not connection["from"] in not_for_render and not connection["to"] in not_for_render:
			create_connection(
				positions[connection["from"]],
				positions[connection["to"]]
			)
	
	for sector in data["sectors"]:
		if not sector["id"] in not_for_render:
			create_sector(
				sector_sample,
				sector["id"],
				positions[sector["id"]]
			)
	
	call_deferred("_patch_scrollbars")
	var fit = fit_graph(self)
	zoom = fit["zoom"]
	scroll_offset = fit["center"]


func process_positions(sectors) -> Dictionary:
	var positions := {}
	
	for sector in sectors:
		var id: String = sector["id"]
		var p: Dictionary = sector["position"]
		
		positions[id] = Vector2(p["x"], p["y"])
	return positions


func _patch_scrollbars() -> void:
	for node in find_children("*", "ScrollBar", true, false):
		var bar := node as ScrollBar
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.hide()

		var cb := _on_scrollbar_visibility_changed.bind(bar)
		if not bar.visibility_changed.is_connected(cb):
			bar.visibility_changed.connect(cb)

func fit_graph(graph_edit: GraphEdit) -> Dictionary:
	var nodes := graph_edit.get_children().filter(
		func(n): return n is GraphElement
	)
	
	if nodes.is_empty():
		return {"zoom": 1, "center": Vector2.ZERO}
	
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	
	for node in nodes:
		var graph_node: GraphElement = node
		
		var pos := graph_node.position_offset
		var size_node := graph_node.size
		
		min_pos.x = min(min_pos.x, pos.x)
		min_pos.y = min(min_pos.y, pos.y)
		
		max_pos.x = max(max_pos.x, pos.x + size_node.x)
		max_pos.y = max(max_pos.y, pos.y + size_node.y)
	
	var content_size := max_pos - min_pos
	
	var viewport_size := graph_edit.size
	
	# небольшой отступ по краям
	var margin := 80.0
	
	var zoom_x: float = viewport_size.x / maxf(content_size.x + margin, 1.0)
	var zoom_y: float = viewport_size.y / maxf(content_size.y + margin, 1.0)
	
	var target_zoom: float = minf(zoom_x, zoom_y)
	
	# ограничиваем допустимыми значениями
	return {
		"zoom": clampf(target_zoom, graph_edit.zoom_min, graph_edit.zoom_max),
		"center": (-viewport_size*0.5)
	}

func _on_scrollbar_visibility_changed(bar: ScrollBar) -> void:
	if bar.visible:
		bar.call_deferred("hide")


func create_sector(sample: GraphElement, id: String, center: Vector2) -> void:
	var node: GraphElement = sample.duplicate()
	add_child(node)

	node.show()
	node.position_offset = center - node.size / 2.0
	node.name = id

func create_connection(from: Vector2, to: Vector2) -> void:
	var node: GraphElement = connection_sample.duplicate()
	add_child(node)
	
	node.show()
	node.position_offset = from
	node.rotation = from.angle_to_point(to)
	node.size.x = from.distance_to(to)
