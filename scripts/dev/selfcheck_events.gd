extends "res://scripts/dev/selfcheck_contractors.gd"
## scripts/dev/selfcheck.gd の検証のうち、出来事の絵と、英霊の塚・灯売りの行商・灰の炉・封蝋の骰子・写し手の机・
## 影の質屋の結果の検証 (gdlint のファイルの行数の上限に収めるため、検証の本体と分けた)。ほかの出来事の検証は
## scripts/dev/selfcheck_run.gd の _check_events()、蝋の祭壇は scripts/dev/selfcheck.gd にある。呼び出しは
## scripts/dev/selfcheck.gd の _initialize() が行う。

## 封蝋の骰子の当たる割合を数える節点のシードの範囲 (1〜GAMBLE_SEEDS。出来事は 10 種なので、骰子の節点は約 1000 個)
## と、当たる割合の許す範囲 (確率 1/2 の約 1000 回で、外れる見込みが十分小さい幅)
const GAMBLE_SEEDS: int = 10000
const GAMBLE_RATE_RANGE: Array[float] = [0.4, 0.6]


## 出来事の絵と選択肢の並び: どの出来事にも絵があり、最後の選択肢はカードも代価も要らない (戦略 bot と遊ぶ人が、
## 選べる選択肢の無い出来事に詰まらないように)
func _check_event_art_and_leave() -> void:
	for event_id: String in Events.EVENTS:
		_check(Art.EVENT_ART.has(event_id), "出来事の絵がある: %s" % event_id)
		var last: Dictionary = Events.EVENTS[event_id]["options"].back()
		_check(
			(
				last["picks"] == 0
				and (last["effect"] == Events.Effect.LEAVE or last["effect"] == Events.Effect.GOLD)
			),
			"最後の選択肢はいつでも選べる: %s" % event_id
		)


## 英霊の塚: 体力を払って英霊 1 枚と契約する。払った後に体力が残らなければ選べない
func _check_hero_barrow() -> void:
	var none: Array[int] = []
	var state: RunStateScript = _state_at_event("hero_barrow")
	var size_before: int = state.deck.size()
	_check(Events.choose(state, 0, none), "体力を払って英霊と契約できる")
	_check(state.deck.size() == size_before + 1, "英霊の塚で 1 枚増える")
	_check(state.card(size_before)["bond"] == Cards.Bond.HERO, "英霊の塚で得るのは英霊")
	_check(state.uses_left(size_before) == state.card(size_before)["max_uses"], "英霊は最大の回数で入る")
	_check(state.hp == state.max_hp - Events.HERO_BLOOD_PRICE, "英霊の塚で体力を払う")
	state.free()
	state = _state_at_event("hero_barrow")
	state.hp = Events.HERO_BLOOD_PRICE
	_check(not Events.choose(state, 0, none), "体力が払う量以下なら英霊の塚で契約できない")
	state.free()


## 灯売りの行商: 所持金を払って、残りの減ったカード 1 枚の残り使用回数を CANDLE_USES 回戻す (最大を超えない)。
## 減っていないカードと、所持金が足りない時は選べない
func _check_candle_peddler() -> void:
	var first: Array[int] = [0]
	var second: Array[int] = [1]
	var state: RunStateScript = _event_state("candle_peddler", ["slash", "guard"])
	state.gold = Events.CANDLE_PRICE
	for _use: int in range(Events.CANDLE_USES + 1):
		state.use_card(0)
	var uses_before: int = state.uses_left(0)
	_check(not Events.choose(state, 0, second), "灯売りの行商で減っていないカードは選べない")
	_check(Events.choose(state, 0, first), "所持金を払って残り使用回数を戻せる")
	_check(state.uses_left(0) == uses_before + Events.CANDLE_USES, "灯売りの行商で残りが決まった回数だけ戻る")
	_check(state.gold == 0, "灯売りの行商で所持金を払う")
	state.free()
	state = _event_state("candle_peddler", ["slash", "guard"])
	state.gold = Events.CANDLE_PRICE
	state.use_card(0)
	_check(
		Events.choose(state, 0, first) and state.uses_left(0) == state.card(0)["max_uses"],
		"灯売りの行商は最大を超えて戻さない"
	)
	state.free()
	state = _event_state("candle_peddler", ["slash", "guard"])
	state.gold = Events.CANDLE_PRICE - 1
	state.use_card(0)
	_check(not Events.choose(state, 0, first), "所持金が足りなければ灯売りの行商で戻せない")
	state.free()


## 灰の炉: 最初に選んだ 1 枚を手放し、続けて選んだ 2 枚の残り使用回数を最大まで戻す。戻すカードは残りの減った
## カードだけで、手放すカードと戻すカードは重ねられず、3 枚に満たないデッキでは選べない
func _check_ash_furnace() -> void:
	var ids: Array[String] = ["slash", "guard", "hero_strike", "breath"]
	var state: RunStateScript = _event_state("ash_furnace", ids)
	state.use_card(1)
	state.use_card(2)
	var overlapping: Array[int] = [1, 1, 2]
	var full_restore: Array[int] = [1, 2, 3]
	var burn: Array[int] = [0, 1, 2]
	_check(not Events.choose(state, 0, overlapping), "灰の炉で手放すカードと戻すカードは重ねられない")
	_check(not Events.choose(state, 0, full_restore), "灰の炉で減っていないカードは戻せない")
	_check(Events.choose(state, 0, burn), "1 枚を炉にくべて 2 枚を戻せる")
	ids.clear()
	for entry: Dictionary in state.deck:
		ids.append(entry["id"])
	_check(ids == ["guard", "hero_strike", "breath"], "灰の炉で最初に選んだ 1 枚だけを手放す: %s" % [ids])
	_check(
		(
			state.uses_left(0) == state.card(0)["max_uses"]
			and state.uses_left(1) == state.card(1)["max_uses"]
		),
		"灰の炉で選んだ 2 枚の残りが最大に戻る"
	)
	state.free()
	state = _event_state("ash_furnace", ["guard", "hero_strike"])
	state.use_card(0)
	state.use_card(1)
	var two: Array[int] = [0, 1]
	_check(
		not Events.can_start(state, 0) and not Events.choose(state, 0, two),
		"2 枚のデッキでは灰の炉を選べない"
	)
	state.free()


