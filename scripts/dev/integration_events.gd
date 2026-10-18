extends "res://scripts/dev/integration_contractors.gd"
## scripts/dev/integration.gd の検証のうち、出来事の画面の検証 (gdlint のファイルの行数の上限に収めるため、検証の
## 本体と分けた)。

## 封蝋の骰子の結果を決めて探す地図のシードの数 (骰子の節点は地図 10 枚に 1 枚ほどで、当たりと外れが半々なので、
## EVENT_SEED_LIMIT と同じ数で見つかる)
const GAMBLE_SEED_LIMIT: int = EVENT_SEED_LIMIT


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


## すべての出来事の画面で、出来事の絵が出て、絵・文・状態・選択肢が 1280x720 の画面に収まり、絵と重ならない
## (canvas_items の拡大で、ウィンドウを狭くしてもこの配置のまま縮む)
func _check_event_layouts(main: MainScript) -> void:
	for event_id: String in Events.EVENTS:
		if not _start_run_at_event(event_id):
			continue
		main.show_run_phase()
		await _settle()
		var event_ui: EventUiScript = main.screen as EventUiScript
		if event_ui == null:
			_check(false, "出来事の画面が出る: %s" % event_id)
			continue
		var screen: Rect2 = Rect2(Vector2.ZERO, root.size)
		var picture: Rect2 = event_ui.picture.get_global_rect()
		_check(
			event_ui.option_buttons.size() == Events.EVENTS[event_id]["options"].size(),
			"選択肢が並ぶ: %s" % event_id
		)
		_check(
			event_ui.picture.visible and event_ui.picture.texture == Art.EVENT_ART[event_id],
			"出来事の絵が出る: %s" % event_id
		)
		_check(screen.encloses(picture), "出来事の絵が画面に収まる: %s" % event_id)
		var texts: Array[Control] = [event_ui.note]
		for child: Node in event_ui.content.get_children():
			if child is Label or child is Button:
				texts.append(child)
		for text: Control in texts:
			var rect: Rect2 = text.get_global_rect()
			var shown: String = text.text if "text" in text else ""
			_check(screen.encloses(rect), "%s の文が画面に収まる: %s" % [event_id, shown])
			_check(not rect.intersects(picture), "%s の文が絵と重ならない: %s" % [event_id, shown])


## 出来事「血の泉」で体力を払って残り使用回数を戻すと、回数の回復の効果音が鳴って地図へ戻る (血の泉が出る
## 地図のシードを 1 から順に探し、その巡礼の出来事の節点に入る)
func _check_blood_spring_sound(main: MainScript) -> void:
	if not _start_run_at_event("blood_spring"):
		return
	run_state.use_card(0)
	main.show_run_phase()
	await _settle()
	var event_ui: EventUiScript = main.screen as EventUiScript
	if event_ui == null:
		_check(false, "血の泉の検証: 出来事の画面が出る")
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


