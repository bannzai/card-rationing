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
		"hp": 32,
		"in_order": true,
		"moves":
		[
			{"move": Move.GUARD, "value": 8},
			{"move": Move.ATTACK, "value": 11},
		],
	},
	"ash_hound":
	{
		"name": "灰の猟犬",
		"rank": Rank.NORMAL,
		"hp": 26,
		"moves":
		[
			{"move": Move.ATTACK, "value": 5, "hits": 2},
			{"move": Move.ATTACK, "value": 9},
		],
	},
	"fallen_guard":
	{
		"name": "堕ちた番兵",
		"rank": Rank.NORMAL,
		"hp": 38,
		"in_order": true,
		"moves":
		[
			{"move": Move.ATTACK, "value": 12},
			{"move": Move.GUARD, "value": 10},
			{"move": Move.ATTACK, "value": 6, "hits": 2},
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
		"hp": 72,
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
		"hp": 150,
		"in_order": true,
		"moves":
		[
			{"move": Move.ATTACK, "value": 8, "hits": 2},
			{"move": Move.GUARD, "value": 20},
			{"move": Move.ATTACK, "value": 26},
			{"move": Move.ATTACK, "value": 5, "hits": 4},
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


## 敵の格 (Rank の値) と、幕の後半か (late_half) に応じた敵の組み合わせの候補。地図 (#7) が節点の種類と
## 階層から選ぶ
static func encounter_candidates(rank: int, late_half: bool) -> Array:
	if rank == Rank.BOSS:
		return [BOSS_ENCOUNTER]
	return (LATE_ENCOUNTERS if late_half else EARLY_ENCOUNTERS)[rank]


## 地図 (#7) ができるまでの仮の 1 幕の道順。前半の戦闘 → 前半の強敵 → 後半の戦闘 → 後半の強敵 → ボスの順に、
## 候補を並び順に 1 つずつ戦う
static func provisional_route() -> Array:
	var route: Array = []
	for late_half: bool in [false, true]:
		for rank: int in [Rank.NORMAL, Rank.ELITE]:
			route.append_array(encounter_candidates(rank, late_half))
	route.append(BOSS_ENCOUNTER)
	return route


## 仮の道順で、階層 (0 始まり) に対応する敵 ID の並び。末尾 (ボス) より先の階層は末尾を繰り返す
static func encounter_for_floor(floor_index: int) -> Array[String]:
	var route: Array = provisional_route()
	var ids: Array[String] = []
	ids.assign(route[mini(floor_index, route.size() - 1)])
	return ids
