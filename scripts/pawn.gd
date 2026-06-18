extends Node2D

signal movement_finished
signal movement_action_required(step: Dictionary, next_step_index: int)

@onready var sprite_layer: AnimatedSprite2D = $Sprite

var move_speed_px: float = 80.0
var oxygen_consumption: float = 2.0
var point_reach_distance_px: float = 1.0

var race: String = "human"
var direction: String = "side" # side, top, down
var animation: String = "standing" # standing, moving

var selected: bool = false

var movement_tween: Tween = null


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
		_:
			push_error("Unknown race: "+str(new_race))

func set_animation(direct: String, anim: String) -> void:
	direction = direct
	animation = anim

	var animation_name: String = "%s_%s_%s" % [
		race,
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
