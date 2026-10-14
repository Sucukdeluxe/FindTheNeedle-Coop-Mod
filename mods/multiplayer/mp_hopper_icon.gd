extends RefCounted

static var _texture: Texture2D

static func texture() -> Texture2D:
	if _texture != null:
		return _texture
	var image := Image.new()
	var svg := FileAccess.get_file_as_string("res://mods/multiplayer/hopper_icon.svg")
	if image.load_svg_from_string(svg) != OK:
		return null
	image.generate_mipmaps()
	_texture = ImageTexture.create_from_image(image)
	return _texture
