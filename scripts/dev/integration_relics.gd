extends "res://scripts/dev/integration_base.gd"
## scripts/dev/integration.gd の検証のうち、護符 (scripts/relics.gd) を手に入れて効く流れの検証 (gdlint のファイルの
## 行数の上限に収めるため、検証の本体と分けた)。どの検証も、終わったら持っている護符を空に戻す (同じラン単位の状態で
## 続くほかの検証が、護符の効果を受けないように)。

const Relics := preload("res://scripts/relics.gd")

## 焼けぬ封蝋が減らないと出る判定の通し番号を探す数 (確率 1/2 なので、数回で見つかる)
const SPARE_SEARCH_LIMIT: int = 64
## 護符の印が光り、名前が浮かぶ動きが終わるまで待つ時間 (秒)。浮かぶ名前 (Art.FLOAT_TIME) が最も長い動きで、
## integration.gd の MOTION_MARGIN と同じ余裕を足す
const RELIC_MOTION_WAIT: float = Art.FLOAT_TIME + 0.2


## 強敵の戦闘: 持っている護符の印が戦闘画面に並び、戦闘の始めに働いた護符 (蝋の盾) の文と防御が出て、印にマウスを
## 載せると説明が出る。攻撃のカードを使うと熾火の刃が働いてダメージが 1 増え、勝つと護符を 1 つ手に入れて報酬の
## 画面に名前が出る。報酬の画面で終了して「続きから」で再開しても、護符と報酬の画面の護符の名前が保たれる
func _check_elite_relic(main: MainScript) -> void:
	run_state.relics.clear()
	run_state.add_relic("wax_ward")
	await _enter_kind(main, ActMap.Kind.ELITE)
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	_check(battle_ui != null, "護符の検証: 強敵の節点で戦闘に入る")
	if battle_ui == null:
		run_state.relics.clear()
		return
	_check(_visible_children(battle_ui.relic_row) == 1, "持っている護符の印が戦闘画面に並ぶ")
	_check(
		battle_ui.battle.block == Relics.RELICS["wax_ward"]["block"],
		"蝋の盾で戦闘の始めに防御がある"
	)
	_check(
		battle_ui.relic_label.text.contains(Relics.RELICS["wax_ward"]["name"]),
		"戦闘の始めに働いた護符の名前が出る"
	)
	var view: Control = battle_ui.relic_row.get_child(0)
	view.mouse_entered.emit()
	_check(
		battle_ui.relic_label.text.contains(Relics.RELICS["wax_ward"]["text"]),
		"護符の印にマウスを載せると効果の説明が出る"
	)
	view.mouse_exited.emit()
	_check(
		not battle_ui.relic_label.text.contains(Relics.RELICS["wax_ward"]["text"]),
		"印からマウスを外すと説明が消える"
	)
	run_state.add_relic("ember_edge")
	_set_deck(["slash", "guard", "guard", "guard", "guard"])
	var slash_hand: int = await _start_battle_with_card_in_hand(battle_ui, "slash")
	_check(_visible_children(battle_ui.relic_row) == 2, "手に入れた護符の印も並ぶ")
	if slash_hand < 0:
		_check(false, "護符の検証: 斬火が手札に来る")
		run_state.relics.clear()
		return
	var slash_view: CardViewScript = _hand_buttons(battle_ui)[slash_hand] as CardViewScript
	_check(
		slash_view.effect_label.text == "攻撃 %d" % (Cards.CARDS["slash"]["damage"] + 1),
		"手札の効果の文に熾火の刃を足したダメージが出る"
	)
	var enemy: Dictionary = battle_ui.battle.enemies[0]
	var hp_before: int = enemy["hp"]
	await _click(_hand_buttons(battle_ui)[slash_hand])
	_check(
		enemy["hp"] == hp_before - Cards.CARDS["slash"]["damage"] - 1,
		"熾火の刃で攻撃のダメージが 1 増える"
	)
	_check(
		battle_ui.relic_label.text.contains(Relics.RELICS["ember_edge"]["name"]),
		"攻撃のカードを使うと、働いた熾火の刃の名前が出る"
	)
	_check(battle_ui.battle.relic_triggers.is_empty(), "見せた護符の発動は消え、次の操作でもう一度見せない")
	enemy["hp"] = 1
	enemy["block"] = 0
	await _press_key(KEY_S)
	var reward: RewardUiScript = main.screen as RewardUiScript
	_check(reward != null and run_state.relics.size() == 3, "強敵に勝つと護符を 1 つ手に入れる")
	if reward == null:
		run_state.relics.clear()
		return
	var gained: String = run_state.relics.back()
	_check(
		reward.relic_label != null and reward.relic_label.text.contains(Relics.RELICS[gained]["name"]),
		"強敵の報酬の画面に手に入れた護符の名前が出る"
	)
	var relics_before: Array[String] = run_state.relics.duplicate()
	await _quit_and_continue(main)
	reward = main.screen as RewardUiScript
	_check(run_state.relics == relics_before, "終了して「続きから」で再開しても護符が保たれる")
	_check(
		(
			reward != null
			and reward.relic_label != null
			and reward.relic_label.text.contains(Relics.RELICS[gained]["name"])
		),
		"「続きから」で戻った報酬の画面にも、手に入れた護符の名前が出る"
	)
	if reward != null:
		await _click(reward.skip_button)
	_check(main.screen is MapUiScript, "護符の検証: 報酬の後は地図")
	run_state.relics.clear()