## 出来事「灰の炉」で、最初に手放す 1 枚 (どのカードも選べる)、続けて残りの減った 2 枚 (減っていないカードは選べない)
## を選ぶと、手放したカードが消えて 2 枚の残りが最大に戻り、回数の回復の効果音が鳴って地図へ戻る。カードを選ぶ間は
## 絵を隠してデッキの格子に幅を譲り、手放すカードを選び直すと後に選んだカードも外れる
func _check_ash_furnace(main: MainScript) -> void:
	if not _start_run_at_event("ash_furnace"):
		return
	_set_deck(["slash", "guard", "hero_strike", "breath"])
	run_state.use_card(1)
	run_state.use_card(2)
	main.show_run_phase()
	await _settle()
	var event_ui: EventUiScript = main.screen as EventUiScript
	if event_ui == null:
		_check(false, "灰の炉の検証: 出来事の画面が出る")
		return
	await _click(event_ui.option_buttons[0])
	if event_ui.deck_grid == null:
		_check(false, "灰の炉でカードを選べる")
		return
	_check(not event_ui.picture.visible, "カードを選ぶ間は出来事の絵を隠す")
	_check(
		event_ui.deck_grid.get_children().all(func(view: Button) -> bool: return not view.disabled),
		"灰の炉で手放すカードはどれも選べる"
	)
	await event_ui.toggle_pick(0)
	_check((event_ui.deck_grid.get_child(3) as Button).disabled, "灰の炉で減っていないカードは戻せない")
	await event_ui.toggle_pick(1)
	await event_ui.toggle_pick(0)
	_check(event_ui.picks.is_empty(), "手放すカードを選び直すと、後に選んだカードも外れる")
	for index: int in [0, 1, 2]:
		await _click(event_ui.deck_grid.get_child(index) as Button)
	_stop_se()
	await _click(event_ui.confirm_button)
	var ids: Array[String] = []
	for entry: Dictionary in run_state.deck:
		ids.append(entry["id"])
	_check(ids == ["guard", "hero_strike", "breath"], "灰の炉で手放したカードが消える: %s" % [ids])
	_check(
		run_state.uses_left(0) == run_state.card(0)["max_uses"]
		and run_state.uses_left(1) == run_state.card(1)["max_uses"],
		"灰の炉で 2 枚の残りが最大に戻る"
	)
	_check(_se_playing(AudioScript.Se.RESTORE), "灰の炉で回数の回復の効果音が鳴る")
	_check(main.screen is MapUiScript, "灰の炉の後は地図")


## 出来事「封蝋の骰子」で使いかけのカードを賭けると、結果 (当たれば残りが最大に戻り回数の回復の効果音、外れれば
## カードを失い契約切れの効果音) を見せ、「進む」で地図へ戻る。結果を見せる前に地図へ戻った局面として保存するので、
## 外れを見て終了し「続きから」で再開しても、カードを失ったまま地図に戻り、賭け直せない
func _check_seal_dice(main: MainScript) -> void:
	for wins: bool in [true, false]:
		if not _start_run_at_gamble(wins):
			return
		_set_deck(["slash", "guard"])
		run_state.use_card(0)
		run_state.autosave()
		main.show_run_phase()
		await _settle()
		var event_ui: EventUiScript = main.screen as EventUiScript
		if event_ui == null:
			_check(false, "封蝋の骰子の検証: 出来事の画面が出る")
			return
		await _click(event_ui.option_buttons[0])
		if event_ui.deck_grid == null:
			_check(false, "封蝋の骰子で賭けるカードを選べる")
			return
		_check((event_ui.deck_grid.get_child(1) as Button).disabled, "封蝋の骰子で減っていないカードは賭けられない")
		await _click(event_ui.deck_grid.get_child(0) as Button)
		_stop_se()
		await _click(event_ui.confirm_button)
		if event_ui.proceed_button == null:
			_check(false, "封蝋の骰子の結果が出る (当たり: %s)" % wins)
			return
		_check(event_ui.picture.visible, "封蝋の骰子の結果と一緒に出来事の絵が出る")
		if wins:
			_check(
				run_state.deck.size() == 2 and run_state.uses_left(0) == run_state.card(0)["max_uses"],
				"骰子が当たると賭けたカードの残りが最大に戻る"
			)
			_check(_se_playing(AudioScript.Se.RESTORE), "骰子が当たると回数の回復の効果音が鳴る")
		else:
			_check(run_state.deck.size() == 1, "骰子が外れると賭けたカードを失う")
			_check(_se_playing(AudioScript.Se.EXPIRED), "骰子が外れると契約切れの効果音が鳴る")
		if wins:
			await _click(event_ui.proceed_button)
			_check(main.screen is MapUiScript, "封蝋の骰子の結果の後は地図")
			continue
		await _quit_and_continue(main)
		_check(
			(
				main.screen is MapUiScript
				and run_state.phase == RunStateScript.Phase.MAP
				and run_state.deck.size() == 1
			),
			"外れの結果を見せている間に終了すると、カードを失ったまま地図から再開する (賭け直せない)"
		)


