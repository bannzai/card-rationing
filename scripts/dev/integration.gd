extends "res://scripts/dev/integration_base.gd"
## メインシーンを tree に置いて動かす入力統合テスト (headless)。画面の遷移やキー・クリックで変わる振る舞いを
## 足したら、ここに検証を足す。実行方法は AGENTS.md「検証方法」を参照。
## キーは root.push_input() に InputEventKey を、クリックはボタンの中心への InputEventMouseButton を渡して起こす。
## 「終了して続きから」は、ラン単位の状態を新しいランで消してからタイトルの「続きから」を押して確かめる
## (起動し直した時と同じく、保存データだけから戻す)。
## 場面ごとに鳴る BGM と効果音は、autoload Audio のプレイヤーが鳴っているかで確かめる (headless でも再生の状態は
## 進む)。効果音は直前の操作のものが鳴り終わっていないことがあるため、確かめる操作の前に _stop_se() で止める。
## 定数・autoload の参照・操作の部品は scripts/dev/integration_base.gd に置く。

## 戦闘の動きの終わりを実時間で待つ時の余裕 (秒)。headless の 1 フレームは数 ms (Makefile の SCRIPT_FRAME_LIMIT の
## 根拠) なので、動きの最後のフレームの後に queue_free が済むまでには数十 ms で足り、CI の runner の遅れを見込んで
## 0.2 秒にした
const MOTION_MARGIN: float = 0.2


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら検証するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	run_state = root.get_node_or_null("RunState")
	settings = root.get_node_or_null("Settings")
	audio = root.get_node_or_null("Audio")
	_check(
		run_state != null and settings != null and audio != null,
		"autoload RunState と Settings と Audio がある"
	)
	if run_state == null or settings == null or audio == null:
		_finish()
		return
	run_state.save_path = INTEGRATION_SAVE_PATH
	settings.settings_path = INTEGRATION_SETTINGS_PATH
	# 入力の直後の画面を確かめる検証が、勝った後の画面の切り替えの待ちや動きの途中の表示に左右されないよう、戦闘の
	# 動きを止める (動きを付けたまま確かめるのは、倍率を 1 に戻して呼ぶ _check_input_during_motion() と
	# _check_win_waits_for_motion() だけ。途中で return しても 0 に戻るよう、倍率は呼ぶ側で切り替える)
	Art.motion_scale = 0.0
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
	await _check_hand_card_seals(main)
	await _check_battle_sounds(main)
	await _check_hand_fits_after_draw(main)
	Art.motion_scale = 1.0
	await _check_input_during_motion(main)
	Art.motion_scale = 0.0
	await _check_battle_resume_keeps_uses(main)
	await _check_exhausted_deck_battle_and_reward(main)
	Art.motion_scale = 1.0
	await _check_win_waits_for_motion(main)
	Art.motion_scale = 0.0
	await _check_shrine_restores_uses(main)
	await _check_deck_grid_follows_focus(main)
	await _check_shop(main)
	await _check_event(main)
	await _check_blood_spring_sound(main)
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
	# 鳴らした BGM・効果音を止め、解放を待ってから終える (待たないとリークの WARNING が出る)
	audio.stop_all()
	await create_timer(AUDIO_RELEASE_TIME).timeout
	# 戦闘の動きの終わりを実時間で待つ検証があるので、Makefile の SCRIPT_FRAME_LIMIT との余裕を CI のログで見る
	print("integration: %d フレーム" % Engine.get_process_frames())
	_finish()