## 商人: 護符が説明と値段付きで並び、買うと所持金が減って護符を持ち、同じ訪問では売り切れになる
func _check_shop_relic(main: MainScript) -> void:
	run_state.relics.clear()
	run_state.gold = NodeRules.RELIC_PRICE + 10
	await _enter_kind(main, ActMap.Kind.SHOP)
	var shop: ShopUiScript = main.screen as ShopUiScript
	_check(shop != null and shop.relic_button != null, "商人に護符が並ぶ")
	if shop == null or shop.relic_button == null:
		run_state.relics.clear()
		return
	var offered: String = NodeRules.shop_relic(run_state)
	_check(shop.relic_button.text.contains(Relics.RELICS[offered]["text"]), "商人の護符に効果の説明が出る")
	_check_buttons_fit([shop.relic_button], "商人の護符")
	await _click(shop.relic_button)
	_check(
		run_state.relics.has(offered) and run_state.gold == 10, "商人で護符を買うと所持金が減って護符を持つ"
	)
	_check(shop.relic_button.disabled, "買った護符は売り切れ")
	await _click(shop.leave_button)
	run_state.relics.clear()


## 焼けぬ封蝋が働いて残り使用回数が減らなかった時: 動きを付けたまま (戦闘の動きの倍率 1) で、残りが減らず、働いた
## ことが文と印の動きで出て、動きが終われば消える (使ったカードの複製は、焼ける印が無くても動く)。呼ぶ側が倍率を
## 1 にして呼ぶ
func _check_unburnt_seal_motion(main: MainScript) -> void:
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	if battle_ui == null:
		_check(false, "焼けぬ封蝋の検証: 戦闘の画面が出ている")
		return
	run_state.relics.clear()
	run_state.add_relic("unburnt_seal")
	_set_deck(["slash", "slash", "slash", "slash", "slash"])
	_start_battle_with(battle_ui, ["skeleton"], 1)
	await _settle()
	var spare_roll: int = -1
	for roll_index: int in range(SPARE_SEARCH_LIMIT):
		if Relics.roll_spare(run_state.map_seed, roll_index):
			spare_roll = roll_index
			break
	_check(spare_roll >= 0, "焼けぬ封蝋が減らないと出る通し番号がある")
	run_state.relic_rolls = maxi(spare_roll, 0)
	var deck_index: int = battle_ui.battle.hand[0]
	var uses_before: int = run_state.uses_left(deck_index)
	await _click(_hand_buttons(battle_ui)[0])
	_check(run_state.uses_left(deck_index) == uses_before, "焼けぬ封蝋が働くと残り使用回数が減らない")
	_check(
		battle_ui.relic_label.text.contains(Relics.RELICS["unburnt_seal"]["name"]),
		"焼けぬ封蝋が働いたことが文で出る"
	)
	_check(_has_label(battle_ui.effects_layer, Relics.RELICS["unburnt_seal"]["name"]), "護符の名前が浮かぶ")
	await create_timer(RELIC_MOTION_WAIT).timeout
	await _settle()
	_check(battle_ui.effects_layer.get_child_count() == 0, "焼けぬ封蝋の動きが終わると複製と名前が消える")
	run_state.relics.clear()
	run_state.relic_rolls = 0


## parent の子に、文が text のラベルがあるか
func _has_label(parent: Node, text: String) -> bool:
	for child: Node in parent.get_children():
		if child is Label and (child as Label).text == text:
			return true
	return false
