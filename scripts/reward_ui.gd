extends Control
## 戦闘に勝った後の報酬の画面。受け取った所持金と体力の回復 (強敵なら手に入れた護符も、契約者の個性で戻った回数も)
## を見せ、カード 3 枚から 1 枚と契約するか、取らずに地図へ戻る (所持金・体力・護符・回数は戦闘を終えた時に
## scripts/run_flow.gd が反映済み)。

const ActMap := preload("res://scripts/act_map.gd")
const AudioScript := preload("res://scripts/audio.gd")
const Contractors := preload("res://scripts/contractors.gd")
## 契約者の個性で回数が戻った時に、回数の回復の効果音を鳴らすまでの秒数。勝利の効果音
## (assets/audio/se_win.wav) の長さ 1.6 秒 (ffprobe で実測) に合わせ、回数の増減の音型を勝利の音と聞き分けられるようにする
const RESTORE_SE_DELAY: float = 1.6
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
## 強敵で手に入れた護符の名前と効果の文 (強敵でなければ null)
var relic_label: Label = null


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
				NodeRules.battle_gold(run_state, kind),
				NodeRules.battle_heal(run_state),
				UiKit.status_text(run_state),
			]
		)
	)
	var relic_id: String = NodeRules.elite_relic(run_state) if kind == ActMap.Kind.ELITE else ""
	if not relic_id.is_empty():
		relic_label = UiKit.add_note(layout, "護符を手に入れた %s" % UiKit.relic_text(relic_id))
	_show_win_restore(layout)
	UiKit.add_label(layout, "新しく契約するカードを 1 枚選ぶ (取らなくてもよい)")
	var row: HBoxContainer = UiKit.add_card_row(layout)
	for card_id: String in NodeRules.offers_here(run_state):
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
		# 同時に鳴る勝利の効果音 (scripts/battle_ui.gd) と重ならないよう、鳴り終わってから鳴らす。待ちはこの画面の
		# Tween に持たせ、待つ間に画面を出たら (scripts/main.gd が解放する) 鳴らさない
		var tween: Tween = create_tween()
		tween.tween_interval(RESTORE_SE_DELAY)
		tween.tween_callback(audio.play_se.bind(AudioScript.Se.RESTORE))


## card_id のカードと契約して地図へ戻る
func take(card_id: String) -> void:
	if NodeRules.take_reward_card(run_state, card_id):
		RunFlow.leave_node(run_state)


## カードを取らずに地図へ戻る
func skip() -> void:
	RunFlow.leave_node(run_state)