## 出来事「蝋の祭壇」で体力を払って契約切れの英霊を選ぶと、最大と残りの使用回数が 1 増え (精霊と、増やしきった
## 英霊は選べない)、回数の回復の効果音が鳴って地図へ戻る。契約の一覧の封蝋の印が増えた最大の数だけ並び、増えた
## 最大は「続きから」の後も保たれる。以後の検証はこの巡礼で続ける
func _check_wax_altar(main: MainScript) -> void:
	if not _start_run_at_event("wax_altar"):
		return
	_set_deck(["slash", "hero_strike", "hero_wall", "guard"])
	while run_state.use_card(1):
		pass
	Events.raise_max_uses(run_state, 2)
	main.show_run_phase()
	await _settle()
	var event_ui: EventUiScript = main.screen as EventUiScript
	if event_ui == null:
		_check(false, "蝋の祭壇の検証: 出来事の画面が出る")
		return
	await _click(event_ui.option_buttons[0])
	if event_ui.deck_grid == null:
		_check(false, "蝋の祭壇で最大使用回数を増やす英霊を選べる")
		return
	_check(
		(event_ui.deck_grid.get_child(3) as Button).disabled,
		"英霊を増やす選択肢では、まだ増やせる精霊 (守りの風) も選べない"
	)
	_check((event_ui.deck_grid.get_child(2) as Button).disabled, "最大使用回数を増やしきった英霊は選べない")
	var max_before: int = Cards.deck_max_uses(run_state.deck[1])
	var hp_before: int = run_state.hp
	await _click(event_ui.deck_grid.get_child(1) as Button)
	_stop_se()
	await _click(event_ui.confirm_button)
	_check(
		Cards.deck_max_uses(run_state.deck[1]) == max_before + 1 and run_state.uses_left(1) == 1,
		"蝋の祭壇で英霊の最大と残りの使用回数が 1 増える"
	)
	_check(run_state.hp == hp_before - Events.RAISE_HERO_PRICE, "蝋の祭壇で体力を払う")
	_check(_se_playing(AudioScript.Se.RESTORE), "蝋の祭壇で回数の回復の効果音が鳴る")
	_check(main.screen is MapUiScript, "蝋の祭壇の後は地図")
	await _press_key(KEY_D)
	var raised: CardViewScript = null
	for view: CardViewScript in main.deck_list.list_grid.get_children():
		if view.card_id == "hero_strike":
			raised = view
	_check(
		raised != null and _seal_counts(raised) == Vector2i(1, max_before),
		"契約の一覧で、増えた最大の数だけ封蝋の印が並ぶ"
	)
	await _press_key(KEY_ESCAPE)
	await _quit_and_continue(main)
	_check(
		Cards.deck_max_uses(run_state.deck[1]) == max_before + 1 and run_state.uses_left(1) == 1,
		"増えた最大使用回数が「続きから」の後も保たれる"
	)


## 封蝋の骰子が出て、その結果が wins になる地図のシードを 1 から順に探して新しい巡礼にし、その出来事の節点に
## 入った局面にする (画面は呼ぶ側が出す)。見つからなければ失敗にして false
func _start_run_at_gamble(wins: bool) -> bool:
	for seed_value: int in range(1, GAMBLE_SEED_LIMIT + 1):
		run_state.new_run([], seed_value)
		var at: Vector2i = ActMap.find_kind(run_state.rows, ActMap.Kind.EVENT)
		run_state.path = ActMap.route_to(run_state.rows, at.x, at.y)
		var node_seed: int = run_state.node_seed()
		if Events.event_for(node_seed) == "seal_dice" and Events.gamble_wins(node_seed) == wins:
			run_state.phase = RunStateScript.Phase.EVENT
			return true
	_check(false, "骰子の結果が %s になる地図が見つかる" % wins)
	return false
