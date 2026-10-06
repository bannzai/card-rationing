extends "res://scripts/dev/headless_check.gd"
## メインシーンを tree に置いて動かす入力統合テスト (headless)。画面の遷移やキー・クリックで変わる振る舞いを
## 足したら、ここに検証を足す。実行方法は AGENTS.md「検証方法」を参照。
## キーは root.push_input() に InputEventKey を、クリックはボタンの中心への InputEventMouseButton を渡して起こす。

const BattleScript := preload("res://scripts/battle.gd")
const BattleUiScript := preload("res://scripts/battle_ui.gd")
const MainScript := preload("res://scripts/main.gd")
const RunStateScript := preload("res://scripts/run_state.gd")

## 起動時に表示するメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")

## autoload RunState (ラン単位の状態)
var run_state: RunStateScript = null


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら検証するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	run_state = root.get_node_or_null("RunState")
	_check(run_state != null, "autoload RunState がある")
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
	_check(main.get_node("Title").is_visible_in_tree(), "タイトルが表示される")
	_check(main.get_node("Title").size.x > 0, "コントロールがレイアウトされる (大きさが 0 でない)")
	await _check_enter_and_win(main)
	await _check_next_battle_keeps_uses(main)
	await _check_target_selection(main)
	await _check_hand_fits_after_draw(main)
	await _check_exhausted_deck_battle(main)
	await _check_defeat_starts_new_run(main)
	main.queue_free()
	await process_frame
	_finish()


## Enter で戦闘に入り、クリックと数字キーでカードを使って敵を倒す (使うたびに残り使用回数が減る)
func _check_enter_and_win(main: MainScript) -> void:
	# 5 枚のデッキにして、シードによらず全カードが手札に来るようにする
	run_state.new_run(["slash", "slash", "guard", "breath", "spirit_arrow"])
	await _press_key(KEY_ENTER)
	var battle_ui: BattleUiScript = main.battle
	_check(battle_ui != null, "Enter で戦闘に入る")
	_check(not main.get_node("Title").visible, "戦闘に入るとタイトルが消える")
	if battle_ui == null:
		return
	_check(
		battle_ui.battle.turn == 1 and battle_ui.battle.energy == BattleScript.ENERGY_PER_TURN,
		"戦闘に入った Enter はターン終了として処理されない"
	)
	_check(_hand_buttons(battle_ui).size() == 5, "手札のボタンが 5 枚")
	_check(_hand_buttons(battle_ui)[0].get_global_rect().size.x > 0, "手札のボタンに大きさがある")
	var slash_hand: int = _hand_index_of(battle_ui, "slash")
	var slash_deck: int = battle_ui.battle.hand[slash_hand]
	await _click(_hand_buttons(battle_ui)[slash_hand])
	_check(run_state.uses_left(slash_deck) == 3, "クリックで斬撃を使うと残り使用回数が 3")
	_check(battle_ui.battle.hand.size() == 4, "使ったカードが手札から消える")
	_check(battle_ui.battle.enemies[0]["hp"] == 8, "野犬の体力 8")
	var second_slash: int = _hand_index_of(battle_ui, "slash")
	var second_slash_deck: int = battle_ui.battle.hand[second_slash]
	await _press_key(KEY_1 + second_slash)
	_check(battle_ui.battle.enemies[0]["hp"] == 2, "数字キーで斬撃を使うと野犬の体力 2")
	_check(run_state.uses_left(second_slash_deck) == 3, "数字キーで使った斬撃も残り使用回数が 3")
	var arrow: int = _hand_index_of(battle_ui, "spirit_arrow")
	var arrow_deck: int = battle_ui.battle.hand[arrow]
	await _press_key(KEY_1 + arrow)
	_check(run_state.uses_left(arrow_deck) == 2, "精霊の矢の残り使用回数が 2")
	_check(battle_ui.battle.outcome == BattleScript.Outcome.WIN, "精霊の矢で倒して勝利")
	_check(battle_ui.next_button.visible, "勝利で「次の戦闘へ」が出る")


## 「次の戦闘へ」で始めた戦闘でも、使ったカードの残り使用回数が減ったまま
func _check_next_battle_keeps_uses(main: MainScript) -> void:
	var battle_ui: BattleUiScript = main.battle
	if battle_ui == null:
		return
	var before: Array[Dictionary] = run_state.deck.duplicate(true)
	_check(before[0]["uses_left"] < 4 or before[1]["uses_left"] < 4, "勝利の時点で斬撃の残りが減っている")
	await _click(battle_ui.next_button)
	_check(run_state.floor_index == 1, "次の戦闘で階層が進む")
	var battle: BattleScript = battle_ui.battle
	_check(battle.turn == 1 and battle.outcome == BattleScript.Outcome.NONE, "新しい戦闘")
	_check(run_state.deck == before, "次の戦闘でも残り使用回数が減ったまま")
	_check(battle_ui.battle.enemies.size() == 2, "2 階は敵が 2 体")


