extends RefCounted
class_name NodeUUID


static func uuid_v4() -> String:
	var crypto: Crypto = Crypto.new()
	var bytes: PackedByteArray = crypto.generate_random_bytes(16)

	# UUID v4 bits
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80

	return "%s%s%s%s-%s%s-%s%s-%s%s-%s%s%s%s%s%s" % [
		_byte_to_hex(bytes[0]),
		_byte_to_hex(bytes[1]),
		_byte_to_hex(bytes[2]),
		_byte_to_hex(bytes[3]),
		_byte_to_hex(bytes[4]),
		_byte_to_hex(bytes[5]),
		_byte_to_hex(bytes[6]),
		_byte_to_hex(bytes[7]),
		_byte_to_hex(bytes[8]),
		_byte_to_hex(bytes[9]),
		_byte_to_hex(bytes[10]),
		_byte_to_hex(bytes[11]),
		_byte_to_hex(bytes[12]),
		_byte_to_hex(bytes[13]),
		_byte_to_hex(bytes[14]),
		_byte_to_hex(bytes[15])
	]


static func _byte_to_hex(value: int) -> String:
	return "%02x" % (value & 0xFF)
