extends "res://scripts/dev/selfcheck_events.gd"
## scripts/dev/selfcheck.gd の検証のうち、加護 (scripts/cards.gd の Kind.POWER) の戦闘での効果と戦略 bot の加護の
## 扱いと指標の数え方の検証 (gdlint のファイルの行数の上限に収めるため、検証の本体と分けた)。呼び出しは
## scripts/dev/selfcheck.gd が行う。

const Bots := preload("res://scripts/dev/strategy_bots.gd")

## 加護のカードの種類の数 (issue #45 の指定)
const POWER_COUNT_RANGE: Array[int] = [4, 6]


## 加護: 使うと残り使用回数が 1 減り、捨て札へ行かず発動中の加護に入って、その戦闘の終わりまで効く (攻撃は 1 回ごとに
## 上乗せ・毎ターンの始めの防御とエネルギーと引く枚数・もがくの上乗せ)。毎ターンの効果は使った次のターンから効く。
## 次の戦闘では発動中の加護が消えて山札に戻り、使った回数は戻らない
func _check_battle_powers() -> void:
	var state: RunStateScript = RunStateScript.new()
	state.new_run(["lamp_ward", "ember_heart", "slash", "twin_flame", "guard"])
	var battle: BattleScript = BattleScript.new()
	battle.start(state, ["skeleton"], 1)
	_check(battle.play(_hand_index_of(battle, state, "lamp_ward")), "灯守りの精を使える")
	_check(
		(
			battle.powers.size() == 1
			and battle.powers[0] == 0
			and battle.discard_pile.is_empty()
			and battle.hand.size() == 4
		),
		"加護は捨て札へ行かず発動中の加護に入る"
	)
	_check(
		state.uses_left(0) == Cards.CARDS["lamp_ward"]["max_uses"] - 1 and battle.energy == 2,
		"加護もコストを払い残り使用回数が 1 減る"
	)
	_check(battle.block == 0, "毎ターンの防御は使ったターンには付かない")
	_check(battle.play(_hand_index_of(battle, state, "ember_heart")), "熾りの精を使える")
	_check(battle.power_total("attack_bonus") == 1, "攻撃の上乗せ 1 が発動している")
	_check(battle.card_damage(2) == 7, "手札に見せる斬火の 1 回のダメージに上乗せ 1 を含む (7)")
	_check(battle.play(_hand_index_of(battle, state, "slash"), 0), "斬火を使える")
	_check(battle.enemies[0]["hp"] == 15, "斬火 6 に上乗せ 1 で 7 ダメージ (22 → 15)")
	battle.enemies[0]["intent"] = {"move": Enemies.Move.GUARD, "value": 0}
	battle.end_turn()
	_check(battle.block == 3 and battle.energy == 3, "次のターンの始めに防御 3 が付く (エネルギーは 3 のまま)")
	_check(
		battle.powers.size() == 2 and battle.hand.size() == 3 and battle.draw_pile.is_empty(),
		"発動中の加護は山札・手札に戻らない (残りの 3 枚だけを引き直す)"
	)
	_check(battle.play(_hand_index_of(battle, state, "twin_flame"), 0), "双つ灯を使える")
	_check(battle.enemies[0]["hp"] == 5, "双つ灯 4×2 の 1 回ごとに上乗せ 1 (15 → 5)")
	_check(battle.struggle_damage() == BattleScript.STRUGGLE_DAMAGE, "もがくの上乗せが無ければもがくは 2")
	# 毎ターンのエネルギー・引く枚数と、もがくの上乗せ。手札と山札の並びを決めて、加護 3 枚を最初の手札に置く
	state.new_run(
		[
			"guiding_light",
			"lighthouse_keeper",
			"defiant_spark",
			"guard",
			"guard",
			"guard",
			"guard",
			"guard",
			"guard",
			"guard",
		]
	)
	battle.start(state, ["skeleton"], 1)
	battle.hand = [0, 1, 2, 3, 4]
	battle.draw_pile = [5, 6, 7, 8, 9]
	battle.discard_pile = []
	for card_id: String in ["guiding_light", "lighthouse_keeper", "defiant_spark"]:
		_check(battle.play(_hand_index_of(battle, state, card_id)), "%s を使える" % card_id)
	_check(battle.energy == 1, "コスト 1・0・1 の加護を使ってエネルギー 1")
	_check(battle.struggle_damage() == 5 and battle.struggle(0), "もがくの上乗せ 3 でもがくは 5")
	_check(battle.enemies[0]["hp"] == 17, "上乗せしたもがくで 22 → 17")
	battle.enemies[0]["intent"] = {"move": Enemies.Move.GUARD, "value": 0}
	battle.end_turn()
	_check(battle.energy == 4, "次のターンの始めにエネルギーが 1 多い (4)")
	_check(battle.hand.size() == 6, "次のターンの始めに 1 枚多く引く (6 枚)")
	# 次の戦闘: 発動中の加護は消えて山札に戻り、使った回数は戻らない
	battle.start(state, ["skeleton"], 2)
	_check(
		battle.powers.is_empty() and battle.hand.size() + battle.draw_pile.size() == state.deck.size(),
		"次の戦闘では発動中の加護が消え、加護も山札に戻る"
	)
	_check(battle.energy == 3 and battle.block == 0, "次の戦闘の最初のターンは加護の効果が無い")
	_check(state.uses_left(1) == 0, "次の戦闘でも加護に使った回数は戻らない (灯台守の英霊は契約切れのまま)")
	state.free()


