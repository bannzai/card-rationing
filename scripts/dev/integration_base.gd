extends "res://scripts/dev/headless_check.gd"
## scripts/dev/integration.gd の検証が使う定数・autoload の参照と、画面の操作・状態の読み取りの部品
## (gdlint のファイルの行数の上限に収めるため、検証の本体と分けた)。

const ActMap := preload("res://scripts/act_map.gd")
const Art := preload("res://scripts/art.gd")
const AudioScript := preload("res://scripts/audio.gd")
const BattleScript := preload("res://scripts/battle.gd")
const BattleUiScript := preload("res://scripts/battle_ui.gd")
const CardViewScript := preload("res://scripts/card_view.gd")
const Cards := preload("res://scripts/cards.gd")
const BossTalkScript := preload("res://scripts/boss_talk.gd")
const CharacterSelectUiScript := preload("res://scripts/character_select_ui.gd")
const Contractors := preload("res://scripts/contractors.gd")
const DeckListUiScript := preload("res://scripts/deck_list_ui.gd")
const Enemies := preload("res://scripts/enemies.gd")
const EnemyViewScript := preload("res://scripts/enemy_view.gd")
const EventUiScript := preload("res://scripts/event_ui.gd")
const Events := preload("res://scripts/events.gd")
const MainScript := preload("res://scripts/main.gd")
const MapUiScript := preload("res://scripts/map_ui.gd")
const NodeRules := preload("res://scripts/node_rules.gd")
const ResultUiScript := preload("res://scripts/result_ui.gd")
const RewardUiScript := preload("res://scripts/reward_ui.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const SettingsScript := preload("res://scripts/settings.gd")
const SettingsUiScript := preload("res://scripts/settings_ui.gd")
const ShopUiScript := preload("res://scripts/shop_ui.gd")
const ShrineUiScript := preload("res://scripts/shrine_ui.gd")
const TitleUiScript := preload("res://scripts/title_ui.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

## 起動時に表示するメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## ボス戦の前の会話の画面 (台詞の送り方を単体で確かめる。地図のボスの節点からの流れは _check_clear_returns_to_title)
const BOSS_TALK_SCENE: PackedScene = preload("res://scenes/boss_talk.tscn")
## 検証で使う保存先 (本番の保存データを触らない)
const INTEGRATION_SAVE_PATH: String = "user://integration_run.json"
const INTEGRATION_SETTINGS_PATH: String = "user://integration_settings.cfg"
## 巡礼の地図と戦闘の乱数を固定するシード (値に意味は無く、失敗を再現できるように固定する)
const RANDOM_SEED: int = 20261006
## 決まった出来事が出る地図を探すシードの数 (出来事は 10 種で、シード 1 つごとに約 1 / 10 で当たる。
## selfcheck の _state_at_event() と同じ数)
const EVENT_SEED_LIMIT: int = 300
## 戦闘の動きの終わりを実時間で待つ時の余裕 (秒)。headless の 1 フレームは数 ms (Makefile の SCRIPT_FRAME_LIMIT の
## 根拠) なので、動きの最後のフレームの後に queue_free が済むまでには数十 ms で足り、CI の runner の遅れを見込んで
## 0.2 秒にした
const MOTION_MARGIN: float = 0.2

## autoload RunState (ラン単位の状態)・Settings (設定)・Audio (BGM と効果音)
var run_state: RunStateScript = null
var settings: SettingsScript = null
var audio: AudioScript = null


## kind の最初の節点の 1 つ手前まで道を進めた地図を出し、その節点をクリックして入る
func _enter_kind(main: MainScript, kind: ActMap.Kind) -> void:
	var at: Vector2i = ActMap.find_kind(run_state.rows, kind)
	var route: Array[int] = ActMap.route_to(run_state.rows, at.x, at.y)
	route.pop_back()
	run_state.path = route
	run_state.phase = RunStateScript.Phase.MAP
	main.show_run_phase()
	await _settle()
	var map_ui: MapUiScript = main.screen as MapUiScript
	var button: Button = map_ui.node_button(at.x, at.y) if map_ui != null else null
	_check(button != null and not button.disabled, "地図で %s の節点を選べる" % ActMap.KIND_NAMES[kind])
	if button != null:
		await _click(button)


## 戦闘の動きがすべて終わるまで待つ時間 (秒)。最も長い動き (残り 1 回・契約切れになったカードを使う動きと、
## 敵 enemy_count 体の戦闘で最も遅く当たる攻撃の最後の当たりから、当たりの後で最も長い浮かぶ数字の終わりまでの
## 大きい方) に MOTION_MARGIN を足す
func _motion_settle_time(enemy_count: int = 1) -> float:
	var last_hit: float = 0.0
	for card: Dictionary in Cards.CARDS.values():
		if not card.has("damage"):
			continue
		var order: int = enemy_count - 1 if card.get("area", false) else 0
		var delay: float = Art.attack_delay(card.get("hits", 1) - 1, order)
		if card["bond"] == Cards.Bond.HERO:
			delay += Art.HERO_HITSTOP
		last_hit = maxf(last_hit, delay)
	return (
		maxf(
			Art.CARD_LIFT_TIME + Art.SEAL_FLASH_TIME + Art.STRONG_TIME + Art.CARD_FLY_TIME,
			last_hit + Art.FLOAT_TIME
		)
		+ MOTION_MARGIN
	)


## node と、その下のすべての Control がマウスを通すか
func _ignores_mouse(node: Node) -> bool:
	if node is Control and (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		return false
	for child: Node in node.get_children():
		if not _ignores_mouse(child):
			return false
	return true


## parent の子に、文が text のラベルがあるか
func _has_label(parent: Node, text: String) -> bool:
	for child: Node in parent.get_children():
		if child is Label and (child as Label).text == text:
			return true
	return false


## event_id の出来事が出る地図のシードを 1 から順に探して新しい巡礼にし、その出来事の節点に入った局面にする
## (画面は呼ぶ側が出す)。見つからなければ失敗にして false
func _start_run_at_event(event_id: String) -> bool:
	for seed_value: int in range(1, EVENT_SEED_LIMIT + 1):
		run_state.new_run([], seed_value)
		var at: Vector2i = ActMap.find_kind(run_state.rows, ActMap.Kind.EVENT)
		run_state.path = ActMap.route_to(run_state.rows, at.x, at.y)
		if Events.event_for(run_state.node_seed()) == event_id:
			run_state.phase = RunStateScript.Phase.EVENT
			return true
	_check(false, "出来事 %s が出る地図が見つかる" % event_id)
	return false


## ゲームを終了して起動し直し、タイトルの「続きから」を押す (ラン単位の状態は新しいランで消し、保存データ
## だけから戻す)
func _quit_and_continue(main: MainScript) -> void:
	run_state.new_run()
	main.show_title()
	await _settle()
	var title: TitleUiScript = main.screen as TitleUiScript
	_check(title.continue_button.visible, "保存があれば「続きから」が出る")
	_check(_bgm_is(AudioScript.Bgm.NONE), "巡礼の途中でタイトルへ戻ると BGM が止まる")
	await _click(title.continue_button)


## 戦闘画面の今の戦闘を、敵 enemy_ids とシード seed_value で始め直す (局面と道はそのまま)
func _start_battle_with(
	battle_ui: BattleUiScript, enemy_ids: Array[String], seed_value: int
) -> void:
	battle_ui.battle.start(run_state, enemy_ids, seed_value)
	battle_ui.pending_hand_index = -1
	battle_ui.finish_scheduled = false
	battle_ui.refresh()


## card_id のカードが手札に来るシードで戦闘を始め、そのカードの手札の位置を返す (シードを 1 から順に試し、
## 見つからなければ -1)
func _start_battle_with_card_in_hand(battle_ui: BattleUiScript, card_id: String) -> int:
	for seed_value: int in range(1, 51):
		_start_battle_with(battle_ui, ["wild_dog"], seed_value)
		var hand_index: int = _hand_index_of(battle_ui, card_id)
		if hand_index >= 0:
			await _settle()
			return hand_index
	return -1


## デッキを ids のカード (最大使用回数) にする (局面と道はそのまま)
func _set_deck(ids: Array[String]) -> void:
	run_state.deck.clear()
	for card_id: String in ids:
		run_state.add_card(card_id)


## 新しいランの初期デッキの要素の並び
func _starter_deck_entries() -> Array[Dictionary]:
	var fresh: RunStateScript = RunStateScript.new()
	fresh.new_run()
	var entries: Array[Dictionary] = fresh.deck.duplicate(true)
	fresh.free()
	return entries


## 保存データを読み込んだ別のラン単位の状態 (呼んだ側が free する)
func _load_saved() -> RunStateScript:
	var saved: RunStateScript = RunStateScript.new()
	_check(saved.load_from(INTEGRATION_SAVE_PATH) == RunStateScript.LoadResult.LOADED, "保存データを読める")
	return saved


## デッキで残り使用回数が最大より減っている最初のカード (無ければ最初のカードを 1 回使ってそれを返す)
func _first_used_card() -> int:
	for index: int in range(run_state.deck.size()):
		if run_state.uses_left(index) < Cards.deck_max_uses(run_state.deck[index]):
			return index
	return 0 if run_state.use_card(0) else -1


## 手札の中で、対象を選ばずに使え (攻撃でないか、敵が 1 体)、使っても戦闘が終わらない (敵を倒さない) カードの
## 位置 (無ければ -1)
func _playable_without_target(battle_ui: BattleUiScript) -> int:
	var alive: Array[int] = battle_ui.battle.alive_enemies()
	for hand_index: int in range(battle_ui.battle.hand.size()):
		var card_id: String = run_state.deck[battle_ui.battle.hand[hand_index]]["id"]
		if not battle_ui.battle.can_play(hand_index):
			continue
		if not Cards.needs_target(card_id):
			return hand_index
		if alive.size() != 1:
			continue
		var enemy: Dictionary = battle_ui.battle.enemies[alive[0]]
		if Cards.CARDS[card_id]["damage"] < enemy["hp"] + enemy["block"]:
			return hand_index
	return -1


## track の BGM が鳴っているか (NONE なら、BGM が鳴っていないか)
func _bgm_is(track: AudioScript.Bgm) -> bool:
	return audio.bgm == track and audio.bgm_player.playing == (track != AudioScript.Bgm.NONE)


## se の効果音が鳴っているか
func _se_playing(se: AudioScript.Se) -> bool:
	return (audio.se_players[se] as AudioStreamPlayer).playing


## 効果音をすべて止める (次の操作で鳴る効果音だけを確かめるため)
func _stop_se() -> void:
	for player: AudioStreamPlayer in audio.se_players.values():
		player.stop()


## 戦闘画面の手札のボタン (表示中のものだけ)
func _hand_buttons(battle_ui: BattleUiScript) -> Array[Button]:
	var buttons: Array[Button] = []
	for child: Button in battle_ui.hand_row.get_children():
		if child.visible:
			buttons.append(child)
	return buttons


## 手札の中で card_id のカードがある位置 (無ければ -1)
func _hand_index_of(battle_ui: BattleUiScript, card_id: String) -> int:
	for hand_index: int in range(battle_ui.battle.hand.size()):
		if run_state.deck[battle_ui.battle.hand[hand_index]]["id"] == card_id:
			return hand_index
	return -1


## buttons のすべてが画面の幅に収まるか (label は失敗の文の頭に付ける)
func _check_buttons_fit(buttons: Array, label: String) -> void:
	for button: Button in buttons:
		var rect: Rect2 = button.get_global_rect()
		_check(
			rect.position.x >= 0 and rect.end.x <= root.size.x,
			"%sのボタンが画面の幅に収まる: %s" % [label, _button_label(button)]
		)


## button を失敗の文で指す名前 (カードならカードの名前、ほかはボタンの文)
func _button_label(button: Button) -> String:
	var view: CardViewScript = button as CardViewScript
	return view.name_label.text if view != null else button.text


## view の封蝋の印の列の (残っている印の数, 焼けた印の数)
func _seal_counts(view: CardViewScript) -> Vector2i:
	var counts: Vector2i = Vector2i.ZERO
	for icon: TextureRect in view.seal_row.get_children():
		if not icon.visible:
			continue
		if icon.texture == Art.SEAL:
			counts.x += 1
		else:
			counts.y += 1
	return counts


## parent の表示中の子の数
func _visible_children(parent: Node) -> int:
	var count: int = 0
	for child: Node in parent.get_children():
		if child is CanvasItem and (child as CanvasItem).visible:
			count += 1
	return count


## parent の子で、文が text のラベルの数
func _count_labels(parent: Node, text: String) -> int:
	var count: int = 0
	for child: Node in parent.get_children():
		if child is Label and (child as Label).text == text:
			count += 1
	return count


## parent の子に、全体の攻撃の波の輪 (閉じた Line2D) があるか
func _has_wave(parent: Node) -> bool:
	for child: Node in parent.get_children():
		if child is Line2D and (child as Line2D).closed:
			return true
	return false


## parent の子に、英霊の攻撃の画面の閃光 (ColorRect) があるか
func _has_screen_flash(parent: Node) -> bool:
	for child: Node in parent.get_children():
		if child is ColorRect:
			return true
	return false


## keycode のキーを押して、画面の更新とレイアウトが終わるまで待つ
func _press_key(keycode: int) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode as Key
	event.pressed = true
	root.push_input(event)
	await _settle()


## control の中心を左クリック (押して離す) して、画面の更新とレイアウトが終わるまで待つ
func _click(control: Control) -> void:
	var center: Vector2 = control.get_global_rect().get_center()
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = center
		event.global_position = center
		root.push_input(event)
	await _settle()


## 画面の更新とコンテナのレイアウト (次のフレームに遅延する) が終わるまで 2 フレーム待つ
func _settle() -> void:
	await process_frame
	await process_frame


## user:// のファイルを消す (無ければ何もしない)
func _remove_user_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.open(path.get_base_dir()).remove(path.get_file())