## タイトル (保存が無いので「続きから」は出ない) → 巡礼を始める → 契約者の選択 → 地図 (出発前)
func _check_title_to_map(main: MainScript) -> void:
	var title: TitleUiScript = main.screen as TitleUiScript
	_check(title != null, "起動するとタイトルが出る")
	if title == null:
		return
	_check(title.start_button.get_global_rect().size.x > 0, "コントロールがレイアウトされる (大きさが 0 でない)")
	_check(not title.continue_button.visible, "保存が無ければ「続きから」は出ない")
	_check(_bgm_is(AudioScript.Bgm.NONE), "タイトルでは BGM を鳴らさない")
	await _click(title.start_button)
	var select: CharacterSelectUiScript = main.screen as CharacterSelectUiScript
	_check(select != null, "「巡礼を始める」で契約者の選択が出る")
	if select == null:
		return
	await _click(select.character_buttons[Contractors.FIRST_CONTRACTOR])
	_check(main.screen is MapUiScript, "契約者を選ぶと地図が出る")
	_check(_bgm_is(AudioScript.Bgm.MAP), "地図では地図の曲が鳴る")
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
	_check(_bgm_is(AudioScript.Bgm.BATTLE), "戦闘では戦闘の曲が鳴る")
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
	_check(
		_se_playing(AudioScript.card_use_se(run_state.uses_left(deck_index))),
		"カードを使うと、使った後の残り使用回数に応じた効果音が鳴る"
	)
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


## 手札のカードは残り使用回数を封蝋の印の列で見せる (残っている印と焼けた印の数が、残りと使った回数に合う)。
## 残り 1 回のカードにはそう書く
func _check_hand_card_seals(main: MainScript) -> void:
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	if battle_ui == null:
		return
	_set_deck(["slash"])
	run_state.use_card(0)
	run_state.use_card(0)
	_start_battle_with(battle_ui, ["wild_dog"], 1)
	await _settle()
	var view: CardViewScript = _hand_buttons(battle_ui)[0] as CardViewScript
	var max_uses: int = Cards.CARDS["slash"]["max_uses"]
	_check(
		_seal_counts(view) == Vector2i(max_uses - 2, 2),
		"2 回使ったカードは、焼けた印が 2 つで残りが残っている印"
	)
	_check(
		view.face.material == null and view.note_label.text == "",
		"残りのあるカードは色を保ち、補足の文を出さない"
	)
	while run_state.uses_left(0) > 1:
		run_state.use_card(0)
	battle_ui.refresh()
	_check(
		_seal_counts(view).x == 1 and view.note_label.text == CardViewScript.LAST_USE_NOTE,
		"残り 1 回のカードは印が 1 つ残り、「最後の 1 回」と出る"
	)


## カードを使った後の残り使用回数で効果音が変わり (鳴らし分けは scripts/audio.gd の card_use_se())、敵の攻撃で
## 体力が減った時だけ被弾の効果音が鳴る
func _check_battle_sounds(main: MainScript) -> void:
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	if battle_ui == null:
		return
	# 守りの風 5 枚 (対象を選ばず、敵を倒さない) を全部手札に持ち、デッキの 0〜2 番目を、使った後の残りが
	# 2・1・0 回になるよう先に減らしておく
	var expected: Array = [AudioScript.Se.CARD_USE, AudioScript.Se.LAST_ONE, AudioScript.Se.EXPIRED]
	_set_deck(["guard", "guard", "guard", "guard", "guard"])
	for deck_index: int in range(expected.size()):
		while run_state.uses_left(deck_index) > expected.size() - deck_index:
			run_state.use_card(deck_index)
	_start_battle_with(battle_ui, ["wild_dog"], 1)
	await _settle()
	for deck_index: int in range(expected.size()):
		_stop_se()
		await _press_key(KEY_1 + battle_ui.battle.hand.find(deck_index))
		for se: AudioScript.Se in expected:
			_check(
				_se_playing(se) == (se == expected[deck_index]),
				(
					"使った後の残り %d 回では効果音 %d だけが鳴る (効果音 %d)"
					% [run_state.uses_left(deck_index), expected[deck_index], se]
				)
			)
	# 守りの風 3 枚の防御 15 が残っているので、最初の攻撃は受け切る。次のターンは防御が消えて体力が減る
	for enemy: Dictionary in battle_ui.battle.enemies:
		enemy["intent"] = {"move": Enemies.Move.ATTACK, "value": 4}
	_stop_se()
	var hp_before: int = run_state.hp
	await _press_key(KEY_ENTER)
	_check(
		run_state.hp == hp_before and not _se_playing(AudioScript.Se.HIT),
		"防御で受け切った攻撃では被弾の効果音が鳴らない"
	)
	for enemy: Dictionary in battle_ui.battle.enemies:
		enemy["intent"] = {"move": Enemies.Move.ATTACK, "value": 4}
	await _press_key(KEY_ENTER)
	_check(
		run_state.hp < hp_before and _se_playing(AudioScript.Se.HIT),
		"体力が減る攻撃で被弾の効果音が鳴る"
	)


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
	_check_buttons_fit(buttons, "手札")
	var last: int = buttons.size() - 1
	if battle_ui.battle.can_play(last) and battle_ui.battle.alive_enemies().size() == 1:
		await _click(buttons[last])
		_check(battle_ui.battle.hand.size() == 5, "右端のカードをクリックで使える")


