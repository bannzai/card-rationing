extends "res://scripts/dev/headless_check.gd"
## メインシーンを tree に置いて動かす入力統合テスト (headless)。画面の遷移やキー・クリックで変わる振る舞いを
## 足したら、ここに検証を足す。実行方法は AGENTS.md「検証方法」を参照。
## キーは root.push_input() に InputEventKey を、クリックはボタンの中心への InputEventMouseButton を渡して起こす。
## 「終了して続きから」は、ラン単位の状態を新しいランで消してからタイトルの「続きから」を押して確かめる
## (起動し直した時と同じく、保存データだけから戻す)。

const ActMap := preload("res://scripts/act_map.gd")
const BattleScript := preload("res://scripts/battle.gd")
const BattleUiScript := preload("res://scripts/battle_ui.gd")
const Cards := preload("res://scripts/cards.gd")
const BossTalkScript := preload("res://scripts/boss_talk.gd")
const CharacterSelectUiScript := preload("res://scripts/character_select_ui.gd")
const Contractors := preload("res://scripts/contractors.gd")
const DeckListUiScript := preload("res://scripts/deck_list_ui.gd")
const Enemies := preload("res://scripts/enemies.gd")
const EventUiScript := preload("res://scripts/event_ui.gd")
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

## 起動時に表示するメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## ボス戦の前の会話の画面 (台詞の送り方を単体で確かめる。地図のボスの節点からの流れは _check_clear_returns_to_title)
const BOSS_TALK_SCENE: PackedScene = preload("res://scenes/boss_talk.tscn")
## 検証で使う保存先 (本番の保存データを触らない)
const INTEGRATION_SAVE_PATH: String = "user://integration_run.json"
const INTEGRATION_SETTINGS_PATH: String = "user://integration_settings.cfg"
## 巡礼の地図と戦闘の乱数を固定するシード (値に意味は無く、失敗を再現できるように固定する)
const RANDOM_SEED: int = 20261006

## autoload RunState (ラン単位の状態) と Settings (設定)
var run_state: RunStateScript = null
var settings: SettingsScript = null


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら検証するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	run_state = root.get_node_or_null("RunState")
	settings = root.get_node_or_null("Settings")
	_check(run_state != null and settings != null, "autoload RunState と Settings がある")
	if run_state == null or settings == null:
		_finish()
		return
	run_state.save_path = INTEGRATION_SAVE_PATH
	settings.settings_path = INTEGRATION_SETTINGS_PATH
	_remove_user_file(INTEGRATION_SAVE_PATH)
	_remove_user_file(INTEGRATION_SETTINGS_PATH)
	seed(RANDOM_SEED)
	# headless の DisplayServer はウィンドウの大きさを 0 と答えるため、root の大きさを project.godot の
	# viewport と同じにしてコントロールをレイアウトさせる (クリックの座標がボタンに当たるように)
	root.size = Vector2i(
		ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height")
	)
	var main: MainScript = MAIN_SCENE.instantiate()
	root.add_child(main)
	current_scene = main
	await _settle()
	_check(main.is_inside_tree(), "メインシーンが tree に入る")
	await _check_title_to_map(main)
	await _check_map_to_battle(main)
	await _check_target_selection(main)
	await _check_hand_fits_after_draw(main)
	await _check_battle_resume_keeps_uses(main)
	await _check_exhausted_deck_battle_and_reward(main)
	await _check_shrine_restores_uses(main)
	await _check_shop(main)
	await _check_event(main)
	await _check_deck_list(main)
	await _check_save_and_continue(main)
	await _check_clear_returns_to_title(main)
	await _check_defeat_returns_to_title(main)
	await _check_settings_saved(main)
	main.queue_free()
	await process_frame
	await _check_boss_talk()
	_remove_user_file(INTEGRATION_SAVE_PATH)
	_remove_user_file(INTEGRATION_SETTINGS_PATH)
	_finish()


