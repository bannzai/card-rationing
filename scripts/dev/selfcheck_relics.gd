extends "res://scripts/dev/selfcheck_run.gd"
## scripts/dev/selfcheck.gd の検証のうち、護符 (scripts/relics.gd) の定義・効果・確率・手に入る経路の検証と、
## 検証の本体と共有する部品 (gdlint のファイルの行数の上限に収めるため、検証の本体と分けた)。呼び出しは
## scripts/dev/selfcheck.gd の _initialize() が行う。

const BattleScript := preload("res://scripts/battle.gd")
const Relics := preload("res://scripts/relics.gd")

## 短い文言 (カード・敵・契約者の名前、カードの効果の文) に使わない句読点
## (~/.claude/rules/coding-rules-general-user-facing-short-copy-punctuation.md)
const SHORT_COPY_PUNCTUATION: Array[String] = ["、", "。", "，", "．"]
## 戦略 bot の検証で遊ばせる地図のシード (値に意味は無く、検証のたびに同じ地図になるよう固定する)
const BOT_SEED: int = 7
## 護符の種類の数 (issue #43 の指定)
const RELIC_COUNT_RANGE: Array[int] = [6, 10]
## 焼けぬ封蝋の判定を引く回数と、減らない割合の許す範囲 (確率 1/2 の 1000 回で、外れる見込みが十分小さい幅)
const SPARE_ROLLS: int = 1000
const SPARE_RATE_RANGE: Array[float] = [0.4, 0.6]


## 護符の定義 (scripts/relics.gd): 6〜10 種で、bannzai が挙げた 2 つ (攻撃 +1・1/2 で減らない) を含み、名前・印・
## 効果の文がある
func _check_relic_definitions() -> void:
	_check(_in_range(Relics.RELICS.size(), RELIC_COUNT_RANGE), "護符が 6〜10 種")
	_check(
		Relics.RELICS.has("ember_edge") and Relics.RELICS.has("unburnt_seal"),
		"攻撃 +1 と 1/2 で減らない護符がある"
	)
	var glyphs: Dictionary = {}
	for relic_id: String in Relics.RELICS:
		var relic: Dictionary = Relics.RELICS[relic_id]
		_check(not relic["name"].is_empty() and _is_short_copy(relic["name"]), "護符の名前: %s" % relic_id)
		_check(not relic["text"].is_empty() and _is_short_copy(relic["text"]), "護符の効果の文: %s" % relic_id)
		_check(
			relic["glyph"].length() == 1 and not glyphs.has(relic["glyph"]),
			"護符の印は 1 字で重ならない: %s" % relic_id
		)
		glyphs[relic["glyph"]] = true
	var all_ids: Array[String] = []
	all_ids.assign(Relics.RELICS.keys())
	_check(Relics.pick_unowned(all_ids, 1).is_empty(), "すべて持っていれば手に入る護符は無い")
	var owned: Array[String] = ["ember_edge"]
	var picked: String = Relics.pick_unowned(owned, 3)
	_check(picked == Relics.pick_unowned(owned, 3), "同じシードなら同じ護符を選ぶ")
	_check(Relics.RELICS.has(picked) and picked != "ember_edge", "持っていない護符から選ぶ")


