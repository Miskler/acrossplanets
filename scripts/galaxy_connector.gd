extends Node

func generate_connections(
	sectors: Array[Dictionary],
	arm_count: int,
	connection_distance: float = 45.0,
	enable_cross_arms: bool = true,
	enable_spur_connections: bool = true,
) -> Array[Dictionary]:
	
	var connections: Array[Dictionary] = []
	
	if sectors.is_empty():
		return connections
	
	# -------- 1. Индексация секторов (как в оригинале) --------
	var sector_dict: Dictionary = {}
	var core_sectors: Array[String] = []
	var arm_sectors: Dictionary = {}      # key: arm_index, value: Array[{"id","step"}]
	var spur_sectors: Dictionary = {}     # key: parent_id, value: Array[String]
	var sector_positions: Dictionary = {}
	
	for sector in sectors:
		var id: String = sector["id"]
		var pos: Vector2 = Vector2(sector["position"]["x"], sector["position"]["y"])
		
		sector_dict[id] = sector
		sector_positions[id] = pos
		
		if id == "C0":
			core_sectors.append(id)
		elif id.begins_with("N"):
			core_sectors.append(id)
		elif id.contains("_S"):
			var parent_key = id.split("_S")[0]
			if not spur_sectors.has(parent_key):
				spur_sectors[parent_key] = []
			spur_sectors[parent_key].append(id)
		elif id.begins_with("A"):
			var parts = id.split("_")
			var arm_idx = int(parts[0].substr(1)) - 1
			var step_idx = int(parts[1])
			
			if not arm_sectors.has(arm_idx):
				arm_sectors[arm_idx] = []
			arm_sectors[arm_idx].append({
				"id": id,
				"step": step_idx
			})
	
	for arm_idx in arm_sectors.keys():
		var lst: Array = arm_sectors[arm_idx]
		lst.sort_custom(func(a, b): return a["step"] < b["step"])
	
	# -------- 2. Вычисляем приоритетные направления для каждого сектора --------
	var preferred_dirs: Dictionary = {}   # String -> Array (Vector2)
	
	var main_core = "C0"
	for core_id in core_sectors:
		var dirs: Array[Vector2] = []
		if core_id == main_core:
			for other in core_sectors:
				if other == main_core:
					continue
				var d = sector_positions[other] - sector_positions[main_core]
				if d.length() > 0.001:
					dirs.append(d.normalized())
		else:
			var d = sector_positions[main_core] - sector_positions[core_id]
			if d.length() > 0.001:
				dirs.append(d.normalized())
		preferred_dirs[core_id] = dirs
	
	var cross_arm_map: Dictionary = {}
	if enable_cross_arms and arm_count > 1:
		for arm_idx in arm_sectors.keys():
			for entry in arm_sectors[arm_idx]:
				var step = entry["step"]
				var key = str(arm_idx) + "_" + str(step)
				cross_arm_map[key] = entry["id"]
	
	for arm_idx in arm_sectors.keys():
		var arm_list: Array = arm_sectors[arm_idx]
		for i in range(arm_list.size()):
			var entry = arm_list[i]
			var sec_id: String = entry["id"]
			var dirs: Array[Vector2] = []
			
			if i > 0:
				var prev_id: String = arm_list[i-1]["id"]
				var d = sector_positions[prev_id] - sector_positions[sec_id]
				if d.length() > 0.001:
					dirs.append(d.normalized())
			
			if i < arm_list.size() - 1:
				var next_id: String = arm_list[i+1]["id"]
				var d = sector_positions[next_id] - sector_positions[sec_id]
				if d.length() > 0.001:
					dirs.append(d.normalized())
			
			if enable_cross_arms and arm_count > 1:
				var step = entry["step"]
				var next_arm = (arm_idx + 1) % arm_count
				var cross_key = str(next_arm) + "_" + str(step)
				if cross_arm_map.has(cross_key):
					var cross_id: String = cross_arm_map[cross_key]
					var d = sector_positions[cross_id] - sector_positions[sec_id]
					if d.length() > 0.001:
						dirs.append(d.normalized())
			
			preferred_dirs[sec_id] = dirs
	
	if enable_spur_connections:
		for parent_id in spur_sectors.keys():
			var children = spur_sectors[parent_id]
			for child_id in children:
				if not preferred_dirs.has(parent_id):
					preferred_dirs[parent_id] = []
				var d_par_to_child = sector_positions[child_id] - sector_positions[parent_id]
				if d_par_to_child.length() > 0.001:
					preferred_dirs[parent_id].append(d_par_to_child.normalized())
				
				if not preferred_dirs.has(child_id):
					preferred_dirs[child_id] = []
				var d_child_to_par = sector_positions[parent_id] - sector_positions[child_id]
				if d_child_to_par.length() > 0.001:
					preferred_dirs[child_id].append(d_child_to_par.normalized())
	
	for sector in sectors:
		var id = sector["id"]
		if not preferred_dirs.has(id):
			preferred_dirs[id] = []
	
	# -------- 3. Лучевой поиск соединений --------
	const NUM_RAYS: int = 16
	const CONE_HALF_ANGLE_DEG: float = 15.0
	const CONE_HALF_ANGLE: float = deg_to_rad(CONE_HALF_ANGLE_DEG)
	const PREFERRED_DOT_THRESHOLD: float = cos(deg_to_rad(25.0))
	
	var edge_dist: Dictionary = {}
	var all_sector_ids: Array[String] = []
	for sector in sectors:
		all_sector_ids.append(sector["id"])
	
	for source_id in all_sector_ids:
		var source_pos: Vector2 = sector_positions[source_id]
		var dirs = preferred_dirs[source_id]   # <-- ИСПРАВЛЕНО: убрана аннотация типа
		
		for ray_index in range(NUM_RAYS):
			var angle: float = ray_index * TAU / NUM_RAYS
			var ray_dir: Vector2 = Vector2(cos(angle), sin(angle))
			
			var is_preferred: bool = false
			for pref_dir in dirs:
				if ray_dir.dot(pref_dir) > PREFERRED_DOT_THRESHOLD:
					is_preferred = true
					break
			
			var max_dist: float = connection_distance * (2.0 if is_preferred else 1.0)
			
			var best_target_id: String = ""
			var best_dist: float = INF
			
			for target_id in all_sector_ids:
				if target_id == source_id:
					continue
				var target_pos: Vector2 = sector_positions[target_id]
				var to_target: Vector2 = target_pos - source_pos
				var dist: float = to_target.length()
				if dist > max_dist:
					continue
				var to_target_norm: Vector2 = to_target.normalized()
				var angle_between: float = acos(clamp(ray_dir.dot(to_target_norm), -1.0, 1.0))
				if angle_between > CONE_HALF_ANGLE:
					continue
				if dist < best_dist:
					best_dist = dist
					best_target_id = target_id
			
			if not best_target_id.is_empty():
				var id1 = source_id
				var id2 = best_target_id
				if id1 > id2:
					var tmp = id1
					id1 = id2
					id2 = tmp
				var edge_key = id1 + "|" + id2
				if not edge_dist.has(edge_key) or best_dist < edge_dist[edge_key]:
					edge_dist[edge_key] = best_dist
	
	# -------- 4. Строим итоговый граф с ограничением степени вершин --------
	const MAX_DEGREE: int = 4
	
	var edge_list: Array[Dictionary] = []
	for edge_key in edge_dist.keys():
		var parts = edge_key.split("|")
		edge_list.append({
			"from": parts[0],
			"to": parts[1],
			"dist": edge_dist[edge_key]
		})
	
	edge_list.sort_custom(func(a, b): return a["dist"] < b["dist"])
	
	var degree: Dictionary = {}
	for id in all_sector_ids:
		degree[id] = 0
	
	for edge in edge_list:
		var u: String = edge["from"]
		var v: String = edge["to"]
		if degree[u] < MAX_DEGREE and degree[v] < MAX_DEGREE:
			degree[u] += 1
			degree[v] += 1
			connections.append({
				"from": u,
				"to": v
			})
	
	return connections

