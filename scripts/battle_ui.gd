extends Control
## 戦闘画面。進行は scripts/battle.gd に任せ、ここは表示と入力 (マウスのクリックとキーボード) だけを受け持つ。
## 見た目は「蝋と灯火」(documents/DIRECTION.md「デザインの方向」): 祠の道の絵の左に巡礼者、右に敵を置き、
## エネルギーは灯っている蝋燭の数、体力は数珠の珠で示す。手札のカード (scripts/card_view.gd) は残り使用回数を
## 封蝋の印の列で必ず見せ、契約切れ (残り 0) のカードは色を失う。
## カードを使うたびとターンの終わりにランを保存し、勝敗が決まったら scripts/run_flow.gd で戦闘を終える
## (報酬・踏破・敗北の画面へは scripts/main.gd が切り替える)。
## カードを使った後の残り使用回数・被弾・勝敗に合わせて効果音を鳴らす (回数の増減を耳でも分かるように)。
## 操作の前後の差で戦闘の動き (使ったカードが持ち上がって封蝋の印が焼け、敵の方へ消える・被弾の揺れと数字・倒した
## 敵が薄くなる・ターンの始まりのフェード。長さと強さは scripts/art.gd) を付ける。動きは表示だけで、戦闘の状態は
## 即時に変わり、次の入力も待たせない。最後の敵を倒した時だけ、動きが見えるよう画面の切り替えを待つ。
## 持っている護符は上の中ほどに印 (scripts/relic_view.gd) で並べ、マウスを載せた印の説明と、直前の操作で働いた
## 護符の名前を印の下の文で見せる (働いた護符の印は光り、名前が浮く)。

