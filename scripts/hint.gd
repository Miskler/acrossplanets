extends Control

@onready var room_layer = $Room
@onready var door_layer = $Door
@onready var pawn_layer = $Pawn

const GRID_STEP: float = 30
const GRID_MAX_IN_ROW: int = 2

const SPECIALIZATIONS: Dictionary = {
	"cameras": "Видеобудка",
	"captains_bridge": "Капитанский мостик",
	"doors": "Дверной контроллер",
	"drones": "Дрон-отсек",
	"engines": "Машинное отделение",
	"guns": "Оружейная",
	"medicine": "Мед. отсек",
	"mind_control": "Контроллер разума",
	"shields": "Генератор щита",
	"oxygen": "Генератор кислорода",
	"teleport": "Телепорт"
}

const TASKS: Dictionary = {
	"battle": "бъётся",
	"goto": "идёт",
	"station": "работает",
	"fire": "тушит",
	"hull_repair": "латает пробоину",
	"room_repair": "восстанавливает станцию",
	"room_destroy": "саботирует",
	"idle": "стоит",
	"door_destroy": "выбивает дверь"
}


func calc_grid_offset(elements: int) -> float:
	var rows: int = ceili(float(elements) / float(GRID_MAX_IN_ROW))
	return float(rows) * GRID_STEP - GRID_STEP

func render_in_grid(data: Dictionary, type_key: String, type_suffix: String, base_path: String, label_prefix: String, label_suffix: String) -> Array[int]:
	var total = 0
	var to_show = 0
	for key: String in data[type_key].keys():
		var value: int = int(data[type_key][key])
		total += value
		var node = get_node_or_null(base_path+key.to_upper()+"_"+type_suffix.to_lower())
		if node == null:
			push_error("Node for parameter `"+key.to_upper()+"` with `"+type_suffix.to_lower()+"` (`"+str(type_key)+"`) not found")
		else:
			node.get_node("Control/Label").text = label_prefix+str(value)+label_suffix
			node.visible = value != 0
			if value != 0:
				to_show += 1
	return [total, to_show]

func render(data: Dictionary) -> void:
	visible = data.get("type") != null
	room_layer.visible = data.get("type") == "room"
	door_layer.visible = data.get("type") == "door"
	pawn_layer.visible = data.get("type") == "pawn"
	
	match data.get("type"):
		null:
			pass
		"room":
			$Title.text = SPECIALIZATIONS.get(data["info"]["specialization"], "Комната")
			
			if data["info"]["hidden"]:
				$Room/Grid/Header/Label.text = "??% * "+str(int(data["info"]["air_capacity"]/100))+"m²"
				$Room/RightBox/Cracks/Label.text = "??"
				$Room/RightBox/Cracks/Healing.value = 0
				$Room/RightBox/Fire/Label.text = "??"
				$Room/RightBox/Fire/Healing.value = 0
			else:
				$Room/Grid/Header/Label.text = str(int(data["info"]["oxygen"]))+"% * "+str(int(data["info"]["air_capacity"]/100))+"m²"
				$Room/RightBox/Cracks/Label.text = str(data["info"]["holes"])
				$Room/RightBox/Cracks/Healing.value = data["info"]["hull_repair_progress"]
				$Room/RightBox/Fire/Label.text = str(data["info"]["fires"])
				$Room/RightBox/Fire/Healing.value = data["info"]["fire_progress"]
			
			$Room/RightBox/Energy/Label.text = str(data["info"]["health"]["energy"])+"|"+str(data["info"]["health"]["current"])
			$Room/RightBox/Heart/Label.text = str(data["info"]["health"]["current"])+"|"+str(data["info"]["health"]["maximum"])
			
			var healing = $Room/RightBox/Heart/Healing
			var damage = $Room/RightBox/Heart/Damage
			if data["info"]["health"]["fortress"] > 100:
				healing.value = data["info"]["health"]["fortress"] - 100
				damage.value = 0
			else:
				healing.value = 0
				damage.value = 100 - data["info"]["health"]["fortress"]
			
			var total_plus = render_in_grid(data["info"]["oxygen_balance"], "income", "income", "Room/Grid/GridContainer/", "+", "%")
			var total_minus = render_in_grid(data["info"]["oxygen_balance"], "loss", "loss", "Room/Grid/GridContainer/", "-", "%")
			if data["info"]["hidden"]:
				$Room/Grid/Total.text = "-?% +?% = ?%/сек"
			else:
				var total = -total_minus[0]+total_plus[0]
				$Room/Grid/Total.text = "-"+str(total_minus[0])+"%+"+str(total_plus[0])+"%="+("+" if total > 0 else "")+str(total)+"%/сек"
			
			size = Vector2(210, 174)
			size.y = max(calc_grid_offset(total_plus[1] + total_minus[1])+size.y, size.y)
		"door":
			var to_title = ""
			if data["info"]["broken"]:
				to_title = "Выломанная"
			elif data["info"]["open"]:
				to_title = "Открытая"
			else:
				to_title = "Закрытая"
			$Title.text = to_title+" дверь"
			print(data["info"])
			if data["info"]["level"] == -1:
				$Title.text = $Title.text + " (обесточено)"
			
			$Door/Level/Label.text = str(data["info"]["level"]+1)
			
			$Door/Heart/Label.text = "OK" if not data["info"]["broken"] else str(int(data["info"]["cooldown"]))+" сек"
			$Door/Heart/Damage.value = 100 if data["info"]["broken"] else (100 - data["info"]["fortress"])
			
			size = Vector2(274, 66)
		"pawn":
			$Title.text = data["info"]["pawn_name"]+" "+TASKS.get(data["info"]["current_task"].to_lower(), data["info"]["current_task"])
			$Pawn/Header/Label.text = str(data["info"]["health"])+"%"
			
			var total_plus = render_in_grid(data["info"]["health_balance"], "income", "income", "Pawn/GridContainer/", "+", "%")
			var total_minus = render_in_grid(data["info"]["health_balance"], "loss", "loss", "Pawn/GridContainer/", "-", "%")
			var total = -total_minus[0]+total_plus[0]
			$Pawn/Total.text = "-"+str(total_minus[0])+"%+"+str(total_plus[0])+"%="+("+" if total > 0 else "")+str(total)+"%/сек"
			
			size = Vector2(204, 118)
			size.y += calc_grid_offset(total_plus[1] + total_minus[1])
		_:
			push_warning("Unknown type for render hint: "+str(data.get("type")))
