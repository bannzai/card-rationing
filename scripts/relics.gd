extends RefCounted
## 護符 (持っている間、ランを通してずっと効く持ち物。Slay the Spire のレリックに当たる) の定義と、確率で働く
## 護符の乱数。1 つの護符の定義は RELICS の 1 要素 (キーが護符 ID) で、name (名前)・glyph (戦闘画面の印に書く
## 漢字 1 字)・text (効果の説明) と、効果の数値を持つ。効果を出す処理は、効く場面のスクリプト (戦闘は
## scripts/battle.gd、戦闘の後の体力と所持金は scripts/run_flow.gd、商人の値段は scripts/node_rules.gd) が
## RunState.relics で確かめて行う。一覧・手に入る経路・確率の扱いの根拠は documents/DIRECTION.md「決めたこと」。
## scripts/run_state.gd から読まれるため、絵を preload しない (scripts/art.gd の冒頭の理由)。

const Cards := preload("res://scripts/cards.gd")

## 焼けぬ封蝋で残り使用回数が減らない確率
const SPARE_CHANCE: float = 0.5
## 確率の乱数のシードを作る時に、地図のシードに掛ける値 (通し番号と足して、地図のシードごとに別の乱数列に
## するためで、通し番号の上限 (1 ランで引く回数) より十分大きい素数なら値に意味は無い)
const ROLL_SEED_STRIDE: int = 1000003

## 護符 ID → 定義。並びは、手に入る護符を選ぶ時の候補の順 (ID の順で並べ直すので、ここの順に意味は無い)
const RELICS: Dictionary = {
	"ember_edge":
	{
		"name": "熾火の刃",
		"glyph": "刃",
		"text": "攻撃カードのダメージ +1 (1 回ごと)",
		"damage": 1,
	},
	"unburnt_seal":
	{
		"name": "焼けぬ封蝋",
		"glyph": "封",
		"text": "精霊のカードを使った時 1/2 で残り使用回数が減らない (英霊と最後の 1 回には効かない)",
	},
	"last_rite":
	{
		"name": "最後の祈り",
		"glyph": "祈",
		"text": "最後の 1 回のカードはダメージ +3 (1 回ごと)・防御 +3",
		"damage": 3,
		"block": 3,
	},
	"mended_ledger":
	{
		"name": "繕いの帳面",
		"glyph": "帳",
		"text": "商人で残り使用回数を戻す値段が 20",
		"restore_price": 20,
	},
	"wax_ward":
	{
		"name": "蝋の盾",
		"glyph": "盾",
		"text": "戦闘の始めに防御 6",
		"block": 6,
	},
	"dawn_wick":
	{
		"name": "夜明けの灯芯",
		"glyph": "灯",
		"text": "戦闘の最初のターンにエネルギー +1",
		"energy": 1,
	},
	"pilgrim_beads":
	{
		"name": "巡礼の数珠",
		"glyph": "珠",
		"text": "戦闘に勝った時の体力の回復 +4",
		"heal": 4,
	},
	"coin_pouch":
	{
		"name": "旅の銭袋",
		"glyph": "銭",
		"text": "戦闘に勝った時の所持金 +8",
		"gold": 8,
	},
}


## owned (持っている護符 ID の並び) に relic_id があれば、その護符の効果の数値 key (無ければ 0)
static func value(owned: Array[String], relic_id: String, key: String) -> int:
	if not owned.has(relic_id):
		return 0
	return RELICS[relic_id].get(key, 0)


## owned (持っている護符 ID の並び) に無い護符のうち、seed_value から選んだ 1 つ (seed_value が同じなら同じ。
## すべて持っていれば空文字)
static func pick_unowned(owned: Array[String], seed_value: int) -> String:
	var pool: Array[String] = []
	for relic_id: String in RELICS:
		if not owned.has(relic_id):
			pool.append(relic_id)
	if pool.is_empty():
		return ""
	pool.sort()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return pool[rng.randi_range(0, pool.size() - 1)]


## 焼けぬ封蝋が効くカードか (精霊で、使う前の残り使用回数が 2 回以上。英霊と最後の 1 回は必ず焼ける)
static func can_spare(card_id: String, uses_before: int) -> bool:
	return Cards.CARDS[card_id]["bond"] == Cards.Bond.SPIRIT and uses_before >= 2


## 地図のシード map_seed のランで、roll_index 回目 (0 始まり) に引く焼けぬ封蝋の判定 (true なら減らない)。
## 地図のシードと通し番号だけで決まり、同じ組なら同じ結果になる
static func roll_spare(map_seed: int, roll_index: int) -> bool:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = map_seed * ROLL_SEED_STRIDE + roll_index
	return rng.randf() < SPARE_CHANCE
