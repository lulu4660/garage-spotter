## Planche de toutes les carrosseries, pour relire le rendu des voitures :
##   godot --headless --path . -s tools/car_sheet.gd -- sortie.png [échelle]
extends SceneTree

const CarRenderer = preload("res://scripts/car_renderer.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "car_sheet.png"
	var scale := float(args[1]) if args.size() > 1 else 2.5
	var rows := [["citadine", "2f6fd1", 0], ["compacte", "e07a1f", 1], ["berline", "f2efe8", 0], ["coupe", "c8202a", 2], ["supercar", "6fbf3f", 3], ["supercar", "4a4d55", 4]]
	var tiles: Array[Image] = []
	var tw := 0
	var th := 0
	for row in rows:
		var r := CarRenderer.render(row[0], Color(row[1]), row[2], scale)
		var img: Image = r["image"]
		tiles.append(img)
		tw = maxi(tw, img.get_width())
		th = maxi(th, img.get_height())
	var sheet := Image.create(tw * 2 + 12, th * 3 + 16, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("2a2930"))
	for i in tiles.size():
		var img := tiles[i]
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(4 + (i % 2) * (tw + 4), 4 + (i / 2) * (th + 4)))
	sheet.save_png(path)
	print("ok ", sheet.get_size())
	quit()
