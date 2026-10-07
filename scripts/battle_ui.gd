extends Control
## 戦闘画面 (仮の見た目。見た目は関門 2 の後に反映する)。進行は scripts/battle.gd に任せ、ここは表示と
## 入力 (マウスのクリックとキーボード) だけを受け持つ。手札のカードには残り使用回数を必ず表示し、
## 残り 1 回と契約切れ (残り 0) を色と文で見分けられるようにする。
## カードを使うたびとターンの終わりにランを保存し、勝敗が決まったら scripts/run_flow.gd で戦闘を終える
## (報酬・踏破・敗北の画面へは scripts/main.gd が切り替える)。

const ActMap := preload("res://scripts/act_map.gd")
const Battle := preload("res://scripts/battle.gd")
const Cards := preload("res://scripts/cards.gd")
const Enemies := preload("res://scripts/enemies.gd")
const RunFlow := preload("res://scripts/run_flow.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

## pending_hand_index の特別な値: もがくの対象を選んでいる
const STRUGGLE_PENDING: int = -2
## 敵の行動の種別と敵の格の表示名 (戦闘の格の敵には付けない)
const MOVE_NAMES: Dictionary = {Enemies.Move.ATTACK: "攻撃", Enemies.Move.GUARD: "防御"}
const RANK_NAMES: Dictionary = {
	Enemies.Rank.NORMAL: "", Enemies.Rank.ELITE: " [強敵]", Enemies.Rank.BOSS: " [ボス]"
}

## 進行中の戦闘
var battle: Battle = null
## ラン単位の状態 (autoload RunState)
var run_state: RunStateScript = null
## 対象の敵を選んでいる途中の手札の index (-1 なら選んでいない。もがくなら STRUGGLE_PENDING)
var pending_hand_index: int = -1

## scenes/battle.tscn のノード (enemy_row / hand_row の子のボタンは refresh() が足す)
@onready var floor_label: Label = $Layout/TopBar/FloorLabel
@onready var enemy_row: HBoxContainer = $Layout/EnemyRow
@onready var message_label: Label = $Layout/MessageLabel
@onready var status_label: Label = $Layout/StatusLabel
@onready var hand_row: HBoxContainer = $Layout/HandRow
@onready var struggle_button: Button = $Layout/ActionRow/StruggleButton
@onready var end_turn_button: Button = $Layout/ActionRow/EndTurnButton


func _ready() -> void:
	run_state = get_tree().root.get_node_or_null("RunState")
	if run_state == null:
		push_error("autoload RunState が無い")
	struggle_button.pressed.connect(request_struggle)
	end_turn_button.pressed.connect(end_turn)


## キーボード操作。数字キーでカード (対象を選んでいる時は敵)、S でもがく、Enter でターン終了、
## Esc で対象の選択をやめる
func _unhandled_key_input(event: InputEvent) -> void:
	if battle == null or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: Key = (event as InputEventKey).keycode
	if key >= KEY_1 and key <= KEY_9:
		select_number(key - KEY_1)
	elif key == KEY_ENTER or key == KEY_KP_ENTER:
		end_turn()
	elif key == KEY_S:
		request_struggle()
	elif key == KEY_ESCAPE:
		cancel_target()


## 今いる節点の敵と seed_value で戦闘を始める
func start_battle(seed_value: int) -> void:
	battle = Battle.new()
	battle.start(run_state, RunFlow.encounter(run_state), seed_value)
	pending_hand_index = -1
	refresh()


## 数字キー (0 始まりの number) の入力。対象を選んでいる時は敵、そうでなければ手札のカード
func select_number(number: int) -> void:
	if pending_hand_index == -1:
		request_card(number)
	else:
		choose_target(number)


## 手札の hand_index 番目のカードを使う。対象を取るカードで敵が 2 体以上いれば対象の選択に入る
func request_card(hand_index: int) -> void:
	if pending_hand_index != -1 or not battle.can_play(hand_index):
		return
	var card_id: String = run_state.deck[battle.hand[hand_index]]["id"]
	if Cards.needs_target(card_id):
		var alive: Array[int] = battle.alive_enemies()
		if alive.size() == 1:
			battle.play(hand_index, alive[0])
		else:
			pending_hand_index = hand_index
	else:
		battle.play(hand_index)
	_after_action()


## もがく。敵が 2 体以上いれば対象の選択に入る。エネルギーが足りない時は何もしない (対象の選択に入ると
## ターン終了が効かなくなるため)
func request_struggle() -> void:
	if pending_hand_index != -1 or battle.outcome != Battle.Outcome.NONE:
		return
	if battle.energy < Battle.STRUGGLE_COST:
		return
	var alive: Array[int] = battle.alive_enemies()
	if alive.size() == 1:
		battle.struggle(alive[0])
	elif alive.size() > 1:
		pending_hand_index = STRUGGLE_PENDING
	_after_action()


## 対象の選択中に敵 (enemies の index) を選ぶ。選択中でなければ何もしない
func choose_target(enemy_index: int) -> void:
	if pending_hand_index == -1 or not battle.is_alive(enemy_index):
		return
	if pending_hand_index == STRUGGLE_PENDING:
		battle.struggle(enemy_index)
	else:
		battle.play(pending_hand_index, enemy_index)
	pending_hand_index = -1
	_after_action()


## 対象の選択をやめる
func cancel_target() -> void:
	pending_hand_index = -1
	refresh()


## ターンを終える (敵の行動の後、次のターンの手札が配られる)
func end_turn() -> void:
	if pending_hand_index != -1:
		return
	battle.end_turn()
	_after_action()


## 戦闘の状態を画面に反映する
func refresh() -> void:
	var kind: int = run_state.current_node().get("kind", ActMap.Kind.BATTLE)
	floor_label.text = (
		"第 %d 幕 %d 階 %s"
		% [run_state.act, maxi(1, run_state.path.size()), ActMap.KIND_NAMES[kind]]
	)
	status_label.text = (
		"体力 %d / %d   防御 %d   エネルギー %d / %d   山札 %d   捨て札 %d   ターン %d"
		% [
			run_state.hp,
			run_state.max_hp,
			battle.block,
			battle.energy,
			Battle.ENERGY_PER_TURN,
			battle.draw_pile.size(),
			battle.discard_pile.size(),
			battle.turn,
		]
	)
	message_label.text = _message_text()
	_refresh_enemies()
	_refresh_hand()
	var over: bool = battle.outcome != Battle.Outcome.NONE
	struggle_button.disabled = over or battle.energy < Battle.STRUGGLE_COST
	end_turn_button.disabled = over


## 操作の後: ランを保存し (戦闘の途中で終えても、使った回数と受けた傷が戻らないように)、勝敗が決まっていれば
## 戦闘を終える (画面の切り替えは scripts/main.gd が局面の変化で行う)。画面を更新する
func _after_action() -> void:
	if battle.outcome == Battle.Outcome.NONE:
		var status: Error = run_state.autosave()
		if status != OK:
			push_error("自動保存に失敗: %s (%s)" % [run_state.save_path, error_string(status)])
	else:
		RunFlow.finish_battle(run_state, battle.outcome == Battle.Outcome.WIN)
	refresh()


## 状況に応じた案内の文
func _message_text() -> String:
	if battle.outcome == Battle.Outcome.WIN:
		return "勝利"
	if battle.outcome == Battle.Outcome.LOSE:
		return "敗北"
	if pending_hand_index != -1:
		return "対象の敵を選ぶ (数字キー / クリック。Esc で戻る)"
	if battle.has_playable_card():
		return ""
	if battle.energy < Battle.STRUGGLE_COST:
		return "エネルギーが尽きた。ターン終了 (Enter)"
	return "今使えるカードが無い。もがく (S) かターン終了 (Enter)"


## 敵のボタンを敵の数だけ用意して、体力・防御・予告を表示する
func _refresh_enemies() -> void:
	_ensure_buttons(enemy_row, battle.enemies.size(), choose_target)
	for index: int in range(enemy_row.get_child_count()):
		var button: Button = enemy_row.get_child(index)
		button.visible = index < battle.enemies.size()
		if not button.visible:
			continue
		var enemy: Dictionary = battle.enemies[index]
		if enemy["hp"] <= 0:
			button.text = "%d. %s\n倒した" % [index + 1, enemy["name"]]
			button.disabled = true
			continue
		var intent: Dictionary = enemy["intent"]
		var hits: int = intent.get("hits", 1)
		button.text = (
			"%d. %s%s\n体力 %d / %d   防御 %d\n予告: %s %d%s"
			% [
				index + 1,
				enemy["name"],
				RANK_NAMES[Enemies.ENEMIES[enemy["id"]]["rank"]],
				enemy["hp"],
				enemy["max_hp"],
				enemy["block"],
				MOVE_NAMES[intent["move"]],
				intent["value"],
				"×%d" % hits if hits > 1 else "",
			]
		)
		button.disabled = false


## 手札のボタンを手札の枚数だけ用意して、効果・コスト・残り使用回数を表示する
func _refresh_hand() -> void:
	_ensure_buttons(hand_row, battle.hand.size(), request_card)
	for index: int in range(hand_row.get_child_count()):
		var button: Button = hand_row.get_child(index)
		button.visible = index < battle.hand.size()
		if not button.visible:
			continue
		var deck_index: int = battle.hand[index]
		var card_id: String = run_state.deck[deck_index]["id"]
		var card: Dictionary = Cards.CARDS[card_id]
		var uses: int = run_state.uses_left(deck_index)
		var uses_text: String = "残り %d / %d" % [uses, card["max_uses"]]
		button.modulate = UiKit.uses_color(uses)
		if uses == 0:
			uses_text += "\n契約切れ"
		elif uses == 1:
			uses_text += " (最後の 1 回)"
		button.text = (
			"%d. %s [%s]\n%s / コスト %d\n%s"
			% [
				index + 1,
				card["name"],
				UiKit.BOND_NAMES[card["bond"]],
				Cards.effect_text(card_id),
				card["cost"],
				uses_text,
			]
		)
		button.disabled = not battle.can_play(index)


## row の子のボタンが count 個以上あるようにする。足したボタンの pressed はその位置の index を付けて
## callback に繋ぐ (ボタンは使い回し、毎回作り直さない)。ボタンは行の幅を等分して並び、ドローで手札が増えても
## 画面の外に出ない (最小幅 100 なら 10 枚でも 1232 幅の行に収まる)
func _ensure_buttons(row: HBoxContainer, count: int, callback: Callable) -> void:
	while row.get_child_count() < count:
		var button: Button = Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(100, 96)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.clip_text = true
		button.pressed.connect(callback.bind(row.get_child_count()))
		row.add_child(button)
