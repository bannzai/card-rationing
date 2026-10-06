extends RefCounted
## カードの定義 (契約した精霊・英霊) と、新しいランの初期デッキ。GDScript の定数で持つ理由は
## documents/DIRECTION.md「決めたこと」を参照。動作確認用の中身で、本番のカードは別の issue で入れ替える。
## 1 枚のカードの定義は CARDS の 1 要素 (キーがカード ID) で、効果は damage / block / draw の値で表す。

## カードの種別
enum Kind { ATTACK, GUARD, SKILL }
## 契約の相手の区分 (精霊は回数が多く、英霊は少ない)
enum Bond { SPIRIT, HERO }

## カード ID → 定義。max_uses が 1 回の巡礼 (ラン) で命令できる回数 (契約の回数)
const CARDS: Dictionary = {
	"slash":
	{
		"name": "斬撃",
		"kind": Kind.ATTACK,
		"bond": Bond.SPIRIT,
		"cost": 1,
		"max_uses": 4,
		"damage": 6,
	},
	"spirit_arrow":
	{
		"name": "精霊の矢",
		"kind": Kind.ATTACK,
		"bond": Bond.SPIRIT,
		"cost": 0,
		"max_uses": 3,
		"damage": 3,
	},
	"guard":
	{
		"name": "守り",
		"kind": Kind.GUARD,
		"bond": Bond.SPIRIT,
		"cost": 1,
		"max_uses": 4,
		"block": 5,
	},
	"breath":
	{
		"name": "深呼吸",
		"kind": Kind.SKILL,
		"bond": Bond.SPIRIT,
		"cost": 0,
		"max_uses": 3,
		"draw": 2,
	},
	"hero_strike":
	{
		"name": "英霊の一閃",
		"kind": Kind.ATTACK,
		"bond": Bond.HERO,
		"cost": 2,
		"max_uses": 1,
		"damage": 18,
	},
	"hero_wall":
	{
		"name": "英霊の盾",
		"kind": Kind.GUARD,
		"bond": Bond.HERO,
		"cost": 1,
		"max_uses": 1,
		"block": 12,
	},
}

## 新しいランの初期デッキ (カード ID の並び。同じ ID が複数あればその枚数だけ別のカードになる)
const STARTER_DECK: Array[String] = [
	"slash",
	"slash",
	"slash",
	"guard",
	"guard",
	"guard",
	"spirit_arrow",
	"breath",
	"hero_strike",
	"hero_wall",
]


## カードの効果を画面に出す短い文 (例: 「攻撃 6」「防御 5」「2 枚引く」)
static func effect_text(card_id: String) -> String:
	var card: Dictionary = CARDS[card_id]
	var parts: Array[String] = []
	if card.has("damage"):
		parts.append("攻撃 %d" % card["damage"])
	if card.has("block"):
		parts.append("防御 %d" % card["block"])
	if card.has("draw"):
		parts.append("%d 枚引く" % card["draw"])
	return " / ".join(parts)


## 使う時に敵を選ぶカードか (攻撃だけが対象を取る)
static func needs_target(card_id: String) -> bool:
	return CARDS[card_id]["kind"] == Kind.ATTACK
