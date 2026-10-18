extends RefCounted
## カードの定義 (契約した精霊・英霊)。GDScript の定数で持つ理由と、回数の配分・強さの定義の考え方は
## documents/DIRECTION.md「決めたこと」を参照。契約者ごとの初期デッキは scripts/contractors.gd が持つ。
## 1 枚のカードの定義は CARDS の 1 要素 (キーがカード ID) で、効果は次のキーの値で表す。
## damage (1 回のダメージ)・hits (damage を与える回数。省略は 1)・area (true なら生きている敵すべてに与える)・
## block (防御)・draw (引く枚数)・energy (このターンに得るエネルギー)。
## 加護 (Kind.POWER) のカードは使った時の効果を持たず、その戦闘の終わりまで続く効果を POWER_TURN_POINTS のキーの値で表す。
## turn_block (毎ターンの始めの防御)・turn_draw (毎ターンの始めに多く引く枚数)・turn_energy (毎ターンの始めに
## 多く得るエネルギー)・attack_bonus (攻撃カードの 1 回のダメージに足す値)・struggle_bonus (もがくのダメージに足す値)

## カードの種別 (POWER は画面では「加護」と呼ぶ)
enum Kind { ATTACK, GUARD, SKILL, POWER }
## 契約の相手の区分 (精霊は回数が多く、英霊は強く回数が少ない)
enum Bond { SPIRIT, HERO }

## 契約の相手の区分の表示名
const BOND_NAMES: Dictionary = {Bond.SPIRIT: "精霊", Bond.HERO: "英霊"}
## 加護の呼び名 (カードの区分の表示と、戦闘画面の発動中の一覧の見出しに使う)
const POWER_NAME: String = "加護"

