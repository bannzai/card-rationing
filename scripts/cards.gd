extends RefCounted
## カードの定義 (契約した精霊・英霊)。GDScript の定数で持つ理由と、回数の配分・強さの定義の考え方は
## documents/DIRECTION.md「決めたこと」を参照。契約者ごとの初期デッキは scripts/contractors.gd が持つ。
## 1 枚のカードの定義は CARDS の 1 要素 (キーがカード ID) で、効果は次のキーの値で表す。
## damage (1 回のダメージ)・hits (damage を与える回数。省略は 1)・area (true なら生きている敵すべてに与える)・
## block (防御)・draw (引く枚数)・energy (このターンに得るエネルギー)

## カードの種別
enum Kind { ATTACK, GUARD, SKILL }
## 契約の相手の区分 (精霊は回数が多く、英霊は強く回数が少ない)
enum Bond { SPIRIT, HERO }

## カード ID → 定義。max_uses が 1 回の巡礼 (ラン) で命令できる回数 (契約の回数)
const CARDS: Dictionary = {
	"slash":
	{
		"name": "斬火",
		"kind": Kind.ATTACK,
		"bond": Bond.SPIRIT,
		"cost": 1,
		"max_uses": 5,
		"damage": 6,
	},
	"spirit_arrow":
	{
		"name": "火の粉",
		"kind": Kind.ATTACK,
		"bond": Bond.SPIRIT,
		"cost": 0,
		"max_uses": 3,
		"damage": 3,
	},
	"twin_flame":
	{
		"name": "双つ灯",
		"kind": Kind.ATTACK,
		"bond": Bond.SPIRIT,
		"cost": 1,
		"max_uses": 3,
		"damage": 4,
		"hits": 2,
	},
	"ember_wave":
	{
		"name": "熾火の波",
		"kind": Kind.ATTACK,
		"bond": Bond.SPIRIT,
		"cost": 1,
		"max_uses": 4,
		"damage": 4,
		"area": true,
	},
	"wind_cut":
	{
		"name": "風切りの精",
		"kind": Kind.ATTACK,
		"bond": Bond.SPIRIT,
		"cost": 1,
		"max_uses": 3,
		"damage": 5,
		"draw": 1,
	},
	"wax_needle":
	{
		"name": "蝋の針",
		"kind": Kind.ATTACK,
		"bond": Bond.SPIRIT,
		"cost": 0,
		"max_uses": 3,
		"damage": 4,
	},
	"ash_fang":
	{
		"name": "灰の牙",
		"kind": Kind.ATTACK,
		"bond": Bond.SPIRIT,
		"cost": 2,
		"max_uses": 2,
		"damage": 13,
	},
	"hero_strike":
	{
		"name": "雷槍の英霊",
		"kind": Kind.ATTACK,
		"bond": Bond.HERO,
		"cost": 2,
		"max_uses": 1,
		"damage": 18,
	},
	"old_blade":
	{
		"name": "古剣の英霊",
		"kind": Kind.ATTACK,
		"bond": Bond.HERO,
		"cost": 1,
		"max_uses": 1,
		"damage": 7,
		"hits": 2,
	},
	"flame_king":
	{
		"name": "焔王の英霊",
		"kind": Kind.ATTACK,
		"bond": Bond.HERO,
		"cost": 3,
		"max_uses": 1,
		"damage": 16,
		"area": true,
	},
	"archer":
	{
		"name": "射手の英霊",
		"kind": Kind.ATTACK,
		"bond": Bond.HERO,
		"cost": 1,
		"max_uses": 2,
		"damage": 4,
		"hits": 3,
	},
	"guard":
	{
		"name": "守りの風",
		"kind": Kind.GUARD,
		"bond": Bond.SPIRIT,
		"cost": 1,
		"max_uses": 5,
		"block": 5,
	},
	"shade":
	{
		"name": "灯影",
		"kind": Kind.GUARD,
		"bond": Bond.SPIRIT,
		"cost": 0,
		"max_uses": 4,
		"block": 3,
	},
	"mist_veil":
	{
		"name": "霧の帳",
		"kind": Kind.GUARD,
		"bond": Bond.SPIRIT,
		"cost": 1,
		"max_uses": 3,
		"block": 8,
	},
	"moss_cloak":
	{
		"name": "苔の衣",
		"kind": Kind.GUARD,
		"bond": Bond.SPIRIT,
		"cost": 1,
		"max_uses": 3,
		"block": 6,
		"draw": 1,
	},
	"soot_wall":
	{
		"name": "煤の壁",
		"kind": Kind.GUARD,
		"bond": Bond.SPIRIT,
		"cost": 2,
		"max_uses": 3,
		"block": 12,
	},
	"hero_wall":
	{
		"name": "盾の英霊",
		"kind": Kind.GUARD,
		"bond": Bond.HERO,
		"cost": 1,
		"max_uses": 1,
		"block": 12,
	},
	"castle_keeper":
	{
		"name": "城守の英霊",
		"kind": Kind.GUARD,
		"bond": Bond.HERO,
		"cost": 2,
		"max_uses": 1,
		"block": 20,
	},
	"saint":
	{
		"name": "聖女の英霊",
		"kind": Kind.GUARD,
		"bond": Bond.HERO,
		"cost": 1,
		"max_uses": 1,
		"block": 8,
		"draw": 2,
	},
	"breath":
	{
		"name": "灯の精",
		"kind": Kind.SKILL,
		"bond": Bond.SPIRIT,
		"cost": 0,
		"max_uses": 3,
		"draw": 2,
	},
	"whirlwind":
	{
		"name": "つむじ風",
		"kind": Kind.SKILL,
		"bond": Bond.SPIRIT,
		"cost": 0,
		"max_uses": 5,
		"draw": 1,
	},
	"candle_flame":
	{
		"name": "蝋燭の火",
		"kind": Kind.SKILL,
		"bond": Bond.SPIRIT,
		"cost": 0,
		"max_uses": 3,
		"energy": 1,
	},
	"night_whisper":
	{
		"name": "夜風の囁き",
		"kind": Kind.SKILL,
		"bond": Bond.SPIRIT,
		"cost": 1,
		"max_uses": 3,
		"draw": 3,
	},
	"lantern_row":
	{
		"name": "灯の連なり",
		"kind": Kind.SKILL,
		"bond": Bond.SPIRIT,
		"cost": 1,
		"max_uses": 3,
		"draw": 2,
		"energy": 1,
	},
	"sage":
	{
		"name": "賢者の英霊",
		"kind": Kind.SKILL,
		"bond": Bond.HERO,
		"cost": 0,
		"max_uses": 1,
		"draw": 3,
		"energy": 1,
	},
	"old_king":
	{
		"name": "古王の宣告",
		"kind": Kind.SKILL,
		"bond": Bond.HERO,
		"cost": 0,
		"max_uses": 1,
		"draw": 1,
		"energy": 2,
	},
	"shrine_maiden":
	{
		"name": "巫女の英霊",
		"kind": Kind.SKILL,
		"bond": Bond.HERO,
		"cost": 1,
		"max_uses": 2,
		"draw": 3,
		"energy": 2,
	},
}

