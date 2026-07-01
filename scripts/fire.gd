extends AnimatedSprite2D

signal fire_spreading(node: Node2D)
signal fire_out(node: Node2D)

@onready var timer = $Timer
var wait_time: float = 0.5

var time_scale: int = 1
var health_level: int = 2

var health_percent: float = 0
var maximum_percent: float = 1.5
var minimum_percent: float = -0.5

var extinguishing_fire: bool = false
var oxygen_consumption: float = 2.0

func _ready() -> void:
	timer.wait_time = wait_time / time_scale

func set_time_scale(new_scale: int):
	new_scale = clamp(new_scale, 1, 10)
	if time_scale != new_scale:
		time_scale = new_scale
		timer.wait_time = wait_time / time_scale
		timer.start()

var inited: bool = false
func set_health(new_health: int):
	if health_level == new_health:
		if inited:
			push_warning("This level has already been set")
			return
		else: inited = true
	health_level = new_health
	health_percent = 0
	if health_level < 1:
		queue_free()
	elif health_level > 3:
		push_error("Unsupported fire level")
	play(str(health_level))
	offset.y = 0 if health_level == 1 else -8
	match health_level:
		1:
			oxygen_consumption = 10
		2:
			oxygen_consumption = 20
		3:
			oxygen_consumption = 30

func extinguish_fire(yes: bool):
	if extinguishing_fire != yes:
		extinguishing_fire = yes
		timer.start()

func oxygen_starvation():
	emit_signal("fire_out", self)
	queue_free()


func _on_timer_timeout() -> void:
	if not extinguishing_fire:
		health_percent += 0.1
		if health_percent >= maximum_percent:
			if health_level < 3:
				set_health(health_level+1)
			else:
				health_percent = 0
				emit_signal("fire_spreading", self)
	else:
		health_percent -= 0.1
		if health_percent <= minimum_percent:
			if health_level > 1:
				set_health(health_level-1)
			else:
				emit_signal("fire_out", self)
				queue_free()
