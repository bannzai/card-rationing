extends "res://scripts/dev/selfcheck_relics.gd"
## scripts/dev/selfcheck.gd の検証のうち、契約者の個性 (scripts/contractors.gd) の検証 (gdlint のファイルの行数の
## 上限に収めるため、検証の本体と分けた)。呼び出しは scripts/dev/selfcheck.gd の _initialize() が行う。

const Art := preload("res://scripts/art.gd")

## 契約者の人数 (issue #46 の「合計 3〜4 人」)
const CONTRACTOR_COUNT_RANGE: Array[int] = [3, 4]


## 契約者の個性 (issue #46): 契約者は 3〜4 人で、全員に個性の名前と効果・最大体力・立ち絵があり、手札 +2 の
## 契約者がいる。新しいランは契約者の最大体力で始まり、戦闘のターンの始まりのエネルギーと引く枚数に個性が効き、
## 保存と読み込みの後も効く
func _check_contractor_traits() -> void:
	_check(_in_range(Contractors.CONTRACTORS.size(), CONTRACTOR_COUNT_RANGE), "契約者が 3〜4 人")
	var has_hand_two: bool = false
	for contractor_id: String in Contractors.CONTRACTORS:
		var contractor: Dictionary = Contractors.CONTRACTORS[contractor_id]
		_check(
			not contractor["trait_name"].is_empty() and _is_short_copy(contractor["trait_name"]),
			"契約者の個性の名前があり句読点が無い: %s" % contractor_id
		)
		_check(not Contractors.trait_lines(contractor_id).is_empty(), "契約者に個性の効果がある: %s" % contractor_id)
		_check(contractor["max_hp"] >= 1, "契約者の最大体力が 1 以上: %s" % contractor_id)
		_check(Art.PORTRAITS.has(contractor_id), "契約者の立ち絵がある: %s" % contractor_id)
		has_hand_two = has_hand_two or Contractors.trait_value(contractor_id, "hand_bonus") == 2
		var state: RunStateScript = RunStateScript.new()
		state.new_run([], 3, contractor_id)
		_check(
			(
				state.character_id == contractor_id
				and state.hp == contractor["max_hp"]
				and state.max_hp == state.hp
			),
			"新しいランは契約者の最大体力で始まる: %s" % contractor_id
		)
		_check_trait_battle(state, contractor_id, "新しいラン")
		_remove_user_file(SELFCHECK_SAVE_PATH)
		state.save_to(SELFCHECK_SAVE_PATH)
		var loaded: RunStateScript = RunStateScript.new()
		loaded.new_run()
		_check(
			loaded.load_from(SELFCHECK_SAVE_PATH) == RunStateScript.LoadResult.LOADED
			and loaded.character_id == contractor_id,
			"保存と読み込みで契約者が保たれる: %s" % contractor_id
		)
		_check_trait_battle(loaded, contractor_id, "読み込んだラン")
		_remove_user_file(SELFCHECK_SAVE_PATH)
		state.free()
		loaded.free()
	_check(has_hand_two, "毎ターン引く枚数が 2 枚多い契約者がいる")
	_check_win_restore()


## state (contractor_id の契約者のラン) で戦闘を始めると、最初のターンのエネルギーと手札の枚数が基準に個性を
## 足した値になる。label は失敗の文の頭に付ける
func _check_trait_battle(state: RunStateScript, contractor_id: String, label: String) -> void:
	var battle: BattleScript = BattleScript.new()
	battle.start(state, ["wisp"], 1)
	var energy: int = (
		BattleScript.ENERGY_PER_TURN + Contractors.trait_value(contractor_id, "energy_bonus")
	)
	var hand: int = mini(
		state.deck.size(), BattleScript.HAND_SIZE + Contractors.trait_value(contractor_id, "hand_bonus")
	)
	_check(battle.energy == energy, "%s: エネルギーに個性が効く (%s)" % [label, contractor_id])
	_check(battle.hand.size() == hand, "%s: 引く枚数に個性が効く (%s)" % [label, contractor_id])