## 戦闘で効く護符: 熾火の刃 (攻撃のダメージ 1 回ごとに +1)、最後の祈り (残り 1 回のカードのダメージと防御 +3)、
## 蝋の盾 (戦闘の始めの防御)、夜明けの灯芯 (最初のターンだけエネルギー +1)。働いた護符が relic_triggers に残る
func _check_relic_battle_effects() -> void:
	var state: RunStateScript = RunStateScript.new()
	state.new_run(["slash", "twin_flame", "guard"])
	state.add_relic("ember_edge")
	var battle: BattleScript = BattleScript.new()
	battle.start(state, ["skeleton"], 1)
	var slash_deck: int = 0
	_check(battle.card_damage(slash_deck) == Cards.CARDS["slash"]["damage"] + 1, "熾火の刃で斬火のダメージ +1")
	_check(battle.card_block(2) == Cards.CARDS["guard"]["block"], "熾火の刃は防御を変えない")
	var hp_before: int = battle.enemies[0]["hp"]
	_check(battle.play(_hand_index_of(battle, state, "twin_flame"), 0), "双つ灯を使える")
	_check(
		battle.enemies[0]["hp"] == hp_before - (Cards.CARDS["twin_flame"]["damage"] + 1) * 2,
		"熾火の刃は複数回の攻撃の 1 回ごとに +1"
	)
	_check(battle.relic_triggers == ["ember_edge"], "攻撃のカードで熾火の刃が働く")
	_check(battle.play(_hand_index_of(battle, state, "guard")), "守りの風を使える")
	_check(battle.relic_triggers.is_empty(), "防御のカードでは熾火の刃は働かない")
	# 最後の祈り: 残り 1 回のカードだけ強くなり、使った後 (契約切れ) は元に戻る
	state.new_run(["slash", "guard"])
	state.add_relic("last_rite")
	while state.uses_left(0) > 1:
		state.use_card(0)
	battle.start(state, ["skeleton"], 1)
	_check(battle.card_damage(0) == Cards.CARDS["slash"]["damage"] + 3, "最後の 1 回の斬火はダメージ +3")
	_check(battle.card_block(1) == Cards.CARDS["guard"]["block"], "残りが 2 回以上なら最後の祈りは効かない")
	state.deck[1]["uses_left"] = 1
	_check(battle.card_block(1) == Cards.CARDS["guard"]["block"] + 3, "最後の 1 回の守りの風は防御 +3")
	_check(battle.play(_hand_index_of(battle, state, "slash"), 0), "最後の 1 回の斬火を使える")
	_check(battle.relic_triggers == ["last_rite"] and state.uses_left(0) == 0, "最後の祈りが働き、契約切れになる")
	# 蝋の盾と夜明けの灯芯: 戦闘の始めの防御と最初のターンのエネルギー。次のターンには残らない
	state.new_run(["guard"])
	state.add_relic("wax_ward")
	state.add_relic("dawn_wick")
	battle.start(state, ["skeleton"], 1)
	_check(
		battle.block == 6 and battle.energy == BattleScript.ENERGY_PER_TURN + 1,
		"戦闘の始めに防御 6・エネルギー +1"
	)
	_check(battle.relic_triggers == ["wax_ward", "dawn_wick"], "戦闘の始めに蝋の盾と夜明けの灯芯が働く")
	battle.enemies[0]["intent"] = {"move": Enemies.Move.GUARD, "value": 1}
	battle.end_turn()
	_check(battle.block == 0 and battle.energy == BattleScript.ENERGY_PER_TURN, "2 ターン目は防御 0・エネルギー 3")
	_check(battle.relic_triggers.is_empty(), "ターンを終えると働いた護符は空になる")
	state.free()


## 焼けぬ封蝋: 判定は地図のシードと通し番号だけで決まり、1000 回で 4〜6 割が減らない。精霊のカードを残り 2 回
## 以上で使った時だけ判定を引き (通し番号が進む)、英霊と最後の 1 回は必ず減る。持っていなければ判定を引かない
func _check_unburnt_seal() -> void:
	var spared: int = 0
	var differs: bool = false
	for roll_index: int in range(SPARE_ROLLS):
		var result: bool = Relics.roll_spare(BOT_SEED, roll_index)
		_check(result == Relics.roll_spare(BOT_SEED, roll_index), "同じシードと通し番号なら同じ判定 (%d)" % roll_index)
		spared += 1 if result else 0
		differs = differs or result != Relics.roll_spare(BOT_SEED + 1, roll_index)
	_check(
		_in_range(float(spared) / SPARE_ROLLS, SPARE_RATE_RANGE),
		"1000 回で 4〜6 割が減らない (%d 回)" % spared
	)
	_check(differs, "地図のシードが違えば判定の並びも違う")
	var state: RunStateScript = RunStateScript.new()
	state.new_run(["slash", "hero_strike"], BOT_SEED)
	_check(not state.spares_use(0) and state.relic_rolls == 0, "護符を持っていなければ判定を引かない")
	state.add_relic("unburnt_seal")
	_check(not state.spares_use(1) and state.relic_rolls == 0, "英霊には効かず判定を引かない")
	var expected: bool = Relics.roll_spare(BOT_SEED, 0)
	_check(state.spares_use(0) == expected and state.relic_rolls == 1, "精霊は判定を引き、結果はシードと通し番号のとおり")
	state.deck[0]["uses_left"] = 1
	_check(not state.spares_use(0) and state.relic_rolls == 1, "最後の 1 回には効かず判定を引かない")
	# 戦闘で使うと、判定が減らないと出た時だけ残りが減らず、焼けぬ封蝋が働いたと残る
	state.new_run(["slash"], BOT_SEED)
	state.add_relic("unburnt_seal")
	var battle: BattleScript = BattleScript.new()
	for turn: int in range(Cards.CARDS["slash"]["max_uses"]):
		battle.start(state, ["skeleton"], turn)
		var uses_before: int = state.uses_left(0)
		var will_spare: bool = uses_before >= 2 and Relics.roll_spare(BOT_SEED, state.relic_rolls)
		battle.play(0, 0)
		_check(
			state.uses_left(0) == uses_before - (0 if will_spare else 1),
			"減らないのは判定が出た時だけ (%d 回目)" % turn
		)
		_check(battle.relic_triggers.has("unburnt_seal") == will_spare, "減らなかった時だけ焼けぬ封蝋が働いたと残る")
	state.free()


