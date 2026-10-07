extends RefCounted
## 画面を組み立てる共通の部品と表示の文。見た目は関門 2 で決めた「蝋と灯火」(documents/DIRECTION.md
## 「デザインの方向」) で、素材と色は scripts/art.gd が持つ。全画面の theme (フォント・木の札のボタン・羊皮紙・
## スライダー) をここで作り、scripts/main.gd がメインシーンに設定する。
## 戦闘とボス戦の前の会話以外の画面はシーンを持たず、この部品でノードを組み立てる。

const Art := preload("res://scripts/art.gd")
const CardView := preload("res://scripts/card_view.gd")
const RunStateScript := preload("res://scripts/run_state.gd")

## 画面の見出しの文字の大きさ (戦闘画面の階の表示より一段大きくする)
const TITLE_FONT_SIZE: int = 32
## 本文の文字の大きさ (1280 幅の 1 行に 60 字前後が収まる大きさ)
const BODY_FONT_SIZE: int = 20
## デッキのカードを並べる格子の列の数 (カードの幅 176 で 1216 幅の画面に収まる数)
const DECK_GRID_COLUMNS: int = 6
## カードを並べる時の間隔
const CARD_SEPARATION: int = 10
## 木の札の絵の、引き伸ばさない左右の端の幅と、ボタンの文字の周りの余白 (左右 / 上下)
const PLAQUE_END_WIDTH: float = 26.0
const BUTTON_MARGIN: Vector2 = Vector2(26, 9)
## 羊皮紙の絵の、引き伸ばさない端の幅と、載せる文の周りの余白 (左右 / 上下)
const PARCHMENT_EDGE_WIDTH: float = 30.0
const PARCHMENT_MARGIN: Vector2 = Vector2(34, 24)
## ボタンの木の札の色合い: マウスを載せた時・押している時・押せない時
const HOVER_TINT: Color = Color(1.3, 1.2, 1.05)
const PRESSED_TINT: Color = Color(0.78, 0.74, 0.7)
const DISABLED_TINT: Color = Color(0.5, 0.5, 0.52, 0.85)


## 全画面の theme: 既定フォント・絵の上で読める文字・木の札のボタン・羊皮紙のパネル・蝋燭色のスライダー
static func build_theme() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font = Art.FONT
	theme.default_font_size = BODY_FONT_SIZE
	theme.set_color("font_color", "Label", Art.PAPER)
	theme.set_color("font_outline_color", "Label", Art.NIGHT)
	theme.set_constant("outline_size", "Label", Art.OUTLINE_SIZE)
	_theme_buttons(theme)
	for panel_type: String in ["Panel", "PanelContainer", "TooltipPanel"]:
		theme.set_stylebox("panel", panel_type, _parchment_style())
	theme.set_color("font_color", "TooltipLabel", Art.INK)
	theme.set_constant("outline_size", "TooltipLabel", 0)
	_theme_sliders(theme)
	_theme_scroll_bars(theme)
	return theme


## parent の全面に背景の絵を敷き、余白付きの縦並びを置いて、見出し title を足して返す (画面の中身はこの
## 縦並びに足す)
static func screen_layout(parent: Control, title: String) -> VBoxContainer:
	parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Art.add_background(parent, Art.BACKDROP)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 32
	layout.offset_top = 20
	layout.offset_right = -32
	layout.offset_bottom = -20
	layout.add_theme_constant_override("separation", 12)
	parent.add_child(layout)
	var title_label: Label = add_label(layout, title, TITLE_FONT_SIZE)
	title_label.add_theme_color_override("font_color", Art.CANDLE)
	return layout


## parent の子をすべて消す (押されたボタン自身の pressed の中からも呼べるよう、tree から外さずに隠して
## フレームの終わりに解放する)
static func clear_children(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = false
		child.queue_free()


## parent に文字の大きさ font_size のラベルを足す (絵の上で読める色と縁取りは theme が付ける)。font_size を
## 省くと、画面の文の大半を占める本文の大きさにする
static func add_label(parent: Control, text: String, font_size: int = BODY_FONT_SIZE) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


## parent に羊皮紙を足し、その上に墨の文字で text を載せる。載せたラベルを返す
static func add_note(parent: Control, text: String, font_size: int = BODY_FONT_SIZE) -> Label:
	var sheet: PanelContainer = PanelContainer.new()
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sheet)
	var label: Label = add_label(sheet, text, font_size)
	Art.on_parchment(label)
	return label


