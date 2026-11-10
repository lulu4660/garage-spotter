## Rend une carrosserie sur fond blanc, pour guider la génération (angle et couleur) :
##   godot --headless --path . -s tools/ai/render_subject.gd -- <carrosserie> <couleur hex> <sortie.png>
extends SceneTree

const CarRenderer = preload("res://scripts/car_renderer.gd")


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var r := CarRenderer.render(a[0], Color(a[1]), 0, 3.0)
	var img: Image = r["image"]
	var bg := Image.create(img.get_width() + 40, img.get_height() + 40, false, Image.FORMAT_RGBA8)
	bg.fill(Color.WHITE)
	bg.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(20, 20))
	bg.save_png(a[2])
	quit()
