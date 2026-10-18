extends Control
## 巡礼の開始で契約者 (プレイヤーキャラクター) を選ぶ画面。契約者ごとのボタンを並べ、フォーカスかマウスを載せた
## 契約者の立ち絵と、物語・個性・最大体力・初期デッキを見せる。選んだら chosen を、戻るなら back_requested を
## 出す (巡礼の開始は scripts/main.gd が行う)。
## 契約者の解放の条件は無く、全員を最初から選べる。

## character_id の契約者が選ばれた
signal chosen(character_id: String)
## 前の画面へ戻る
signal back_requested

const Art := preload("res://scripts/art.gd")
const Cards := preload("res://scripts/cards.gd")
const Contractors := preload("res://scripts/contractors.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

## 巡礼者の立ち絵を置く範囲 (画面の左)
const PORTRAIT_RECT: Rect2 = Rect2(40, 90, 360, 600)

## 契約者 ID → その契約者を選ぶボタン
var character_buttons: Dictionary = {}
## 前の画面へ戻るボタン
var back_button: Button = null
## 立ち絵と説明を見せている契約者の ID
var shown_id: String = ""
## 見せている契約者の立ち絵と、説明の羊皮紙の文
var portrait: TextureRect = null
var detail_label: Label = null
## 説明の羊皮紙に載せる文の幅 (立ち絵の分だけ狭くなった縦並びに収める)
var detail_width: float = 0.0


## 画面のノードを組み立てる
func _ready() -> void:
	var layout: VBoxContainer = UiKit.screen_layout(self, "契約者を選ぶ")
	# 左に契約者の立ち絵を置き、説明とボタンはその右に並べる
	portrait = Art.picture(null)
	portrait.position = PORTRAIT_RECT.position
	portrait.size = PORTRAIT_RECT.size
	add_child(portrait)
	layout.offset_left = PORTRAIT_RECT.end.x + 24
	detail_width = UiKit.NOTE_TEXT_WIDTH - (layout.offset_left - UiKit.LAYOUT_MARGIN)
	UiKit.add_label(layout, "契約者ごとに個性と、最初に契約している精霊・英霊が違う。")
	detail_label = UiKit.add_note(layout, "", UiKit.BODY_FONT_SIZE, detail_width)
	for character_id: String in Contractors.CONTRACTORS:
		var button: Button = UiKit.add_button(
			layout,
			"%s と巡礼に出る" % Contractors.CONTRACTORS[character_id]["name"],
			chosen.emit.bind(character_id)
		)
		button.focus_entered.connect(show_contractor.bind(character_id))
		button.mouse_entered.connect(show_contractor.bind(character_id))
		character_buttons[character_id] = button
	back_button = UiKit.add_button(layout, "戻る", back_requested.emit)
	show_contractor(Contractors.FIRST_CONTRACTOR)
	character_buttons[Contractors.FIRST_CONTRACTOR].grab_focus()


## character_id の契約者の立ち絵と説明を見せる
func show_contractor(character_id: String) -> void:
	shown_id = character_id
	portrait.texture = Art.PORTRAITS[character_id]
	var character: Dictionary = Contractors.CONTRACTORS[character_id]
	detail_label.text = (
		"%s   最大体力 %d\n%s\n個性「%s」: %s\n最初の契約: %s"
		% [
			character["name"],
			character["max_hp"],
			character["story"],
			character["trait_name"],
			" / ".join(Contractors.trait_lines(character_id)),
			_deck_text(character_id),
		]
	)
	# 契約者を切り替えても羊皮紙の幅が変わらないよう、文の長さによらず幅いっぱいにする
	detail_label.custom_minimum_size.x = detail_width


## character_id の契約者の初期デッキの「名前 ×枚数」の並び (例: 「斬火 ×3、守りの風 ×3」)
func _deck_text(character_id: String) -> String:
	var counts: Dictionary = {}
	for card_id: String in Contractors.starter_deck(character_id):
		counts[card_id] = counts.get(card_id, 0) + 1
	var parts: Array[String] = []
	for card_id: String in counts:
		parts.append("%s ×%d" % [Cards.CARDS[card_id]["name"], counts[card_id]])
	return "、".join(parts)
