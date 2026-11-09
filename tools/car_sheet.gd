## Planche de toutes les carrosseries, pour relire le rendu des voitures :
##   godot --headless --path . -s tools/car_sheet.gd -- sortie.png [échelle] [locked]
extends SceneTree

const CarRenderer = preload("res://scripts/car_renderer.gd")
const COLORS := ["c8202a", "2f6fd1", "e07a1f", "f2efe8", "3d8c4a", "6a6d75", "d9b44a", "7a2a8a"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "car_sheet.png"
	var scale := float(args[1]) if args.size() > 1 else 2.0
	var locked := args.size() > 2 and args[2] == "locked"
	var tiles: Array[Image] = []
	var tw := 0
	var th := 0
	var i := 0
	for body in CarRenderer.BODIES:
		var r := CarRenderer.render(body, Color(COLORS[i % COLORS.size()]), i % 4, scale, locked)
		var img: Image = r["image"]
		tiles.append(img)
		tw = maxi(tw, img.get_width())
		th = maxi(th, img.get_height())
		i += 1
	var cols := 4
	var rows := int(ceil(tiles.size() / float(cols)))
	var sheet := Image.create(tw * cols + 4 * (cols + 1), th * rows + 4 * (rows + 1), false, Image.FORMAT_RGBA8)
	sheet.fill(Color("1a191e"))
	for k in tiles.size():
		var img := tiles[k]
		var cell := Vector2i(4 + (k % cols) * (tw + 4), 4 + (k / cols) * (th + 4))
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), cell + Vector2i((tw - img.get_width()) / 2, th - img.get_height()))
	sheet.save_png(path)
	print("ok ", sheet.get_size())
	quit()