## タイトル (保存が無いので「続きから」は出ない) → 巡礼を始める → 契約者の選択 → 地図 (出発前)
func _check_title_to_map(main: MainScript) -> void:
	var title: TitleUiScript = main.screen as TitleUiScript
	_check(title != null, "起動するとタイトルが出る")
	if title == null:
		return
	_check(title.start_button.get_global_rect().size.x > 0, "コントロールがレイアウトされる (大きさが 0 でない)")
	_check(not title.continue_button.visible, "保存が無ければ「続きから」は出ない")
	await _click(title.start_button)
	var select: CharacterSelectUiScript = main.screen as CharacterSelectUiScript
	_check(select != null, "「巡礼を始める」で契約者の選択が出る")
	if select == null:
		return
	await _click(select.character_buttons[Contractors.FIRST_CONTRACTOR])
	_check(main.screen is MapUiScript, "契約者を選ぶと地図が出る")
	_check(run_state.phase == RunStateScript.Phase.MAP and run_state.path.is_empty(), "出発前の地図")
	var starter: Array[String] = Contractors.starter_deck(Contractors.FIRST_CONTRACTOR)
	_check(run_state.deck.size() == starter.size(), "契約者の初期デッキで始まる")
	_check(FileAccess.file_exists(INTEGRATION_SAVE_PATH), "巡礼を始めると保存する")
	_check(main.deck_button.visible, "ランの画面では契約の一覧のボタンが出る")


## 地図で数字キー 1 を押すと段 0 (すべて戦闘) の左端の節点の戦闘に入り、カードを使うと残り使用回数が減って保存される
func _check_map_to_battle(main: MainScript) -> void:
	var map_ui: MapUiScript = main.screen as MapUiScript
	if map_ui == null:
		return
	var first: int = map_ui.choices[0]
	await _press_key(KEY_1)
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	_check(battle_ui != null, "地図で 1 を押すと戦闘に入る")
	_check(run_state.path.size() == 1 and run_state.path[0] == first, "選んだ節点が道に入る")
	if battle_ui == null:
		return
	_check(
		battle_ui.battle.turn == 1 and battle_ui.battle.energy == BattleScript.ENERGY_PER_TURN,
		"戦闘に入ったキーはターン終了として処理されない"
	)
	_check(_hand_buttons(battle_ui).size() == BattleScript.HAND_SIZE, "手札のボタンが 5 枚")
	_check(_hand_buttons(battle_ui)[0].get_global_rect().size.x > 0, "手札のボタンに大きさがある")
	# 段 0 の敵は 2 体のこともあるため、対象を選ばずに使えるよう敵 1 体で始め直してからカードを使う
	_start_battle_with(battle_ui, ["wild_dog"], 1)
	await _settle()
	var hand_index: int = _playable_without_target(battle_ui)
	if hand_index < 0:
		_check(false, "対象を選ばずに使えるカードが手札にある")
		return
	var deck_index: int = battle_ui.battle.hand[hand_index]
	var uses_before: int = run_state.uses_left(deck_index)
	await _click(_hand_buttons(battle_ui)[hand_index])
	_check(run_state.uses_left(deck_index) == uses_before - 1, "クリックでカードを使うと残り使用回数が 1 減る")
	var saved: RunStateScript = _load_saved()
	_check(saved.uses_left(deck_index) == uses_before - 1, "カードを使うたびに保存される")
	saved.free()


