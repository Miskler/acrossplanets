extends Node2D

signal movement_finished
signal movement_action_required(step: Dictionary, next_step_index: int)
signal dead

@onready var sprite_layer: AnimatedSprite2D = $Sprite
@onready var health_bar: ProgressBar = $HealthBar

var animations: Dictionary = {
	"human": preload("res://assets/races/human.tres")
}

var min_oxygen: int = 1
var max_oxygen: int = 100

var max_health: int = 100
var health: int = 100
var no_oxygen_damage_factor: float = 1
var fire_room_damage_factor: float = 1
var battle_damage_factor: float = 1

var impact_engineering: int = 3 # заплатка пробоин, ремонт станций и их саботаж
var impact_force: int = 3 # сила удара вблизи
var impact_force_remotely: int = 3 # сила удара вдали
var move_speed_px: float = 80.0 # скорость передвижения
var oxygen_consumption: float = 2.0 # потребления кислорода (можно поставить выработку если <0)
var point_reach_distance_px: float = 1.0

# Логика следующая:
# starship определяет какому кораблю пренадлежит пешка
# только ИИ / юзер данного корабля может управлять пешкой
var starship: String = ""
# временный переход пешки под управление другого корабля (ии или игрока)
var temporary_management_starship: String = ""

var pawn_name: String = "!!NONAME!!"
var race: String = "human"
var direction: String = "side" # side, top, down
var animation: String = "standing" # standing, moving

var selected: bool = false

var movement_tween: Tween = null

func control_is_available(target_starship: String) -> bool:
	return target_starship == get_current_starship()

func get_current_starship() -> String:
	if not temporary_management_starship.is_empty():
		return temporary_management_starship
	return starship

func damage(value: int) -> void:
	set_health(health-value)

func healing(value: int) -> void:
	set_health(clamp(health+value, 0, max_health))

func set_health(value: int) -> void:
	health = value
	health_bar.value = value
	if health <= 0:
		emit_signal("dead")
		queue_free()

func set_selected(new_selected: bool) -> void:
	selected = new_selected
	if selected:
		modulate = Color.RED
	else:
		modulate = Color.WHITE

func set_race(new_race: String):
	match new_race:
		"human":
			move_speed_px = 80
			oxygen_consumption = 20
			
			impact_engineering = 3
			impact_force = 3
			impact_force_remotely = 2
			
			max_health = 100
			min_oxygen = 1
			max_oxygen = 100
			no_oxygen_damage_factor = 1
			fire_room_damage_factor = 1
			battle_damage_factor = 1
		_:
			push_error("Unknown race: "+str(new_race))
	health_bar.max_value = max_health
	sprite_layer.sprite_frames = animations[new_race]

func set_animation(direct: String, anim: String) -> void:
	direction = direct
	animation = anim

	var animation_name: String = "%s_%s" % [
		direct,
		anim
	]

	if sprite_layer.sprite_frames != null and sprite_layer.sprite_frames.has_animation(animation_name):
		sprite_layer.animation = animation_name
		sprite_layer.play()
	else:
		push_warning("Animation not found: " + animation_name)

func move_by_steps_until_action(steps: Array, start_index: int = 0) -> void:
	stop_movement(false)
	
	if start_index >= steps.size():
		set_animation(direction, "standing")
		movement_finished.emit()
		return
	
	movement_tween = create_tween()
	movement_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	
	var current_position: Vector2 = global_position
	var has_segments: bool = false
	
	set_animation(direction, "moving")
	
	var i: int = start_index
	
	while i < steps.size():
		var step: Dictionary = steps[i]
		var target_position: Vector2 = step["point"]
		var action: String = str(step.get("action", "move"))
		
		var distance: float = current_position.distance_to(target_position)
		
		if distance > point_reach_distance_px:
			var move_vector: Vector2 = target_position - current_position
			var duration: float = distance / move_speed_px
			
			movement_tween.tween_callback(
				Callable(self, "update_direction_by_vector").bind(move_vector)
			)
			
			movement_tween.tween_property(
				self,
				"global_position",
				target_position,
				duration
			).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
			
			current_position = target_position
			has_segments = true
		
		if _is_ship_action(action):
			movement_tween.tween_callback(
				Callable(self, "_on_movement_action_reached").bind(step, i + 1)
			)
			return
		
		i += 1
	
	if has_segments:
		movement_tween.tween_callback(
			Callable(self, "_on_movement_tween_finished")
		)
	else:
		movement_tween.kill()
		movement_tween = null
		set_animation(direction, "standing")
		movement_finished.emit()

func _is_ship_action(action: String) -> bool:
	return action == "open_door" or action == "close_door"

func _on_movement_action_reached(step: Dictionary, next_step_index: int) -> void:
	movement_tween = null
	set_animation(direction, "standing")
	movement_action_required.emit(step, next_step_index)

func stop_movement(emit_finished: bool) -> void:
	if movement_tween != null:
		if movement_tween.is_valid():
			movement_tween.kill()

		movement_tween = null

	set_animation(direction, "standing")

	if emit_finished:
		movement_finished.emit()

func _on_movement_tween_finished() -> void:
	movement_tween = null
	set_animation(direction, "standing")
	movement_finished.emit()

func update_direction_by_vector(move_vector: Vector2) -> void:
	if move_vector.length() <= 0.001:
		return

	if absf(move_vector.x) > absf(move_vector.y):
		direction = "side"

		if move_vector.x < 0.0:
			sprite_layer.flip_h = true
		else:
			sprite_layer.flip_h = false

		set_animation(direction, animation)
		return

	sprite_layer.flip_h = false

	if move_vector.y < 0.0:
		direction = "top"
	else:
		direction = "down"

	set_animation(direction, "moving")


# геттеры (тут происходит подсчет фактических значений с учетом навыков)

func get_impact_engineering() -> int:
	return impact_engineering

func get_impact_force() -> int:
	return impact_force

func get_impact_force_remotely() -> int:
	return impact_force_remotely

func get_move_speed_px() -> float:
	return move_speed_px

func get_oxygen_consumption() -> float:
	return oxygen_consumption

func get_no_oxygen_damage_factor() -> float:
	return no_oxygen_damage_factor

func get_fire_room_damage_factor() -> float:
	return fire_room_damage_factor

func get_battle_damage_factor() -> float:
	return battle_damage_factor
