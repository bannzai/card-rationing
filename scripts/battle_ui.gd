extends Control
## 戦闘画面。進行は scripts/battle.gd に任せ、ここは表示と入力 (マウスのクリックとキーボード) だけを受け持つ。
## 見た目は「蝋と灯火」(documents/DIRECTION.md「デザインの方向」): 祠の道の絵の左に巡礼者、右に敵を置き、
## エネルギーは灯っている蝋燭の数、体力は数珠の珠で示す。手札のカード (scripts/card_view.gd) は残り使用回数を
## 封蝋の印の列で必ず見せ、契約切れ (残り 0) のカードは色を失う。
## カードを使うたびとターンの終わりにランを保存し、勝敗が決まったら scripts/run_flow.gd で戦闘を終える
## (報酬・踏破・敗北の画面へは scripts/main.gd が切り替える)。
## カードを使った後の残り使用回数・被弾・勝敗に合わせて効果音を鳴らす (回数の増減を耳でも分かるように)。
## 操作の前後の差で戦闘の動き (使ったカードが持ち上がって封蝋の印が焼け、敵の方へ消える・被弾の揺れと数字・倒した
## 敵が薄くなる・ターンの始まりのフェード。長さと強さは scripts/art.gd) を付ける。攻撃カードは、敵に当たる演出を
## 攻撃の形 (単体・複数回・全体) と区分 (精霊・英霊) で変え、当たりごとに揺れと数字を出す。動きは表示だけで、
## 戦闘の状態は即時に変わり、次の入力も待たせない。最後の敵を倒した時だけ、動きが見えるよう画面の切り替えを待つ。

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
## 戦闘の動き (使ったカードの複製・浮かぶ数字) を描く層。最後の子にして手札と敵の上に描き、マウスは通す
var effects_layer: Control = null
## 巡礼者の絵の元の位置 (被弾で揺らした後に戻す) と、動いている被弾・手札のフェードの tween
var pilgrim_base: Vector2 = Vector2.ZERO
var pilgrim_tween: Tween = null
var hand_tween: Tween = null
## 勝敗が決まった後の戦闘の終わりを予約したか (勝った後の待ちの間の入力で、戦闘を 2 度終えないように)
var finish_scheduled: bool = false
## 直前に使った攻撃カード ({"card_id", "hits": battle.last_play_hits の複製})。_after_action() が受け取って
## 空にする (攻撃カードを使わなかった操作では空)
var played_attack: Dictionary = {}
## 攻撃の 2 回目以降の当たりと英霊の間 (ヒットストップ) の後の演出を待たせている tween (戦闘を始め直す時と画面を
## 隠す時に止め、次の戦闘の敵に演出を出さない)
var attack_tweens: Array[Tween] = []
## 戦闘画面の元の位置 (英霊の攻撃で揺らした後に戻す) と、動いている画面の揺れの tween
var screen_base: Vector2 = Vector2.ZERO
var screen_tween: Tween = null

## scenes/battle.tscn のノード (enemy_row の敵・hand_row のカード・energy_row の蝋燭・health_row の珠は
## refresh() が足す)
@onready var floor_label: Label = $FloorLabel
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
	pilgrim_base = pilgrim.position
	screen_base = position
	message_label.add_theme_color_override("font_color", Art.CANDLE)
	struggle_button.pressed.connect(request_struggle)
	end_turn_button.pressed.connect(end_turn)
	effects_layer = Control.new()
	effects_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	effects_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(effects_layer)


## 画面を隠したら (戦闘を終えて scripts/main.gd が切り替えた)、待たせている攻撃の演出を止める
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		_stop_attacks()


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


