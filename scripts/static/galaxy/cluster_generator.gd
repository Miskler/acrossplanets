extends Node
class_name ClusterGenerator

static func generate_spiral_galaxy(
	arm_count: int,
	sectors_per_arm: int,
	seed_value: int = -1,
	sector_spacing: float = 28.0,
	total_turns: float = 0.72,
	arm_waviness: float = 0.18,
	arm_zone_scatter: float = 30.75,
	clumpiness: float = 10.55,
	min_sector_distance: float = 80.0   # новый параметр
) -> Dictionary:
	if arm_count < 1:
		arm_count = 1
	if sectors_per_arm < 1:
		sectors_per_arm = 1

	var sector_spacing_safe: float = maxf(sector_spacing, 8.0)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	if seed_value == -1:
		rng.randomize()
	else:
		rng.seed = seed_value

	var sectors: Array[Dictionary] = []

	# =========================
	# Размер и плотность
	# =========================
	var min_radius: float = sector_spacing_safe * 1.5
	var max_radius: float = min_radius + sector_spacing_safe * float(sectors_per_arm - 1)

	var arm_width_inner: float = sector_spacing_safe * 0.25
	var arm_width_outer: float = sector_spacing_safe * 0.85
	var radial_jitter_base: float = sector_spacing_safe * 0.15
	var squash_y: float = 0.82

	# =========================
	# Центр галактики
	# =========================
	sectors.append({
		"id": "C0",
		"position": {"x": 0.0, "y": 0.0}
	})
	
	var core_satellites: int = min(3, arm_count)
	var core_radius: float = sector_spacing_safe * 0.8
	
	for i in range(core_satellites):
		var core_angle: float = TAU * float(i) / float(core_satellites)
		core_angle += rng.randf_range(-0.3, 0.3)
		var core_node_radius: float = rng.randf_range(core_radius * 0.4, core_radius)
		var core_pos: Vector2 = Vector2(cos(core_angle), sin(core_angle)) * core_node_radius
		core_pos.y *= squash_y
		sectors.append({
			"id": "N%d" % [i + 1],
			"position": {"x": core_pos.x, "y": core_pos.y}
		})

	# =========================
	# Основные рукава
	# =========================
	for arm in range(arm_count):
		var arm_base_angle: float = TAU * float(arm) / float(arm_count)
		var wave_phase_a: float = rng.randf_range(0.0, TAU)
		var wave_phase_b: float = rng.randf_range(0.0, TAU)
		var wave_phase_c: float = rng.randf_range(0.0, TAU)
		var wave_strength: float = rng.randf_range(0.7, 1.3)
		
		var clump_count: int = max(2, int(round(float(sectors_per_arm) / 6.0)))
		var clump_t_values: Array[float] = []
		var clump_side_values: Array[float] = []
		var clump_radial_values: Array[float] = []
		var clump_strength_values: Array[float] = []
		
		for _i in range(clump_count):
			clump_t_values.append(rng.randf_range(0.1, 0.95))
			clump_side_values.append(rng.randf_range(-1.0, 1.0))
			clump_radial_values.append(rng.randf_range(-0.5, 0.5))
			clump_strength_values.append(rng.randf_range(0.4, 1.0))
		
		for step in range(sectors_per_arm):
			var t: float = float(step) / float(sectors_per_arm - 1) if sectors_per_arm > 1 else 0.5
			var base_radius: float = lerpf(min_radius, max_radius, t)
			var arm_width: float = lerpf(arm_width_inner, arm_width_outer, t)
			var base_angle: float = arm_base_angle + total_turns * TAU * t
			
			var wave_a: float = sin(t * TAU * 1.2 + wave_phase_a) * 0.6
			var wave_b: float = sin(t * TAU * 2.8 + wave_phase_b) * 0.3
			var wave_c: float = sin(t * TAU * 5.5 + wave_phase_c) * 0.15
			var angle_offset: float = (wave_a + wave_b + wave_c) * arm_waviness * wave_strength
			var final_angle: float = base_angle + angle_offset
			
			var radial_dir: Vector2 = Vector2(cos(final_angle), sin(final_angle))
			var tangent_dir: Vector2 = Vector2(-radial_dir.y, radial_dir.x)
			
			# Влияние скоплений
			var side_pull: float = 0.0
			var radial_pull: float = 0.0
			var width_boost: float = 0.0
			for ci in range(clump_count):
				var delta_t: float = t - clump_t_values[ci]
				var sigma: float = 0.12
				var influence: float = exp(-(delta_t * delta_t) / (2.0 * sigma * sigma))
				influence *= clumpiness * clump_strength_values[ci]
				side_pull += clump_side_values[ci] * arm_width * 0.7 * influence
				radial_pull += clump_radial_values[ci] * sector_spacing_safe * 0.3 * influence
				width_boost += influence
			
			var side_noise: float = _rand_normal(rng) * arm_width * arm_zone_scatter
			var radial_noise: float = _rand_normal(rng) * radial_jitter_base * (0.5 + t)
			var long_noise: float = _rand_normal(rng) * sector_spacing_safe * 0.12
			var clump_scatter: float = minf(width_boost * 0.8, 1.2)
			side_noise += _rand_normal(rng) * arm_width * 0.4 * clump_scatter
			
			var final_radius: float = base_radius + radial_noise + radial_pull
			var sector_pos: Vector2 = radial_dir * final_radius
			sector_pos += tangent_dir * (side_noise + side_pull)
			sector_pos += tangent_dir * long_noise
			sector_pos.y *= squash_y
			
			var sector_id: String = "A%d_%d" % [arm + 1, step + 1]
			sectors.append({
				"id": sector_id,
				"position": {"x": sector_pos.x, "y": sector_pos.y}
			})
			
			# Генерация ответвлений (спор)
			var spur_chance: float = 0.12
			if sectors_per_arm <= 12:
				spur_chance = 0.18
			elif sectors_per_arm >= 28:
				spur_chance = 0.07
			if t > 0.25 and t < 0.85 and rng.randf() < spur_chance:
				var spur_length: int = rng.randi_range(1, 2)
				var spur_side: float = 1.0 if rng.randf() < 0.5 else -1.0
				var spur_parent: String = sector_id
				for spur_step in range(spur_length):
					var spur_t: float = float(spur_step + 1) * 0.5
					var spur_angle: float = final_angle + spur_side * 0.25 * spur_t
					var spur_radius: float = final_radius + sector_spacing_safe * 0.5 * spur_t
					var spur_dir: Vector2 = Vector2(cos(spur_angle), sin(spur_angle))
					var spur_tangent: Vector2 = Vector2(-spur_dir.y, spur_dir.x)
					var spur_pos: Vector2 = spur_dir * spur_radius
					spur_pos += spur_tangent * spur_side * arm_width * 1.2
					spur_pos += spur_tangent * _rand_normal(rng) * sector_spacing_safe * 0.2
					spur_pos.y *= squash_y
					var spur_id: String = "%s_S%d" % [sector_id, spur_step + 1]
					sectors.append({
						"id": spur_id,
						"position": {"x": spur_pos.x, "y": spur_pos.y}
					})
	
	# =========================
	# Пост-обработка: расталкивание слишком близких секторов
	# =========================
	if min_sector_distance > 0.0:
		_relax_sectors(sectors, min_sector_distance, 6)
	
	return {"sectors": sectors}