## 戦闘の動きの途中に続けて入力しても、戦闘の状態と表示が壊れない: カードを使う動きの最中に次のカードをキーで
## 使い、手札をクリックで使い、ターンを終えると防御で受けた量の数字が出る。動きの層は入力を受けない。動きが
## 終わると、複製と数字が消え、揺らした・光らせた・フェードした表示が元に戻る
func _check_input_during_motion(main: MainScript) -> void:
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	if battle_ui == null:
		_check(false, "動きの検証: 戦闘の画面が出ている")
		return
	_set_deck(["guard", "guard", "slash", "slash", "slash"])
	_start_battle_with(battle_ui, ["wild_dog"], 1)
	await _settle()
	var guards: Array[int] = []
	for hand_index: int in range(battle_ui.battle.hand.size()):
		if run_state.deck[battle_ui.battle.hand[hand_index]]["id"] == "guard":
			guards.append(battle_ui.battle.hand[hand_index])
	await _click(_hand_buttons(battle_ui)[battle_ui.battle.hand.find(guards[0])])
	_check(battle_ui.effects_layer.get_child_count() > 0, "カードを使うと、使ったカードの複製が動いている")
	await _press_key(KEY_1 + battle_ui.battle.hand.find(guards[1]))
	var guard: Dictionary = Cards.CARDS["guard"]
	_check(
		(
			battle_ui.battle.energy == BattleScript.ENERGY_PER_TURN - 2 * guard["cost"]
			and battle_ui.battle.hand.size() == 3
			and battle_ui.battle.block == 2 * guard["block"]
			and run_state.uses_left(guards[0]) == guard["max_uses"] - 1
			and run_state.uses_left(guards[1]) == guard["max_uses"] - 1
		),
		"動きの途中に続けて使ったカードも、エネルギー・手札・防御・残り使用回数に反映される"
	)
	_check(_ignores_mouse(battle_ui.effects_layer), "動きの層 (複製と数字) はすべてマウスを通す")
	var enemy: Dictionary = battle_ui.battle.enemies[0]
	var hp_before: int = enemy["hp"]
	await _click(_hand_buttons(battle_ui)[0])
	_check(
		enemy["hp"] == hp_before - Cards.CARDS["slash"]["damage"] and battle_ui.battle.hand.size() == 2,
		"複製が動いている間も手札をクリックで使える"
	)
	enemy["intent"] = {"move": Enemies.Move.ATTACK, "value": 4}
	var player_hp: int = run_state.hp
	await _press_key(KEY_ENTER)
	_check(
		battle_ui.battle.turn == 2 and run_state.hp == player_hp,
		"動きの途中に Enter でターンを終え、防御で受け切る"
	)
	_check(
		_has_label(battle_ui.effects_layer, "防御 %d" % 4), "防御で受けた量の数字が出る"
	)
	for index: int in range(battle_ui.battle.hand.size()):
		var view: CardViewScript = _hand_buttons(battle_ui)[index] as CardViewScript
		var deck_index: int = battle_ui.battle.hand[index]
		_check(
			(
				view.card_id == run_state.deck[deck_index]["id"]
				and view.uses_left == run_state.uses_left(deck_index)
			),
			"動きの途中に配られた手札の %d 枚目が、手札のカードと残り使用回数を見せる" % (index + 1)
		)
	await create_timer(_motion_settle_time()).timeout
	await _settle()
	_check(battle_ui.effects_layer.get_child_count() == 0, "動きが終わると複製と数字が消える")
	var enemy_view: EnemyViewScript = battle_ui.enemy_row.get_child(0) as EnemyViewScript
	_check(
		(
			battle_ui.hand_row.modulate.is_equal_approx(Color.WHITE)
			and enemy_view.column.position.is_equal_approx(Vector2.ZERO)
			and enemy_view.art.self_modulate.is_equal_approx(Color.WHITE)
			and enemy_view.intent_label.modulate.is_equal_approx(Color.WHITE)
			and battle_ui.pilgrim.position.is_equal_approx(battle_ui.pilgrim_base)
			and battle_ui.pilgrim.self_modulate.is_equal_approx(Color.WHITE)
		),
		"動きが終わると、手札・敵・巡礼者の位置と色が元に戻る"
	)


