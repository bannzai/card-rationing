extends Control
## ランの終わり (敗北・踏破) の画面。そのランの結果 (到達した階層・勝った戦闘の数・使い切った契約の数など) を
## 見せ、「タイトルへ」で closed を出す (保存データはランの終わりに scripts/run_flow.gd が消し済み)。

## 画面を閉じる (呼んだ側が次の画面を出す)
signal closed

const ActMap := preload("res://scripts/act_map.gd")
const Contractors := preload("res://scripts/contractors.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

## ラン単位の状態 (autoload RunState)
var run_state: RunStateScript = null
## ランの結果の文と、タイトルへ戻るボタン
var summary_label: Label = null
var title_button: Button = null


## 画面のノードを組み立てる
func _ready() -> void:
	run_state = get_tree().root.get_node_or_null("RunState")
	var cleared: bool = run_state.phase == RunStateScript.Phase.CLEAR
	var layout: VBoxContainer = UiKit.screen_layout(
		self, "踏破 — 第 %d 幕を越えた" % run_state.act if cleared else "敗北 — 巡礼はここで途絶えた"
	)
	summary_label = UiKit.add_label(layout, summary_text(run_state))
	title_button = UiKit.add_button(layout, "タイトルへ", closed.emit)
	title_button.grab_focus()


## state のランの結果の文
static func summary_text(state: RunStateScript) -> String:
	var exhausted_now: int = 0
	for index: int in range(state.deck.size()):
		if not state.can_use(index):
			exhausted_now += 1
	return "\n".join(
		[
			"契約者: %s" % Contractors.CONTRACTORS[state.character_id]["name"],
			"到達した階層: %d / %d 階" % [state.path.size(), ActMap.ROWS],
			"勝った戦闘: %d" % state.battles_won,
			"使い切った契約: %d 回 (今の契約切れ %d 枚)" % [state.exhausted_count, exhausted_now],
			"残りの体力: %d / %d   所持金: %d" % [state.hp, state.max_hp, state.gold],
			"契約の数: %d 枚" % state.deck.size(),
		]
	)
