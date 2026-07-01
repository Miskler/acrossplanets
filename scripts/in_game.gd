extends Control

@onready var starship = get_node("../../Starship")
@onready var services = get_node("Services")
@onready var services_box = services.get_node("Box")
const SERVICES_RIGHT_MARGIN := 8.0

const ACTIVE_COLOR: Color = Color.WHITE
const NON_ACTIVE_COLOR: Color = Color.DARK_GRAY
const BROKEN_COLOR: Color = Color("ff0000")

func _ready() -> void:
	regen_services(starship.get_specialized_rooms_state())

func _recalc_levels_state_service(node: VBoxContainer, energy: int, health: int, fortitude: float) -> void:
	var last_child_active = null
	var last_child_non_active = null
	var id = -1
	var children = node.get_children()
	children.reverse()
	for child in children:
		if child.name != "*Sample":
			id += 1
			child.get_node("Healing").value = 0
			child.get_node("Damage").value = 0
			
			child.get_node("Active").color = BROKEN_COLOR if id >= health else (NON_ACTIVE_COLOR if id >= energy else ACTIVE_COLOR)
			if id < health:
				last_child_active = child
			elif last_child_non_active == null:
				last_child_non_active = child
	
	if fortitude != 100:
		if fortitude < 100 and last_child_active != null:
			last_child_active.get_node("Damage").value = 100 - fortitude
		elif last_child_non_active != null:
			last_child_non_active.get_node("Healing").value = fortitude - 100

func _regen_levels_service(node: VBoxContainer, opened_max_level: int) -> void:
	for child in node.get_children():
		if child.name != "*Sample":
			child.queue_free()
	
	var level_sample: Control = node.get_node("*Sample")
	for level in opened_max_level:
		var new_level = level_sample.duplicate()
		new_level.show()
		new_level.get_node("Healing").value = 0
		new_level.get_node("Damage").value = 0
		new_level.get_node("Active").color = NON_ACTIVE_COLOR
		node.add_child(new_level)

func regen_services(data: Array[Dictionary]):
	for node in services_box.get_children():
		if node.name != "*Sample":
			node.queue_free()
	
	starship.connect("specialized_room_state_changed", service_changed)
	
	var sample = services_box.get_node("*Sample")
	sample.hide()
	var level_sample = sample.get_node("Energy/*Sample")
	level_sample.hide()
	for room_data in data:
		var new_room = sample.duplicate()
		new_room.name = room_data["specialization"]
		new_room.get_node("Icon").texture = load("res://assets/consoles/icons/"+room_data["specialization"]+".png")
		
		print(room_data)
		var energy_node = new_room.get_node("Energy")
		_regen_levels_service(energy_node, room_data["opened_max_level"])
		_recalc_levels_state_service(energy_node, room_data["energy"], room_data["health"], room_data["fortitude"])
		
		new_room.set_meta("specialization", room_data["specialization"])
		new_room.set_meta("opened_max_level", room_data["opened_max_level"])
		new_room.set_meta("energy", room_data["energy"])
		
		new_room.connect("gui_input", service_pressed.bind(new_room))
		
		new_room.show()
		services_box.add_child(new_room)
	
	services.size.x = services_box.get_child_count() * sample.custom_minimum_size.x
	services.position.x = get_viewport_rect().size.x - services.size.x - SERVICES_RIGHT_MARGIN

func service_pressed(event: InputEvent, service_node: Control) -> void:
	if event is InputEventMouseButton and event.pressed:
		var to_add = event.button_index == MOUSE_BUTTON_LEFT
		
		var new_value = service_node.get_meta("energy") + (1 if to_add else -1)
		new_value = clamp(new_value, 0, service_node.get_meta("opened_max_level"))
		
		starship.set_specialized_room_energy(service_node.get_meta("specialization"), new_value)

func service_changed(
	specialization: String,
	health: float,
	fortitude: float,
	energy: int,
	opened_max_level: int
) -> void:
	var service_node: Control = get_node("Services/Box/"+specialization)
	
	var energy_node = service_node.get_node("Energy")
	if opened_max_level != service_node.get_meta("opened_max_level"):
		service_node.set_meta("opened_max_level", opened_max_level)
		_regen_levels_service(energy_node, opened_max_level)
	
	service_node.set_meta("energy", energy)
	_recalc_levels_state_service(energy_node, energy, health, fortitude)
