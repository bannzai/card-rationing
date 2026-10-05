extends Control
## 契約の祠の画面。代価なしで「契約を更新する (1 枚の残り使用回数を最大まで戻す)」「契約を破棄する (1 枚を
## デッキから外す)」「新しい契約を結ぶ (3 体から 1 体を選ぶ)」から 1 つを選び、済ませたら地図へ戻る。
## 処理は scripts/node_rules.gd、選んでいる途中の画面 (どの選択肢のカードを選んでいるか) だけをここに持つ。

## 画面の段階: 3 択を選ぶ / 更新・破棄するカードを選ぶ / 新しく契約するカードを選ぶ
enum Mode { OPTIONS, RENEW, BREAK, CONTRACT }

const NodeRules := preload("res://scripts/node_rules.gd")
const RunFlow := preload("res://scripts/run_flow.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

## ラン単位の状態 (autoload RunState)
var run_state: RunStateScript = null
## 今の画面の段階
var mode: Mode = Mode.OPTIONS
## 今の段階の画面の中身 (段階が変わるたびに作り直す)
var content: VBoxContainer = null
## 3 択の段階のボタン (更新 / 破棄 / 新しい契約 / 立ち去る)
var renew_button: Button = null
var break_button: Button = null
var contract_button: Button = null
var leave_button: Button = null
## カードを選ぶ段階の格子 (更新・破棄) と、新しい契約の候補のボタン (カード ID → ボタン)
var deck_grid: GridContainer = null
var offer_buttons: Dictionary = {}


## 画面のノードを組み立てる
func _ready() -> void:
	run_state = get_tree().root.get_node_or_null("RunState")
	var layout: VBoxContainer = UiKit.screen_layout(self, "契約の祠")
	UiKit.add_label(layout, "古い祠に契約の印が灯っている。代価なし。1 つだけ選べる。")
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	layout.add_child(content)
	show_mode(Mode.OPTIONS)


## 段階を next_mode にして画面の中身を作り直す
func show_mode(next_mode: Mode) -> void:
	mode = next_mode
	UiKit.clear_children(content)
	deck_grid = null
	offer_buttons = {}
	match mode:
		Mode.OPTIONS:
			_build_options()
		Mode.RENEW:
			UiKit.add_label(content, "更新する契約を選ぶ (残り使用回数が最大まで戻る)")
			deck_grid = UiKit.add_deck_grid(
				content,
				run_state,
				func(index: int) -> bool: return NodeRules.can_restore(run_state, index),
				renew
			)
		Mode.BREAK:
			UiKit.add_label(content, "破棄する契約を選ぶ (デッキから外れる)")
			deck_grid = UiKit.add_deck_grid(
				content,
				run_state,
				func(index: int) -> bool: return NodeRules.can_remove(run_state, index),
				break_contract
			)
		Mode.CONTRACT:
			_build_contracts()
	if mode != Mode.OPTIONS:
		UiKit.add_button(content, "戻る", show_mode.bind(Mode.OPTIONS))


## デッキの index 番目のカードの契約を更新して地図へ戻る
func renew(index: int) -> void:
	if NodeRules.shrine_renew(run_state, index):
		RunFlow.leave_node(run_state)


## デッキの index 番目のカードの契約を破棄して地図へ戻る
func break_contract(index: int) -> void:
	if NodeRules.shrine_break(run_state, index):
		RunFlow.leave_node(run_state)


## card_id のカードと新しく契約して地図へ戻る
func contract(card_id: String) -> void:
	if NodeRules.shrine_contract(run_state, card_id):
		RunFlow.leave_node(run_state)


## 何もせずに地図へ戻る
func leave() -> void:
	RunFlow.leave_node(run_state)


## 3 択と立ち去るボタン
func _build_options() -> void:
	UiKit.add_label(content, UiKit.status_text(run_state))
	renew_button = UiKit.add_button(
		content, "契約を更新する — 1 枚の残り使用回数を最大まで戻す", show_mode.bind(Mode.RENEW)
	)
	break_button = UiKit.add_button(
		content, "契約を破棄する — 1 枚をデッキから外す", show_mode.bind(Mode.BREAK)
	)
	contract_button = UiKit.add_button(
		content, "新しい契約を結ぶ — 3 体から 1 体を選ぶ", show_mode.bind(Mode.CONTRACT)
	)
	leave_button = UiKit.add_button(content, "何もせずに立ち去る", leave)
	renew_button.grab_focus()


## 新しい契約の候補 3 枚
func _build_contracts() -> void:
	UiKit.add_label(content, "契約する精霊・英霊を選ぶ")
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	for card_id: String in NodeRules.card_offers(run_state.node_seed()):
		var button: Button = UiKit.add_button(row, UiKit.offer_text(card_id), contract.bind(card_id))
		button.custom_minimum_size = UiKit.CARD_BUTTON_SIZE
		offer_buttons[card_id] = button
