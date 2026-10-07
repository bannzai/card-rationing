extends Control
## 契約の一覧 (デッキ) を重ねて見せる画面。ランの間いつでも開け、全カードと残り使用回数を並べる。並べ方は
## 強さ順と残り回数順を切り替える。開いている間はキー入力をすべて受け止め、下の画面に渡さない。
## D か Esc か「閉じる」で closed を出す。

## 画面を閉じる (呼んだ側が次の画面を出す)
signal closed

## 並べ方。強さ順はカードの強さ (scripts/cards.gd の strength()) の強い順、残り回数順は残りの少ない順で、
## 同じ残りの中は強さ順
enum Order { STRENGTH, USES_LEFT }

const CardView := preload("res://scripts/card_view.gd")
const Cards := preload("res://scripts/cards.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

## ラン単位の状態 (autoload RunState)
var run_state: RunStateScript = null
## 今の並べ方
var order: Order = Order.STRENGTH
## 見出し (枚数と並べ方) と、並べ方を切り替える・閉じるボタン
var title_label: Label = null
var strength_button: Button = null
var uses_button: Button = null
var close_button: Button = null
## カードを並べる格子 (並べ方を変えるたびに作り直す)
var list_grid: GridContainer = null
## list_grid を縦にスクロールする入れ物 (矢印キーと PageUp / PageDown で動かす)
var list_scroll: ScrollContainer = null


## 画面のノードを組み立てる
func _ready() -> void:
	run_state = get_tree().root.get_node_or_null("RunState")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 背景の絵で下の画面を覆う
	var layout: VBoxContainer = UiKit.screen_layout(self, "")
	title_label = layout.get_child(0)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	layout.add_child(row)
	strength_button = UiKit.add_button(row, "強さ順 (1)", set_order.bind(Order.STRENGTH))
	uses_button = UiKit.add_button(row, "残り回数順 (2)", set_order.bind(Order.USES_LEFT))
	close_button = UiKit.add_button(row, "閉じる (D / Esc)", closed.emit)
	for button: Button in [strength_button, uses_button, close_button]:
		button.focus_mode = Control.FOCUS_NONE
	list_grid = UiKit.add_card_grid(layout)
	list_scroll = list_grid.get_parent() as ScrollContainer
	set_order(order)
	# 下の画面のボタンにフォーカスが残ると Enter で押せてしまうため外す
	get_viewport().gui_release_focus()


## 開いている間のキー入力をすべて受け止め、下の画面に渡さない (GUI より先に呼ばれるため、フォーカス移動と
## 決定のキーで下の画面のボタンも押させない)。一覧のスクロールのキーはここで処理する
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	get_viewport().set_input_as_handled()
	var key_event: InputEventKey = event
	if not key_event.pressed:
		return
	match key_event.keycode:
		KEY_D, KEY_ESCAPE:
			if not key_event.echo:
				closed.emit()
		KEY_1:
			set_order(Order.STRENGTH)
		KEY_2:
			set_order(Order.USES_LEFT)
		KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN:
			scroll_list(key_event.keycode)


## 一覧を keycode のキーの分だけ縦にスクロールする (矢印は 1 行、PageUp / PageDown は表示の高さ 1 つ分)
func scroll_list(keycode: Key) -> void:
	var page: int = int(list_scroll.get_v_scroll_bar().page)
	var line: int = int(CardView.BASE_SIZE.y)
	var amounts: Dictionary = {KEY_UP: -line, KEY_DOWN: line, KEY_PAGEUP: -page, KEY_PAGEDOWN: page}
	list_scroll.scroll_vertical += amounts[keycode]


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
		var view: CardView = CardView.new()
		view.show_deck_card(run_state.deck[index]["id"], run_state.uses_left(index))
		# 見せるだけで、押せずフォーカスも受けない
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.focus_mode = Control.FOCUS_NONE
		list_grid.add_child(view)


## deck の index を sort_order の並べ方で並べた並び (同じ順位はデッキの順)
static func sorted_indices(deck: Array[Dictionary], sort_order: Order) -> Array[int]:
	var indices: Array[int] = []
	for index: int in range(deck.size()):
		indices.append(index)
	indices.sort_custom(
		func(a: int, b: int) -> bool: return _comes_before(deck, sort_order, a, b)
	)
	return indices


## sort_order の並べ方で、deck の a 番目が b 番目より前に来るか
static func _comes_before(deck: Array[Dictionary], sort_order: Order, a: int, b: int) -> bool:
	if sort_order == Order.USES_LEFT and deck[a]["uses_left"] != deck[b]["uses_left"]:
		return deck[a]["uses_left"] < deck[b]["uses_left"]
	var strength_a: float = Cards.strength(deck[a]["id"])
	var strength_b: float = Cards.strength(deck[b]["id"])
	if strength_a != strength_b:
		return strength_a > strength_b
	return a < b