## 敵が 2 体いる時、攻撃は対象を選んでから使う (数字キーで敵を選ぶ。Esc でやめる)
func _check_target_selection(main: MainScript) -> void:
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	if battle_ui == null:
		return
	_set_deck(["slash", "slash", "guard", "breath", "spirit_arrow"])
	_start_battle_with(battle_ui, ["wild_dog", "skeleton"], 1)
	await _settle()
	var slash_hand: int = _hand_index_of(battle_ui, "slash")
	await _press_key(KEY_1 + slash_hand)
	_check(battle_ui.pending_hand_index == slash_hand, "攻撃を選ぶと対象の選択に入る")
	_check(battle_ui.message_label.text.contains("対象"), "対象を選ぶ案内が出る")
	_check(battle_ui.battle.enemies[1]["hp"] == 22, "まだ骸骨兵の体力 22")
	await _press_key(KEY_2)
	_check(battle_ui.battle.enemies[1]["hp"] == 16, "2 を押すと骸の巡礼者に 6 ダメージ")
	_check(battle_ui.pending_hand_index == -1, "使ったら対象の選択が終わる")
	var other_slash: int = _hand_index_of(battle_ui, "slash")
	var other_slash_uses: int = run_state.uses_left(battle_ui.battle.hand[other_slash])
	await _press_key(KEY_1 + other_slash)
	_check(battle_ui.pending_hand_index == other_slash, "2 枚目の斬火で対象の選択に入る")
	await _press_key(KEY_ESCAPE)
	_check(battle_ui.pending_hand_index == -1, "Esc で対象の選択をやめる")
	_check(
		run_state.uses_left(battle_ui.battle.hand[other_slash]) == other_slash_uses,
		"やめたカードは使われない"
	)
	# エネルギー 0 で S を押しても、もがくの対象の選択に入らない (入ると Enter のターン終了が効かなくなる)
	battle_ui.battle.energy = 0
	await _press_key(KEY_S)
	_check(battle_ui.pending_hand_index == -1, "エネルギー 0 ではもがくの対象の選択に入らない")
	await _press_key(KEY_ENTER)
	_check(battle_ui.battle.turn == 2, "Enter でターン終了")


## ドローで手札が 5 枚を超えても、手札のボタンがすべて画面の幅に収まり押せる
func _check_hand_fits_after_draw(main: MainScript) -> void:
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	if battle_ui == null:
		return
	_set_deck(["breath", "slash", "slash", "guard", "guard", "guard", "spirit_arrow", "slash"])
	var breath_hand: int = await _start_battle_with_card_in_hand(battle_ui, "breath")
	if breath_hand < 0:
		_check(false, "灯の精が手札に来るシードが見つかる")
		return
	await _press_key(KEY_1 + breath_hand)
	_check(battle_ui.battle.hand.size() == 6, "灯の精で手札が 6 枚になる")
	var buttons: Array[Button] = _hand_buttons(battle_ui)
	_check(buttons.size() == 6, "手札のボタンが 6 枚")
	for button: Button in buttons:
		var rect: Rect2 = button.get_global_rect()
		_check(
			rect.position.x >= 0 and rect.end.x <= root.size.x,
			"手札のボタンが画面の幅に収まる: %s" % button.text
		)
	var last: int = buttons.size() - 1
	if battle_ui.battle.can_play(last) and battle_ui.battle.alive_enemies().size() == 1:
		await _click(buttons[last])
		_check(battle_ui.battle.hand.size() == 5, "右端のカードをクリックで使える")


## 戦闘の途中で終了して「続きから」で再開しても、使ったカードの残り使用回数と受けた傷は戻らない
## (戦闘はその節点の最初からやり直す)
func _check_battle_resume_keeps_uses(main: MainScript) -> void:
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	if battle_ui == null:
		return
	run_state.new_run([], RANDOM_SEED)
	run_state.path.append(ActMap.next_columns(run_state.rows, run_state.path)[0])
	run_state.phase = RunStateScript.Phase.BATTLE
	run_state.autosave()
	main.show_run_phase()
	await _settle()
	battle_ui = main.screen as BattleUiScript
	_start_battle_with(battle_ui, ["wild_dog"], 1)
	await _settle()
	var hand_index: int = _playable_without_target(battle_ui)
	if hand_index < 0:
		_check(false, "再開の検証: 対象を選ばずに使えるカードが手札にある")
		return
	await _press_key(KEY_1 + hand_index)
	var deck_after_use: Array[Dictionary] = run_state.deck.duplicate(true)
	_check(deck_after_use != _starter_deck_entries(), "カードを使って残り使用回数が減っている")
	await _quit_and_continue(main)
	battle_ui = main.screen as BattleUiScript
	_check(battle_ui != null, "戦闘の途中から「続きから」で戦闘に戻る")
	if battle_ui == null:
		return
	_check(run_state.deck == deck_after_use, "戦闘の途中から再開しても残り使用回数が戻らない")
	_check(battle_ui.battle.turn == 1, "再開した戦闘は最初のターンから")
	# 敵の攻撃を受けてから終了しても、体力は戻らない
	for enemy: Dictionary in battle_ui.battle.enemies:
		enemy["intent"] = {"move": Enemies.Move.ATTACK, "value": 4}
	await _press_key(KEY_ENTER)
	var hp_after_attack: int = run_state.hp
	_check(hp_after_attack < RunStateScript.START_HP, "敵の攻撃で体力が減る")
	await _quit_and_continue(main)
	_check(run_state.hp == hp_after_attack, "ターンの終わりに保存され、再開しても体力が戻らない")