## 強さの計算で、引く 1 枚と得るエネルギー 1 を何点とみなすか (ダメージと防御は 1 につき 1 点)。
## 基準のカード (斬火: コスト 1 で攻撃 6) の強さ 3 = 手札 1 枚ぶんの価値で、1 枚引くことは手札 1 枚を
## 取り戻すのと同じ、エネルギー 1 はコスト 1 を取り戻すのと同じとみなす
const DRAW_POINTS: float = 3.0
const ENERGY_POINTS: float = 3.0
## 全体攻撃のダメージの倍率 (1 幕の戦闘の敵は 1〜2 体のため、1 体ぶんより大きく 2 体ぶんより小さくする)
const AREA_RATE: float = 1.5


## カードの強さ。効果の点数 ÷ (コスト + 1) で、最大使用回数は含めない (定義は documents/DIRECTION.md
## 「決めたこと」)。分母の + 1 は、使うと手札 1 枚を消費するぶん
static func strength(card_id: String) -> float:
	var card: Dictionary = CARDS[card_id]
	var points: float = (
		float(card.get("damage", 0) * card.get("hits", 1))
		* (AREA_RATE if card.get("area", false) else 1.0)
	)
	points += card.get("block", 0)
	points += card.get("draw", 0) * DRAW_POINTS
	points += card.get("energy", 0) * ENERGY_POINTS
	return points / (card["cost"] + 1)


## カードの効果を画面に出す短い文 (例: 「攻撃 6」「攻撃 4×2」「全体攻撃 4」「防御 5」「2 枚引く」)
static func effect_text(card_id: String) -> String:
	var card: Dictionary = CARDS[card_id]
	var parts: Array[String] = []
	if card.has("damage"):
		var hits: int = card.get("hits", 1)
		parts.append(
			(
				("全体攻撃 %d" if card.get("area", false) else "攻撃 %d") % card["damage"]
				+ ("×%d" % hits if hits > 1 else "")
			)
		)
	if card.has("block"):
		parts.append("防御 %d" % card["block"])
	if card.has("draw"):
		parts.append("%d 枚引く" % card["draw"])
	if card.has("energy"):
		parts.append("エネルギー +%d" % card["energy"])
	return " / ".join(parts)


## 使う時に敵を選ぶカードか (全体攻撃でない攻撃だけが対象を取る)
static func needs_target(card_id: String) -> bool:
	var card: Dictionary = CARDS[card_id]
	return card.has("damage") and not card.get("area", false)