## 戦略 bot の加護の扱い: 戦闘の残りのターンの見込みで点数を付け、新しい契約では技と同じく攻撃・防御の後に取る。
## state と battle は呼ぶ側の bot の検証のものを使い回す (state は新しいランで上書きする)
func _check_bot_powers(state: RunStateScript, battle: BattleScript) -> void:
	# 加護は戦闘の残りのターンの見込みで点数を付ける: 敵の体力 22 なら次のターンが残る見込みで使い、1 ターンの
	# ダメージの見込み以下なら今のターンで倒しきれる見込みで使わない (点数 0)。攻撃カードの無いデッキの見込みは、
	# エネルギー 3 をすべてもがくに使った 6
	state.new_run(["lamp_ward"], BOT_SEED)
	state.path = ActMap.route_to(state.rows, 0, state.rows[0][0]["column"])
	battle.start(state, ["skeleton"], 1)
	for strategy: int in Bots.Strategy.values():
		_check(
			Bots.battle_move(strategy, battle, state)["move"] == Bots.BattleMove.PLAY,
			"敵の体力が 22 なら加護を使う: %s" % Bots.STRATEGY_NAMES[strategy]
		)
	_check(is_equal_approx(Bots._turn_damage(battle), 6.0), "攻撃カードが無ければ 1 ターンのダメージの見込みは 6")
	battle.enemies[0]["hp"] = 6
	_check(
		Bots.battle_move(Bots.Strategy.SPEND, battle, state)["move"] == Bots.BattleMove.STRUGGLE,
		"今のターンで倒しきれる見込みなら加護を使わない"
	)
	# 新しい契約で、加護は技と同じく攻撃・防御の後に取る (並びに無い種別を先に取らない)
	state.new_run(["slash", "guard"], BOT_SEED)
	var offers: Array[String] = ["lamp_ward", "war_banner", "slash"]
	_check(Bots._choose_offer(state, offers) == "slash", "攻撃が足りなければ加護より攻撃を取る")


## 戦略 bot の指標: 手札の半分以上が契約切れかは実際の手札の枚数で数え、報酬に攻撃カードがあったかは並んだカードで
## 決まる。state と battle は呼ぶ側の bot の検証のものを使い回す (state は新しいランで上書きする)
func _check_bot_metrics(state: RunStateScript, battle: BattleScript) -> void:
	state.new_run(["slash", "guard", "breath"], BOT_SEED)
	state.path = ActMap.route_to(state.rows, 0, state.rows[0][0]["column"])
	while state.use_card(0):
		pass
	battle.start(state, ["skeleton"], 1)
	_check(battle.hand.size() == 3, "3 枚のデッキなら手札は 3 枚")
	_check(not Bots.hand_mostly_expired(battle, state), "手札 3 枚のうち契約切れ 1 枚は半分未満")
	while state.use_card(1):
		pass
	_check(Bots.hand_mostly_expired(battle, state), "手札 3 枚のうち契約切れ 2 枚は半分以上")
	_check(Bots.offers_attack(["guard", "slash"]), "攻撃カードが並べば報酬に攻撃がある")
	_check(not Bots.offers_attack(["guard", "breath"]), "攻撃カードが並ばなければ報酬に攻撃が無い")


## 加護のカードの定義: 種類の数が POWER_COUNT_RANGE に入り、精霊と英霊の両方がある。加護は割合でなく種類の数で絞る
## (攻撃・防御・技を 2 割以上に保ったまま足すため)
func _check_power_cards() -> void:
	var power_count: int = 0
	var power_bonds: Dictionary = {}
	for card_id: String in Cards.CARDS:
		if Cards.CARDS[card_id]["kind"] == Cards.Kind.POWER:
			power_count += 1
			power_bonds[Cards.CARDS[card_id]["bond"]] = true
	_check(_in_range(power_count, POWER_COUNT_RANGE), "加護が 4〜6 種 (%d)" % power_count)
	_check(power_bonds.size() == Cards.BOND_NAMES.size(), "加護に精霊と英霊の両方がある")