## デッキの全カードが契約切れでも、もがく (S) とターン終了 (Enter) で戦闘が勝敗まで進み、勝つと報酬の画面で
## 所持金を受け取り、カードを 1 枚選んで地図へ戻る
func _check_exhausted_deck_battle_and_reward(main: MainScript) -> void:
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	if battle_ui == null:
		return
	_set_deck(["slash", "guard", "breath"])
	for index: int in range(run_state.deck.size()):
		while run_state.use_card(index):
			pass
	run_state.hp = run_state.max_hp
	_start_battle_with(battle_ui, ["wild_dog"], 11)
	await _settle()
	_check(battle_ui.battle.hand.size() == 3, "契約切れのカードも手札に来る")
	for button: Button in _hand_buttons(battle_ui):
		_check(button.disabled and button.text.contains("契約切れ"), "契約切れのカードは押せず、そう表示される")
	_check(battle_ui.message_label.text.contains("使えるカードが無い"), "使えるカードが無い案内が出る")
	var gold_before: int = run_state.gold
	var steps: int = 0
	while main.screen == battle_ui and steps < EXHAUSTED_BATTLE_STEP_LIMIT:
		if battle_ui.battle.energy >= BattleScript.STRUGGLE_COST:
			await _press_key(KEY_S)
		else:
			await _press_key(KEY_ENTER)
		steps += 1
	var reward: RewardUiScript = main.screen as RewardUiScript
	_check(reward != null, "契約切れだけのデッキでも勝ち、報酬の画面が出る")
	if reward == null:
		return
	_check(run_state.phase == RunStateScript.Phase.REWARD, "勝つと報酬の局面")
	_check(
		run_state.gold == gold_before + NodeRules.reward_gold(run_state.node_seed(), ActMap.Kind.BATTLE),
		"勝つと所持金を受け取る"
	)
	_check(run_state.battles_won == 1, "勝った戦闘の数が 1")
	_check(root.gui_get_focus_owner() == reward.skip_button, "報酬の画面のフォーカスは「取らずに地図へ戻る」")
	var card_id: String = reward.offer_buttons.keys()[0]
	var size_before: int = run_state.deck.size()
	await _click(reward.offer_buttons[card_id])
	_check(run_state.deck.size() == size_before + 1, "報酬のカードを選ぶとデッキに入る")
	_check(main.screen is MapUiScript and run_state.phase == RunStateScript.Phase.MAP, "報酬の後は地図")


## 地図で契約の祠に入り、「契約を更新する」で減ったカードの残り使用回数が最大まで戻る (保存にも反映される)
func _check_shrine_restores_uses(main: MainScript) -> void:
	await _enter_kind(main, ActMap.Kind.SHRINE)
	var shrine: ShrineUiScript = main.screen as ShrineUiScript
	_check(shrine != null, "地図の祠の節点で契約の祠に入る")
	if shrine == null:
		return
	_check(run_state.phase == RunStateScript.Phase.SHRINE, "祠の局面")
	var index: int = _first_used_card()
	await _click(shrine.renew_button)
	_check(shrine.deck_grid != null, "「契約を更新する」でカードを選ぶ")
	if shrine.deck_grid == null or index < 0:
		return
	var focused: Control = root.gui_get_focus_owner()
	_check(
		focused != null and focused.get_parent() == shrine.deck_grid and not (focused as Button).disabled,
		"カードを選ぶ段階では押せる最初のカードにフォーカスがある"
	)
	var max_uses: int = run_state.card(index)["max_uses"]
	await _click(shrine.deck_grid.get_child(index) as Button)
	_check(run_state.uses_left(index) == max_uses, "祠で契約を更新すると残り使用回数が最大に戻る")
	_check(main.screen is MapUiScript and run_state.phase == RunStateScript.Phase.MAP, "祠の後は地図")
	var saved: RunStateScript = _load_saved()
	_check(saved.uses_left(index) == max_uses, "祠の結果が保存される")
	saved.free()


