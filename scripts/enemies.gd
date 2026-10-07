extends RefCounted
## 敵の定義と、敵の格 (戦闘・強敵・ボス) と幕の前半・後半ごとの敵の組み合わせの候補。配置の考え方は
## documents/DIRECTION.md「決めたこと」を参照。
## 1 体の敵の定義は ENEMIES の 1 要素 (キーが敵 ID) で、moves は予告して実行する行動の候補。in_order が true の敵は
## moves を先頭から順に繰り返し、それ以外は戦闘の乱数で選ぶ。攻撃の行動の hits は value を与える回数 (省略は 1)。
## ボスの talk はボス戦の前の会話の台詞 (scenes/boss_talk.tscn が 1 行ずつ出す)。

## 敵の行動の種別
enum Move { ATTACK, GUARD }
## 敵の格 (地図の節点の種類のうち戦闘になるもの)
enum Rank { NORMAL, ELITE, BOSS }

## 敵 ID → 定義
const ENEMIES: Dictionary = {
	"wild_dog":
	{
		"name": "影の野犬",
		"rank": Rank.NORMAL,
		"hp": 14,
		"moves":
		[
			{"move": Move.ATTACK, "value": 5},
			{"move": Move.ATTACK, "value": 3},
			{"move": Move.GUARD, "value": 4},
		],
	},
	"skeleton":
	{
		"name": "骸の巡礼者",
		"rank": Rank.NORMAL,
		"hp": 22,
		"moves":
		[
			{"move": Move.ATTACK, "value": 7},
			{"move": Move.GUARD, "value": 6},
		],
	},
	"wisp":
	{
		"name": "迷い火",
		"rank": Rank.NORMAL,
		"hp": 10,
		"moves":
		[
			{"move": Move.ATTACK, "value": 2, "hits": 2},
			{"move": Move.ATTACK, "value": 4},
		],
	},
	"moth":
	{
		"name": "煤蛾",
		"rank": Rank.NORMAL,
		"hp": 12,
		"in_order": true,
		"moves":
		[
			{"move": Move.ATTACK, "value": 3},
			{"move": Move.ATTACK, "value": 2, "hits": 3},
		],
	},
	"wax_doll":
	{
		"name": "蝋の人形",
		"rank": Rank.NORMAL,
		"hp": 26,
		"in_order": true,
		"moves":
		[
			{"move": Move.GUARD, "value": 8},
			{"move": Move.ATTACK, "value": 8},
		],
	},
	"ash_hound":
	{
		"name": "灰の猟犬",
		"rank": Rank.NORMAL,
		"hp": 23,
		"moves":
		[
			{"move": Move.ATTACK, "value": 3, "hits": 2},
			{"move": Move.ATTACK, "value": 7},
		],
	},
	"fallen_guard":
	{
		"name": "堕ちた番兵",
		"rank": Rank.NORMAL,
		"hp": 30,
		"in_order": true,
		"moves":
		[
			{"move": Move.ATTACK, "value": 9},
			{"move": Move.GUARD, "value": 10},
			{"move": Move.ATTACK, "value": 4, "hits": 2},
		],
	},
	"candle_warden":
	{
		"name": "燭台の守り手",
		"rank": Rank.ELITE,
		"hp": 48,
		"in_order": true,
		"moves":
		[
			{"move": Move.ATTACK, "value": 6, "hits": 2},
			{"move": Move.GUARD, "value": 12},
			{"move": Move.ATTACK, "value": 16},
		],
	},
	"seal_knight":
	{
		"name": "封蝋の騎士",
		"rank": Rank.ELITE,
		"hp": 56,
		"in_order": true,
		"moves":
		[
			{"move": Move.ATTACK, "value": 9, "hits": 2},
			{"move": Move.GUARD, "value": 16},
			{"move": Move.ATTACK, "value": 24},
		],
	},
	"wick_eater":
	{
		"name": "灯喰らいの司祭",
		"rank": Rank.BOSS,
		"hp": 80,
		"in_order": true,
		"moves":
		[
			{"move": Move.ATTACK, "value": 6, "hits": 2},
			{"move": Move.GUARD, "value": 8},
			{"move": Move.ATTACK, "value": 18},
			{"move": Move.ATTACK, "value": 4, "hits": 3},
		],
		"talk":
		[
			"その手の印、まだ焼け残っているのか。",
			"誰に結ばされたかも知らずに、よくここまで命じてきたものだ。",
			"最後の一回を命じた時、印が代わりに何を持っていくか。あの方は教えなかったろう。",
			"よい。ここで燃え尽きるなら、それもあの方の望みだ。",
		],
	},
}

## 幕の前半の、敵の格 (Rank.NORMAL / Rank.ELITE) → 敵の組み合わせ (敵 ID の並び) の候補
const EARLY_ENCOUNTERS: Dictionary = {
	Rank.NORMAL: [["wild_dog"], ["wild_dog", "skeleton"], ["wisp", "moth"], ["skeleton", "wisp"]],
	Rank.ELITE: [["candle_warden"]],
}
## 幕の後半の、敵の格 → 敵の組み合わせの候補 (前半より強い敵だけで組む)
const LATE_ENCOUNTERS: Dictionary = {
	Rank.NORMAL: [["wax_doll"], ["ash_hound"], ["fallen_guard"], ["wax_doll", "ash_hound"]],
	Rank.ELITE: [["seal_knight"]],
}
## 幕の最後のボス戦の敵 (ボスは前半・後半の区別なくこの組み合わせ)
const BOSS_ENCOUNTER: Array[String] = ["wick_eater"]


## 敵の格 (Rank の値) と、幕の後半か (late_half) に応じた敵の組み合わせの候補。地図の節点の種類と段で
## scripts/run_flow.gd の encounter() が選ぶ
static func encounter_candidates(rank: int, late_half: bool) -> Array:
	if rank == Rank.BOSS:
		return [BOSS_ENCOUNTER]
	return (LATE_ENCOUNTERS if late_half else EARLY_ENCOUNTERS)[rank]


## 敵の格 (Rank の値) と幕の後半か (late_half) の候補から、seed_value で選んだ敵 ID の並び (同じシードなら
## 同じ組み合わせ。地図の節点のシードを渡す)
static func encounter(rank: int, late_half: bool, seed_value: int) -> Array[String]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var candidates: Array = encounter_candidates(rank, late_half)
	var ids: Array[String] = []
	ids.assign(candidates[rng.randi_range(0, candidates.size() - 1)])
	return ids