## 勝つたびに回数を戻す個性 (NodeRules.win_restore()): 通常の戦闘と強敵に勝つと、精霊のうち減っている回数が
## 最も多い 1 枚 (同じならデッキの先) だけが個性の回数戻り、最大を超えない。英霊・ボス・個性の無い契約者では戻らない
## (残り使用回数を増やす経路の検証。.claude/rules/card-uses-persist-across-run.md)
func _check_win_restore() -> void:
	var restorer: String = ""
	var plain: String = ""
	for contractor_id: String in Contractors.CONTRACTORS:
		if Contractors.trait_value(contractor_id, "win_restore") > 0:
			restorer = contractor_id
		elif plain.is_empty():
			plain = contractor_id
	_check(not restorer.is_empty() and not plain.is_empty(), "勝つたびに回数を戻す契約者と、戻さない契約者がいる")
	if restorer.is_empty() or plain.is_empty():
		return
	var amount: int = Contractors.trait_value(restorer, "win_restore")
	var deck: Array[String] = ["slash", "guard", "hero_strike", "slash"]
	var hero_max: int = Cards.CARDS["hero_strike"]["max_uses"]
	for kind: int in [ActMap.Kind.BATTLE, ActMap.Kind.ELITE]:
		var state: RunStateScript = _trait_state_at(restorer, deck, kind)
		for index: int in [0, 0, 1, 2, 3, 3, 3]:
			state.use_card(index)
		RunFlow.finish_battle(state, true)
		_check(state.visit.get("win_restored", -1) == 3, "最も回数の減った精霊が戻る (種類 %d)" % kind)
		_check(
			state.uses_left(3) == Cards.CARDS["slash"]["max_uses"] - 3 + amount,
			"個性の回数だけ戻る (種類 %d)" % kind
		)
		_check(
			(
				state.uses_left(0) == Cards.CARDS["slash"]["max_uses"] - 2
				and state.uses_left(2) == hero_max - 1
			),
			"ほかの精霊と英霊は戻らない (種類 %d)" % kind
		)
		state.free()
	var tied: RunStateScript = _trait_state_at(restorer, deck, ActMap.Kind.BATTLE)
	tied.use_card(3)
	tied.use_card(0)
	tied.use_card(2)
	RunFlow.finish_battle(tied, true)
	_check(tied.visit.get("win_restored", -1) == 0, "減っている回数が同じならデッキの先の精霊が戻る")
	_check(tied.uses_left(0) == Cards.CARDS["slash"]["max_uses"], "戻しても最大を超えない")
	tied.free()
	var hero_only: RunStateScript = _trait_state_at(restorer, deck, ActMap.Kind.BATTLE)
	hero_only.use_card(2)
	RunFlow.finish_battle(hero_only, true)
	_check(
		not hero_only.visit.has("win_restored") and hero_only.uses_left(2) == hero_max - 1,
		"減っているのが英霊だけなら戻さない"
	)
	hero_only.free()
	var boss: RunStateScript = _trait_state_at(restorer, deck, ActMap.Kind.BOSS)
	boss.use_card(0)
	RunFlow.finish_battle(boss, true)
	_check(boss.uses_left(0) == Cards.CARDS["slash"]["max_uses"] - 1, "ボスに勝っても戻さない")
	boss.free()
	var other: RunStateScript = _trait_state_at(plain, deck, ActMap.Kind.BATTLE)
	other.use_card(0)
	RunFlow.finish_battle(other, true)
	_check(other.uses_left(0) == Cards.CARDS["slash"]["max_uses"] - 1, "個性の無い契約者は戻さない")
	other.free()
	_remove_user_file(SELFCHECK_SAVE_PATH)


## contractor_id の契約者で、デッキを deck_ids にして kind の最初の節点に入った局面のラン (地図のシードは 11)
func _trait_state_at(contractor_id: String, deck_ids: Array[String], kind: int) -> RunStateScript:
	var state: RunStateScript = RunStateScript.new()
	state.save_path = SELFCHECK_SAVE_PATH
	state.new_run(deck_ids, 11, contractor_id)
	var at: Vector2i = ActMap.find_kind(state.rows, kind)
	state.path = ActMap.route_to(state.rows, at.x, at.y)
	state.phase = RunFlow.KIND_PHASES[kind]
	return state
