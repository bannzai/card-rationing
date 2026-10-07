extends RefCounted
## 画面を組み立てる共通の部品と表示の文 (仮の見た目。関門 2 で決めた見た目は #11 で反映する)。
## 戦闘以外の画面はシーンを持たず、この部品でノードを組み立てる。

const Cards := preload("res://scripts/cards.gd")
const RunStateScript := preload("res://scripts/run_state.gd")

## 契約の相手の区分の表示名
const BOND_NAMES: Dictionary = {Cards.Bond.SPIRIT: "精霊", Cards.Bond.HERO: "英霊"}
## 残り使用回数の色 (通常 / 最後の 1 回 / 契約切れ)
const COLOR_NORMAL: Color = Color(1, 1, 1, 1)
const COLOR_LAST: Color = Color(1, 0.75, 0.4, 1)
const COLOR_EXHAUSTED: Color = Color(0.55, 0.55, 0.55, 1)
## 画面の見出しの文字の大きさ (戦闘画面の階の表示 22 より一段大きくする)
const TITLE_FONT_SIZE: int = 30
## 本文の文字の大きさ (戦闘画面の状態の行 22 と揃え、1280 幅の 1 行に 60 字前後が収まる大きさ)
const BODY_FONT_SIZE: int = 20
## デッキのカードを並べる格子の列の数と、1 枚のボタンの大きさ
const DECK_GRID_COLUMNS: int = 4
const CARD_BUTTON_SIZE: Vector2 = Vector2(290, 64)


## parent の全面に余白付きの縦並びを置き、見出し title を足して返す (画面の中身はこの縦並びに足す)
static func screen_layout(parent: Control, title: String) -> VBoxContainer:
	parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 32
	layout.offset_top = 20
	layout.offset_right = -32
	layout.offset_bottom = -20
	layout.add_theme_constant_override("separation", 12)
	parent.add_child(layout)
	add_label(layout, title, TITLE_FONT_SIZE)
	return layout


## parent の子をすべて消す (押されたボタン自身の pressed の中からも呼べるよう、tree から外さずに隠して
## フレームの終わりに解放する)
static func clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = false
		child.queue_free()


## parent に文字の大きさ font_size のラベルを足す
static func add_label(parent: Control, text: String, font_size: int = BODY_FONT_SIZE) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


## parent にボタンを足し、押したら callback を呼ぶ
static func add_button(parent: Control, text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


## カードの名前・区分・コストの行と、効果の行の 2 行 (例: 「斬火 [精霊] コスト 1」「攻撃 6」)
static func card_summary(card_id: String) -> String:
	var card: Dictionary = Cards.CARDS[card_id]
	return (
		"%s [%s] コスト %d\n%s"
		% [card["name"], BOND_NAMES[card["bond"]], card["cost"], Cards.effect_text(card_id)]
	)


## 新しく契約するカードの文 (要約と、契約で決まる回数)
static func offer_text(card_id: String) -> String:
	return "%s\n回数 %d" % [card_summary(card_id), Cards.CARDS[card_id]["max_uses"]]


## デッキの index 番目のカードの文 (要約と残り使用回数。最後の 1 回と契約切れはそう書く)
static func deck_card_text(state: RunStateScript, index: int) -> String:
	var uses: int = state.uses_left(index)
	var text: String = "%s\n残り %d / %d" % [
		card_summary(state.deck[index]["id"]), uses, state.card(index)["max_uses"]
	]
	if uses == 0:
		text += " 契約切れ"
	elif uses == 1:
		text += " (最後の 1 回)"
	return text


## 残り使用回数 uses の色
static func uses_color(uses: int) -> Color:
	if uses == 0:
		return COLOR_EXHAUSTED
	return COLOR_LAST if uses == 1 else COLOR_NORMAL


## 体力・所持金・デッキの枚数の 1 行
static func status_text(state: RunStateScript) -> String:
	return "体力 %d / %d   所持金 %d   契約 %d 枚" % [state.hp, state.max_hp, state.gold, state.deck.size()]


## parent にカード 1 枚のボタン (CARD_BUTTON_SIZE の幅で文を折り返す) を足し、押したら callback を呼ぶ
static func add_card_button(parent: Control, text: String, callback: Callable) -> Button:
	var button: Button = add_button(parent, text, callback)
	button.custom_minimum_size = CARD_BUTTON_SIZE
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return button


## parent にデッキの全カードのボタンを格子で並べる。enabled.call(index) が false のカードは押せず、押したら
## on_pick.call(index) を呼ぶ。押せる最初のカードにフォーカスを置く (キーボードだけで選べるように)。並べた格子を返す
static func add_deck_grid(
	parent: Control, state: RunStateScript, enabled: Callable, on_pick: Callable
) -> GridContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var grid: GridContainer = GridContainer.new()
	grid.columns = DECK_GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for index: int in range(state.deck.size()):
		var button: Button = add_card_button(grid, deck_card_text(state, index), on_pick.bind(index))
		button.modulate = uses_color(state.uses_left(index))
		button.disabled = not enabled.call(index)
	for button: Button in grid.get_children():
		if not button.disabled:
			button.grab_focus()
			break
	return grid
