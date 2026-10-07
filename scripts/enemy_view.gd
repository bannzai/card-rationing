extends Button
## 戦闘の敵 1 体の見た目。格ごとに共有する絵・予告 (次の行動)・名前・体力の数珠と数・防御を縦に並べる。
## ボタンとして押せ、対象の選択で使う。大きさは敵の格で決める。

const Art := preload("res://scripts/art.gd")
const Enemies := preload("res://scripts/enemies.gd")

## 敵の行動の種別の表示名と、名前に添える敵の格 (戦闘の格の敵には付けない)
const MOVE_NAMES: Dictionary = {Enemies.Move.ATTACK: "攻撃", Enemies.Move.GUARD: "防御"}
const RANK_NAMES: Dictionary = {
	Enemies.Rank.NORMAL: "", Enemies.Rank.ELITE: " [強敵]", Enemies.Rank.BOSS: " [ボス]"
}
## 敵の格 → 見た目の大きさ。格が上がるほど大きくし、どれも戦闘画面の敵の行 (scenes/battle.tscn の EnemyRow) の
## 高さに収め、通常の敵は 2 体が横に並ぶ幅にした
const RANK_SIZES: Dictionary = {
	Enemies.Rank.NORMAL: Vector2(236, 320),
	Enemies.Rank.ELITE: Vector2(290, 400),
	Enemies.Rank.BOSS: Vector2(330, 420),
}
## 体力の数珠の珠の数と、珠 1 つの大きさ
const BEADS: int = 10
const BEAD_SIZE: Vector2 = Vector2(16, 16)
## 予告・名前・体力と防御の文字の大きさ
const INTENT_FONT_SIZE: int = 20
const NAME_FONT_SIZE: int = 18
const STATUS_FONT_SIZE: int = 15
## 倒した敵の絵の色 (暗く透かす) と、マウスを載せた敵の明るさ
const DEFEATED_MODULATE: Color = Color(0.3, 0.3, 0.36, 0.5)
const HOVER_TONE: float = 1.16

## 予告・絵・名前・体力の数珠・体力と防御の文
var intent_label: Label = null
var art: TextureRect = null
var name_label: Label = null
var bead_row: HBoxContainer = null
var status_label: Label = null
## 倒した敵を見せているか
var defeated: bool = false


## 中身のノードを組み立てる
func _init() -> void:
	for style_name: String in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	intent_label = _add_text(column, INTENT_FONT_SIZE)
	intent_label.add_theme_color_override("font_color", Art.CANDLE)
	art = Art.picture(null)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(art)
	name_label = _add_text(column, NAME_FONT_SIZE)
	bead_row = HBoxContainer.new()
	bead_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bead_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bead_row.add_theme_constant_override("separation", 1)
	column.add_child(bead_row)
	status_label = _add_text(column, STATUS_FONT_SIZE)


## マウスが載っている押せる敵 (対象の選択中) を明るくする (Button は状態が変わるたびに描き直す)
func _draw() -> void:
	if defeated:
		return
	var tone: float = HOVER_TONE if is_hovered() and not disabled else 1.0
	art.modulate = Color(tone, tone, tone)


## 戦闘の敵 enemy (scripts/battle.gd の enemies の 1 要素) を、数字キーの番号 number (1 始まり) で見せる
func show_enemy(number: int, enemy: Dictionary) -> void:
	var rank: int = Enemies.ENEMIES[enemy["id"]]["rank"]
	custom_minimum_size = RANK_SIZES[rank]
	art.texture = Art.ENEMY_ART[rank]
	name_label.text = "%d. %s%s" % [number, enemy["name"], RANK_NAMES[rank]]
	defeated = enemy["hp"] <= 0
	disabled = defeated
	Art.set_icons(
		bead_row,
		Art.BEAD,
		Art.BEAD_DULL,
		Art.lit_count(enemy["hp"], enemy["max_hp"], BEADS),
		BEADS,
		BEAD_SIZE
	)
	if defeated:
		art.modulate = DEFEATED_MODULATE
		intent_label.text = ""
		status_label.text = "倒した"
		return
	var intent: Dictionary = enemy["intent"]
	var hits: int = intent.get("hits", 1)
	intent_label.text = (
		"予告: %s %d%s"
		% [MOVE_NAMES[intent["move"]], intent["value"], "×%d" % hits if hits > 1 else ""]
	)
	status_label.text = "体力 %d / %d   防御 %d" % [enemy["hp"], enemy["max_hp"], enemy["block"]]
	queue_redraw()


## column に、中央に寄せた文字の大きさ font_size のラベルを足す
func _add_text(column: VBoxContainer, font_size: int) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(label)
	return label
