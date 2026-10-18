extends Control
## 戦闘画面に並べる、持っている護符 1 つの印。護符ごとの絵は作らず、蝋燭の橙の縁の丸い札に護符の漢字 1 字
## (scripts/relics.gd の glyph) を書いて見分ける。マウスを載せると hovered を出し (戦闘画面が説明を出す)、
## 護符が働いた時は flash() で光って膨らむ (長さと強さは scripts/art.gd)。

## マウスを載せた (relic_id の説明を出す合図) / 外した
signal hovered(relic_id: String)
signal unhovered

const Art := preload("res://scripts/art.gd")
const Relics := preload("res://scripts/relics.gd")

## 印の大きさと、漢字の文字の大きさ・丸い札の縁の太さ・札の地の色 (夜の藍より少し明るい焦げ茶)
const SIZE: Vector2 = Vector2(34, 34)
const GLYPH_FONT_SIZE: int = 20
const RING_WIDTH: float = 2.0
const FACE: Color = Color(0.16, 0.11, 0.08)

## 見せている護符の ID
var relic_id: String = ""
## 漢字 1 字のラベル
var glyph_label: Label = null
## 動いている発動の tween (次の発動の前に止める)
var flash_tween: Tween = null


## 中身のノードを組み立てる
func _init() -> void:
	custom_minimum_size = SIZE
	pivot_offset = SIZE / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	glyph_label = Label.new()
	glyph_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glyph_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_label.add_theme_font_size_override("font_size", GLYPH_FONT_SIZE)
	Art.on_picture(glyph_label, Art.CANDLE)
	add_child(glyph_label)
	mouse_entered.connect(func() -> void: hovered.emit(relic_id))
	mouse_exited.connect(func() -> void: unhovered.emit())


## id の護符を見せる (印の字と、マウスを載せた時のツールチップ)
func show_relic(id: String) -> void:
	relic_id = id
	var relic: Dictionary = Relics.RELICS[id]
	glyph_label.text = relic["glyph"]
	tooltip_text = "%s\n%s" % [relic["name"], relic["text"]]


## 丸い札 (焦げ茶の地に蝋燭の橙の縁)
func _draw() -> void:
	var center: Vector2 = size / 2.0
	var radius: float = minf(size.x, size.y) / 2.0
	draw_circle(center, radius, FACE)
	draw_arc(center, radius - RING_WIDTH / 2.0, 0.0, TAU, 32, Art.CANDLE, RING_WIDTH, true)


## 護符が働いたことを見せる: RELIC_FLASH の色で光りながら RELIC_SCALE に膨らみ、RELIC_FLASH_TIME で元に戻る
func flash() -> void:
	if not Art.motion_on():
		return
	if flash_tween != null:
		flash_tween.kill()
	var half: float = Art.RELIC_FLASH_TIME * Art.motion_scale / 2.0
	flash_tween = create_tween()
	flash_tween.tween_property(self, "scale", Vector2.ONE * Art.RELIC_SCALE, half)
	flash_tween.parallel().tween_property(self, "modulate", Art.RELIC_FLASH, half)
	flash_tween.tween_property(self, "scale", Vector2.ONE, half)
	flash_tween.parallel().tween_property(self, "modulate", Color.WHITE, half)
