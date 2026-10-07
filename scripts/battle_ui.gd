extends Control
## 戦闘画面。進行は scripts/battle.gd に任せ、ここは表示と入力 (マウスのクリックとキーボード) だけを受け持つ。
## 見た目は「蝋と灯火」(documents/DIRECTION.md「デザインの方向」): 祠の道の絵の左に巡礼者、右に敵を置き、
## エネルギーは灯っている蝋燭の数、体力は数珠の珠で示す。手札のカード (scripts/card_view.gd) は残り使用回数を
## 封蝋の印の列で必ず見せ、契約切れ (残り 0) のカードは色を失う。
## カードを使うたびとターンの終わりにランを保存し、勝敗が決まったら scripts/run_flow.gd で戦闘を終える
## (報酬・踏破・敗北の画面へは scripts/main.gd が切り替える)。
## カードを使った後の残り使用回数・被弾・勝敗に合わせて効果音を鳴らす (回数の増減を耳でも分かるように)。

const ActMap := preload("res://scripts/act_map.gd")
const Art := preload("res://scripts/art.gd")
const AudioScript := preload("res://scripts/audio.gd")
const Battle := preload("res://scripts/battle.gd")
const CardView := preload("res://scripts/card_view.gd")
const Cards := preload("res://scripts/cards.gd")
const EnemyView := preload("res://scripts/enemy_view.gd")
const RunFlow := preload("res://scripts/run_flow.gd")
const RunStateScript := preload("res://scripts/run_state.gd")

## pending_hand_index の特別な値: もがくの対象を選んでいる
const STRUGGLE_PENDING: int = -2
## エネルギーの蝋燭 1 本の大きさと、体力の数珠の珠の数・珠 1 つの大きさ。蝋燭 3 本 (1 ターンの分) と珠 10 個
## (体力の 1 割ごと) が、手札の行の左に空けた幅 (scenes/battle.tscn の PlayerPanel) に並ぶ大きさにした
const CANDLE_SIZE: Vector2 = Vector2(38, 64)
const HEALTH_BEADS: int = 10
const BEAD_SIZE: Vector2 = Vector2(16, 16)

## 進行中の戦闘
var battle: Battle = null
## ラン単位の状態 (autoload RunState)
var run_state: RunStateScript = null
## BGM と効果音 (autoload Audio)
var audio: AudioScript = null
## 対象の敵を選んでいる途中の手札の index (-1 なら選んでいない。もがくなら STRUGGLE_PENDING)
var pending_hand_index: int = -1

## scenes/battle.tscn のノード (enemy_row の敵・hand_row のカード・energy_row の蝋燭・health_row の珠は
## refresh() が足す)
@onready var floor_label: Label = $FloorLabel
@onready var enemy_row: HBoxContainer = $EnemyRow
@onready var message_label: Label = $MessageLabel
@onready var energy_row: HBoxContainer = $PlayerPanel/EnergyRow
@onready var energy_label: Label = $PlayerPanel/EnergyLabel
@onready var health_row: HBoxContainer = $PlayerPanel/HealthRow
@onready var status_label: Label = $PlayerPanel/StatusLabel
@onready var pile_label: Label = $PlayerPanel/PileLabel
@onready var hand_row: HBoxContainer = $HandRow
@onready var struggle_button: Button = $ActionColumn/StruggleButton
@onready var end_turn_button: Button = $ActionColumn/EndTurnButton


func _ready() -> void:
	run_state = get_tree().root.get_node_or_null("RunState")
	audio = get_tree().root.get_node_or_null("Audio")
	if run_state == null or audio == null:
		push_error("autoload RunState か Audio が無い")
	($Background as TextureRect).texture = Art.BATTLE_BG
	($Pilgrim as TextureRect).texture = Art.PILGRIM
	message_label.add_theme_color_override("font_color", Art.CANDLE)
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
			_play_card(hand_index, alive[0])
		else:
			pending_hand_index = hand_index
	else:
		_play_card(hand_index)
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
		_play_card(pending_hand_index, enemy_index)
	pending_hand_index = -1
	_after_action()


## 対象の選択をやめる
func cancel_target() -> void:
	pending_hand_index = -1
	refresh()


## ターンを終える (敵の行動の後、次のターンの手札が配られる)。敵の攻撃で体力が減ったら被弾の効果音を鳴らす
## (防御で受け切った時は鳴らさない)
func end_turn() -> void:
	if pending_hand_index != -1:
		return
	var hp_before: int = run_state.hp
	battle.end_turn()
	if run_state.hp < hp_before:
		audio.play_se(AudioScript.Se.HIT)
	_after_action()


