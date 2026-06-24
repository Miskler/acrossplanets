extends Node2D


const PART_TIME: float = 0.2
const WAIT_TIME: float = 1

const START_BLOCK_TIME: float = 0.8
const END_BLOCK_TIME: float = 0.1

@onready var hand: TextureRect = $Hand
@onready var block: TextureRect = $Block
@onready var check: TextureRect = $Check

var current_tween: Tween


func anim(time: float) -> void:
	print(time)
	modulate.a = 0.0
	hand.modulate.a = 1.0
	block.modulate.a = 1.0
	check.modulate.a = 0.0
	
	current_tween = get_tree().create_tween()
	
	current_tween.tween_property(self, "modulate:a", 1.0, PART_TIME)
	
	# Крест мигает всё быстрее в течение time секунд
	var elapsed: float = 0.0
	
	var vsbl = true
	while elapsed < time:
		var progress: float = elapsed / time
		var blink_time: float = lerpf(START_BLOCK_TIME, END_BLOCK_TIME, progress)
		
		if elapsed + blink_time > time:
			blink_time = time - elapsed
		
		vsbl = !vsbl
		
		current_tween.tween_property(block, "modulate:a", float(vsbl), blink_time)\
			.set_trans(Tween.TRANS_LINEAR)\
			.set_ease(Tween.EASE_IN_OUT)
		
		elapsed += blink_time
	
	current_tween.tween_property(block, "modulate:a", 0.0, PART_TIME)
	current_tween.tween_property(check, "modulate:a", 1.0, PART_TIME)
	current_tween.tween_interval(WAIT_TIME)
	current_tween.tween_property(self, "modulate:a", 0.0, PART_TIME)
	
	await current_tween.finished
	queue_free()
