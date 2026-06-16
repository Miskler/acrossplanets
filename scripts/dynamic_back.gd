extends Control

var planets = [
	preload("res://planets/Asteroids/Asteroid.tscn"),
	preload("res://planets/Asteroids/Asteroid.tscn"),
	preload("res://planets/BlackHole/BlackHole.tscn"),
	preload("res://planets/BlackHole/BlackHole.tscn"),
	preload("res://planets/Galaxy/Galaxy.tscn"),
	preload("res://planets/Star/Star.tscn"),
	preload("res://planets/Star/Star.tscn"),
	preload("res://planets/Star/Star.tscn"),
	preload("res://planets/Star/Star.tscn"),
	preload("res://planets/Star/Star.tscn"),
	preload("res://planets/Star/Star.tscn"),
]


func _ready() -> void:
	gen_back()

func gen_back():
	for child in get_children():
		child.queue_free()
	var rnd = RandomNumberGenerator.new()
	for i in range(30):
		var pos = Vector2(rnd.randf_range(0, size.x), rnd.randf_range(0, size.y))
		var plt = planets[rnd.randi_range(0, planets.size() - 1)].instantiate()
		add_child(plt)
		plt.position = pos
		plt.scale = Vector2.ONE * 0.2
		plt.rotation = rnd.randi_range(-180, 180)
		for child in plt.get_children():
			child.material = child.material.duplicate()
		plt.randomize_colors()
