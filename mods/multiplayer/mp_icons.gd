extends RefCounted

static var _textures := {}

static func building(id: String) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	var path := "res://mods/multiplayer/icons/" + id + ".png"
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_textures[id] = texture
	return texture

static func upgrade(id: String) -> Texture2D:
	var key := "upgrade:" + id
	if _textures.has(key):
		return _textures[key]
	var tile := TechTree.icon_of(id)
	var native := TechPanel.icon_for(tile)
	if native != null and not id.begins_with("mp_receiver") and not id.begins_with("mp_splitter"):
		return native
	var base: Texture2D
	if id.begins_with("mp_receiver") or id.begins_with("mp_splitter"):
		base = building(id)
	elif id == "mp_sale_scales":
		base = building("mp_sale_scale")
	else:
		base = TechPanel.icon_for(tile.get_slice("+", 0))
		if base == null and tile.begins_with("belt_loaded"):
			base = TechPanel.icon_for("belt")
	if base == null:
		return null
	var image := base.get_image()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	var suffix := tile.get_slice("+", 1)
	if not suffix.is_empty() or id == "mp_sale_scales":
		var badge := TechPanel.icon_for("yard_vac+speed" if suffix == "speed" else "yard_vac+more").get_image()
		badge.convert(Image.FORMAT_RGBA8)
		badge.resize(256, 256, Image.INTERPOLATE_LANCZOS)
		for y in range(148, 256):
			for x in range(148, 256):
				if Vector2(x - 201, y - 201).length_squared() <= 52.0 * 52.0:
					image.set_pixel(x, y, badge.get_pixel(x, y))
	image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(image)
	_textures[key] = texture
	return texture
