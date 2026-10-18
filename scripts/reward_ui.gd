extends Control
## 戦闘に勝った後の報酬の画面。受け取った所持金と体力の回復 (と、契約者の個性で戻った回数) を見せ、カード 3 枚から
## 1 枚と契約するか、取らずに地図へ戻る (所持金・体力・回数は戦闘を終えた時に scripts/run_flow.gd が反映済み)。

const AudioScript := preload("res://scripts/audio.gd")
const Contractors := preload("res://scripts/contractors.gd")
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
	_show_win_restore(layout)
	UiKit.add_label(layout, "新しく契約するカードを 1 枚選ぶ (取らなくてもよい)")
	var row: HBoxContainer = UiKit.add_card_row(layout)
	for card_id: String in NodeRules.card_offers(run_state.node_seed()):
		offer_buttons[card_id] = UiKit.add_offer_card(row, card_id, "", take.bind(card_id))
	skip_button = UiKit.add_button(layout, "取らずに地図へ戻る", skip)
	# 戦闘の Enter (ターン終了) の続けて押しで、見ずにカードと契約しないよう、取らない方に置く
	skip_button.grab_focus()


## 戦闘に勝った時に契約者の個性で残り使用回数が戻ったカード (NodeRules.win_restore()) があれば、その文を足して
## 回数の回復の効果音を鳴らす (戻ったことは保存データに残らないので、報酬の局面から再開した時は出ない)
func _show_win_restore(layout: VBoxContainer) -> void:
	var index: int = run_state.visit.get("win_restored", -1)
	if index < 0:
		return
	UiKit.add_label(
		layout,
		(
			"個性「%s」: %s の残りが %d 回になった"
			% [
				Contractors.CONTRACTORS[run_state.character_id]["trait_name"],
				run_state.card(index)["name"],
				run_state.uses_left(index),
			]
		)
	)
	var audio: AudioScript = get_tree().root.get_node_or_null("Audio")
	if audio != null:
		audio.play_se(AudioScript.Se.RESTORE)


## card_id のカードと契約して地図へ戻る
func take(card_id: String) -> void:
	if NodeRules.take_reward_card(run_state, card_id):
		RunFlow.leave_node(run_state)


## カードを取らずに地図へ戻る
func skip() -> void:
	RunFlow.leave_node(run_state)
