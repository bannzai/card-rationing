extends Control
## 契約の一覧 (デッキ) を重ねて見せる画面。ランの間いつでも開け、全カードと残り使用回数を並べる。並べ方は
## 強さ順と残り回数順を切り替える。開いている間はキー入力をすべて受け止め、下の画面に渡さない。
## D か Esc か「閉じる」で closed を出す。

## 画面を閉じる (呼んだ側が次の画面を出す)
signal closed

## 並べ方。強さ順は英霊を先にし、同じ区分の中は最大使用回数の少ない順 (1 人目の契約者の中身 (#9) が強さを
## 定義したら、それに置き換える)。残り回数順は残りの少ない順で、同じ残りの中は強さ順
enum Order { STRENGTH, USES_LEFT }

const Cards := preload("res://scripts/cards.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

## 後ろの画面を暗くする色
const SHADE_COLOR: Color = Color(0, 0, 0, 0.82)

## ラン単位の状態 (autoload RunState)
var run_state: RunStateScript = null
## 今の並べ方
var order: Order = Order.STRENGTH
## 見出し (枚数と並べ方) と、並べ方を切り替える・閉じるボタン
var title_label: Label = null
var strength_button: Button = null
var uses_button: Button = null
var close_button: Button = null
## カードの文を並べる格子 (並べ方を変えるたびに作り直す)
var list_grid: GridContainer = null


## 画面のノードを組み立てる
func _ready() -> void:
	run_state = get_tree().root.get_node_or_null("RunState")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade: ColorRect = ColorRect.new()
	shade.color = SHADE_COLOR
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var layout: VBoxContainer = UiKit.screen_layout(self, "")
	title_label = layout.get_child(0)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	layout.add_child(row)
	strength_button = UiKit.add_button(row, "強さ順", set_order.bind(Order.STRENGTH))
	uses_button = UiKit.add_button(row, "残り回数順", set_order.bind(Order.USES_LEFT))
	close_button = UiKit.add_button(row, "閉じる (D / Esc)", closed.emit)
	for button: Button in [strength_button, uses_button, close_button]:
		button.focus_mode = Control.FOCUS_NONE
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	list_grid = GridContainer.new()
	list_grid.columns = UiKit.DECK_GRID_COLUMNS
	list_grid.add_theme_constant_override("h_separation", 8)
	list_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(list_grid)
	set_order(order)
	# 下の画面のボタンにフォーカスが残ると Enter で押せてしまうため外す
	get_viewport().gui_release_focus()


## 開いている間はキーをすべて受け止める。D と Esc で閉じる
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	get_viewport().set_input_as_handled()
	var key_event: InputEventKey = event
	if key_event.pressed and not key_event.echo and key_event.keycode in [KEY_D, KEY_ESCAPE]:
		closed.emit()


## 並べ方を next_order にして一覧を作り直す
func set_order(next_order: Order) -> void:
	order = next_order
	title_label.text = (
		"契約の一覧 (%d 枚、%s)"
		% [run_state.deck.size(), "強さ順" if order == Order.STRENGTH else "残り回数順"]
	)
	strength_button.disabled = order == Order.STRENGTH
	uses_button.disabled = order == Order.USES_LEFT
	UiKit.clear_children(list_grid)
	for index: int in sorted_indices(run_state.deck, order):
		var label: Label = UiKit.add_label(list_grid, UiKit.deck_card_text(run_state, index), 16)
		label.custom_minimum_size = UiKit.CARD_BUTTON_SIZE
		label.modulate = UiKit.uses_color(run_state.uses_left(index))


## deck の index を sort_order の並べ方で並べた並び (同じ順位はデッキの順)
static func sorted_indices(deck: Array[Dictionary], sort_order: Order) -> Array[int]:
	var keys: Dictionary = {}
	var indices: Array[int] = []
	for index: int in range(deck.size()):
		indices.append(index)
		var card: Dictionary = Cards.CARDS[deck[index]["id"]]
		# 区分 (英霊が先)・最大使用回数・デッキの順を桁に詰めた 1 つの数 (デッキと回数は 1000 未満)
		var key: int = (
			(0 if card["bond"] == Cards.Bond.HERO else 1) * 1000000 + card["max_uses"] * 1000 + index
		)
		if sort_order == Order.USES_LEFT:
			key += deck[index]["uses_left"] * 10000000
		keys[index] = key
	indices.sort_custom(func(a: int, b: int) -> bool: return keys[a] < keys[b])
	return indices
