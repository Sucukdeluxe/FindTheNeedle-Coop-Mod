extends RefCounted
static var _cache := {}
static func texture(count: int) -> Texture2D:
	if not _cache.has(count):
		var image := Image.new()
		if image.load_svg_from_string(FileAccess.get_file_as_string("res://mods/multiplayer/receiver%d_icon.svg" % count)) != OK:
			return null
		image.generate_mipmaps()
		_cache[count] = ImageTexture.create_from_image(image)
	return _cache[count]
