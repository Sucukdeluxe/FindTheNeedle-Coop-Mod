extends RefCounted

static var _texture: Texture2D

static func texture() -> Texture2D:
	if _texture != null:
		return _texture
	var image := Image.new()
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128"><path d="M58 42h12v44H58z" fill="#9aabba"/><rect x="36" y="10" width="56" height="45" rx="8" fill="#344753" stroke="#cad6dc" stroke-width="4"/><path d="M45 40a20 20 0 0 1 38 0" fill="none" stroke="#efedcf" stroke-width="3"/><path d="M64 39l12-17" stroke="#e9a345" stroke-width="4"/><rect x="17" y="81" width="94" height="20" rx="5" fill="#b4c4c9" stroke="#364c58" stroke-width="4"/><path d="M27 101v13h74v-13" fill="#536c78" stroke="#d4dfe1" stroke-width="4"/></svg>'
	if image.load_svg_from_string(svg) != OK:
		return null
	image.generate_mipmaps()
	_texture = ImageTexture.create_from_image(image)
	return _texture