## 地図で商人に入り、カードを買う・残り使用回数を戻す・立ち去ると、所持金とデッキに反映される
func _check_shop(main: MainScript) -> void:
	run_state.gold = 300
	await _enter_kind(main, ActMap.Kind.SHOP)
	var shop: ShopUiScript = main.screen as ShopUiScript
	_check(shop != null, "地図の商人の節点で商人に入る")
	if shop == null:
		return
	var card_id: String = shop.card_buttons.keys()[0]
	var size_before: int = run_state.deck.size()
	await _click(shop.card_buttons[card_id])
	_check(run_state.deck.size() == size_before + 1, "商人でカードを買える")
	_check(run_state.gold == 300 - NodeRules.card_price(card_id), "値段の分だけ所持金が減る")
	_check(shop.card_buttons[card_id].disabled, "買ったカードは売り切れ")
	var index: int = _first_used_card()
	var gold_before: int = run_state.gold
	await _click(shop.restore_button)
	if shop.deck_grid != null and index >= 0:
		await _click(shop.deck_grid.get_child(index) as Button)
		_check(run_state.uses_left(index) == run_state.card(index)["max_uses"], "商人で残り使用回数を戻せる")
		_check(run_state.gold == gold_before - NodeRules.RESTORE_PRICE, "戻す値段の分だけ所持金が減る")
	else:
		_check(false, "商人で残り使用回数を戻すカードを選べる")
	await _click(shop.leave_button)
	_check(main.screen is MapUiScript and run_state.phase == RunStateScript.Phase.MAP, "商人の後は地図")


## 地図で出来事に入り、カードを選ばない選択肢を選ぶと地図へ戻る
func _check_event(main: MainScript) -> void:
	await _enter_kind(main, ActMap.Kind.EVENT)
	var event_ui: EventUiScript = main.screen as EventUiScript
	_check(event_ui != null, "地図の出来事の節点で出来事に入る")
	if event_ui == null:
		return
	var last: Button = event_ui.option_buttons.back()
	_check(not last.disabled, "最後の選択肢 (カードを選ばない) を選べる")
	await _click(last)
	_check(main.screen is MapUiScript and run_state.phase == RunStateScript.Phase.MAP, "出来事の後は地図")


## 地図で D を押すと契約の一覧が開き、全カードを並べ、並べ方を変えられ、Esc で閉じる
func _check_deck_list(main: MainScript) -> void:
	await _press_key(KEY_D)
	var deck_list: DeckListUiScript = main.deck_list
	_check(deck_list != null, "D で契約の一覧が開く")
	if deck_list == null:
		return
	_check(_visible_children(deck_list.list_grid) == run_state.deck.size(), "契約の一覧に全カードが並ぶ")
	await _click(deck_list.uses_button)
	_check(deck_list.order == DeckListUiScript.Order.USES_LEFT, "残り回数順に切り替えられる")
	var path_before: int = run_state.path.size()
	await _press_key(KEY_1)
	_check(deck_list.order == DeckListUiScript.Order.STRENGTH, "1 で強さ順に切り替えられる")
	await _press_key(KEY_2)
	_check(deck_list.order == DeckListUiScript.Order.USES_LEFT, "2 で残り回数順に切り替えられる")
	# Tab でフォーカスを地図の節点に移して Enter で押す操作も、一覧が受け止める
	await _press_key(KEY_TAB)
	await _press_key(KEY_ENTER)
	_check(
		main.screen is MapUiScript and run_state.path.size() == path_before,
		"契約の一覧を開いている間は地図のキー (数字・Tab と Enter) が効かない"
	)
	await _press_key(KEY_ESCAPE)
	_check(main.deck_list == null, "Esc で契約の一覧が閉じる")
	var map_ui: MapUiScript = main.screen as MapUiScript
	_check(
		root.gui_get_focus_owner() == map_ui.node_button(run_state.path.size(), map_ui.choices[0]),
		"契約の一覧を閉じると、開く前の地図の節点にフォーカスが戻る"
	)


