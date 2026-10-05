extends RefCounted
## 契約者 (プレイヤーキャラクター) の定義。巡礼の開始で選び、初期デッキが決まる。動作確認用の中身で、
## 1 人目の契約者の本番の中身 (#9) で入れ替える。1 人の定義は CHARACTERS の 1 要素 (キーが契約者 ID)。

const Cards := preload("res://scripts/cards.gd")

## 契約者 ID → 定義。deck は初期デッキのカード ID の並び
const CHARACTERS: Dictionary = {
	"pilgrim":
	{
		"name": "巡礼者",
		"description": "精霊と英霊に少しずつ契約を結んだ、最初の巡礼者。",
		"deck": Cards.STARTER_DECK,
	},
}
## 新しいランで契約者を指定しない時の契約者 (今は契約者が 1 人だけのため、その 1 人)
const DEFAULT_CHARACTER: String = "pilgrim"
