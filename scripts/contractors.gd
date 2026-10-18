extends RefCounted
## 契約者 (プレイヤーキャラクター) の定義。1 人の定義は CONTRACTORS の 1 要素 (キーが契約者 ID) で、
## starter_deck が新しい巡礼 (ラン) の初期デッキ (カード ID の並び。同じ ID が複数あればその枚数だけ別のカード)、
## max_hp が巡礼の始まりの体力と最大体力。巡礼の開始で契約者の選択画面 (scripts/character_select_ui.gd) から選ぶ。
## 個性 (常に効く固有の効果) は trait_name (画面に出す名前) と、次のキーの値で表す (省略は 0。画面に出す説明は
## trait_lines() が値から作る)。hand_bonus (毎ターン引く枚数に足す数)・energy_bonus (毎ターンのエネルギーに
## 足す数)・win_restore (通常の戦闘と強敵に勝つたびに、契約切れでない精霊のうち減っている回数が最も多い 1 枚の
## 残り使用回数を戻す回数)。個性はラン単位の状態 (scripts/run_state.gd) の契約者 ID から決まり、保存データには契約者 ID だけを
## 持つ。契約者の一覧・個性・決めた理由は documents/DIRECTION.md「決めたこと」。

## 契約者 ID → 定義
const CONTRACTORS: Dictionary = {
	"yura":
	{
		"name": "灯持ちのユラ",
		"story":
		(
			"消えかけた祠の灯を継ぐために巡礼に出た灯守りの娘。"
			+ "幼いころ誰かに結ばされた印で、小さな精霊と二柱の英霊を呼ぶ。"
		),
		"max_hp": 40,
		"trait_name": "灯守り",
		"win_restore": 1,
		"starter_deck":
		[
			"slash",
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
		],
	},
	"shion":
	{
		"name": "綴り手のシオン",
		"story":
		(
			"結ばれた契約を一つ残らず書き留める写本の綴り手。"
			+ "頁をめくるように多くの印を一度に読むが、筆より重いものを持ったことがない。"
		),
		"max_hp": 30,
		"trait_name": "多読",
		"hand_bonus": 2,
		"starter_deck":
		[
			"slash",
			"slash",
			"slash",
			"slash",
			"wax_needle",
			"guard",
			"guard",
			"guard",
			"shade",
			"hero_strike",
			"hero_wall",
		],
	},
	"kagari":
	{
		"name": "熾火のカガリ",
		"story":
		(
			"祠の火を絶やさぬよう熾火を担いで歩く火守り。"
			+ "火の気で精霊を急き立てて多く命じるが、そのぶん契約も早く尽きる。"
		),
		"max_hp": 22,
		"trait_name": "熾火",
		"energy_bonus": 1,
		"starter_deck":
		[
			"slash",
			"slash",
			"slash",
			"slash",
			"slash",
			"twin_flame",
			"guard",
			"guard",
			"soot_wall",
			"hero_strike",
			"hero_wall",
		],
	},
}
## 契約者を指定しない新しい巡礼 (起動時・検証) で使う契約者と、契約者の選択画面で最初にフォーカスする契約者
const FIRST_CONTRACTOR: String = "yura"


## 契約者の初期デッキ (カード ID の並び)
static func starter_deck(contractor_id: String) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(CONTRACTORS[contractor_id]["starter_deck"])
	return ids


## 契約者の個性の値 (key は hand_bonus・energy_bonus・win_restore。定義に無ければ 0)
static func trait_value(contractor_id: String, key: String) -> int:
	return CONTRACTORS[contractor_id].get(key, 0)


## 契約者の個性の効果を画面に出す行の並び (値が 0 の効果は出さない)
static func trait_lines(contractor_id: String) -> Array[String]:
	var lines: Array[String] = []
	var hand_bonus: int = trait_value(contractor_id, "hand_bonus")
	if hand_bonus > 0:
		lines.append("毎ターン引く枚数 +%d" % hand_bonus)
	var energy_bonus: int = trait_value(contractor_id, "energy_bonus")
	if energy_bonus > 0:
		lines.append("毎ターンのエネルギー +%d" % energy_bonus)
	var win_restore: int = trait_value(contractor_id, "win_restore")
	if win_restore > 0:
		lines.append("戦闘に勝つたび (ボスを除く) 契約切れでない精霊で最も減った 1 枚の残りを %d 回戻す" % win_restore)
	return lines