const ActMap := preload("res://scripts/act_map.gd")
const Art := preload("res://scripts/art.gd")
const AudioScript := preload("res://scripts/audio.gd")
const Battle := preload("res://scripts/battle.gd")
const CardView := preload("res://scripts/card_view.gd")
const Cards := preload("res://scripts/cards.gd")
const EnemyView := preload("res://scripts/enemy_view.gd")
const RelicView := preload("res://scripts/relic_view.gd")
const Relics := preload("res://scripts/relics.gd")
const RunFlow := preload("res://scripts/run_flow.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

## pending_hand_index の特別な値: もがくの対象を選んでいる
const STRUGGLE_PENDING: int = -2
## エネルギーの蝋燭 1 本の大きさと、体力の数珠の珠の数・珠 1 つの大きさ。蝋燭 3 本 (1 ターンの分) と珠 10 個
## (体力の 1 割ごと) が、手札の行の左に空けた幅 (scenes/battle.tscn の PlayerPanel) に並ぶ大きさにした
const CANDLE_SIZE: Vector2 = Vector2(38, 64)
const HEALTH_BEADS: int = 10
const BEAD_SIZE: Vector2 = Vector2(16, 16)
## 護符の説明の文で、マウスを載せた印も働いた護符も無い時に出す案内
const RELIC_HINT: String = "護符の印にマウスを載せると説明が出る"

## 進行中の戦闘
var battle: Battle = null
## ラン単位の状態 (autoload RunState)
var run_state: RunStateScript = null
## BGM と効果音 (autoload Audio)
var audio: AudioScript = null
## 対象の敵を選んでいる途中の手札の index (-1 なら選んでいない。もがくなら STRUGGLE_PENDING)
var pending_hand_index: int = -1
## 戦闘の動き (使ったカードの複製・浮かぶ数字) を描く層。最後の子にして手札と敵の上に描き、マウスは通す
var effects_layer: Control = null
## 巡礼者の絵の元の位置 (被弾で揺らした後に戻す) と、動いている被弾・手札のフェードの tween
var pilgrim_base: Vector2 = Vector2.ZERO
var pilgrim_tween: Tween = null
var hand_tween: Tween = null
## 勝敗が決まった後の戦闘の終わりを予約したか (勝った後の待ちの間の入力で、戦闘を 2 度終えないように)
var finish_scheduled: bool = false
## 直前の操作で働いた護符の文 (護符の説明の文に、マウスを載せた印が無い時に出す。無ければ空文字)
var relic_trigger_text: String = ""

## scenes/battle.tscn のノード (enemy_row の敵・hand_row のカード・energy_row の蝋燭・health_row の珠・
## relic_row の護符の印は refresh() が足す)
@onready var floor_label: Label = $FloorLabel
@onready var relic_row: HBoxContainer = $RelicRow
@onready var relic_label: Label = $RelicLabel
@onready var pilgrim: TextureRect = $Pilgrim
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
	pilgrim.texture = Art.PILGRIM
	pilgrim_base = pilgrim.position
	message_label.add_theme_color_override("font_color", Art.CANDLE)
	struggle_button.pressed.connect(request_struggle)
	end_turn_button.pressed.connect(end_turn)
	effects_layer = Control.new()
	effects_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	effects_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(effects_layer)


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
	finish_scheduled = false
	refresh()
	_show_relic_triggers()


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
	var before: Dictionary = _snapshot()
	var card_id: String = run_state.deck[battle.hand[hand_index]]["id"]
	if Cards.needs_target(card_id):
		var alive: Array[int] = battle.alive_enemies()
		if alive.size() == 1:
			_play_card(hand_index, alive[0])
		else:
			pending_hand_index = hand_index
	else:
		_play_card(hand_index)
	_after_action(before)


## もがく。敵が 2 体以上いれば対象の選択に入る。エネルギーが足りない時は何もしない (対象の選択に入ると
## ターン終了が効かなくなるため)
func request_struggle() -> void:
	if pending_hand_index != -1 or battle.outcome != Battle.Outcome.NONE:
		return
	if battle.energy < Battle.STRUGGLE_COST:
		return
	var before: Dictionary = _snapshot()
	var alive: Array[int] = battle.alive_enemies()
	if alive.size() == 1:
		battle.struggle(alive[0])
	elif alive.size() > 1:
		pending_hand_index = STRUGGLE_PENDING
	_after_action(before)


## 対象の選択中に敵 (enemies の index) を選ぶ。選択中でなければ何もしない
func choose_target(enemy_index: int) -> void:
	if pending_hand_index == -1 or not battle.is_alive(enemy_index):
		return
	var before: Dictionary = _snapshot()
	if pending_hand_index == STRUGGLE_PENDING:
		battle.struggle(enemy_index)
	else:
		_play_card(pending_hand_index, enemy_index)
	pending_hand_index = -1
	_after_action(before)


## 対象の選択をやめる
func cancel_target() -> void:
	pending_hand_index = -1
	refresh()


## ターンを終える (敵の行動の後、次のターンの手札が配られる)。敵の攻撃で体力が減ったら被弾の効果音を鳴らす
## (防御で受け切った時は鳴らさない)。勝敗が決まった後 (勝った後の画面の切り替えの待ちの間) は何もしない
func end_turn() -> void:
	if pending_hand_index != -1 or battle.outcome != Battle.Outcome.NONE:
		return
	var before: Dictionary = _snapshot()
	battle.end_turn()
	if run_state.hp < before["hp"]:
		audio.play_se(AudioScript.Se.HIT)
	_after_action(before, true)


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
	_refresh_relics()
	var over: bool = battle.outcome != Battle.Outcome.NONE
	struggle_button.disabled = over or battle.energy < Battle.STRUGGLE_COST
	end_turn_button.disabled = over


## 手札の hand_index 番目のカードを target の敵に使う (対象を取らないカードは target を省く)。使えた時は、
## 回数が減ったことを耳で知らせる効果音を鳴らし (使ったカードは捨て札へ行き、残りの表示が見えなくなるため)、
## 使ったカードの複製で使う動きを見せる (手札の表示は refresh() で詰めるので、元の位置を先に控える)
func _play_card(hand_index: int, target: int = -1) -> void:
	var deck_index: int = battle.hand[hand_index]
	var card_id: String = run_state.deck[deck_index]["id"]
	var from: Rect2 = (hand_row.get_child(hand_index) as Control).get_global_rect()
	var uses_before: int = run_state.uses_left(deck_index)
	if battle.play(hand_index, target):
		var uses: int = run_state.uses_left(deck_index)
		audio.play_se(AudioScript.card_use_se(uses))
		_animate_card(card_id, uses_before, uses, from, _card_destination(card_id, target))


## 操作の後: ランを保存し (戦闘の途中で終えても、使った回数と受けた傷が戻らないように)、勝敗が決まっていれば
## 戦闘を終える (画面の切り替えは scripts/main.gd が局面の変化で行う)。勝った時は倒す動きと決めの 1 枚の動きが
## 見えるよう Art.WIN_DELAY 待ってから終え、待つ前に保存する (待ちの間に終了しても、使った回数が戻らないように)。
## 画面を更新し、操作の前の値 before (_snapshot()) との差で動きを付ける。enemy_acted は敵が行動した (ターン終了)
func _after_action(before: Dictionary, enemy_acted: bool = false) -> void:
	if battle.outcome == Battle.Outcome.NONE:
		_autosave()
	elif not finish_scheduled:
		finish_scheduled = true
		if battle.outcome == Battle.Outcome.WIN and Art.motion_on():
			_autosave()
			var wait: Tween = create_tween()
			wait.tween_interval(Art.WIN_DELAY * Art.motion_scale)
			wait.tween_callback(_finish_battle)
		else:
			_finish_battle()
	refresh()
	# 戦闘を終えて画面が切り替わった (scripts/main.gd が隠した) 後は動きを付けない
	if visible:
		_animate_changes(before, enemy_acted)
		_show_relic_triggers()


## ランを保存する。失敗したら ERROR を出す
func _autosave() -> void:
	var status: Error = run_state.autosave()
	if status != OK:
		push_error("自動保存に失敗: %s (%s)" % [run_state.save_path, error_string(status)])


## 決まった勝敗で戦闘を終え、勝利・敗北の効果音を鳴らす
func _finish_battle() -> void:
	if RunFlow.finish_battle(run_state, battle.outcome == Battle.Outcome.WIN):
		audio.play_se(
			AudioScript.Se.WIN if battle.outcome == Battle.Outcome.WIN else AudioScript.Se.LOSE
		)


## 操作の前に控える、動きを付けるために比べる値 (巡礼者の体力・ターン・敵ごとの体力と防御)
func _snapshot() -> Dictionary:
	var enemies: Array[Dictionary] = []
	for enemy: Dictionary in battle.enemies:
		enemies.append({"hp": enemy["hp"], "block": enemy["block"]})
	return {"hp": run_state.hp, "turn": battle.turn, "enemies": enemies}


## 操作の前の値 before との差で動きを付ける: 巡礼者と敵の被弾 (揺れ・赤い光・減った体力の数字。防御で受けた量は
## 別の色の数字)、倒した敵が薄くなる、ターンが変わったら手札と敵の予告をフェードで現す
func _animate_changes(before: Dictionary, enemy_acted: bool) -> void:
	if not Art.motion_on():
		return
	var lost: int = before["hp"] - run_state.hp
	var blocked: int = battle.blocked_last_enemy_turn if enemy_acted else 0
	if lost > 0 or blocked > 0:
		pilgrim_tween = Art.hit(pilgrim, pilgrim, pilgrim_tween, pilgrim_base, Art.PLAYER_SHAKE)
		_show_numbers(pilgrim.get_global_rect().get_center(), lost, blocked)
	var turn_changed: bool = battle.turn != before["turn"]
	if turn_changed:
		hand_tween = Art.fade_in(hand_row, hand_tween)
	var old_enemies: Array[Dictionary] = before["enemies"]
	for index: int in range(mini(old_enemies.size(), battle.enemies.size())):
		var enemy: Dictionary = battle.enemies[index]
		var view: EnemyView = enemy_row.get_child(index)
		var lost_hp: int = old_enemies[index]["hp"] - enemy["hp"]
		# 敵の防御は敵の行動で消えて付け直すので、受けた量は巡礼者の操作の時だけ見る
		var absorbed: int = 0 if enemy_acted else old_enemies[index]["block"] - enemy["block"]
		if lost_hp > 0 or absorbed > 0:
			view.play_hit()
			_show_numbers(view.art.get_global_rect().get_center(), lost_hp, absorbed)
		if lost_hp > 0 and enemy["hp"] <= 0:
			view.play_defeat()
		elif turn_changed and enemy["hp"] > 0:
			view.fade_in_intent()


## 全体の座標 at の上に、減った体力 lost (赤) と防御で受けた量 blocked (青。減った体力の数字の下) の数字を
## 浮かべる (0 の数字は出さない)
func _show_numbers(at: Vector2, lost: int, blocked: int) -> void:
	var local: Vector2 = at - effects_layer.global_position
	if lost > 0:
		Art.float_text(effects_layer, local, "-%d" % lost, Art.DAMAGE_COLOR)
	if blocked > 0:
		Art.float_text(
			effects_layer,
			local + Vector2(0, Art.FLOAT_FONT_SIZE),
			"防御 %d" % blocked,
			Art.BLOCKED_COLOR
		)


## card_id のカードを target の敵に使った時に、カードの複製が飛んでいく先 (全体の座標)。攻撃は狙った敵
## (全体攻撃は敵の行) の絵へ、攻撃でないカードは巡礼者へ
func _card_destination(card_id: String, target: int) -> Vector2:
	if not Cards.CARDS[card_id].has("damage"):
		return pilgrim.get_global_rect().get_center()
	if target >= 0 and target < enemy_row.get_child_count():
		return (enemy_row.get_child(target) as EnemyView).art.get_global_rect().get_center()
	return enemy_row.get_global_rect().get_center()


## 使ったカード card_id (残り uses_before 回 → uses 回) の複製を、手札で元のカードがあった全体の矩形 from に置き、
## 持ち上げ → 使った封蝋の印を光らせて焼けた印に (残り 1 回・契約切れはカードを膨らませて光らせる) → 全体の座標
## to へ縮みながら消える、と動かす。複製は入力を受けない (下の手札と敵をそのまま押せる)
func _animate_card(card_id: String, uses_before: int, uses: int, from: Rect2, to: Vector2) -> void:
	if not Art.motion_on():
		return
	var ghost: CardView = CardView.new()
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.focus_mode = Control.FOCUS_NONE
	ghost.custom_minimum_size = from.size
	effects_layer.add_child(ghost)
	ghost.show_deck_card(card_id, uses_before)
	ghost.position = from.position - effects_layer.global_position
	ghost.size = from.size
	ghost.pivot_offset = from.size / 2.0
	var scale_of: float = Art.motion_scale
	var tween: Tween = ghost.create_tween()
	tween.tween_property(
		ghost, "position:y", ghost.position.y - Art.CARD_LIFT, Art.CARD_LIFT_TIME * scale_of
	)
	# 焼けぬ封蝋で残りが減らなかった時は、焼ける印が無いので印を光らせない (発動は護符の印が見せる)
	if uses < uses_before:
		var seal: CanvasItem = ghost.seal_row.get_child(uses)
		tween.tween_property(seal, "modulate", Art.SEAL_FLASH, Art.SEAL_FLASH_TIME * scale_of)
		tween.tween_callback(_burn_seal.bind(ghost, seal, card_id, uses))
	if uses < uses_before and uses <= 1:
		var half: float = Art.STRONG_TIME * scale_of / 2.0
		tween.tween_property(ghost, "scale", Vector2.ONE * Art.STRONG_SCALE, half)
		tween.parallel().tween_property(ghost, "modulate", Art.STRONG_FLASH, half)
		tween.tween_property(ghost, "scale", Vector2.ONE, half)
		tween.parallel().tween_property(ghost, "modulate", Color.WHITE, half)
	var fly: float = Art.CARD_FLY_TIME * scale_of
	var landing: Vector2 = to - effects_layer.global_position - from.size / 2.0
	tween.tween_property(ghost, "position", landing, fly).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(ghost, "scale", Vector2.ONE * Art.CARD_FLY_SCALE, fly)
	tween.parallel().tween_property(ghost, "modulate:a", 0.0, fly).set_ease(Tween.EASE_IN)
	tween.tween_callback(ghost.queue_free)


## 使ったカードの複製 ghost の光らせた封蝋の印 seal を戻し、使った後の残り uses 回で見せ直す (光った印が焼けた印に
## なり、残り 1 回・契約切れの文と契約切れの色抜きが出る)
func _burn_seal(ghost: CardView, seal: CanvasItem, card_id: String, uses: int) -> void:
	seal.modulate = Color.WHITE
	ghost.show_deck_card(card_id, uses)


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
		var card_id: String = run_state.deck[deck_index]["id"]
		view.show_deck_card(card_id, run_state.uses_left(deck_index))
		view.show_effect(
			Cards.effect_text(card_id, battle.card_damage(deck_index), battle.card_block(deck_index))
		)
		view.set_key_number(index + 1)
		view.disabled = not battle.can_play(index)


## 持っている護符の印 (scripts/relic_view.gd) を手に入れた順に並べる (印は使い回す)。護符が無ければ説明の文も
## 出さない
func _refresh_relics() -> void:
	while relic_row.get_child_count() < run_state.relics.size():
		var view: RelicView = RelicView.new()
		view.hovered.connect(show_relic_info)
		view.unhovered.connect(_show_relic_label)
		relic_row.add_child(view)
	for index: int in range(relic_row.get_child_count()):
		var view: RelicView = relic_row.get_child(index)
		view.visible = index < run_state.relics.size()
		if view.visible:
			view.show_relic(run_state.relics[index])
	_show_relic_label()


## 護符の説明の文に relic_id の護符の名前と効果を出す (印にマウスを載せた時。検証と撮影からも呼ぶ)
func show_relic_info(relic_id: String) -> void:
	relic_label.text = UiKit.relic_text(relic_id)


## 護符の説明の文を、直前の操作で働いた護符の文 (無ければ案内) に戻す。護符が無ければ空にする
func _show_relic_label() -> void:
	if run_state.relics.is_empty():
		relic_label.text = ""
	elif not relic_trigger_text.is_empty():
		relic_label.text = relic_trigger_text
	else:
		relic_label.text = RELIC_HINT


## 直前の操作 (戦闘の開始・カードを使う) で働いた護符を見せる: 説明の文に名前を出し、動きを付けるなら印を光らせて
## 名前を印の下から浮かべる。見せた発動は battle.relic_triggers から消す (対象の選択に入るだけの操作など、護符が
## 働かない操作の後に、前の発動をもう一度見せないため)。働いた護符が無い操作の後は説明の文の名前も消すが、対象の
## 選択に入っただけの時は残す
func _show_relic_triggers() -> void:
	var triggers: Array[String] = battle.relic_triggers
	battle.relic_triggers = []
	if triggers.is_empty() and pending_hand_index != -1:
		return
	var names: Array[String] = []
	for relic_id: String in triggers:
		names.append(Relics.RELICS[relic_id]["name"])
	relic_trigger_text = "" if names.is_empty() else "護符が働いた: %s" % "・".join(names)
	_show_relic_label()
	if not Art.motion_on():
		return
	for order: int in range(triggers.size()):
		var index: int = run_state.relics.find(triggers[order])
		if index < 0 or index >= relic_row.get_child_count():
			continue
		(relic_row.get_child(index) as RelicView).flash()
		# 印の行のレイアウトは次のフレームまで遅れることがある (戦闘の開始の直後) ため、印の位置は並びから求める。
		# 同時に働いた名前は 1 つずつ下にずらして重ならないようにする
		var step: float = RelicView.SIZE.x + relic_row.get_theme_constant("separation")
		var at: Vector2 = (
			relic_row.global_position
			+ Vector2(index * step + RelicView.SIZE.x / 2.0, RelicView.SIZE.y + Art.FLOAT_FONT_SIZE * order)
		)
		Art.float_text(effects_layer, at - effects_layer.global_position, names[order], Art.CANDLE)


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