func find_sectors_not_connected_to_center(sectors: Array[Dictionary], connections: Array[Dictionary]) -> Array[String]:
	# Результат: список id секторов, которые недостижимы из центра "C0"
	var candidates: Array[String] = []
	
	if sectors.is_empty():
		return candidates
	
	# Проверяем, есть ли C0
	var center_exists = false
	for sector in sectors:
		if sector["id"] == "C0":
			center_exists = true
			break
	
	# Если центра нет, удаляем все сектора (нет связи с несуществующим центром)
	if not center_exists:
		for sector in sectors:
			candidates.append(sector["id"])
		return candidates
	
	# Строим граф соседей из соединений (неориентированный)
	var graph: Dictionary = {}
	for sector in sectors:
		graph[sector["id"]] = []
	
	for conn in connections:
		var from_id: String = conn["from"]
		var to_id: String = conn["to"]
		if graph.has(from_id) and graph.has(to_id):
			graph[from_id].append(to_id)
			graph[to_id].append(from_id)
	
	# BFS от C0
	var visited: Dictionary = {}
	var queue: Array[String] = ["C0"]
	visited["C0"] = true
	
	while not queue.is_empty():
		var current = queue.pop_front()
		for neighbor in graph[current]:
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	
	# Все сектора, не попавшие в visited, — кандидаты на удаление
	for sector in sectors:
		var id: String = sector["id"]
		if not visited.has(id):
			candidates.append(id)
	
	return candidates