## 今いる節点の敵と seed_value で戦闘を始める (巡礼者の絵は巡礼に出ている契約者の立ち絵)
func start_battle(seed_value: int) -> void:
	pilgrim.texture = Art.PORTRAITS[run_state.character_id]
	battle = Battle.new()
	battle.start(run_state, RunFlow.encounter(run_state), seed_value)
	_stop_attacks()
	pending_hand_index = -1
	finish_scheduled = false
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
	# カードの効果でエネルギーが 1 ターンの分 (契約者の個性で増えた分を含む) を超えたら、蝋燭を増やして見せる
	# (基準の本数を超えた分は蝋燭を縮め、手札の行にはみ出さないようにする)
	var candles: int = maxi(battle.energy, battle.energy_per_turn())
	Art.set_icons(
		energy_row,
		Art.CANDLE_LIT,
		Art.CANDLE_OUT,
		battle.energy,
		candles,
		CANDLE_SIZE * minf(1.0, float(Battle.ENERGY_PER_TURN) / candles)
	)
	energy_label.text = "エネルギー %d / %d" % [battle.energy, battle.energy_per_turn()]
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
## 回数が減ったことを耳で知らせる効果音を鳴らし (使ったカードは捨て札へ行き、残りの表示が見えなくなるため)、
## 使ったカードの複製で使う動きを見せる (手札の表示は refresh() で詰めるので、元の位置を先に控える)。攻撃カードは
## 当たりごとの結果を控え、_after_action() で当たる演出を付ける
func _play_card(hand_index: int, target: int = -1) -> void:
	var deck_index: int = battle.hand[hand_index]
	var card_id: String = run_state.deck[deck_index]["id"]
	var from: Rect2 = (hand_row.get_child(hand_index) as Control).get_global_rect()
	var uses_before: int = run_state.uses_left(deck_index)
	if battle.play(hand_index, target):
		var uses: int = run_state.uses_left(deck_index)
		audio.play_se(AudioScript.card_use_se(uses))
		_animate_card(card_id, uses_before, uses, from, _card_destination(card_id, target))
		if not battle.last_play_hits.is_empty():
			played_attack = {"card_id": card_id, "hits": battle.last_play_hits.duplicate(true)}


## 操作の後: ランを保存し (戦闘の途中で終えても、使った回数と受けた傷が戻らないように)、勝敗が決まっていれば
## 戦闘を終える (画面の切り替えは scripts/main.gd が局面の変化で行う)。勝った時は倒す動きと決めの 1 枚の動きが
## 見えるよう Art.WIN_DELAY 待ってから終え、待つ前に保存する (待ちの間に終了しても、使った回数が戻らないように)。
## 画面を更新し、操作の前の値 before (_snapshot()) との差と、使った攻撃カード (played_attack) で動きを付ける。
## enemy_acted は敵が行動した (ターン終了)
func _after_action(before: Dictionary, enemy_acted: bool = false) -> void:
	var attack: Dictionary = played_attack
	played_attack = {}
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
		_animate_changes(before, enemy_acted, attack)


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
## 別の色の数字)、倒した敵が薄くなる、ターンが変わったら手札と敵の予告をフェードで現す。攻撃カード attack
## (played_attack) が当たった敵は、差ではなく当たりごとの演出 (_animate_attack()) で見せる
func _animate_changes(before: Dictionary, enemy_acted: bool, attack: Dictionary) -> void:
	if not Art.motion_on():
		return
	var struck: Dictionary = {}
	if not attack.is_empty():
		struck = _animate_attack(attack)
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
		if struck.has(index):
			continue
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


## 攻撃カード attack (played_attack) が敵に当たる演出を、当たりごとに Art.attack_delay() の時に出す (1 回目は
## すぐ)。当たった敵の enemies の index の集まり (キーだけを使う) を返す。当たりで倒した敵は、倒す動きを最後の
## 当たりまで待たせ、それまでは生きている時の色で見せる
func _animate_attack(attack: Dictionary) -> Dictionary:
	var card: Dictionary = Cards.CARDS[attack["card_id"]]
	var hero: bool = card["bond"] == Cards.Bond.HERO
	var area: bool = card.get("area", false)
	var hits: Array = attack["hits"]
	var last_hit: Dictionary = {}
	for index: int in range(hits.size()):
		last_hit[hits[index]["target"]] = index
	for target: int in last_hit:
		if battle.enemies[target]["hp"] <= 0:
			(enemy_row.get_child(target) as EnemyView).art.modulate = Color.WHITE
	for index: int in range(hits.size()):
		var entry: Dictionary = hits[index]
		var defeats: bool = (
			last_hit[entry["target"]] == index and battle.enemies[entry["target"]]["hp"] <= 0
		)
		_after_delay(
			Art.attack_delay(entry["hit"], entry["order"]),
			_strike_enemy.bind(entry, area, hero, defeats)
		)
	return last_hit


