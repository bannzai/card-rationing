extends Control
## 巡礼の地図の画面。1 幕の地図の全体 (下が出発、上がボス) を羊皮紙の上に最初から見せ、節点は種類ごとの印の絵で
## 示す (契約の祠は蝋燭の灯る祠の印で、先まで分かる)。次に進める節点だけを押せ、クリックか数字キー (左から
## 1, 2, ...) で選ぶと scripts/run_flow.gd で節点に入る (画面の切り替えは scripts/main.gd が局面の変化で行う)。

const ActMap := preload("res://scripts/act_map.gd")
const Art := preload("res://scripts/art.gd")
const RunFlow := preload("res://scripts/run_flow.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

## 地図の配置: 最下段の中心の y、段の間隔、最左列の中心の x、列の間隔。15 段が画面の高さ 720 に、5 列が
## 羊皮紙 (SHEET_RECT) の破れた端の内側に収まり、印どうしが重ならない間隔にした
const MAP_BOTTOM: float = 668.0
const ROW_SPACING: float = 44.0
const MAP_LEFT: float = 124.0
const COLUMN_SPACING: float = 136.0
## 地図を載せる羊皮紙を置く範囲と、右側の説明 (幕と階・凡例・操作) を置く位置と幅 (高さは中身で決まる)
const SHEET_RECT: Rect2 = Rect2(30, 6, 734, 708)
const SIDE_RECT: Rect2 = Rect2(800, 20, 450, 0)
## 節点の印の大きさ (次に進める節点 / ほか)
const CHOICE_SIZE: Vector2 = Vector2(46, 46)
const NODE_SIZE: Vector2 = Vector2(36, 36)
## 辺の色 (ほか = 墨 / 通った道 = 封蝋の赤) と太さ
const EDGE_COLOR: Color = Color(Art.INK, 0.5)
const PATH_EDGE_COLOR: Color = Art.SEAL_RED
const EDGE_WIDTH: float = 2.0
const PATH_EDGE_WIDTH: float = 4.0
## まだ進めない先の節点の印の色合い (次に進める節点より沈める)
const FAR_TINT: Color = Color(0.82, 0.8, 0.78)
## 凡例の印の大きさ
const LEGEND_ICON_SIZE: Vector2 = Vector2(28, 28)

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
	Art.add_background(self, Art.BACKDROP)
	var sheet: Panel = Panel.new()
	sheet.position = SHEET_RECT.position
	sheet.size = SHEET_RECT.size
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sheet)
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


## 節点のボタンを置く。見た目は節点の種類の印の絵で、通った節点は焼けた封蝋の印にする。次に進める節点だけ
## 押せ、大きく見せて数字キーの番号を添える
func _add_node_button(row: int, node: Dictionary) -> void:
	var column: int = node["column"]
	var kind: int = node["kind"]
	var button: Button = Button.new()
	var selectable: bool = row == run_state.path.size() and choices.has(column)
	var visited: bool = row < run_state.path.size() and run_state.path[row] == column
	button.icon = Art.SEAL_BURNT if visited else Art.MAP_ICONS[kind]
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_color_override("icon_disabled_color", Color.WHITE if visited else FAR_TINT)
	for style_name: String in ["normal", "disabled", "hover", "pressed"]:
		button.add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	var ring: StyleBoxFlat = StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = Art.SEAL_RED
	ring.set_border_width_all(3)
	ring.set_corner_radius_all(int(CHOICE_SIZE.x))
	ring.set_expand_margin_all(4)
	button.add_theme_stylebox_override("focus", ring)
	button.size = CHOICE_SIZE if selectable else NODE_SIZE
	button.position = node_center(row, column) - button.size / 2
	button.disabled = not selectable
	button.focus_mode = Control.FOCUS_ALL if selectable else Control.FOCUS_NONE
	button.tooltip_text = ActMap.KIND_NAMES[kind]
	button.pressed.connect(choose.bind(column))
	add_child(button)
	node_buttons["%d,%d" % [row, column]] = button
	if selectable:
		var number: Label = UiKit.add_label(button, str(choices.find(column) + 1), 18)
		number.autowrap_mode = TextServer.AUTOWRAP_OFF
		number.mouse_filter = Control.MOUSE_FILTER_IGNORE
		number.position = Vector2(-16, -12)


## 右側の説明: 幕と階・体力と所持金・凡例・操作
func _build_side_panel() -> void:
	var panel: VBoxContainer = VBoxContainer.new()
	panel.position = SIDE_RECT.position
	panel.custom_minimum_size = SIDE_RECT.size
	panel.add_theme_constant_override("separation", 8)
	add_child(panel)
	var title: Label = UiKit.add_label(
		panel, "第 %d 幕 巡礼の地図" % run_state.act, UiKit.TITLE_FONT_SIZE
	)
	title.add_theme_color_override("font_color", Art.CANDLE)
	info_label = UiKit.add_label(
		panel,
		(
			"%d / %d 階まで来た\n%s"
			% [run_state.path.size(), ActMap.ROWS, UiKit.status_text(run_state)]
		)
	)
	for kind: int in ActMap.KIND_NAMES:
		_add_legend(panel, Art.MAP_ICONS[kind], ActMap.KIND_NAMES[kind])
	_add_legend(panel, Art.SEAL_BURNT, "通った節点")
	UiKit.add_note(
		panel,
		(
			"契約の祠では代価なしで、契約の更新 (残り使用回数を最大まで戻す)・破棄・"
			+ "新しい契約から 1 つを選べる。\n数字キー / クリック: 次の節点   D: 契約の一覧"
		),
		16,
		SIDE_RECT.size.x - 2 * UiKit.PARCHMENT_MARGIN.x
	)


## 凡例の 1 行 (印の絵と名前) を panel に足す
func _add_legend(panel: VBoxContainer, icon: Texture2D, text: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var picture: TextureRect = Art.picture(icon)
	picture.custom_minimum_size = LEGEND_ICON_SIZE
	row.add_child(picture)
	# 行の中のラベルは折り返さない (幅の決まらない横並びでは 1 文字ずつ折り返してしまう)
	UiKit.add_label(row, text, 18).autowrap_mode = TextServer.AUTOWRAP_OFF


## 地図の辺を描く (通った道は封蝋の赤の太い線)
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
					PATH_EDGE_WIDTH if on_path else EDGE_WIDTH
				)
