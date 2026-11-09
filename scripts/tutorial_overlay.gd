## Tutoriel guidé : un doigt en pixel art montre l'élément à toucher,
## une bulle explique. Les touches passent au travers, sauf le bouton OK.
extends Control

const Palette = preload("res://scripts/palette.gd")

signal ok_pressed

## Doigt pointé vers le bas ; # contour, w peau, s ombre.
const HAND: Array[String] = [
	"..#####..",
	".#wwwww#.",
	"#wwwwwws#",
	"#wwwwwws#",
	"#wsws#ws#",
	".#wwwww#.",
	"..#wws#..",
	"..#wws#..",
	"..#wws#..",
	"..#wws#..",
	"...##....",
]
const SKIN := Color("f3d2b0")
const SHADE := Color("c9a07e")
const INK := Color("1a1210")

var target: Control
var _bubble: PanelContainer
var _label: Label
var _ok: Button
var _time := 0.0
var _finger := Vector2.ZERO
var _point_up := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble = PanelContainer.new()
	var sb := Palette.bevel(Color("26221d"), Palette.ORANGE, 2)
	sb.set_border_width_all(2)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	_bubble.add_theme_stylebox_override("panel", sb)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(vb)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(220, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_label)
	_ok = Button.new()
	_ok.text = "OK"
	_ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ok.custom_minimum_size = Vector2(80, 0)
	Palette.style_button(_ok, Palette.ORANGE_DARK)
	_ok.pressed.connect(func() -> void: ok_pressed.emit())
	vb.add_child(_ok)
	add_child(_bubble)
	hide()


func show_step(new_target: Control, text: String, with_ok: bool) -> void:
	target = new_target
	_label.text = text
	_ok.visible = with_ok
	_bubble.reset_size()
	show()


func _process(delta: float) -> void:
	if not visible or target == null or not is_instance_valid(target):
		return
	_time += delta
	var r := target.get_global_rect()
	var local := Rect2(r.position - global_position, r.size)
	var bob := sin(_time * 6.0) * 4.0
	var hand_h := HAND.size() * 3.0
	_point_up = local.position.y < hand_h + 20.0
	if _point_up:
		_finger = Vector2(local.get_center().x, local.end.y + 4.0 - bob)
	else:
		_finger = Vector2(local.get_center().x, local.position.y + local.size.y * 0.35 - hand_h + bob)
	var bs := _bubble.get_combined_minimum_size()
	_bubble.size = bs
	var bx := clampf(local.get_center().x - bs.x * 0.5, 8.0, size.x - bs.x - 8.0)
	var by: float
	if local.get_center().y > size.y * 0.5:
		by = minf(local.position.y, _finger.y) - bs.y - 8.0
	else:
		by = maxf(local.end.y, _finger.y + hand_h) + 8.0
	_bubble.position = Vector2(bx, clampf(by, 8.0, size.y - bs.y - 8.0))
	queue_redraw()


func _draw() -> void:
	if target == null:
		return
	var px := 3.0
	var w := HAND[0].length() * px
	for row in HAND.size():
		var line: String = HAND[row]
		var ry := HAND.size() - 1 - row if _point_up else row
		for col in line.length():
			var ch := line[col]
			if ch == ".":
				continue
			var c := INK if ch == "#" else (SHADE if ch == "s" else SKIN)
			draw_rect(Rect2(_finger.x - w * 0.5 + col * px, _finger.y + ry * px, px, px), c)
