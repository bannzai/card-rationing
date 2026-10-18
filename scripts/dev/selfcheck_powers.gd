extends "res://scripts/dev/selfcheck_relics.gd"
## scripts/dev/selfcheck.gd の検証のうち、加護 (scripts/cards.gd の Kind.POWER) の戦闘での効果の検証 (gdlint の
## ファイルの行数の上限に収めるため、検証の本体と分けた)。呼び出しは scripts/dev/selfcheck.gd の _initialize() が行う。


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