## 封蝋の骰子: 当たり外れは節点のシードで決まり、出来事の選択の乱数とずらしてあるので、骰子の節点のうち当たる割合が
## 1/2 の近くになる。当たれば賭けたカードの残りが最大に戻り、外れればそのカードを失う。賭けられるのは残りが 1 以上で
## 減ったカードだけ
func _check_seal_dice() -> void:
	var nodes: int = 0
	var wins: int = 0
	for seed_value: int in range(1, GAMBLE_SEEDS + 1):
		if Events.event_for(seed_value) == "seal_dice":
			nodes += 1
			wins += 1 if Events.gamble_wins(seed_value) else 0
	var rate: float = float(wins) / maxi(nodes, 1)
	_check(_in_range(rate, GAMBLE_RATE_RANGE), "封蝋の骰子が当たる割合が 1/2 の近く: %.3f (%d 回)" % [rate, nodes])
	var first: Array[int] = [0]
	var second: Array[int] = [1]
	for wins_here: bool in [true, false]:
		var state: RunStateScript = _gamble_state(wins_here)
		_check(not Events.choose(state, 0, second), "封蝋の骰子で減っていないカードは賭けられない")
		while state.use_card(1):
			pass
		_check(not Events.choose(state, 0, second), "封蝋の骰子で契約切れのカードは賭けられない")
		state.use_card(0)
		_check(Events.choose(state, 0, first), "使いかけのカードを骰子に賭けられる")
		if wins_here:
			_check(
				state.deck.size() == 2 and state.uses_left(0) == state.card(0)["max_uses"],
				"骰子が当たると賭けたカードの残りが最大に戻る"
			)
		else:
			_check(
				state.deck.size() == 1 and state.deck[0]["id"] == "guard",
				"骰子が外れると賭けたカードを失う"
			)
		state.free()


## 写し手の机: 所持金を払って、選んだ精霊と同じ精霊ともう 1 枚 (最大の回数で) 契約する。英霊は写せず、所持金が
## 足りない時は選べない
func _check_scribe_desk() -> void:
	var spirit: Array[int] = [0]
	var hero: Array[int] = [1]
	var state: RunStateScript = _event_state("scribe_desk", ["breath", "hero_strike"])
	state.gold = Events.COPY_PRICE
	state.use_card(0)
	_check(not Events.choose(state, 0, hero), "写し手の机で英霊は写せない")
	_check(Events.choose(state, 0, spirit), "所持金を払って精霊を写せる")
	_check(
		(
			state.deck.size() == 3
			and state.deck[2]["id"] == "breath"
			and state.uses_left(2) == state.card(2)["max_uses"]
		),
		"写した精霊は同じカードが最大の回数で増える"
	)
	_check(state.uses_left(0) == state.card(0)["max_uses"] - 1, "写した元の精霊の残りは変わらない")
	_check(state.gold == 0, "写し手の机で所持金を払う")
	state.free()
	state = _event_state("scribe_desk", ["breath", "hero_strike"])
	state.gold = Events.COPY_PRICE - 1
	_check(not Events.choose(state, 0, spirit), "所持金が足りなければ精霊を写せない")
	state.free()


## 影の質屋: 1 枚を手放して所持金を得る。1 枚だけのデッキでは選べない
func _check_shadow_pawn() -> void:
	var first: Array[int] = [0]
	var state: RunStateScript = _event_state("shadow_pawn", ["slash", "guard"])
	_check(Events.choose(state, 0, first), "1 枚を手放して所持金を得られる")
	_check(state.deck.size() == 1 and state.deck[0]["id"] == "guard", "影の質屋で選んだ 1 枚を手放す")
	_check(state.gold == Events.PAWN_GOLD, "影の質屋で所持金を得る")
	state.free()
	state = _event_state("shadow_pawn", ["slash"])
	_check(not Events.choose(state, 0, first), "1 枚だけのデッキでは影の質屋で手放せない")
	state.free()


## event_id の出来事の節点に入った局面のランで、デッキを ids のカード (最大使用回数) にしたもの
func _event_state(event_id: String, ids: Array[String]) -> RunStateScript:
	var state: RunStateScript = _state_at_event(event_id)
	state.deck.clear()
	for card_id: String in ids:
		state.add_card(card_id)
	return state


## 封蝋の骰子の節点に入った局面で、骰子の結果が wins になるラン (デッキは斬火・守りの風。地図のシードを 1 から順に
## 試す。見つからなければ失敗にして、最初に見つかった骰子の節点のランを返す)
func _gamble_state(wins: bool) -> RunStateScript:
	for seed_value: int in range(1, 1001):
		var state: RunStateScript = _state_at(ActMap.Kind.EVENT, seed_value)
		var node_seed: int = state.node_seed()
		if Events.event_for(node_seed) == "seal_dice" and Events.gamble_wins(node_seed) == wins:
			state.deck.clear()
			state.add_card("slash")
			state.add_card("guard")
			return state
		state.free()
	_check(false, "骰子の結果が %s になる地図が見つかる" % wins)
	return _event_state("seal_dice", ["slash", "guard"])
