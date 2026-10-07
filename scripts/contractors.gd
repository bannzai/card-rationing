extends RefCounted
## 契約者 (プレイヤーキャラクター) の定義。1 人の定義は CONTRACTORS の 1 要素 (キーが契約者 ID) で、
## starter_deck が新しい巡礼 (ラン) の初期デッキ (カード ID の並び。同じ ID が複数あればその枚数だけ別のカード)。
## 巡礼の開始で契約者の選択画面 (scripts/character_select_ui.gd) から選ぶ。

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
		"starter_deck":
		[
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
}
## 契約者を指定しない新しい巡礼 (起動時・検証) で使う契約者と、契約者の選択画面で最初にフォーカスする契約者
const FIRST_CONTRACTOR: String = "yura"


## 契約者の初期デッキ (カード ID の並び)
static func starter_deck(contractor_id: String) -> Array[String]:
	var ids: Array[String] = []
	ids.assign(CONTRACTORS[contractor_id]["starter_deck"])
	return ids
