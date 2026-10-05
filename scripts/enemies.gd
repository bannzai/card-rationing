extends RefCounted
## 敵の定義と、地図の節点ごとの敵の組み合わせ。動作確認用の中身で、本番の敵・強敵・ボスは 1 人目の契約者の
## 1 幕分の中身 (#9) で入れ替える。1 体の敵の定義は ENEMIES の 1 要素 (キーが敵 ID) で、moves は予告して
## 実行する行動の候補。

## 敵の行動の種別
enum Move { ATTACK, GUARD }
## 戦闘の格 (地図の節点の戦闘・強敵・ボスに対応する)
enum Tier { NORMAL, ELITE, BOSS }

## 敵 ID → 定義。moves の中から戦闘の乱数で次の行動を選ぶ
const ENEMIES: Dictionary = {
	"wild_dog":
	{
		"name": "野犬",
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
		"name": "骸骨兵",
		"hp": 22,
		"moves":
		[
			{"move": Move.ATTACK, "value": 7},
			{"move": Move.GUARD, "value": 6},
		],
	},
	"grave_knight":
	{
		"name": "墓守の騎士",
		"hp": 36,
		"moves":
		[
			{"move": Move.ATTACK, "value": 10},
			{"move": Move.ATTACK, "value": 5},
			{"move": Move.GUARD, "value": 8},
		],
	},
	"warden":
	{
		"name": "契約の番人",
		"hp": 60,
		"moves":
		[
			{"move": Move.ATTACK, "value": 12},
			{"move": Move.ATTACK, "value": 7},
			{"move": Move.GUARD, "value": 10},
		],
	},
}

## 前半の通常の戦闘の敵の組み合わせの候補 (各要素が 1 回の戦闘の敵 ID の並び。節点のシードで 1 つを選ぶ)
const NORMAL_EARLY: Array = [["wild_dog"], ["skeleton"]]
## 後半の通常の戦闘の敵の組み合わせの候補
const NORMAL_LATE: Array = [["wild_dog", "skeleton"], ["wild_dog", "wild_dog"]]
## 強敵の組み合わせの候補
const ELITES: Array = [["grave_knight"]]
## ボスの組み合わせの候補
const BOSSES: Array = [["warden"]]


## tier の格と前半 / 後半 (late) の敵の組み合わせの候補
static func candidates(tier: Tier, late: bool) -> Array:
	match tier:
		Tier.ELITE:
			return ELITES
		Tier.BOSS:
			return BOSSES
	return NORMAL_LATE if late else NORMAL_EARLY


## tier の格と前半 / 後半 (late) の候補から、seed_value で選んだ敵 ID の並び (同じシードなら同じ組み合わせ)
static func encounter(tier: Tier, late: bool, seed_value: int) -> Array[String]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var pool: Array = candidates(tier, late)
	var ids: Array[String] = []
	ids.assign(pool[rng.randi_range(0, pool.size() - 1)])
	return ids
