extends "res://scripts/dev/integration_events.gd"
## scripts/dev/integration.gd の検証のうち、加護 (scripts/cards.gd の Kind.POWER) を使って戦闘の終わりまで効く流れの
## 検証 (gdlint のファイルの行数の上限に収めるため、検証の本体と分けた)。呼び出しは scripts/dev/integration.gd の
## _run() が行う。


## 加護のカードを数字キーで使うと、手札から消えて発動中の加護の一覧に 1 行ずつ並び (マウスを乗せるとカードの名前が
## 出る)、ターンを終えても一覧に残って次のターンの始めに効く (防御が付く)。手札に戻らない。発動中の加護が無い戦闘では
## 一覧を隠す
func _check_power_lasts(main: MainScript) -> void:
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	if battle_ui == null:
		return
	_set_deck(["lamp_ward", "ember_heart", "slash", "guard", "guard"])
	_start_battle_with(battle_ui, ["wild_dog"], 1)
	await _settle()
	_check(not battle_ui.power_column.visible, "発動中の加護が無ければ一覧を隠す")
	await _press_key(KEY_1 + _hand_index_of(battle_ui, "lamp_ward"))
	await _press_key(KEY_1 + _hand_index_of(battle_ui, "ember_heart"))
	_check(_hand_buttons(battle_ui).size() == 3, "使った加護は手札から消える")
	_check(
		battle_ui.power_column.visible and _visible_children(battle_ui.power_column) == 3,
		"発動中の加護の一覧に、見出しと加護 2 種の行が出る"
	)
	var row: Label = battle_ui.power_column.get_child(1) as Label
	_check(
		(
			row.text == Cards.power_text("lamp_ward")
			and row.tooltip_text.contains(Cards.CARDS["lamp_ward"]["name"])
		),
		"一覧の行は続く効果を見せ、マウスを乗せるとカードの名前が出る"
	)
	for enemy: Dictionary in battle_ui.battle.enemies:
		enemy["intent"] = {"move": Enemies.Move.GUARD, "value": 1}
	await _press_key(KEY_ENTER)
	_check(battle_ui.battle.turn == 2, "Enter でターン終了")
	_check(
		battle_ui.status_label.text.contains("防御 %d" % Cards.CARDS["lamp_ward"]["turn_block"]),
		"次のターンの始めに加護の防御が付いて見える"
	)
	_check(_visible_children(battle_ui.power_column) == 3, "ターンを終えても発動中の加護は一覧に残る")
	_check(
		_hand_index_of(battle_ui, "lamp_ward") < 0 and _hand_index_of(battle_ui, "ember_heart") < 0,
		"使った加護はこの戦闘の間は手札に戻らない"
	)
	_start_battle_with(battle_ui, ["wild_dog"], 2)
	await _settle()
	_check(not battle_ui.power_column.visible, "次の戦闘では発動中の加護の一覧が消える")
	# 加護の全種が発動していても、一覧は案内の文と手札に重ならない
	var power_ids: Array[String] = []
	for card_id: String in Cards.CARDS:
		if Cards.CARDS[card_id]["kind"] == Cards.Kind.POWER:
			power_ids.append(card_id)
	_set_deck(power_ids)
	_start_battle_with(battle_ui, ["wild_dog"], 1)
	for deck_index: int in range(power_ids.size()):
		battle_ui.battle.powers.append(deck_index)
	battle_ui.refresh()
	await _settle()
	var column: Rect2 = battle_ui.power_column.get_global_rect()
	_check(
		(
			_visible_children(battle_ui.power_column) == power_ids.size() + 1
			and column.end.y <= battle_ui.hand_row.get_global_rect().position.y
			and column.position.y >= battle_ui.message_label.get_global_rect().end.y
		),
		"加護の全 %d 種が発動していても、一覧が案内の文と手札に重ならない" % power_ids.size()
	)