## カード ID → 定義。max_uses が 1 回の巡礼 (ラン) で命令できる回数 (契約の回数)
const CARDS: Dictionary = {
	"slash":
	{
		"name": "斬火",
		"kind": Kind.ATTACK,
		"bond": Bond.SPIRIT,
		"cost": 1,
		"max_uses": 6,
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
	"lamp_ward":
	{
		"name": "灯守りの精",
		"kind": Kind.POWER,
		"bond": Bond.SPIRIT,
		"cost": 1,
		"max_uses": 3,
		"turn_block": 3,
	},
	"guiding_light":
	{
		"name": "導きの灯",
		"kind": Kind.POWER,
		"bond": Bond.SPIRIT,
		"cost": 1,
		"max_uses": 3,
		"turn_draw": 1,
	},
	"ember_heart":
	{
		"name": "熾りの精",
		"kind": Kind.POWER,
		"bond": Bond.SPIRIT,
		"cost": 1,
		"max_uses": 4,
		"attack_bonus": 1,
	},
	"defiant_spark":
	{
		"name": "抗いの火",
		"kind": Kind.POWER,
		"bond": Bond.SPIRIT,
		"cost": 1,
		"max_uses": 3,
		"struggle_bonus": 3,
	},
	"war_banner":
	{
		"name": "戦旗の英霊",
		"kind": Kind.POWER,
		"bond": Bond.HERO,
		"cost": 1,
		"max_uses": 1,
		"attack_bonus": 3,
	},
	"lighthouse_keeper":
	{
		"name": "灯台守の英霊",
		"kind": Kind.POWER,
		"bond": Bond.HERO,
		"cost": 0,
		"max_uses": 1,
		"turn_energy": 1,
	},
}

## 強さの計算で、引く 1 枚と得るエネルギー 1 を何点とみなすか (ダメージと防御は 1 につき 1 点)。
## 基準のカード (斬火: コスト 1 で攻撃 6) の強さ 3 = 手札 1 枚ぶんの価値で、1 枚引くことは手札 1 枚を
## 取り戻すのと同じ、エネルギー 1 はコスト 1 を取り戻すのと同じとみなす
const DRAW_POINTS: float = 3.0
const ENERGY_POINTS: float = 3.0
## 全体攻撃のダメージの倍率 (1 幕の戦闘の敵は 1〜2 体のため、1 体ぶんより大きく 2 体ぶんより小さくする)
const AREA_RATE: float = 1.5
## 加護の効果のキー → 値 1 が 1 ターンに生む点数。防御 1 は 1 点、引く 1 枚とエネルギー 1 は DRAW_POINTS と
## ENERGY_POINTS、攻撃の上乗せ 1 は 1 ターンに使う攻撃カードを 2 枚 (エネルギー 3 を攻撃 2・防御 1 に使う配分) と
## みなして 2 点、もがくの上乗せ 1 は 1 ターンに 1 回もがくとみなして 1 点
const POWER_TURN_POINTS: Dictionary = {
	"turn_block": 1.0,
	"turn_draw": DRAW_POINTS,
	"turn_energy": ENERGY_POINTS,
	"attack_bonus": 2.0,
	"struggle_bonus": 1.0,
}
## 1 ターンに敵に与えるダメージの見込み (攻撃カード 2 枚。基準の斬火 6 × 2)。加護が効くターンの数の見込みに使う
const TURN_DAMAGE: int = 12
## 強さの計算で、加護が効くとみなすターンの数。1 ターンに TURN_DAMAGE を与えるとみなすと、前半の敵 (体力 10〜22) は
## 1〜2 ターン、強敵とボス (体力 48〜66) は 4〜6 ターンで倒れる。戦闘の最初のターンに使い、残りのターンに効くと
## みなして 3 にした
const POWER_TURNS: float = 3.0


## カードの強さ。効果の点数 ÷ (コスト + 1) で、最大使用回数は含めない (定義は documents/DIRECTION.md
## 「決めたこと」)。分母の + 1 は、使うと手札 1 枚を消費するぶん。加護の効果の点数は、1 ターンの点数
## (power_turn_points()) × POWER_TURNS
static func strength(card_id: String) -> float:
	var card: Dictionary = CARDS[card_id]
	var points: float = (
		float(card.get("damage", 0) * card.get("hits", 1))
		* (AREA_RATE if card.get("area", false) else 1.0)
	)
	points += card.get("block", 0)
	points += card.get("draw", 0) * DRAW_POINTS
	points += card.get("energy", 0) * ENERGY_POINTS
	points += power_turn_points(card_id) * POWER_TURNS
	return points / (card["cost"] + 1)


## 加護のカードの効果が 1 ターンに生む点数 (POWER_TURN_POINTS。加護でなければ 0)
static func power_turn_points(card_id: String) -> float:
	var card: Dictionary = CARDS[card_id]
	var points: float = 0.0
	for key: String in POWER_TURN_POINTS:
		points += card.get(key, 0) * POWER_TURN_POINTS[key]
	return points


## カードの効果を画面に出す短い文 (例: 「攻撃 6」「攻撃 4×2」「全体攻撃 4」「防御 5」「2 枚引く」。加護は
## 「戦闘の間 毎ターン防御 3」)
static func effect_text(card_id: String) -> String:
	var card: Dictionary = CARDS[card_id]
	if card["kind"] == Kind.POWER:
		return "戦闘の間 " + power_text(card_id)
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


## 加護のカードの続く効果の短い文 (例: 「毎ターン防御 3」「攻撃のダメージ +1」。加護でなければ空)
static func power_text(card_id: String) -> String:
	var card: Dictionary = CARDS[card_id]
	var parts: Array[String] = []
	if card.has("turn_block"):
		parts.append("毎ターン防御 %d" % card["turn_block"])
	if card.has("turn_draw"):
		parts.append("毎ターン %d 枚多く引く" % card["turn_draw"])
	if card.has("turn_energy"):
		parts.append("毎ターン エネルギー +%d" % card["turn_energy"])
	if card.has("attack_bonus"):
		parts.append("攻撃のダメージ +%d" % card["attack_bonus"])
	if card.has("struggle_bonus"):
		parts.append("もがくのダメージ +%d" % card["struggle_bonus"])
	return " / ".join(parts)


## 使う時に敵を選ぶカードか (全体攻撃でない攻撃だけが対象を取る)
static func needs_target(card_id: String) -> bool:
	var card: Dictionary = CARDS[card_id]
	return card.has("damage") and not card.get("area", false)
