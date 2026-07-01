extends Control

@onready var starship = get_node("../../Starship")
@onready var services = get_node("Services")
@onready var services_box = services.get_node("Box")
const SERVICES_RIGHT_MARGIN := 8.0

func _ready() -> void:
	regen_services(starship.get_specialized_rooms_state())

func regen_services(data: Array[Dictionary]):
	for node in services_box.get_children():
		if node.name != "*Sample":
			node.queue_free()
	
	var sample = services_box.get_node("*Sample")
	sample.hide()
	var level_sample = sample.get_node("Energy/*Sample")
	level_sample.hide()
	for room_data in data:
		var new_room = sample.duplicate()
		new_room.name = room_data["specialization"]
		new_room.get_node("Icon").texture = load("res://assets/consoles/icons/"+room_data["specialization"]+".png")
		
		var energy_layer = new_room.get_node("Energy")
		for level in room_data["opened_max_level"]:
			var new_level = level_sample.duplicate()
			new_level.show()
			energy_layer.add_child(new_level)
		
		new_room.show()
		services_box.add_child(new_room)
	
	services.size.x = services_box.get_child_count() * sample.custom_minimum_size.x
	services.position.x = get_viewport_rect().size.x - services.size.x - SERVICES_RIGHT_MARGIN