## 地図で終了して「続きから」で再開すると、同じ状態 (デッキ・体力・所持金・道・局面) に戻る
func _check_save_and_continue(main: MainScript) -> void:
	var before: Dictionary = run_state.to_dict()
	await _quit_and_continue(main)
	_check(run_state.to_dict() == before, "「続きから」で保存した時と同じ状態に戻る")
	_check(main.screen is MapUiScript, "地図で終了したら地図から再開する")


## ボスの節点に入るとボス戦の前の会話が出て、送り終えるとボスとの戦闘に入り、倒すと踏破の画面が出て、
## 「タイトルへ」でタイトルに戻る (保存データは消え、続きからは出ない)
func _check_clear_returns_to_title(main: MainScript) -> void:
	await _enter_kind(main, ActMap.Kind.BOSS)
	var talk: BossTalkScript = main.screen as BossTalkScript
	_check(talk != null, "ボスの節点ではボス戦の前の会話が出る")
	if talk == null:
		return
	_check(talk.boss_id == Enemies.BOSS_ENCOUNTER[0], "会話するのはボスの節点の敵")
	var lines: int = Enemies.ENEMIES[talk.boss_id]["talk"].size()
	for _i: int in range(lines):
		await _press_key(KEY_ENTER)
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	_check(battle_ui != null, "会話の後にボスとの戦闘に入る")
	if battle_ui == null:
		return
	_check(battle_ui.battle.turn == 1, "会話を送った Enter は戦闘のターン終了に届かない")
	_check(battle_ui.battle.enemies[0]["id"] == Enemies.BOSS_ENCOUNTER[0], "戦う相手はボス")
	for enemy: Dictionary in battle_ui.battle.enemies:
		enemy["hp"] = 1
		enemy["block"] = 0
	await _press_key(KEY_S)
	var result: ResultUiScript = main.screen as ResultUiScript
	_check(result != null and run_state.phase == RunStateScript.Phase.CLEAR, "ボスを倒すと踏破の画面")
	if result == null:
		return
	_check(result.summary_label.text.contains("到達した階層: 15"), "踏破の結果に到達した階層が出る")
	_check(not FileAccess.file_exists(INTEGRATION_SAVE_PATH), "踏破で保存データが消える")
	await _click(result.title_button)
	var title: TitleUiScript = main.screen as TitleUiScript
	_check(title != null and not title.continue_button.visible, "踏破の後はタイトル (続きからは出ない)")


## タイトルから巡礼を始め、地図・戦闘を経て敗北の画面からタイトルへ戻る
func _check_defeat_returns_to_title(main: MainScript) -> void:
	var title: TitleUiScript = main.screen as TitleUiScript
	if title == null:
		return
	await _click(title.start_button)
	var select: CharacterSelectUiScript = main.screen as CharacterSelectUiScript
	if select == null:
		_check(false, "2 回目の巡礼の契約者の選択が出る")
		return
	await _click(select.character_buttons[Contractors.FIRST_CONTRACTOR])
	await _press_key(KEY_1)
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	_check(battle_ui != null, "2 回目の巡礼で戦闘に入る")
	if battle_ui == null:
		return
	run_state.hp = 1
	for _i: int in range(10):
		if main.screen != battle_ui:
			break
		for enemy: Dictionary in battle_ui.battle.enemies:
			enemy["intent"] = {"move": Enemies.Move.ATTACK, "value": 5}
		await _press_key(KEY_ENTER)
	var result: ResultUiScript = main.screen as ResultUiScript
	_check(result != null and run_state.phase == RunStateScript.Phase.DEFEAT, "体力 0 で敗北の画面")
	if result == null:
		return
	_check(result.summary_label.text.contains("到達した階層: 1"), "敗北の結果に到達した階層が出る")
	_check(not FileAccess.file_exists(INTEGRATION_SAVE_PATH), "敗北で保存データが消える")
	_check(not main.deck_button.visible, "結果の画面では契約の一覧のボタンが出ない")
	await _click(result.title_button)
	_check(main.screen is TitleUiScript, "敗北の後はタイトルへ戻る")


