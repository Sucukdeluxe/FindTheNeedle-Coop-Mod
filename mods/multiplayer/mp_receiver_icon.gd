extends RefCounted
static var _cache := {}
static func texture(count: int, distributor: bool = false) -> Texture2D:
	var key := str(count) + str(distributor)
	if _cache.has(key):return _cache[key]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><rect x="8" y="8" width="240" height="240" rx="24" fill="#162022"/>'
	for side in count:
		var output := side != count / 2 if distributor else side == 0
		svg += '<g transform="rotate(%s 128 128)"><path d="M104 120V22H152V120" fill="#35454a" stroke="#8b9797" stroke-width="4"/><path d="M116 %sL128 %sL140 %s" fill="none" stroke="%s" stroke-width="6"/></g>' % [str(side*360.0/count),"48" if output else "38","38" if output else "48","48" if output else "38","#e9c875" if output else "#e2ebe9"]
	svg += '<circle cx="128" cy="128" r="38" fill="#273237" stroke="#859494" stroke-width="5"/><text x="128" y="141" text-anchor="middle" font-family="sans-serif" font-weight="bold" font-size="36" fill="#e9c875">%d</text></svg>' % count
	var image := Image.new()
	if image.load_svg_from_string(svg) != OK:return null
	image.generate_mipmaps()
	_cache[key] = ImageTexture.create_from_image(image)
	return _cache[key]