## 最後の敵を倒すと、倒す動きが見えるよう Art.WIN_DELAY だけ戦闘の画面のまま待ってから報酬の画面へ移る。待つ前に
## 保存し、待ちの間の入力 (Enter・S) では戦闘を 2 度終えない (勝った戦闘の数と所持金は 1 回分だけ増える)
func _check_win_waits_for_motion(main: MainScript) -> void:
	await _enter_kind(main, ActMap.Kind.BATTLE)
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	if battle_ui == null:
		_check(false, "勝った後の待ちの検証: 戦闘の画面が出る")
		return
	_set_deck(["slash"])
	_start_battle_with(battle_ui, ["wild_dog"], 1)
	battle_ui.battle.enemies[0]["hp"] = 1
	battle_ui.refresh()
	await _settle()
	var won_before: int = run_state.battles_won
	var gold_before: int = run_state.gold
	await _press_key(KEY_1)
	_check(
		(
			battle_ui.battle.outcome == BattleScript.Outcome.WIN
			and main.screen == battle_ui
			and run_state.phase == RunStateScript.Phase.BATTLE
		),
		"最後の敵を倒した直後は、戦闘の画面のまま待つ"
	)
	var saved: RunStateScript = _load_saved()
	_check(
		saved.uses_left(0) == Cards.CARDS["slash"]["max_uses"] - 1,
		"勝った後に待つ前に、使ったカードの残り使用回数を保存する"
	)
	saved.free()
	await _press_key(KEY_ENTER)
	await _press_key(KEY_S)
	_check(run_state.battles_won == won_before, "待ちの間の Enter と S では戦闘を終えない")
	await create_timer(Art.WIN_DELAY + MOTION_MARGIN).timeout
	await _settle()
	_check(main.screen is RewardUiScript, "待った後に報酬の画面へ移る")
	_check(
		(
			run_state.battles_won == won_before + 1
			and (
				run_state.gold
				== gold_before + NodeRules.reward_gold(run_state.node_seed(), ActMap.Kind.BATTLE)
			)
		),
		"勝った戦闘の数と所持金は 1 回分だけ増える"
	)


