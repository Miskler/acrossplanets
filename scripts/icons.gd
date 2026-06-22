extends Node2D

signal restart_finish

var icons_main_colors: Dictionary = {
	"cameras": "#F87EB8",
	"captains_bridge": "#357340",
	"doors": "#65399B",
	"drones": "#FE7C06",
	"engines": "#FEC505",
	"guns": "#FFFFFE",
	"medicine": "#00C4E4",
	"mind_control": "#FD5A65",
	"shields": "#084FF3",
	"oxygen": "#FCB485",
	"teleport": "#E7C7FB"
}

func _ready() -> void:
	get_parent().connect("restart_finish", restart_postprocess)

func restart_postprocess():
	setup_icons(get_parent().foundation_layer, get_parent().rooms)
	emit_signal("restart_finish")

func setup_icons(foundation_layer: TileMapLayer, rooms):
	for child in self.get_children():
		child.queue_free()
	var tile_size: Vector2 = Vector2(foundation_layer.tile_set.tile_size)
	var icon_size: Vector2 = tile_size * 3
	for room in rooms:
		add_room_kind_icon(
			room,
			foundation_layer,
			self,
			icon_size
		)

static func add_room_kind_icon(
	room: Dictionary,
	room_polygon_space: CanvasItem,
	target_parent: CanvasItem,
	icon_size: Vector2,
	icon_dir: String = "res://assets/consoles/icons/",
) -> TextureRect:
	if room_polygon_space == null:
		push_warning("room_polygon_space is null")
		return null

	if target_parent == null:
		push_warning("target_parent is null")
		return null

	var kind: Variant = room.get("kind", null)
	var kind_string: String = str(kind)
	var icon_path: String = icon_dir.path_join(kind_string + ".png")

	if not ResourceLoader.exists(icon_path):
		push_warning("Icon not found: " + icon_path)
		return null

	var texture: Texture2D = load(icon_path) as Texture2D

	if texture == null:
		push_warning("Failed to load icon: " + icon_path)
		return null

	var polygons: Array = room.get("polygons", [])
	var room_center_local: Vector2 = _get_room_polygons_center(polygons)
	var room_center_global: Vector2 = room_polygon_space.to_global(room_center_local)
	var icon_center_position: Vector2 = target_parent.to_local(room_center_global)

	var icon: TextureRect = TextureRect.new()
	icon.name = "RoomIcon_%s" % [
		str(room.get("room_id", -1))
	]

	# Центрируем TextureRect относительно центра комнаты.
	icon.position = icon_center_position - icon_size * 0.5

	# Godot 4 TextureRect.
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Фиксированный размер.
	icon.size = icon_size
	
	icon.texture = texture

	target_parent.add_child(icon)

	return icon

static func _get_room_polygons_center(polygons: Array) -> Vector2:
	var has_point: bool = false
	var min_point: Vector2 = Vector2.ZERO
	var max_point: Vector2 = Vector2.ZERO

	for polygon_variant: Variant in polygons:
		if typeof(polygon_variant) != TYPE_PACKED_VECTOR2_ARRAY:
			continue

		var polygon: PackedVector2Array = polygon_variant

		for point: Vector2 in polygon:
			if not has_point:
				has_point = true
				min_point = point
				max_point = point
			else:
				min_point.x = minf(min_point.x, point.x)
				min_point.y = minf(min_point.y, point.y)
				max_point.x = maxf(max_point.x, point.x)
				max_point.y = maxf(max_point.y, point.y)

	if not has_point:
		return Vector2.ZERO

	return min_point + (max_point - min_point) * 0.5