## 設定で音量を変えて戻ると保存され、設定を読み直しても同じ値になる
func _check_settings_saved(main: MainScript) -> void:
	var title: TitleUiScript = main.screen as TitleUiScript
	if title == null:
		return
	await _click(title.settings_button)
	var settings_ui: SettingsUiScript = main.screen as SettingsUiScript
	_check(settings_ui != null, "「設定」で設定の画面が出る")
	if settings_ui == null:
		return
	settings_ui.bgm_slider.value = 35
	settings_ui.se_slider.value = 60
	_check(settings.bgm_volume == 35 and settings.se_volume == 60, "スライダーで音量が変わる")
	# 画面を閉じる前 (戻るを押さずにゲームを終えた時) でも保存されている
	var saved: SettingsScript = SettingsScript.new()
	saved.settings_path = INTEGRATION_SETTINGS_PATH
	saved.load_settings()
	_check(saved.bgm_volume == 35 and saved.se_volume == 60, "スライダーを動かすたびに保存される")
	saved.free()
	await _press_key(KEY_ESCAPE)
	_check(main.screen is TitleUiScript, "Esc で設定からタイトルへ戻る")
	settings.bgm_volume = 0
	settings.se_volume = 0
	settings.load_settings()
	_check(settings.bgm_volume == 35 and settings.se_volume == 60, "保存した音量を読み直すと同じ値")


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


## ゲームを終了して起動し直し、タイトルの「続きから」を押す (ラン単位の状態は新しいランで消し、保存データ
## だけから戻す)
func _quit_and_continue(main: MainScript) -> void:
	run_state.new_run()
	main.show_title()
	await _settle()
	var title: TitleUiScript = main.screen as TitleUiScript
	_check(title.continue_button.visible, "保存があれば「続きから」が出る")
	await _click(title.continue_button)


## 戦闘画面の今の戦闘を、敵 enemy_ids とシード seed_value で始め直す (局面と道はそのまま)
func _start_battle_with(
	battle_ui: BattleUiScript, enemy_ids: Array[String], seed_value: int
) -> void:
	battle_ui.battle.start(run_state, enemy_ids, seed_value)
	battle_ui.pending_hand_index = -1
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
		if run_state.uses_left(index) < run_state.card(index)["max_uses"]:
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


## ボス戦の前の会話: クリックと Enter で台詞が 1 行ずつ進み、最後の台詞でだけ「戦う」が出て、選ぶと finished が
## 1 度だけ出る
func _check_boss_talk() -> void:
	var talk: BossTalkScript = BOSS_TALK_SCENE.instantiate()
	root.add_child(talk)
	await _settle()
	var boss_id: String = Enemies.BOSS_ENCOUNTER[0]
	var lines: Array = Enemies.ENEMIES[boss_id]["talk"]
	var finished_count: Array[int] = [0]
	talk.finished.connect(func() -> void: finished_count[0] += 1)
	_check(talk.boss_name_label.text == Enemies.ENEMIES[boss_id]["name"], "ボスの名前が出る")
	_check(talk.line_label.text == lines[0], "最初の台詞が出る")
	_check(not talk.fight_button.visible, "最初の台詞では「戦う」が出ない")
	await _click(talk.boss_name_label)
	_check(talk.line_label.text == lines[1], "クリックで次の台詞へ進む")
	for _i: int in range(lines.size() - 2):
		await _press_key(KEY_ENTER)
	_check(talk.line_label.text == lines[lines.size() - 1], "Enter で最後の台詞まで進む")
	_check(talk.fight_button.visible, "最後の台詞で「戦う」が出る")
	_check(finished_count[0] == 0, "最後の台詞を出しただけでは終わらない")
	await _click(talk.fight_button)
	_check(finished_count[0] == 1, "「戦う」で finished が出る")
	await _press_key(KEY_ENTER)
	_check(finished_count[0] == 1, "finished は 1 度だけ出る")
	talk.queue_free()
	await process_frame


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


## parent の表示中の子の数
func _visible_children(parent: Node) -> int:
	var count: int = 0
	for child: Node in parent.get_children():
		if child is CanvasItem and (child as CanvasItem).visible:
			count += 1
	return count


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