## parent にボタン (木の札) を足し、押したら callback を呼ぶ。縦並びの中では文の幅に合わせ、行の幅いっぱいには
## 伸ばさない
static func add_button(parent: Control, text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


## 体力・所持金・デッキの枚数の 1 行
static func status_text(state: RunStateScript) -> String:
	return "体力 %d / %d   所持金 %d   契約 %d 枚" % [state.hp, state.max_hp, state.gold, state.deck.size()]


## parent に、カードを横に並べる行を足す
static func add_card_row(parent: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", CARD_SEPARATION)
	parent.add_child(row)
	return row


## parent に、これから契約するカード card_id (回数は最大) を足し、押したら callback を呼ぶ。note は効果の下の
## 1 行 (値段など)
static func add_offer_card(
	parent: Control, card_id: String, note: String, callback: Callable
) -> CardView:
	var view: CardView = CardView.new()
	view.show_offer(card_id, note)
	view.pressed.connect(callback)
	parent.add_child(view)
	return view


## parent に、縦にスクロールするカードの格子を足して返す (格子の親が ScrollContainer)
static func add_card_grid(parent: Control) -> GridContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var grid: GridContainer = GridContainer.new()
	grid.columns = DECK_GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", CARD_SEPARATION)
	grid.add_theme_constant_override("v_separation", CARD_SEPARATION)
	scroll.add_child(grid)
	return grid


## parent にデッキの全カードを格子で並べる。enabled.call(index) が false のカードは押せず、押したら
## on_pick.call(index) を呼ぶ。押せる最初のカードにフォーカスを置く (キーボードだけで選べるように)。並べた格子を返す
static func add_deck_grid(
	parent: Control, state: RunStateScript, enabled: Callable, on_pick: Callable
) -> GridContainer:
	var grid: GridContainer = add_card_grid(parent)
	# キーボードでフォーカスを移したカードが表示の外なら、見える位置までスクロールする
	(grid.get_parent() as ScrollContainer).follow_focus = true
	for index: int in range(state.deck.size()):
		var view: CardView = CardView.new()
		view.show_deck_card(state.deck[index]["id"], state.uses_left(index))
		view.disabled = not enabled.call(index)
		view.pressed.connect(on_pick.bind(index))
		grid.add_child(view)
	for view: CardView in grid.get_children():
		if not view.disabled:
			view.grab_focus()
			break
	return grid


## ボタンを木の札にする (状態は札の色合いで見せ、フォーカスは蝋燭の橙の枠で見せる)
static func _theme_buttons(theme: Theme) -> void:
	theme.set_stylebox("normal", "Button", _plaque_style(Color.WHITE))
	theme.set_stylebox("hover", "Button", _plaque_style(HOVER_TINT))
	theme.set_stylebox("pressed", "Button", _plaque_style(PRESSED_TINT))
	theme.set_stylebox("disabled", "Button", _plaque_style(DISABLED_TINT))
	var focus: StyleBoxFlat = StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = Art.CANDLE
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(6)
	theme.set_stylebox("focus", "Button", focus)
	for color_name: String in ["font_color", "font_focus_color", "font_pressed_color"]:
		theme.set_color(color_name, "Button", Art.PAPER)
	for color_name: String in ["font_hover_color", "font_hover_pressed_color"]:
		theme.set_color(color_name, "Button", Art.CANDLE)
	theme.set_color("font_disabled_color", "Button", Art.ASH)
	theme.set_color("font_outline_color", "Button", Art.NIGHT)
	theme.set_constant("outline_size", "Button", 4)


## 木の札の絵を、左右の端を残して引き伸ばす StyleBox (tint の色合い)
static func _plaque_style(tint: Color) -> StyleBoxTexture:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = Art.PLAQUE
	style.texture_margin_left = PLAQUE_END_WIDTH
	style.texture_margin_right = PLAQUE_END_WIDTH
	style.content_margin_left = BUTTON_MARGIN.x
	style.content_margin_right = BUTTON_MARGIN.x
	style.content_margin_top = BUTTON_MARGIN.y
	style.content_margin_bottom = BUTTON_MARGIN.y
	style.modulate_color = tint
	return style


## 羊皮紙の絵を、破れた端を残して引き伸ばす StyleBox
static func _parchment_style() -> StyleBoxTexture:
	var style: StyleBoxTexture = StyleBoxTexture.new()
	style.texture = Art.PARCHMENT
	style.set_texture_margin_all(PARCHMENT_EDGE_WIDTH)
	style.content_margin_left = PARCHMENT_MARGIN.x
	style.content_margin_right = PARCHMENT_MARGIN.x
	style.content_margin_top = PARCHMENT_MARGIN.y
	style.content_margin_bottom = PARCHMENT_MARGIN.y
	return style


## スライダーを、蝋燭の橙の線と封蝋の印のつまみにする
static func _theme_sliders(theme: Theme) -> void:
	theme.set_stylebox("slider", "HSlider", _line_style(Color(Art.PAPER, 0.45), 3, false))
	for style_name: String in ["grabber_area", "grabber_area_highlight"]:
		theme.set_stylebox(style_name, "HSlider", _line_style(Art.CANDLE, 3, false))
	for icon_name: String in ["grabber", "grabber_highlight", "grabber_disabled"]:
		theme.set_icon(icon_name, "HSlider", Art.SEAL_GRABBER)


## 縦のスクロールバーを、細い線と蝋燭の橙のつまみにする
static func _theme_scroll_bars(theme: Theme) -> void:
	theme.set_stylebox("scroll", "VScrollBar", _line_style(Color(Art.PAPER, 0.3), 2, true))
	theme.set_stylebox("grabber", "VScrollBar", _line_style(Color(Art.CANDLE, 0.7), 6, true))
	for style_name: String in ["grabber_highlight", "grabber_pressed"]:
		theme.set_stylebox(style_name, "VScrollBar", _line_style(Art.CANDLE, 6, true))


## color の色・thickness の太さの線の StyleBox (vertical なら縦の線)。線の太さの分の幅を確保する
static func _line_style(color: Color, thickness: int, vertical: bool) -> StyleBoxLine:
	var style: StyleBoxLine = StyleBoxLine.new()
	style.color = color
	style.thickness = thickness
	style.vertical = vertical
	if vertical:
		style.content_margin_left = thickness
		style.content_margin_right = thickness
	else:
		style.content_margin_top = thickness
		style.content_margin_bottom = thickness
	return style
