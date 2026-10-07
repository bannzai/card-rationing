extends Control
## 商人の画面。所持金を払って、カードを買う・1 枚の残り使用回数を最大まで戻す・1 枚を外す。済ませたら
## 「立ち去る」で地図へ戻る。処理と値段は scripts/node_rules.gd、選んでいる途中の画面 (戻す・外すカードを
## 選んでいるか) だけをここに持つ。

## 画面の段階: 品物を選ぶ / 残り使用回数を戻すカードを選ぶ / 外すカードを選ぶ
enum Mode { GOODS, RESTORE, REMOVE }

const AudioScript := preload("res://scripts/audio.gd")
const NodeRules := preload("res://scripts/node_rules.gd")
const RunFlow := preload("res://scripts/run_flow.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

## ラン単位の状態 (autoload RunState)
var run_state: RunStateScript = null
## BGM と効果音 (autoload Audio)
var audio: AudioScript = null
## 今の画面の段階
var mode: Mode = Mode.GOODS
## 今の段階の画面の中身 (段階が変わるたびや買うたびに作り直す)
var content: VBoxContainer = null
var status_label: Label = null
## 品物の段階のボタン: カード ID → 買うボタン、戻す・外す・立ち去るボタン
var card_buttons: Dictionary = {}
var restore_button: Button = null
var remove_button: Button = null
var leave_button: Button = null
## カードを選ぶ段階 (戻す・外す) の格子
var deck_grid: GridContainer = null


## 画面のノードを組み立てる
func _ready() -> void:
	run_state = get_tree().root.get_node_or_null("RunState")
	audio = get_tree().root.get_node_or_null("Audio")
	var layout: VBoxContainer = UiKit.screen_layout(self, "商人")
	UiKit.add_label(layout, "「契約の切れ端なら、いくらでも売ってやるよ」")
	status_label = UiKit.add_label(layout, "")
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	layout.add_child(content)
	show_mode(Mode.GOODS)


## 段階を next_mode にして画面の中身を作り直す
func show_mode(next_mode: Mode) -> void:
	mode = next_mode
	status_label.text = UiKit.status_text(run_state)
	UiKit.clear_children(content)
	card_buttons = {}
	deck_grid = null
	match mode:
		Mode.GOODS:
			_build_goods()
		Mode.RESTORE:
			UiKit.add_label(
				content, "残り使用回数を最大まで戻すカードを選ぶ (値段 %d)" % NodeRules.RESTORE_PRICE
			)
			deck_grid = UiKit.add_deck_grid(
				content,
				run_state,
				func(index: int) -> bool: return NodeRules.can_restore(run_state, index),
				restore
			)
		Mode.REMOVE:
			UiKit.add_label(content, "外すカードを選ぶ (値段 %d)" % NodeRules.REMOVE_PRICE)
			deck_grid = UiKit.add_deck_grid(
				content,
				run_state,
				func(index: int) -> bool: return NodeRules.can_remove(run_state, index),
				remove_from_deck
			)
	if mode != Mode.GOODS:
		var back: Button = UiKit.add_button(content, "戻る", show_mode.bind(Mode.GOODS))
		# 押せるカードが無くてフォーカスがどこにも無い時は、キーボードで戻れるよう「戻る」に置く
		if get_viewport().gui_get_focus_owner() == null:
			back.grab_focus()


## card_id のカードを買う
func buy(card_id: String) -> void:
	if NodeRules.buy_card(run_state, card_id):
		show_mode(Mode.GOODS)


## デッキの index 番目のカードの残り使用回数を戻す (回数の回復の効果音を鳴らす)
func restore(index: int) -> void:
	if NodeRules.buy_restore(run_state, index):
		audio.play_se(AudioScript.Se.RESTORE)
		show_mode(Mode.GOODS)


## デッキの index 番目のカードを外す
func remove_from_deck(index: int) -> void:
	if NodeRules.buy_removal(run_state, index):
		show_mode(Mode.GOODS)


## 地図へ戻る
func leave() -> void:
	RunFlow.leave_node(run_state)


## 売り物のカード 3 枚と、戻す・外す・立ち去るボタン。買えないもの (売り切れ・所持金が足りない・この訪問で
## 済ませた) は押せない
func _build_goods() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	var sold: Array = run_state.visit.get("sold", [])
	for card_id: String in NodeRules.card_offers(run_state.node_seed()):
		var price: int = NodeRules.card_price(card_id)
		var label: String = "%s\n値段 %d" % [UiKit.offer_text(card_id), price]
		var button: Button = UiKit.add_card_button(row, label, buy.bind(card_id))
		if sold.has(card_id):
			button.text = "%s\n売り切れ" % UiKit.card_summary(card_id)
		button.disabled = sold.has(card_id) or run_state.gold < price
		card_buttons[card_id] = button
	restore_button = UiKit.add_button(
		content,
		"1 枚の残り使用回数を最大まで戻す (値段 %d)" % NodeRules.RESTORE_PRICE,
		show_mode.bind(Mode.RESTORE)
	)
	# 戻せるカード (残りの減ったカード) が無ければ押せない (契約の祠の更新と同じ)
	restore_button.disabled = (
		run_state.visit.has("restored")
		or run_state.gold < NodeRules.RESTORE_PRICE
		or not range(run_state.deck.size()).any(
			func(index: int) -> bool: return NodeRules.can_restore(run_state, index)
		)
	)
	remove_button = UiKit.add_button(
		content, "1 枚を外す (値段 %d)" % NodeRules.REMOVE_PRICE, show_mode.bind(Mode.REMOVE)
	)
	remove_button.disabled = run_state.visit.has("removed") or run_state.gold < NodeRules.REMOVE_PRICE
	leave_button = UiKit.add_button(content, "立ち去る", leave)
	leave_button.grab_focus()
