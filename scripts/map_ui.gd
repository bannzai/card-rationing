extends Control
## 巡礼の地図の画面。1 幕の地図の全体 (下が出発、上がボス) を最初から見せ、契約の祠を色で目立たせて先まで
## 分かるようにする。次に進める節点だけを押せ、クリックか数字キー (左から 1, 2, ...) で選ぶと
## scripts/run_flow.gd で節点に入る (画面の切り替えは scripts/main.gd が局面の変化で行う)。

const ActMap := preload("res://scripts/act_map.gd")
const RunFlow := preload("res://scripts/run_flow.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

## 地図の配置: 最下段の中心の y、段の間隔、最左列の中心の x、列の間隔、節点のボタンの大きさ
const MAP_BOTTOM: float = 684.0
const ROW_SPACING: float = 45.0
const MAP_LEFT: float = 110.0
const COLUMN_SPACING: float = 140.0
const NODE_SIZE: Vector2 = Vector2(64, 34)
## 節点の種類ごとの文字の色 (祠は先まで見えるよう最も明るい金色)
const KIND_COLORS: Dictionary = {
	ActMap.Kind.BATTLE: Color(0.85, 0.85, 0.85),
	ActMap.Kind.ELITE: Color(1, 0.5, 0.45),
	ActMap.Kind.EVENT: Color(0.6, 0.8, 1),
	ActMap.Kind.SHRINE: Color(1, 0.85, 0.3),
	ActMap.Kind.SHOP: Color(0.6, 0.95, 0.6),
	ActMap.Kind.BOSS: Color(0.95, 0.6, 1),
}
## 辺の色 (通った道 / ほか) と太さ
const EDGE_COLOR: Color = Color(0.45, 0.43, 0.5)
const PATH_EDGE_COLOR: Color = Color(1, 0.85, 0.3)
const EDGE_WIDTH: float = 2.0
## 通った節点の明るさ (不透明のまま暗くし、辺が文字に透けないようにする)
const VISITED_MODULATE: Color = Color(0.6, 0.6, 0.6, 1)
## 節点のボタンの背景 (不透明にして、節点を通る辺を文字の下に隠す) と、次に進める節点の枠の太さ
const NODE_BG_COLOR: Color = Color(0.15, 0.14, 0.18, 1)
const SELECTABLE_BORDER_WIDTH: int = 2

## ラン単位の状態 (autoload RunState)
var run_state: RunStateScript = null
## 次に進める列 (左から順。数字キーの 1, 2, ... に対応する)
var choices: Array[int] = []
## 「段,列」→ 節点のボタン
var node_buttons: Dictionary = {}
## 地図の辺を描く全面の Control (節点のボタンの下に置く)
var edge_canvas: Control = null
## 右側の説明の、今の階と体力・所持金の文
var info_label: Label = null


## 画面のノードを組み立てる
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	run_state = get_tree().root.get_node_or_null("RunState")
	choices = ActMap.next_columns(run_state.rows, run_state.path)
	edge_canvas = Control.new()
	edge_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	edge_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge_canvas.draw.connect(_draw_edges)
	add_child(edge_canvas)
	for row: int in range(run_state.rows.size()):
		for node: Dictionary in run_state.rows[row]:
			_add_node_button(row, node)
	_build_side_panel()
	if not choices.is_empty():
		node_button(run_state.path.size(), choices[0]).grab_focus()


## 数字キー (1 始まり) で次に進める節点を左から選ぶ
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: Key = (event as InputEventKey).keycode
	if key >= KEY_1 and key <= KEY_9 and key - KEY_1 < choices.size():
		get_viewport().set_input_as_handled()
		choose(choices[key - KEY_1])


## 次の段の column 列の節点へ進む (進めない列なら何もしない)
func choose(column: int) -> void:
	RunFlow.enter_node(run_state, column)


## row 段 column 列の節点のボタン (無ければ null)
func node_button(row: int, column: int) -> Button:
	return node_buttons.get("%d,%d" % [row, column])


## 地図の上の節点の中心
func node_center(row: int, column: int) -> Vector2:
	return Vector2(MAP_LEFT + column * COLUMN_SPACING, MAP_BOTTOM - row * ROW_SPACING)


## 節点のボタンを置く。次に進める節点だけ押せ、数字キーの番号を付ける
func _add_node_button(row: int, node: Dictionary) -> void:
	var column: int = node["column"]
	var kind: int = node["kind"]
	var button: Button = Button.new()
	var selectable: bool = row == run_state.path.size() and choices.has(column)
	var visited: bool = row < run_state.path.size() and run_state.path[row] == column
	button.text = ActMap.KIND_MARKS[kind]
	if selectable:
		button.text = "%d %s" % [choices.find(column) + 1, button.text]
	button.size = NODE_SIZE
	button.position = node_center(row, column) - NODE_SIZE / 2
	button.disabled = not selectable
	button.focus_mode = Control.FOCUS_ALL if selectable else Control.FOCUS_NONE
	for color_name: String in ["font_color", "font_disabled_color", "font_hover_color"]:
		button.add_theme_color_override(color_name, KIND_COLORS[kind])
	var background: StyleBoxFlat = StyleBoxFlat.new()
	background.bg_color = NODE_BG_COLOR
	background.set_corner_radius_all(6)
	if selectable:
		background.set_border_width_all(SELECTABLE_BORDER_WIDTH)
		background.border_color = KIND_COLORS[kind]
	for style_name: String in ["normal", "disabled", "hover", "pressed"]:
		button.add_theme_stylebox_override(style_name, background)
	if visited:
		button.modulate = VISITED_MODULATE
	button.tooltip_text = ActMap.KIND_NAMES[kind]
	button.pressed.connect(choose.bind(column))
	add_child(button)
	node_buttons["%d,%d" % [row, column]] = button


## 右側の説明: 幕と階・体力と所持金・凡例・操作
func _build_side_panel() -> void:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.position = Vector2(820, 24)
	panel.custom_minimum_size = Vector2(430, 0)
	panel.add_theme_constant_override("separation", 10)
	add_child(panel)
	UiKit.add_label(panel, "第 %d 幕 巡礼の地図" % run_state.act, UiKit.TITLE_FONT_SIZE)
	info_label = UiKit.add_label(
		panel,
		(
			"%d / %d 階まで来た\n%s"
			% [run_state.path.size(), ActMap.ROWS, UiKit.status_text(run_state)]
		)
	)
	for kind: int in ActMap.KIND_MARKS:
		var legend: Label = UiKit.add_label(
			panel, "%s  %s" % [ActMap.KIND_MARKS[kind], ActMap.KIND_NAMES[kind]], 18
		)
		legend.add_theme_color_override("font_color", KIND_COLORS[kind])
	UiKit.add_label(
		panel,
		(
			"契約の祠 (祠) では代価なしで、契約の更新 (残り使用回数を最大まで戻す)・破棄・"
			+ "新しい契約から 1 つを選べる。\n数字キー / クリック: 次の節点   D: 契約の一覧"
		),
		16
	)


## 地図の辺を描く (通った道は明るい色)
func _draw_edges() -> void:
	for row: int in range(run_state.rows.size()):
		for node: Dictionary in run_state.rows[row]:
			var from: Vector2 = node_center(row, node["column"])
			for next_column: int in node["next"]:
				var on_path: bool = (
					row + 1 < run_state.path.size()
					and run_state.path[row] == node["column"]
					and run_state.path[row + 1] == next_column
				)
				edge_canvas.draw_line(
					from,
					node_center(row + 1, next_column),
					PATH_EDGE_COLOR if on_path else EDGE_COLOR,
					EDGE_WIDTH
				)
