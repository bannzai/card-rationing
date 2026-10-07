extends Control
## 戦闘に勝った後の報酬の画面。受け取った所持金と体力の回復を見せ、カード 3 枚から 1 枚と契約するか、
## 取らずに地図へ戻る (所持金と体力は戦闘を終えた時に scripts/run_flow.gd が反映済み)。

const NodeRules := preload("res://scripts/node_rules.gd")
const RunFlow := preload("res://scripts/run_flow.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

## ラン単位の状態 (autoload RunState)
var run_state: RunStateScript = null
## 並べたカード ID → 契約するボタン
var offer_buttons: Dictionary = {}
## カードを取らずに地図へ戻るボタン
var skip_button: Button = null


## 画面のノードを組み立てる
func _ready() -> void:
	run_state = get_tree().root.get_node_or_null("RunState")
	var layout: VBoxContainer = UiKit.screen_layout(self, "勝利")
	var kind: int = run_state.current_node()["kind"]
	UiKit.add_label(
		layout,
		(
			"所持金 +%d   体力 +%d (最大まで)\n%s"
			% [
				NodeRules.reward_gold(run_state.node_seed(), kind),
				NodeRules.BATTLE_HEAL,
				UiKit.status_text(run_state),
			]
		)
	)
	UiKit.add_label(layout, "新しく契約するカードを 1 枚選ぶ (取らなくてもよい)")
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	layout.add_child(row)
	for card_id: String in NodeRules.card_offers(run_state.node_seed()):
		var button: Button = UiKit.add_card_button(row, UiKit.offer_text(card_id), take.bind(card_id))
		offer_buttons[card_id] = button
	skip_button = UiKit.add_button(layout, "取らずに地図へ戻る", skip)
	# 戦闘の Enter (ターン終了) の続けて押しで、見ずにカードと契約しないよう、取らない方に置く
	skip_button.grab_focus()


## card_id のカードと契約して地図へ戻る
func take(card_id: String) -> void:
	if NodeRules.take_reward_card(run_state, card_id):
		RunFlow.leave_node(run_state)


## カードを取らずに地図へ戻る
func skip() -> void:
	RunFlow.leave_node(run_state)