## 戦闘の状態を画面に反映する
func refresh() -> void:
	var kind: int = run_state.current_node().get("kind", ActMap.Kind.BATTLE)
	floor_label.text = (
		"第 %d 幕 %d 階 %s"
		% [run_state.act, maxi(1, run_state.path.size()), ActMap.KIND_NAMES[kind]]
	)
	# カードの効果でエネルギーが 1 ターンの分を超えたら、蝋燭を増やして見せる (増えた分は蝋燭を縮め、手札の
	# 行にはみ出さないようにする)
	var candles: int = maxi(battle.energy, Battle.ENERGY_PER_TURN)
	Art.set_icons(
		energy_row,
		Art.CANDLE_LIT,
		Art.CANDLE_OUT,
		battle.energy,
		candles,
		CANDLE_SIZE * minf(1.0, float(Battle.ENERGY_PER_TURN) / candles)
	)
	energy_label.text = "エネルギー %d / %d" % [battle.energy, Battle.ENERGY_PER_TURN]
	Art.set_icons(
		health_row,
		Art.BEAD,
		Art.BEAD_DULL,
		Art.lit_count(run_state.hp, run_state.max_hp, HEALTH_BEADS),
		HEALTH_BEADS,
		BEAD_SIZE
	)
	status_label.text = "体力 %d / %d   防御 %d" % [run_state.hp, run_state.max_hp, battle.block]
	pile_label.text = (
		"山札 %d   捨て札 %d\nターン %d"
		% [battle.draw_pile.size(), battle.discard_pile.size(), battle.turn]
	)
	message_label.text = _message_text()
	_refresh_enemies()
	_refresh_hand()
	var over: bool = battle.outcome != Battle.Outcome.NONE
	struggle_button.disabled = over or battle.energy < Battle.STRUGGLE_COST
	end_turn_button.disabled = over


## 手札の hand_index 番目のカードを target の敵に使う (対象を取らないカードは target を省く)。使えた時は、
## 回数が減ったことを耳で知らせる効果音を鳴らす (使ったカードは捨て札へ行き、残りの表示が見えなくなるため)
func _play_card(hand_index: int, target: int = -1) -> void:
	var deck_index: int = battle.hand[hand_index]
	if battle.play(hand_index, target):
		audio.play_se(AudioScript.card_use_se(run_state.uses_left(deck_index)))


## 操作の後: ランを保存し (戦闘の途中で終えても、使った回数と受けた傷が戻らないように)、勝敗が決まっていれば
## 戦闘を終えて勝利・敗北の効果音を鳴らす (画面の切り替えは scripts/main.gd が局面の変化で行う)。画面を更新する
func _after_action() -> void:
	if battle.outcome == Battle.Outcome.NONE:
		var status: Error = run_state.autosave()
		if status != OK:
			push_error("自動保存に失敗: %s (%s)" % [run_state.save_path, error_string(status)])
	elif RunFlow.finish_battle(run_state, battle.outcome == Battle.Outcome.WIN):
		audio.play_se(
			AudioScript.Se.WIN if battle.outcome == Battle.Outcome.WIN else AudioScript.Se.LOSE
		)
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


## 敵 (scripts/enemy_view.gd) を敵の数だけ用意して、体力・防御・予告を見せる
func _refresh_enemies() -> void:
	_ensure_views(enemy_row, battle.enemies.size(), EnemyView, choose_target)
	for index: int in range(enemy_row.get_child_count()):
		var view: EnemyView = enemy_row.get_child(index)
		view.visible = index < battle.enemies.size()
		if view.visible:
			view.show_enemy(index + 1, battle.enemies[index])


## 手札のカード (scripts/card_view.gd) を手札の枚数だけ用意して、数字キーの番号と残り使用回数を見せる。
## カードは手札の行の幅に収まる大きさに縮め、ドローで手札が増えても画面の外に出さない
func _refresh_hand() -> void:
	var count: int = battle.hand.size()
	_ensure_views(hand_row, count, CardView, request_card)
	var gaps: float = hand_row.get_theme_constant("separation") * maxi(count - 1, 0)
	var row_width: float = hand_row.offset_right - hand_row.offset_left
	var width: float = minf(CardView.BASE_SIZE.x, floorf((row_width - gaps) / maxi(count, 1)))
	for index: int in range(hand_row.get_child_count()):
		var view: CardView = hand_row.get_child(index)
		view.visible = index < count
		if not view.visible:
			continue
		var deck_index: int = battle.hand[index]
		view.custom_minimum_size = CardView.BASE_SIZE * (width / CardView.BASE_SIZE.x)
		view.show_deck_card(run_state.deck[deck_index]["id"], run_state.uses_left(deck_index))
		view.set_key_number(index + 1)
		view.disabled = not battle.can_play(index)


## row の子 (view_script のボタン) が count 個以上あるようにする。足したボタンの pressed はその位置の index を
## 付けて callback に繋ぐ (ボタンは使い回し、毎回作り直さない)
func _ensure_views(
	row: HBoxContainer, count: int, view_script: GDScript, callback: Callable
) -> void:
	while row.get_child_count() < count:
		var view: Button = view_script.new()
		view.focus_mode = Control.FOCUS_NONE
		# 行の下の端に揃える (縮めた手札のカードも、格の違う敵も足元を揃える)
		view.size_flags_vertical = Control.SIZE_SHRINK_END
		view.pressed.connect(callback.bind(row.get_child_count()))
		row.add_child(view)


