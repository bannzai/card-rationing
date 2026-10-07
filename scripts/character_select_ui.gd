extends Control
## 巡礼の開始で契約者 (プレイヤーキャラクター) を選ぶ画面。契約者ごとに名前・説明・初期デッキを並べ、選んだら
## chosen を、戻るなら back_requested を出す (巡礼の開始は scripts/main.gd が行う)。

## character_id の契約者が選ばれた
signal chosen(character_id: String)
## 前の画面へ戻る
signal back_requested

const Cards := preload("res://scripts/cards.gd")
const Contractors := preload("res://scripts/contractors.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

## 契約者 ID → その契約者を選ぶボタン
var character_buttons: Dictionary = {}
## 前の画面へ戻るボタン
var back_button: Button = null


## 画面のノードを組み立てる
func _ready() -> void:
	var layout: VBoxContainer = UiKit.screen_layout(self, "契約者を選ぶ")
	UiKit.add_label(layout, "巡礼に出る契約者を選ぶ。契約者ごとに、最初に契約している精霊・英霊が違う。")
	for character_id: String in Contractors.CONTRACTORS:
		var character: Dictionary = Contractors.CONTRACTORS[character_id]
		var button: Button = UiKit.add_button(
			layout,
			"%s\n%s\n初期デッキ: %s" % [character["name"], character["story"], _deck_text(character_id)],
			chosen.emit.bind(character_id)
		)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# 契約者の話は 1 行に収まらない長さがあるため、画面の幅で折り返す
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		character_buttons[character_id] = button
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