## 戦闘の動きがすべて終わるまで待つ時間 (秒)。最も長い動き (残り 1 回・契約切れになったカードを使う動きと、浮かぶ
## 数字の大きい方) に MOTION_MARGIN を足す
func _motion_settle_time() -> float:
	return (
		maxf(
			Art.CARD_LIFT_TIME + Art.SEAL_FLASH_TIME + Art.STRONG_TIME + Art.CARD_FLY_TIME,
			Art.FLOAT_TIME
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
	_check(_bgm_is(AudioScript.Bgm.BATTLE), "「続きから」で戦闘に戻ると戦闘の曲が鳴る")
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
		var view: CardViewScript = button as CardViewScript
		_check(
			view.disabled and view.note_label.text == CardViewScript.EXHAUSTED_NOTE,
			"契約切れのカードは押せず、そう表示される"
		)
		_check(view.face.material != null, "契約切れのカードは色を失う")
		_check(
			_seal_counts(view) == Vector2i(0, Cards.CARDS[view.card_id]["max_uses"]),
			"契約切れのカードの印はすべて焼けている"
		)
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
	_check(_se_playing(AudioScript.Se.WIN), "戦闘に勝つと勝利の効果音が鳴る")
	_check(_bgm_is(AudioScript.Bgm.MAP), "報酬の画面では地図の曲が鳴る")
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
	_stop_se()
	await _click(shrine.deck_grid.get_child(index) as Button)
	_check(run_state.uses_left(index) == max_uses, "祠で契約を更新すると残り使用回数が最大に戻る")
	_check(_se_playing(AudioScript.Se.RESTORE), "祠で契約を更新すると回数の回復の効果音が鳴る")
	_check(main.screen is MapUiScript and run_state.phase == RunStateScript.Phase.MAP, "祠の後は地図")
	var saved: RunStateScript = _load_saved()
	_check(saved.uses_left(index) == max_uses, "祠の結果が保存される")
	saved.free()


## デッキが表示に収まらない枚数の時、契約の祠でカードを選ぶ格子の下の方のカードへフォーカスを移すと、そのカードが
## 見える位置までスクロールし、そのカードを選ぶと地図へ戻る
func _check_deck_grid_follows_focus(main: MainScript) -> void:
	var ids: Array[String] = []
	for _i: int in range(6):
		ids.append_array(["slash", "guard", "breath", "spirit_arrow"])
	_set_deck(ids)
	for index: int in range(run_state.deck.size()):
		run_state.use_card(index)
	await _enter_kind(main, ActMap.Kind.SHRINE)
	var shrine: ShrineUiScript = main.screen as ShrineUiScript
	if shrine == null:
		_check(false, "スクロールの検証: 契約の祠に入る")
		return
	await _click(shrine.renew_button)
	var last: Button = shrine.deck_grid.get_child(shrine.deck_grid.get_child_count() - 1)
	var scroll: ScrollContainer = shrine.deck_grid.get_parent() as ScrollContainer
	last.grab_focus()
	await _settle()
	var view: Rect2 = scroll.get_global_rect()
	_check(scroll.scroll_vertical > 0, "下の方のカードへフォーカスを移すと格子がスクロールする")
	_check(
		view.encloses(last.get_global_rect()), "フォーカスを移したカードが格子の表示の中に見える"
	)
	await _click(last)
	_check(main.screen is MapUiScript, "スクロールした先のカードを選ぶと地図へ戻る")


## 地図で商人に入り、カードを買う・残り使用回数を戻す・立ち去ると、所持金とデッキに反映される
func _check_shop(main: MainScript) -> void:
	run_state.gold = 300
	await _enter_kind(main, ActMap.Kind.SHOP)
	var shop: ShopUiScript = main.screen as ShopUiScript
	_check(shop != null, "地図の商人の節点で商人に入る")
	if shop == null:
		return
	_check_buttons_fit(shop.card_buttons.values(), "商人のカード")
	await _check_cards_fit(main)
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
		_stop_se()
		await _click(shop.deck_grid.get_child(index) as Button)
		_check(_se_playing(AudioScript.Se.RESTORE), "商人で残り使用回数を戻すと回数の回復の効果音が鳴る")
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


## 出来事「血の泉」で体力を払って残り使用回数を戻すと、回数の回復の効果音が鳴って地図へ戻る (血の泉が出る
## 地図のシードを 1 から順に探し、その巡礼の出来事の節点に入る。以後の検証はこの巡礼で続ける)
func _check_blood_spring_sound(main: MainScript) -> void:
	for seed_value: int in range(1, EVENT_SEED_LIMIT + 1):
		run_state.new_run([], seed_value)
		var at: Vector2i = ActMap.find_kind(run_state.rows, ActMap.Kind.EVENT)
		run_state.path = ActMap.route_to(run_state.rows, at.x, at.y)
		if Events.event_for(run_state.node_seed()) == "blood_spring":
			break
	run_state.use_card(0)
	run_state.phase = RunStateScript.Phase.EVENT
	main.show_run_phase()
	await _settle()
	var event_ui: EventUiScript = main.screen as EventUiScript
	if event_ui == null:
		_check(false, "血の泉の検証: 出来事の画面が出る")
		return
	if event_ui.event_id != "blood_spring":
		_check(false, "血の泉が出る地図が見つかる")
		await _click(event_ui.option_buttons.back())
		return
	await _click(event_ui.option_buttons[0])
	if event_ui.deck_grid == null:
		_check(false, "血の泉で残り使用回数を戻すカードを選べる")
		return
	await _click(event_ui.deck_grid.get_child(0) as Button)
	_stop_se()
	await _click(event_ui.confirm_button)
	_check(
		run_state.uses_left(0) == run_state.card(0)["max_uses"],
		"血の泉で残り使用回数が最大に戻る"
	)
	_check(_se_playing(AudioScript.Se.RESTORE), "血の泉で回数の回復の効果音が鳴る")
	_check(main.screen is MapUiScript, "血の泉の後は地図")


## 地図で D を押すと契約の一覧が開き、全カードを並べ、キーでスクロールでき、並べ方を変えられ、Esc で閉じる
func _check_deck_list(main: MainScript) -> void:
	# 一覧が縦に収まらない枚数にして、キーでのスクロールも確かめる
	var ids: Array[String] = []
	for _i: int in range(12):
		ids.append_array(["slash", "guard", "breath", "spirit_arrow"])
	_set_deck(ids)
	# 次の「続きから」の検証は保存データと今の状態を比べるため、変えたデッキを保存しておく
	run_state.autosave()
	await _press_key(KEY_D)
	var deck_list: DeckListUiScript = main.deck_list
	_check(deck_list != null, "D で契約の一覧が開く")
	if deck_list == null:
		return
	_check(_visible_children(deck_list.list_grid) == run_state.deck.size(), "契約の一覧に全カードが並ぶ")
	await _press_key(KEY_PAGEDOWN)
	var paged: int = deck_list.list_scroll.scroll_vertical
	_check(paged > 0, "PageDown で契約の一覧が下へスクロールする")
	await _press_key(KEY_UP)
	_check(deck_list.list_scroll.scroll_vertical < paged, "上の矢印で契約の一覧が上へスクロールする")
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
	_check(_bgm_is(AudioScript.Bgm.BOSS), "ボス戦の前の会話からボスの曲が鳴る")
	_check(not main.deck_button.visible, "会話の間は契約の一覧のボタンを出さない (「戦う」と重ならない)")
	var lines: int = Enemies.ENEMIES[talk.boss_id]["talk"].size()
	for _i: int in range(lines):
		await _press_key(KEY_ENTER)
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	_check(battle_ui != null, "会話の後にボスとの戦闘に入る")
	if battle_ui == null:
		return
	_check(battle_ui.battle.turn == 1, "会話を送った Enter は戦闘のターン終了に届かない")
	_check(battle_ui.battle.enemies[0]["id"] == Enemies.BOSS_ENCOUNTER[0], "戦う相手はボス")
	_check(_bgm_is(AudioScript.Bgm.BOSS), "ボス戦でもボスの曲が鳴る")
	for enemy: Dictionary in battle_ui.battle.enemies:
		enemy["hp"] = 1
		enemy["block"] = 0
	await _press_key(KEY_S)
	var result: ResultUiScript = main.screen as ResultUiScript
	_check(result != null and run_state.phase == RunStateScript.Phase.CLEAR, "ボスを倒すと踏破の画面")
	if result == null:
		return
	_check(result.summary_label.text.contains("到達した階層: 15"), "踏破の結果に到達した階層が出る")
	_check(
		_bgm_is(AudioScript.Bgm.NONE) and _se_playing(AudioScript.Se.WIN),
		"踏破で BGM が止まり、勝利の効果音が鳴る"
	)
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
	_check(
		_bgm_is(AudioScript.Bgm.NONE) and _se_playing(AudioScript.Se.LOSE),
		"敗北で BGM が止まり、敗北の効果音が鳴る"
	)
	_check(not FileAccess.file_exists(INTEGRATION_SAVE_PATH), "敗北で保存データが消える")
	_check(not main.deck_button.visible, "結果の画面では契約の一覧のボタンが出ない")
	await _click(result.title_button)
	_check(main.screen is TitleUiScript, "敗北の後はタイトルへ戻る")


## 設定で音量を変えると BGM・効果音のバスに反映されて保存され、設定を読み直しても同じ値になる
func _check_settings_saved(main: MainScript) -> void:
	var title: TitleUiScript = main.screen as TitleUiScript
	if title == null:
		return
	await _click(title.settings_button)
	var settings_ui: SettingsUiScript = main.screen as SettingsUiScript
	_check(settings_ui != null, "「設定」で設定の画面が出る")
	if settings_ui == null:
		return
	_check(_bgm_is(AudioScript.Bgm.MAP), "設定の画面では音量を確かめるための BGM が鳴る")
	var bgm_bus: int = AudioServer.get_bus_index(AudioScript.BGM_BUS)
	var se_bus: int = AudioServer.get_bus_index(AudioScript.SE_BUS)
	settings_ui.se_slider.value = 0
	_check(AudioServer.is_bus_mute(se_bus), "効果音の音量 0 で効果音のバスがミュートになる")
	_stop_se()
	settings_ui.bgm_slider.value = 35
	settings_ui.se_slider.value = 60
	_check(settings.bgm_volume == 35 and settings.se_volume == 60, "スライダーで音量が変わる")
	_check(
		(
			is_equal_approx(AudioServer.get_bus_volume_db(bgm_bus), linear_to_db(0.35))
			and is_equal_approx(AudioServer.get_bus_volume_db(se_bus), linear_to_db(0.6))
			and not AudioServer.is_bus_mute(se_bus)
		),
		"スライダーの音量が BGM と効果音のバスに反映される"
	)
	_check(_se_playing(AudioScript.Se.CARD_USE), "効果音の音量を変えると、確かめるための効果音が鳴る")
	# 画面を閉じる前 (戻るを押さずにゲームを終えた時) でも保存されている
	var saved: SettingsScript = SettingsScript.new()
	saved.settings_path = INTEGRATION_SETTINGS_PATH
	saved.load_settings()
	_check(saved.bgm_volume == 35 and saved.se_volume == 60, "スライダーを動かすたびに保存される")
	saved.free()
	await _press_key(KEY_ESCAPE)
	_check(main.screen is TitleUiScript, "Esc で設定からタイトルへ戻る")
	_check(_bgm_is(AudioScript.Bgm.NONE), "設定を閉じると BGM が止まる")
	settings.bgm_volume = 0
	settings.se_volume = 0
	settings.load_settings()
	_check(settings.bgm_volume == 35 and settings.se_volume == 60, "保存した音量を読み直すと同じ値")


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


## 報酬・祠・商人の 3 枚の並び (値段の行付き) とデッキの格子が画面の幅に収まり、全カードの名前と効果の文が
## カードの中に収まる (メインシーンの theme のフォントで、画面と同じ余白の入れ物に置いて確かめ、確かめた後に消す)
func _check_cards_fit(main: MainScript) -> void:
	var probe: Control = Control.new()
	main.add_child(probe)
	var layout: VBoxContainer = UiKit.screen_layout(probe, "")
	var row: HBoxContainer = UiKit.add_card_row(layout)
	var grid: GridContainer = UiKit.add_card_grid(layout)
	var views: Array[Button] = []
	var card_ids: Array = Cards.CARDS.keys()
	for card_id: String in card_ids.slice(0, NodeRules.OFFER_COUNT):
		var note: String = "値段 %d" % NodeRules.card_price(card_id)
		views.append(UiKit.add_offer_card(row, card_id, note, func() -> void: pass))
	for card_id: String in card_ids:
		views.append(UiKit.add_offer_card(grid, card_id, "", func() -> void: pass))
	await _settle()
	_check_buttons_fit(views, "並べたカード")
	for button: Button in views:
		var view: CardViewScript = button as CardViewScript
		var card_name: String = view.name_label.text
		var name_width: float = (
			Art.FONT.get_string_size(
				card_name, HORIZONTAL_ALIGNMENT_LEFT, -1, CardViewScript.NAME_FONT_SIZE
			).x
		)
		_check(
			name_width <= CardViewScript.NAME_RECT.size.x, "名前がカードの幅に収まる: %s" % card_name
		)
		_check(
			view.effect_label.get_line_count() <= CardViewScript.EFFECT_MAX_LINES,
			"効果の文がカードの行の数に収まる: %s" % card_name
		)
		_check(
			view.seal_row.get_combined_minimum_size().x <= CardViewScript.SEAL_RECT.size.x,
			"封蝋の印の列がカードの幅に収まる: %s" % card_name
		)
	probe.queue_free()
	await process_frame
