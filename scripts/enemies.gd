extends RefCounted
## 敵の定義と、戦闘ごとの敵の組み合わせ。動作確認用の中身で、本番の敵は別の issue で入れ替える。
## 1 体の敵の定義は ENEMIES の 1 要素 (キーが敵 ID) で、moves は予告して実行する行動の候補。

## 敵の行動の種別
enum Move { ATTACK, GUARD }

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
}

## 階層 (0 始まり) ごとの敵の組み合わせ。末尾より先の階層は末尾を繰り返す
const ENCOUNTERS: Array = [
	["wild_dog"],
	["wild_dog", "skeleton"],
]


## 階層に対応する敵 ID の並び
static func encounter_for_floor(floor_index: int) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(ENCOUNTERS[mini(floor_index, ENCOUNTERS.size() - 1)])
	return ids
