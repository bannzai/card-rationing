extends Control
## 巡礼の開始で契約者 (プレイヤーキャラクター) を選ぶ画面。契約者ごとに名前・説明・初期デッキを並べ、選んだら
## chosen を、戻るなら back_requested を出す (巡礼の開始は scripts/main.gd が行う)。

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


## 画面のノードを組み立てる
func _ready() -> void:
	var layout: VBoxContainer = UiKit.screen_layout(self, "契約者を選ぶ")
	# 左に巡礼者の立ち絵を置き、契約者の話とボタンはその右に並べる
	var portrait: TextureRect = Art.picture(Art.PILGRIM)
	portrait.position = PORTRAIT_RECT.position
	portrait.size = PORTRAIT_RECT.size
	add_child(portrait)
	layout.offset_left = PORTRAIT_RECT.end.x + 24
	UiKit.add_label(layout, "巡礼に出る契約者を選ぶ。契約者ごとに、最初に契約している精霊・英霊が違う。")
	for character_id: String in Contractors.CONTRACTORS:
		var character: Dictionary = Contractors.CONTRACTORS[character_id]
		UiKit.add_note(
			layout, "%s\n最初の契約: %s" % [character["story"], _deck_text(character_id)]
		)
		character_buttons[character_id] = UiKit.add_button(
			layout, "%s と巡礼に出る" % character["name"], chosen.emit.bind(character_id)
		)
	back_button = UiKit.add_button(layout, "戻る", back_requested.emit)
	character_buttons[Contractors.FIRST_CONTRACTOR].grab_focus()


## character_id の契約者の初期デッキの「名前 ×枚数」の並び (例: 「斬火 ×3、守りの風 ×3」)
func _deck_text(character_id: String) -> String:
	var counts: Dictionary = {}
	for card_id: String in Contractors.starter_deck(character_id):
		counts[card_id] = counts.get(card_id, 0) + 1
	var parts: Array[String] = []
	for card_id: String in counts:
		parts.append("%s ×%d" % [Cards.CARDS[card_id]["name"], counts[card_id]])
	return "、".join(parts)