## 敵が 2 体いる時、攻撃は対象を選んでから使う (数字キーで敵を選ぶ)
func _check_target_selection(main: MainScript) -> void:
	var battle_ui: BattleUiScript = main.battle
	if battle_ui == null:
		return
	var slash_hand: int = _hand_index_of(battle_ui, "slash")
	await _press_key(KEY_1 + slash_hand)
	_check(battle_ui.pending_hand_index == slash_hand, "攻撃を選ぶと対象の選択に入る")
	_check(battle_ui.message_label.text.contains("対象"), "対象を選ぶ案内が出る")
	if battle_ui.battle.enemies.size() < 2:
		return
	_check(battle_ui.battle.enemies[1]["hp"] == 22, "まだ骸骨兵の体力 22")
	await _press_key(KEY_2)
	_check(battle_ui.battle.enemies[1]["hp"] == 16, "2 を押すと骸骨兵に 6 ダメージ")
	_check(battle_ui.pending_hand_index == -1, "使ったら対象の選択が終わる")
	var other_slash: int = _hand_index_of(battle_ui, "slash")
	var other_slash_uses: int = run_state.uses_left(battle_ui.battle.hand[other_slash])
	await _press_key(KEY_1 + other_slash)
	_check(battle_ui.pending_hand_index == other_slash, "2 枚目の斬撃で対象の選択に入る")
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
	var battle_ui: BattleUiScript = main.battle
	if battle_ui == null:
		return
	run_state.new_run(["breath", "slash", "slash", "guard", "guard", "guard", "spirit_arrow", "slash"])
	var breath_hand: int = await _start_battle_with_card_in_hand(battle_ui, "breath")
	if breath_hand < 0:
		_check(false, "深呼吸が手札に来るシードが見つかる")
		return
	await _press_key(KEY_1 + breath_hand)
	_check(battle_ui.battle.hand.size() == 6, "深呼吸で手札が 6 枚になる")
	var buttons: Array[Button] = _hand_buttons(battle_ui)
	_check(buttons.size() == 6, "手札のボタンが 6 枚")
	for button: Button in buttons:
		var rect: Rect2 = button.get_global_rect()
		_check(rect.position.x >= 0 and rect.end.x <= root.size.x, "手札のボタンが画面の幅に収まる: %s" % button.text)
	if battle_ui.battle.can_play(buttons.size() - 1):
		await _click(buttons[buttons.size() - 1])
		_check(battle_ui.battle.hand.size() == 5, "右端のカードをクリックで使える")


## デッキの全カードが契約切れでも、もがく (S) とターン終了 (Enter) で戦闘が勝敗まで進む
func _check_exhausted_deck_battle(main: MainScript) -> void:
	var battle_ui: BattleUiScript = main.battle
	if battle_ui == null:
		return
	run_state.new_run(["slash", "guard", "breath"])
	for index: int in range(run_state.deck.size()):
		while run_state.use_card(index):
			pass
	battle_ui.start_battle(11)
	await _settle()
	_check(battle_ui.battle.hand.size() == 3, "契約切れのカードも手札に来る")
	for button: Button in _hand_buttons(battle_ui):
		_check(button.disabled and button.text.contains("契約切れ"), "契約切れのカードは押せず、そう表示される")
	_check(battle_ui.message_label.text.contains("使えるカードが無い"), "使えるカードが無い案内が出る")
	var steps: int = 0
	var battle: BattleScript = battle_ui.battle
	while battle.outcome == BattleScript.Outcome.NONE and steps < EXHAUSTED_BATTLE_STEP_LIMIT:
		if battle.energy >= BattleScript.STRUGGLE_COST:
			await _press_key(KEY_S)
		else:
			await _press_key(KEY_ENTER)
		steps += 1
	_check(battle_ui.battle.outcome != BattleScript.Outcome.NONE, "契約切れだけのデッキでも勝敗まで進む")


## 敗北の後は Enter で新しいラン (初期デッキ・体力・最初の階層) の戦闘が始まる
func _check_defeat_starts_new_run(main: MainScript) -> void:
	var battle_ui: BattleUiScript = main.battle
	if battle_ui == null:
		return
	run_state.new_run(["guard"])
	run_state.use_card(0)
	run_state.take_damage(49)
	run_state.advance_floor()
	battle_ui.start_battle(13)
	await _settle()
	for _i: int in range(10):
		if battle_ui.battle.outcome != BattleScript.Outcome.NONE:
			break
		await _press_key(KEY_ENTER)
	_check(battle_ui.battle.outcome == BattleScript.Outcome.LOSE, "体力 1 のランは敗北で終わる")
	_check(battle_ui.message_label.text.contains("敗北"), "敗北の案内が出る")
	await _press_key(KEY_ENTER)
	_check(run_state.hp == 50 and run_state.floor_index == 0, "敗北の後は新しいランの体力と最初の階層")
	_check(run_state.deck.size() == 10 and run_state.uses_left(0) == 4, "敗北の後は初期デッキで残りが最大")
	var battle: BattleScript = battle_ui.battle
	_check(battle.turn == 1 and battle.outcome == BattleScript.Outcome.NONE, "敗北の後に新しい戦闘が始まる")


## 戦闘画面の手札のボタン (表示中のものだけ)
func _hand_buttons(battle_ui: BattleUiScript) -> Array[Button]:
	var buttons: Array[Button] = []
	for child: Button in battle_ui.hand_row.get_children():
		if child.visible:
			buttons.append(child)
	return buttons


## card_id のカードが手札に来るシードで戦闘を始め、そのカードの手札の位置を返す (シードを 1 から順に試し、
## 見つからなければ -1)
func _start_battle_with_card_in_hand(battle_ui: BattleUiScript, card_id: String) -> int:
	for seed_value: int in range(1, 51):
		battle_ui.start_battle(seed_value)
		var hand_index: int = _hand_index_of(battle_ui, card_id)
		if hand_index >= 0:
			await _settle()
			return hand_index
	return -1


## 手札の中で card_id のカードがある位置 (無ければ -1)
func _hand_index_of(battle_ui: BattleUiScript, card_id: String) -> int:
	for hand_index: int in range(battle_ui.battle.hand.size()):
		if run_state.deck[battle_ui.battle.hand[hand_index]]["id"] == card_id:
			return hand_index
	return -1


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
