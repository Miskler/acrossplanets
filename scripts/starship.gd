extends Node2D
class_name Starship

@onready var foundation_layer = $Foundation
@onready var stations_layer = $Stations
@onready var technical_layer = $Technical
const SAMPLES_PER_TILE: int = 1

var rooms: Array[Dictionary] = []

func _ready() -> void:
	rooms = recalc_rooms()
	#technical_layer.hide()
	#print(rooms)

func recalc_rooms() -> Array[Dictionary]:
	var rooms_data: Dictionary = ShipRooms.validate(foundation_layer, SAMPLES_PER_TILE)
	
	var floor_data: Dictionary = ShipRoomFloors.validate(
		foundation_layer,
		technical_layer,
		rooms_data["rooms"],
		[stations_layer]
	)
	
	for id in range(floor_data["rooms"].size()):
		rooms_data["rooms"][id].merge(floor_data["rooms"][id])
	
	return rooms_data["rooms"]

func setup_icons():
	pass