## 護符の手に入る経路と、戦闘の外で効く護符: 強敵に勝つと持っていない護符を 1 つ得る (通常の戦闘では得ない)、
## 巡礼の数珠と旅の銭袋で勝った時の体力と所持金が増える、商人で護符を 1 訪問に 1 つ買え、繕いの帳面で回数を戻す
## 値段が下がる
func _check_relic_sources() -> void:
	_remove_user_file(SELFCHECK_SAVE_PATH)
	var state: RunStateScript = RunStateScript.new()
	state.save_path = SELFCHECK_SAVE_PATH
	state.new_run([], BOT_SEED)
	var battle_at: Vector2i = Vector2i(0, state.rows[0][0]["column"])
	state.path = ActMap.route_to(state.rows, battle_at.x, battle_at.y)
	state.phase = RunStateScript.Phase.BATTLE
	RunFlow.finish_battle(state, true)
	_check(state.relics.is_empty(), "通常の戦闘では護符を得ない")
	var elite: Vector2i = ActMap.find_kind(state.rows, ActMap.Kind.ELITE)
	state.path = ActMap.route_to(state.rows, elite.x, elite.y)
	state.phase = RunStateScript.Phase.BATTLE
	state.add_relic("pilgrim_beads")
	state.add_relic("coin_pouch")
	state.hp = 10
	var gold_before: int = state.gold
	var relic_seed: int = state.node_seed() + NodeRules.RELIC_SEED_OFFSET
	var expected: String = Relics.pick_unowned(state.relics, relic_seed)
	RunFlow.finish_battle(state, true)
	_check(state.relics.size() == 3 and state.relics.back() == expected, "強敵に勝つと持っていない護符を 1 つ得る")
	_check(NodeRules.elite_relic(state) == expected, "報酬の画面に見せる護符は強敵で得た護符")
	_check(state.hp == 10 + NodeRules.BATTLE_HEAL + 4, "巡礼の数珠で勝った時の体力の回復 +4")
	_check(
		state.gold == gold_before + NodeRules.reward_gold(state.node_seed(), ActMap.Kind.ELITE) + 8,
		"旅の銭袋で勝った時の所持金 +8"
	)
	state.visit = {}
	state.gold = NodeRules.RELIC_PRICE * 2
	var offered: String = NodeRules.shop_relic(state)
	_check(not state.relics.has(offered), "商人には持っていない護符が並ぶ")
	_check(NodeRules.buy_relic(state) and state.relics.has(offered), "商人で護符を買える")
	_check(state.gold == NodeRules.RELIC_PRICE, "護符の値段の分だけ所持金が減る")
	_check(
		NodeRules.shop_relic(state) == offered and not NodeRules.buy_relic(state),
		"買った後は同じ護符が売り切れで、2 つ目は買えない"
	)
	_check(NodeRules.restore_price(state) == NodeRules.RESTORE_PRICE, "繕いの帳面が無ければ回数を戻す値段は元のまま")
	state.add_relic("mended_ledger")
	_check(NodeRules.restore_price(state) == 20, "繕いの帳面で回数を戻す値段が 20")
	# 強敵で得た旅の銭袋・巡礼の数珠は、その勝利の所持金と体力から効く (報酬の画面の数と受け取った量が合う)
	for gained: String in ["coin_pouch", "pilgrim_beads"]:
		state.relics.assign(Relics.RELICS.keys().filter(func(id: String) -> bool: return id != gained))
		state.phase = RunStateScript.Phase.BATTLE
		state.hp = 10
		gold_before = state.gold
		RunFlow.finish_battle(state, true)
		_check(state.relics.back() == gained, "最後に残った護符を強敵で得る: %s" % gained)
		_check(
			(
				state.gold == gold_before + NodeRules.battle_gold(state, ActMap.Kind.ELITE)
				and state.hp == 10 + NodeRules.battle_heal(state)
			),
			"強敵で得た護符もその勝利の所持金と体力に効き、報酬の画面の数と合う: %s" % gained
		)
	_check(
		NodeRules.battle_gold(state, ActMap.Kind.ELITE)
		== NodeRules.reward_gold(state.node_seed(), ActMap.Kind.ELITE) + 8,
		"旅の銭袋の分が勝った時の所持金に入る"
	)
	state.free()
	_remove_user_file(SELFCHECK_SAVE_PATH)


## battle の手札の中で card_id のカードがある位置 (無ければ -1)
func _hand_index_of(battle: BattleScript, state: RunStateScript, card_id: String) -> int:
	for hand_index: int in range(battle.hand.size()):
		if state.deck[battle.hand[hand_index]]["id"] == card_id:
			return hand_index
	return -1


## value が bounds ([最小, 最大]) の範囲内か
func _in_range(value: Variant, bounds: Array) -> bool:
	return value >= bounds[0] and value <= bounds[1]


## 短い文言に句読点が無いか (SHORT_COPY_PUNCTUATION のどれも含まない)
func _is_short_copy(text: String) -> bool:
	for mark: String in SHORT_COPY_PUNCTUATION:
		if text.contains(mark):
			return false
	return true
