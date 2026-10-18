extends "res://scripts/dev/integration_base.gd"
## scripts/dev/integration.gd の検証のうち、契約者の選択と個性の検証 (gdlint のファイルの行数の上限に収めるため、
## 検証の本体と分けた)。


## 契約者の選択と個性: 全員のボタンが画面に収まり、フォーカスを移すとその契約者の立ち絵と個性が出る。どの契約者を
## 選んでも、その初期デッキ・最大体力で巡礼が始まり、戦闘ではその立ち絵が出て、最初のターンのエネルギーと手札の
## 枚数に個性が効く。戦闘の途中から「続きから」で再開しても同じ契約者で、個性が効く。最後にタイトルへ戻る
func _check_contractor_traits(main: MainScript) -> void:
	for contractor_id: String in Contractors.CONTRACTORS:
		var title: TitleUiScript = main.screen as TitleUiScript
		if title == null:
			_check(false, "契約者の検証: タイトルが出ている (%s)" % contractor_id)
			return
		await _click(title.start_button)
		var select: CharacterSelectUiScript = main.screen as CharacterSelectUiScript
		if select == null:
			_check(false, "契約者の検証: 契約者の選択が出る (%s)" % contractor_id)
			return
		_check(select.character_buttons.size() == Contractors.CONTRACTORS.size(), "全員の契約者のボタンがある")
		var buttons: Array = select.character_buttons.values()
		buttons.append(select.back_button)
		for button: Button in buttons:
			_check(button.get_global_rect().end.y <= root.size.y, "契約者の選択のボタンが画面の高さに収まる")
		var contractor: Dictionary = Contractors.CONTRACTORS[contractor_id]
		(select.character_buttons[contractor_id] as Button).grab_focus()
		await _settle()
		_check(
			(
				select.shown_id == contractor_id
				and select.portrait.texture == Art.PORTRAITS[contractor_id]
				and select.detail_label.text.contains(contractor["trait_name"])
			),
			"フォーカスした契約者の立ち絵と個性が出る: %s" % contractor_id
		)
		await _click(select.character_buttons[contractor_id])
		_check(
			(
				run_state.character_id == contractor_id
				and run_state.deck.size() == Contractors.starter_deck(contractor_id).size()
				and run_state.hp == contractor["max_hp"]
				and run_state.max_hp == contractor["max_hp"]
			),
			"選んだ契約者の初期デッキと最大体力で巡礼が始まる: %s" % contractor_id
		)
		await _press_key(KEY_1)
		_check_trait_battle(main, contractor_id, "巡礼の最初の戦闘")
		await _quit_and_continue(main)
		_check(run_state.character_id == contractor_id, "「続きから」で同じ契約者に戻る: %s" % contractor_id)
		_check_trait_battle(main, contractor_id, "「続きから」で戻った戦闘")
		main.show_title()
		await _settle()


## 今の画面が contractor_id の契約者の戦闘で、その立ち絵が出て、最初のターンのエネルギー (と蝋燭の表示) と手札の
## 枚数に個性が効いている。label は失敗の文の頭に付ける
func _check_trait_battle(main: MainScript, contractor_id: String, label: String) -> void:
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	_check(battle_ui != null, "%s: 戦闘の画面が出る (%s)" % [label, contractor_id])
	if battle_ui == null:
		return
	var energy: int = (
		BattleScript.ENERGY_PER_TURN + Contractors.trait_value(contractor_id, "energy_bonus")
	)
	var hand: int = mini(
		run_state.deck.size(),
		BattleScript.HAND_SIZE + Contractors.trait_value(contractor_id, "hand_bonus")
	)
	_check(
		battle_ui.pilgrim.texture == Art.PORTRAITS[contractor_id],
		"%s: 契約者の立ち絵が出る (%s)" % [label, contractor_id]
	)
	_check(
		(
			battle_ui.battle.turn == 1
			and battle_ui.battle.energy == energy
			and battle_ui.energy_label.text == "エネルギー %d / %d" % [energy, energy]
			and _visible_children(battle_ui.energy_row) == energy
		),
		"%s: エネルギーに個性が効く (%s)" % [label, contractor_id]
	)
	_check(
		battle_ui.battle.hand.size() == hand and _hand_buttons(battle_ui).size() == hand,
		"%s: 手札の枚数に個性が効く (%s)" % [label, contractor_id]
	)
	_check_buttons_fit(_hand_buttons(battle_ui), "%s の手札" % label)
