extends Node
class_name NameGenerator


const NAMES_DIR: String = "res://assets/names"

static var _cache: Dictionary = {}
static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
static var _rng_ready: bool = false


static func random(scope: String) -> String:
	if not _rng_ready:
		_rng.randomize()
		_rng_ready = true
	
	var lines: Array[String] = _get_scope_lines(scope)
	
	if lines.is_empty():
		return ""
	
	return lines[_rng.randi_range(0, lines.size() - 1)]


static func all(scope: String) -> Array[String]:
	return _get_scope_lines(scope).duplicate()


static func reload(scope: String) -> void:
	_cache.erase(scope)


static func reload_all() -> void:
	_cache.clear()


static func _get_scope_lines(scope: String) -> Array[String]:
	if _cache.has(scope):
		return _cache[scope]
	
	var path: String = "%s/%s.txt" % [NAMES_DIR, scope]
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	
	if file == null:
		push_error("NamePool: file not found: " + path)
		_cache[scope] = []
		return _cache[scope]
	
	var lines: Array[String] = []
	
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		
		if line.is_empty():
			continue
		
		if line.begins_with("#"):
			continue
		
		lines.append(line)
	
	_cache[scope] = lines
	return lines