## 攻撃の当たり entry (battle.last_play_hits の 1 要素) の演出を、当たった敵の絵の上に出す: 全体の攻撃 (area) は
## 波の輪、それ以外は斬撃の軌跡 (複数回の攻撃は 1 回ごとに向きを入れ替える) に、閃光と火の粉を添える。英霊 (hero)
## は大きくし、画面を光らせ、間 (ヒットストップ) を置いてから揺れと数字を出す。defeats なら倒す動きも出す
func _strike_enemy(entry: Dictionary, area: bool, hero: bool, defeats: bool) -> void:
	var view: EnemyView = _struck_view(entry)
	if view == null:
		return
	var at: Vector2 = view.art.get_global_rect().get_center() - effects_layer.global_position
	var magnitude: float = Art.HERO_SCALE if hero else 1.0
	if area:
		Art.wave(effects_layer, at, magnitude)
	else:
		var tilt: float = -Art.STRIKE_ANGLE if entry["hit"] % 2 == 0 else Art.STRIKE_ANGLE
		Art.strike(effects_layer, at, tilt, magnitude)
	Art.impact(effects_layer, at, magnitude)
	Art.sparks(effects_layer, at, magnitude)
	if hero:
		Art.screen_flash(effects_layer)
		_after_delay(Art.HERO_HITSTOP, _land_hit.bind(entry, hero, defeats))
	else:
		_land_hit(entry, hero, defeats)


## 攻撃の当たり entry を受けた敵を揺らし、減った体力と防御で受けた量の数字を出す。英霊 (hero) なら画面も揺らす。
## defeats なら倒す動きを出す
func _land_hit(entry: Dictionary, hero: bool, defeats: bool) -> void:
	var view: EnemyView = _struck_view(entry)
	if view == null:
		return
	view.play_hit()
	_show_numbers(view.art.get_global_rect().get_center(), entry["lost"], entry["absorbed"])
	if defeats:
		view.play_defeat()
	if hero:
		screen_tween = Art.hit(self, null, screen_tween, screen_base, Art.SCREEN_SHAKE)


## 攻撃の当たり entry を受けた敵の見た目。画面を隠した後や、敵の数が変わった後 (演出を出す先が無い) は null
func _struck_view(entry: Dictionary) -> EnemyView:
	var target: int = entry["target"]
	if not visible or target >= enemy_row.get_child_count():
		return null
	return enemy_row.get_child(target) as EnemyView


## delay 秒 (motion_scale を掛ける前) の後に callback を呼ぶ。0 ならすぐ呼ぶ。待たせる tween は attack_tweens に
## 控える (_stop_attacks() で止める)
func _after_delay(delay: float, callback: Callable) -> void:
	if delay <= 0.0:
		callback.call()
		return
	var valid: Array[Tween] = []
	for tween: Tween in attack_tweens:
		if tween.is_valid():
			valid.append(tween)
	attack_tweens = valid
	var waiting: Tween = create_tween()
	waiting.tween_interval(delay * Art.motion_scale)
	waiting.tween_callback(callback)
	attack_tweens.append(waiting)


## 待たせている攻撃の演出をすべて止める
func _stop_attacks() -> void:
	for tween: Tween in attack_tweens:
		tween.kill()
	attack_tweens.clear()


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
	var seal: CanvasItem = ghost.seal_row.get_child(uses)
	var scale_of: float = Art.motion_scale
	var tween: Tween = ghost.create_tween()
	tween.tween_property(
		ghost, "position:y", ghost.position.y - Art.CARD_LIFT, Art.CARD_LIFT_TIME * scale_of
	)
	tween.tween_property(seal, "modulate", Art.SEAL_FLASH, Art.SEAL_FLASH_TIME * scale_of)
	tween.tween_callback(_burn_seal.bind(ghost, seal, card_id, uses))
	if uses <= 1:
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