# Вспомогательная функция: нормальное распределение
static func _rand_normal(rng: RandomNumberGenerator) -> float:
	var sum: float = 0.0
	for i in range(12):
		sum += rng.randf()
	return (sum - 6.0) / 3.0


# Расталкивание секторов, чтобы соблюдалась минимальная дистанция
static func _relax_sectors(sectors: Array[Dictionary], min_dist: float, iterations: int = 6) -> void:
	if sectors.size() < 2:
		return
	
	# Центральное ядро не двигаем
	var fixed_indices: Array[int] = []
	for i in range(sectors.size()):
		if sectors[i]["id"] == "C0":
			fixed_indices.append(i)
			break
	
	# Копируем позиции
	var positions: Array[Vector2] = []
	for s in sectors:
		var pos: Vector2 = Vector2(s["position"]["x"], s["position"]["y"])
		positions.append(pos)
	
	var damping: float = 0.5  # чтобы не разлетались слишком сильно
	for _iter in range(iterations):
		var forces: Array[Vector2] = []
		forces.resize(sectors.size())
		for i in range(sectors.size()):
			forces[i] = Vector2.ZERO
		
		# Вычисляем силы отталкивания
		for i in range(sectors.size()):
			for j in range(i + 1, sectors.size()):
				var delta: Vector2 = positions[i] - positions[j]
				var dist: float = delta.length()
				if dist < min_dist and dist > 0.001:
					var overlap: float = min_dist - dist
					var dir: Vector2 = delta.normalized()
					var force: Vector2 = dir * overlap * 0.5  # делим силу между двумя
					forces[i] += force
					forces[j] -= force
		
		# Применяем силы
		for i in range(sectors.size()):
			if i in fixed_indices:
				continue
			var move: Vector2 = forces[i] * damping
			# Ограничиваем максимальное смещение, чтобы не вылететь за пределы
			if move.length() > min_dist * 0.5:
				move = move.normalized() * min_dist * 0.5
			positions[i] += move
		
		# Небольшое затухание на следующий шаг
		damping *= 0.85
	
	# Записываем обратно в словари
	for i in range(sectors.size()):
		sectors[i]["position"]["x"] = positions[i].x
		sectors[i]["position"]["y"] = positions[i].y
