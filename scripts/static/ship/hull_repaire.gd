extends Node
class_name HullRepairLogic

const HOLE_LEVEL_TO_ATLAS: Dictionary = {
	1: Vector2i(4, 1),
	2: Vector2i(4, 2),
	3: Vector2i(4, 3)
}


static func collect_hull_holes(foundation_layer: TileMapLayer) -> Dictionary:
	var result: Dictionary = {}

	for cell: Vector2i in foundation_layer.get_used_cells():
		var atlas_coords: Vector2i = foundation_layer.get_cell_atlas_coords(cell)

		for level: int in HOLE_LEVEL_TO_ATLAS.keys():
			if atlas_coords == HOLE_LEVEL_TO_ATLAS[level]:
				result[cell] = level
				break

	return result


static func process_hull_repair(
	foundation_layer: TileMapLayer,
	hull_holes: Dictionary,
	hull_repair_progress: Dictionary,
	workers_by_cell: Dictionary,
	delta: float,
	seconds_per_step: float
) -> Array[Vector2i]:
	var finished_cells: Array[Vector2i] = []

	for cell: Vector2i in workers_by_cell.keys():
		if not hull_holes.has(cell):
			continue

		var workers: int = int(workers_by_cell[cell])

		if workers <= 0:
			continue

		if not hull_repair_progress.has(cell):
			hull_repair_progress[cell] = 0.0

		hull_repair_progress[cell] += delta * float(workers)

		while hull_holes.has(cell) and hull_repair_progress.has(cell) and hull_repair_progress[cell] >= seconds_per_step:
			hull_repair_progress[cell] -= seconds_per_step

			var new_level: int = int(hull_holes[cell]) + 1

			if new_level <= 3:
				hull_holes[cell] = new_level
				set_hole_level(foundation_layer, cell, new_level)
			else:
				hull_holes.erase(cell)
				hull_repair_progress.erase(cell)
				set_first_tile_with_state(foundation_layer, cell, "floor")
				finished_cells.append(cell)
				break

	return finished_cells


static func set_hole_level(
	foundation_layer: TileMapLayer,
	cell: Vector2i,
	level: int
) -> void:
	var atlas_coords: Vector2i = HOLE_LEVEL_TO_ATLAS[level]
	var source_id: int = foundation_layer.get_cell_source_id(cell)
	var alternative_tile: int = foundation_layer.get_cell_alternative_tile(cell)

	if source_id < 0:
		source_id = find_source_with_atlas_coords(foundation_layer, atlas_coords)

	foundation_layer.set_cell(
		cell,
		source_id,
		atlas_coords,
		alternative_tile
	)


static func set_first_tile_with_state(
	foundation_layer: TileMapLayer,
	cell: Vector2i,
	state: String
) -> void:
	var tile_set: TileSet = foundation_layer.tile_set

	for source_index: int in range(tile_set.get_source_count()):
		var source_id: int = tile_set.get_source_id(source_index)
		var source: TileSetSource = tile_set.get_source(source_id)

		if not source is TileSetAtlasSource:
			continue

		var atlas_source: TileSetAtlasSource = source

		for tile_index: int in range(atlas_source.get_tiles_count()):
			var atlas_coords: Vector2i = atlas_source.get_tile_id(tile_index)

			for alt_index: int in range(atlas_source.get_alternative_tiles_count(atlas_coords)):
				var alternative_tile: int = atlas_source.get_alternative_tile_id(
					atlas_coords,
					alt_index
				)

				var tile_data: TileData = atlas_source.get_tile_data(
					atlas_coords,
					alternative_tile
				)

				if String(tile_data.get_custom_data("state")) != state:
					continue

				foundation_layer.set_cell(
					cell,
					source_id,
					atlas_coords,
					alternative_tile
				)
				return


static func find_source_with_atlas_coords(
	foundation_layer: TileMapLayer,
	atlas_coords: Vector2i
) -> int:
	var tile_set: TileSet = foundation_layer.tile_set

	for source_index: int in range(tile_set.get_source_count()):
		var source_id: int = tile_set.get_source_id(source_index)
		var source: TileSetSource = tile_set.get_source(source_id)

		if not source is TileSetAtlasSource:
			continue

		var atlas_source: TileSetAtlasSource = source

		if atlas_source.has_tile(atlas_coords):
			return source_id

	return 0
