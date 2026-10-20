extends RefCounted

var _cache := {}

func names(shader: Shader) -> PackedStringArray:
	if shader == null:
		return PackedStringArray()
	if _cache.has(shader):
		return _cache[shader]
	var result := PackedStringArray()
	for uniform in shader.get_shader_uniform_list():
		if int(uniform.get("type", -1)) == TYPE_FLOAT:
			result.append(String(uniform.get("name", "")))
	_cache[shader] = result
	return result

func clear() -> void:
	_cache.clear()
