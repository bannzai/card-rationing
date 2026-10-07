extends "res://scripts/dev/headless_check.gd"
## selfcheck (scripts/dev/selfcheck.gd) のうち、巡礼の地図と局面の移り変わり・報酬・契約の祠・商人・出来事・契約の一覧・
## 設定の検証 (#7・#8)。selfcheck.gd がこのスクリプトを継承して _initialize() から呼ぶ (1 ファイルの行数の上限
## (gdlintrc の max-file-lines) に収めるため分けた)。

const ActMap := preload("res://scripts/act_map.gd")
const Cards := preload("res://scripts/cards.gd")
const Contractors := preload("res://scripts/contractors.gd")
const DeckListUiScript := preload("res://scripts/deck_list_ui.gd")
const Enemies := preload("res://scripts/enemies.gd")
const Events := preload("res://scripts/events.gd")
const NodeRules := preload("res://scripts/node_rules.gd")
const RunFlow := preload("res://scripts/run_flow.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const SettingsScript := preload("res://scripts/settings.gd")

## 保存と読み込みの検証に使う保存先 (本番の RunState.SAVE_PATH とは別)
const SELFCHECK_SAVE_PATH: String = "user://selfcheck_save.json"
## 設定の保存と読み込みの検証に使う保存先 (本番の Settings.SETTINGS_PATH とは別)
const SELFCHECK_SETTINGS_PATH: String = "user://selfcheck_settings.cfg"
## 地図の生成の制約を確かめるシードの数 (シード 1〜MAP_SEEDS。issue #7 が例に挙げた 100 個)
const MAP_SEEDS: int = 100


## 地図の生成: 同じシードなら同じ地図で、シード 1〜MAP_SEEDS のすべての地図が生成の制約
## (documents/DIRECTION.md「決めたこと」) を満たす
func _check_map_generation() -> void:
	var first_map: Array = ActMap.generate(3)
	var second_map: Array = ActMap.generate(3)
	_check(first_map == second_map, "同じシードなら同じ地図")
	var distinct: Dictionary = {}
	for seed_value: int in range(1, MAP_SEEDS + 1):
		var rows: Array = ActMap.generate(seed_value)
		distinct[str(rows)] = true
		_check_map_constraints(rows, "シード %d" % seed_value)
	_check(distinct.size() * 2 > MAP_SEEDS, "シードが違えば地図もおおむね違う")


## 1 枚の地図 rows が生成の制約を満たすか。label は失敗の文の頭に付ける
func _check_map_constraints(rows: Array, label: String) -> void:
	_check(rows.size() == ActMap.ROWS, "%s: 段の数が %d" % [label, ActMap.ROWS])
	_check(rows[0].size() >= 2, "%s: 出発の選択肢が 2 つ以上" % label)
	var top: Array = rows[ActMap.BOSS_ROW]
	_check(top.size() == 1 and top[0]["kind"] == ActMap.Kind.BOSS, "%s: 最上段はボス 1 つだけ" % label)
	var seen: Dictionary = {}
	for row: int in range(rows.size()):
		_check(
			not rows[row].is_empty() and rows[row].size() <= ActMap.COLUMNS,
			"%s: 段 %d の節点の数" % [label, row]
		)
		for node: Dictionary in rows[row]:
			seen[node["kind"]] = true
			_check_node_kind(rows, row, node, label)
			_check_node_edges(rows, row, node, label)
		if row < ActMap.BOSS_ROW - 1:
			_check(not _has_crossing_edges(rows[row]), "%s: 段 %d の辺が交差しない" % [label, row])
	for kind: int in ActMap.REQUIRED_KINDS:
		_check(seen.has(kind), "%s: 種類 %s が出る" % [label, ActMap.KIND_NAMES[kind]])
	_check(
		_min_shrines_on_any_path(rows) >= ActMap.SHRINE_ROWS.size(),
		"%s: どの道を通っても契約の祠に %d 回以上立ち寄る" % [label, ActMap.SHRINE_ROWS.size()]
	)


## row 段の節点 node の種類が段の決まりに合うか (段 0 は戦闘、祠の段は祠、最上段だけボス、強敵・商人・
## 乱数の祠は出てよい段だけ、強敵・商人・祠は親子で続かない)
func _check_node_kind(rows: Array, row: int, node: Dictionary, label: String) -> void:
	var kind: int = node["kind"]
	var at: String = "%s: 段 %d 列 %d (%s)" % [label, row, node["column"], ActMap.KIND_NAMES[kind]]
	if row == 0:
		_check(kind == ActMap.Kind.BATTLE, "%s: 段 0 は戦闘" % at)
	if ActMap.SHRINE_ROWS.has(row):
		_check(kind == ActMap.Kind.SHRINE, "%s: 祠の段は祠" % at)
	_check((kind == ActMap.Kind.BOSS) == (row == ActMap.BOSS_ROW), "%s: ボスは最上段だけ" % at)
	if kind == ActMap.Kind.ELITE:
		_check(row >= ActMap.ELITE_MIN_ROW, "%s: 強敵は段 %d から" % [at, ActMap.ELITE_MIN_ROW])
	if kind == ActMap.Kind.SHOP:
		_check(row >= ActMap.SHOP_MIN_ROW, "%s: 商人は段 %d から" % [at, ActMap.SHOP_MIN_ROW])
	if kind == ActMap.Kind.SHRINE and not ActMap.SHRINE_ROWS.has(row):
		_check(ActMap.RANDOM_SHRINE_ROWS.has(row), "%s: 乱数の祠は決めた段だけ" % at)
	if ActMap.NO_REPEAT_KINDS.has(kind):
		for parent_column: int in ActMap.parents(rows, row, node["column"]):
			var parent_kind: int = ActMap.node_at(rows, row - 1, parent_column)["kind"]
			_check(parent_kind != kind, "%s: 親子で同じ種類が続かない" % at)


## row 段の節点 node の辺: ボス以外は次の段の存在する節点へ 1 本以上 (ボスの段の手前までは隣の列まで)、
## 段 0 以外は親が 1 つ以上
func _check_node_edges(rows: Array, row: int, node: Dictionary, label: String) -> void:
	var column: int = node["column"]
	var at: String = "%s: 段 %d 列 %d" % [label, row, column]
	if row > 0:
		_check(not ActMap.parents(rows, row, column).is_empty(), "%s: 下の段から入れる" % at)
	if row == ActMap.BOSS_ROW:
		_check(node["next"].is_empty(), "%s: ボスの先は無い" % at)
		return
	_check(not node["next"].is_empty(), "%s: 上の段へ進める" % at)
	for next_column: int in node["next"]:
		_check(not ActMap.node_at(rows, row + 1, next_column).is_empty(), "%s: 辺の先がある" % at)
		if row + 1 < ActMap.BOSS_ROW:
			_check(absi(next_column - column) <= 1, "%s: 辺は隣の列まで" % at)


## nodes (1 つの段の節点) から出る辺のうち、交差する組があるか
func _has_crossing_edges(nodes: Array) -> bool:
	var edges: Array[Vector2i] = []
	for node: Dictionary in nodes:
		for next_column: int in node["next"]:
			edges.append(Vector2i(node["column"], next_column))
	for a: Vector2i in edges:
		for b: Vector2i in edges:
			if (a.x < b.x and a.y > b.y) or (a.x > b.x and a.y < b.y):
				return true
	return false


## 段 0 からボスまでのどの道でも通る契約の祠の数の最小 (上の段から順に、各節点から先の最小を求める)
func _min_shrines_on_any_path(rows: Array) -> int:
	var best: Dictionary = {}
	for row: int in range(rows.size() - 1, -1, -1):
		for node: Dictionary in rows[row]:
			var ahead: int = 0
			if not node["next"].is_empty():
				ahead = ActMap.ROWS
				for next_column: int in node["next"]:
					ahead = mini(ahead, best[Vector2i(row + 1, next_column)])
			var here: int = 1 if node["kind"] == ActMap.Kind.SHRINE else 0
			best[Vector2i(row, node["column"])] = here + ahead
	var fewest: int = ActMap.ROWS
	for node: Dictionary in rows[0]:
		fewest = mini(fewest, best[Vector2i(0, node["column"])])
	return fewest


## ランの局面の移り変わり: 巡礼の開始・節点に入る (選べない節点には入れない)・戦闘の終わり (報酬・敗北・
## 踏破)・節点を出る。局面が変わるたびに保存し、ランの終わりで保存データを消す。戦闘の敵は節点の種類と段で選ぶ
func _check_run_flow() -> void:
	_remove_user_file(SELFCHECK_SAVE_PATH)
	var state: RunStateScript = RunStateScript.new()
	state.save_path = SELFCHECK_SAVE_PATH
	RunFlow.start_run(state, Contractors.FIRST_CONTRACTOR, 11)
	_check(state.phase == RunStateScript.Phase.MAP and state.path.is_empty(), "巡礼の開始は出発前の地図")
	_check(state.map_seed == 11 and state.rows == ActMap.generate(11), "巡礼の開始で地図をシードから作る")
	_check(
		state.deck.size() == Contractors.starter_deck(Contractors.FIRST_CONTRACTOR).size(),
		"巡礼の開始は契約者の初期デッキ"
	)
	_check(FileAccess.file_exists(SELFCHECK_SAVE_PATH), "巡礼の開始で保存する")
	_check(not RunFlow.leave_node(state), "地図の局面では節点を出られない")
	_check(not RunFlow.finish_battle(state, true), "地図の局面では戦闘を終えられない")
	var choices: Array[int] = ActMap.next_columns(state.rows, state.path)
	for column: int in range(ActMap.COLUMNS):
		if not choices.has(column):
			_check(not RunFlow.enter_node(state, column), "選べない列 %d の節点には入れない" % column)
	_check(RunFlow.enter_node(state, choices[0]), "段 0 の節点に入れる")
	_check(state.phase == RunStateScript.Phase.BATTLE and state.path.size() == 1, "段 0 の節点は戦闘")
	_check(not RunFlow.enter_node(state, choices[0]), "戦闘の局面では次の節点に入れない")
	var saved: RunStateScript = RunStateScript.new()
	_check(
		saved.load_from(SELFCHECK_SAVE_PATH) == RunStateScript.LoadResult.LOADED
		and saved.phase == RunStateScript.Phase.BATTLE,
		"節点に入ると保存する"
	)
	saved.free()
	_check(
		Enemies.encounter_candidates(Enemies.Rank.NORMAL, false).has(RunFlow.encounter(state)),
		"段 0 の戦闘は前半の通常の敵"
	)
	state.take_damage(20)
	var gold_before: int = state.gold
	_check(RunFlow.finish_battle(state, true), "戦闘を終えられる")
	_check(state.phase == RunStateScript.Phase.REWARD, "勝つと報酬の局面")
	_check(
		state.gold == gold_before + NodeRules.reward_gold(state.node_seed(), ActMap.Kind.BATTLE),
		"勝つと所持金を受け取る"
	)
	_check(state.hp == RunStateScript.START_HP - 20 + NodeRules.BATTLE_HEAL, "勝つと体力が回復する")
	_check(state.battles_won == 1, "勝った戦闘の数が増える")
	_check(RunFlow.leave_node(state) and state.phase == RunStateScript.Phase.MAP, "報酬の後は地図へ戻る")
	_check(not RunFlow.leave_node(state), "地図へ戻った後は節点を出られない")
	state.free()
	_check_flow_by_kind()


## 強敵・後半の戦闘・ボスの敵の選び方、強敵の報酬と体力の回復の上限、ボスに勝つと踏破、負けると敗北
## (ランの終わりは保存データを消す)
func _check_flow_by_kind() -> void:
	var elite: RunStateScript = _state_at(ActMap.Kind.ELITE, 11)
	_check(
		Enemies.encounter_candidates(Enemies.Rank.ELITE, false).has(RunFlow.encounter(elite)), "強敵の節点は強敵"
	)
	RunFlow.finish_battle(elite, true)
	var span: Array = NodeRules.REWARD_GOLD[ActMap.Kind.ELITE]
	_check(elite.gold >= span[0] and elite.gold <= span[1], "強敵の報酬の所持金は強敵の範囲")
	_check(elite.hp == elite.max_hp, "体力の回復は最大を超えない")
	elite.free()
	var late: RunStateScript = _state_at(ActMap.Kind.BATTLE, 11)
	for row: int in range(ActMap.LATE_ROW, ActMap.BOSS_ROW):
		for node: Dictionary in late.rows[row]:
			if node["kind"] == ActMap.Kind.BATTLE and late.path.size() < ActMap.LATE_ROW:
				late.path = ActMap.route_to(late.rows, row, node["column"])
	_check(late.path.size() > ActMap.LATE_ROW, "後半の戦闘の節点がある")
	_check(
		Enemies.encounter_candidates(Enemies.Rank.NORMAL, true).has(RunFlow.encounter(late)),
		"後半の戦闘は後半の通常の敵"
	)
	_check(RunFlow.finish_battle(late, false), "負けて戦闘を終えられる")
	_check(late.phase == RunStateScript.Phase.DEFEAT, "負けると敗北")
	_check(not FileAccess.file_exists(SELFCHECK_SAVE_PATH), "敗北で保存データを消す")
	late.free()
	var boss: RunStateScript = _state_at(ActMap.Kind.BOSS, 11)
	_check(
		Enemies.encounter_candidates(Enemies.Rank.BOSS, false).has(RunFlow.encounter(boss)),
		"ボスの節点はボス"
	)
	boss.autosave()
	RunFlow.finish_battle(boss, true)
	_check(boss.phase == RunStateScript.Phase.CLEAR, "ボスに勝つと踏破")
	_check(not FileAccess.file_exists(SELFCHECK_SAVE_PATH), "踏破で保存データを消す")
	boss.free()


## 戦闘の報酬: 所持金は種類の範囲で、カードは互いに違う 3 枚 (同じシードなら同じ)。並んだカードの 1 枚だけを
## 最大の回数で受け取れる
func _check_battle_rewards() -> void:
	for kind: int in NodeRules.REWARD_GOLD:
		var span: Array = NodeRules.REWARD_GOLD[kind]
		for seed_value: int in range(20):
			var gold: int = NodeRules.reward_gold(seed_value, kind)
			_check(gold >= span[0] and gold <= span[1], "報酬の所持金が範囲内: 種類 %d" % kind)
	var offers: Array[String] = NodeRules.card_offers(5)
	_check(offers == NodeRules.card_offers(5), "同じシードなら同じカードが並ぶ")
	_check(offers.size() == NodeRules.OFFER_COUNT, "カードが %d 枚並ぶ" % NodeRules.OFFER_COUNT)
	var unique: Dictionary = {}
	for card_id: String in offers:
		unique[card_id] = true
		_check(Cards.CARDS.has(card_id), "並んだカードが定義済み: %s" % card_id)
	_check(unique.size() == offers.size(), "並んだカードは互いに違う")
	for card_id: String in NodeRules.card_offers(5, Cards.Bond.HERO):
		_check(Cards.CARDS[card_id]["bond"] == Cards.Bond.HERO, "英霊だけを並べられる")
	var state: RunStateScript = _state_at(ActMap.Kind.BATTLE, 11)
	state.phase = RunStateScript.Phase.REWARD
	var reward_offers: Array[String] = NodeRules.card_offers(state.node_seed())
	var outsider: String = _card_not_in(reward_offers)
	if not outsider.is_empty():
		_check(not NodeRules.take_reward_card(state, outsider), "並んでいないカードは受け取れない")
	var size_before: int = state.deck.size()
	_check(NodeRules.take_reward_card(state, reward_offers[0]), "並んだカードを受け取れる")
	_check(state.deck.size() == size_before + 1, "受け取るとデッキが 1 枚増える")
	_check(
		state.uses_left(size_before) == Cards.CARDS[reward_offers[0]]["max_uses"],
		"新しい契約は最大の回数で入る"
	)
	_check(not NodeRules.take_reward_card(state, reward_offers[1]), "報酬のカードは 1 枚だけ")
	state.free()


## 契約の祠: 代価なしで 1 つだけ。更新は減ったカードの残り使用回数を最大まで戻し、破棄は 1 枚を外し
## (最後の 1 枚は外せない)、新しい契約は並んだ 3 枚の 1 枚を最大の回数で足す
func _check_shrine() -> void:
	var state: RunStateScript = _state_at(ActMap.Kind.SHRINE, 11)
	var gold_before: int = state.gold
	_check(not NodeRules.shrine_renew(state, 0), "減っていないカードは更新しない")
	state.use_card(0)
	state.use_card(0)
	_check(NodeRules.shrine_renew(state, 0), "減ったカードの契約を更新できる")
	_check(state.uses_left(0) == state.card(0)["max_uses"], "更新で残り使用回数が最大に戻る")
	_check(state.gold == gold_before, "祠は代価なし")
	state.use_card(1)
	_check(not NodeRules.shrine_renew(state, 1), "祠で選べるのは 1 つだけ")
	state.free()
	state = _state_at(ActMap.Kind.SHRINE, 11)
	var size_before: int = state.deck.size()
	_check(NodeRules.shrine_break(state, 0) and state.deck.size() == size_before - 1, "破棄で 1 枚外れる")
	state.free()
	state = _state_at(ActMap.Kind.SHRINE, 11)
	var offers: Array[String] = NodeRules.card_offers(state.node_seed())
	var outsider: String = _card_not_in(offers)
	if not outsider.is_empty():
		_check(not NodeRules.shrine_contract(state, outsider), "並んでいないカードとは契約できない")
	_check(NodeRules.shrine_contract(state, offers[2]), "並んだカードと新しく契約できる")
	var last: int = state.deck.size() - 1
	_check(
		state.deck[last]["id"] == offers[2] and state.uses_left(last) == state.card(last)["max_uses"],
		"新しい契約はデッキの末尾に最大の回数で入る"
	)
	state.free()
	state = _state_at(ActMap.Kind.SHRINE, 11)
	var single: Array[Dictionary] = [{"id": "slash", "uses_left": 1}]
	state.deck = single
	_check(not NodeRules.shrine_break(state, 0), "最後の 1 枚は破棄できない")
	state.free()


## 商人: 所持金が足りる時だけ、並んだカードを 1 枚ずつ買える。残り使用回数を戻す・外すは 1 回の訪問で 1 回ずつ
func _check_shop() -> void:
	var state: RunStateScript = _state_at(ActMap.Kind.SHOP, 11)
	var offers: Array[String] = NodeRules.card_offers(state.node_seed())
	_check(not NodeRules.buy_card(state, offers[0]), "所持金が足りなければ買えない")
	state.gold = 300
	var size_before: int = state.deck.size()
	_check(NodeRules.buy_card(state, offers[0]), "所持金が足りれば買える")
	_check(state.gold == 300 - NodeRules.card_price(offers[0]), "値段の分だけ所持金が減る")
	_check(state.deck.size() == size_before + 1 and state.deck.back()["id"] == offers[0], "買ったカードが入る")
	_check(not NodeRules.buy_card(state, offers[0]), "同じカードは 2 回買えない")
	var outsider: String = _card_not_in(offers)
	if not outsider.is_empty():
		_check(not NodeRules.buy_card(state, outsider), "並んでいないカードは買えない")
	var gold_before: int = state.gold
	_check(not NodeRules.buy_restore(state, 0), "減っていないカードの回数は戻さない")
	state.use_card(0)
	_check(NodeRules.buy_restore(state, 0), "減ったカードの回数を戻せる")
	_check(state.uses_left(0) == state.card(0)["max_uses"], "戻すと最大になる")
	_check(state.gold == gold_before - NodeRules.RESTORE_PRICE, "戻す値段の分だけ所持金が減る")
	state.use_card(1)
	_check(not NodeRules.buy_restore(state, 1), "回数を戻すのは 1 回の訪問で 1 回")
	size_before = state.deck.size()
	gold_before = state.gold
	_check(NodeRules.buy_removal(state, 0), "1 枚を外せる")
	_check(state.deck.size() == size_before - 1, "外すとデッキが 1 枚減る")
	_check(state.gold == gold_before - NodeRules.REMOVE_PRICE, "外す値段の分だけ所持金が減る")
	_check(not NodeRules.buy_removal(state, 0), "外すのは 1 回の訪問で 1 回")
	state.free()


## 出来事: 定義がそろい (デッキの入れ替えと、代償と引き換えの回復を含む)、同じシードなら同じ出来事。
## 各選択肢の結果がランに反映され、1 つの出来事で選べるのは 1 回だけ
func _check_events() -> void:
	var effects: Dictionary = {}
	for event_id: String in Events.EVENTS:
		var event: Dictionary = Events.EVENTS[event_id]
		_check(not event["title"].is_empty() and not event["text"].is_empty(), "出来事の文: %s" % event_id)
		_check(not event["options"].is_empty(), "出来事の選択肢: %s" % event_id)
		for option: Dictionary in event["options"]:
			effects[option["effect"]] = true
			_check(not option["label"].is_empty(), "選択肢の文: %s" % event_id)
	_check(Events.EVENTS.size() >= 2 and Events.EVENTS.size() <= 3, "出来事は 2〜3 種")
	_check(effects.has(Events.Effect.SWAP), "デッキの入れ替えの出来事がある")
	_check(effects.has(Events.Effect.BLOOD_RESTORE), "代償と引き換えの回復の出来事がある")
	var first_event: String = Events.event_for(9)
	var second_event: String = Events.event_for(9)
	_check(first_event == second_event, "同じシードなら同じ出来事")
	var two: Array[int] = [0, 1]
	var one: Array[int] = [0]
	var same: Array[int] = [0, 0]
	var none: Array[int] = []
	var state: RunStateScript = _state_at_event("nameless_grave")
	var size_before: int = state.deck.size()
	_check(not Events.choose(state, 0, one), "入れ替えは 2 枚を選ぶ")
	_check(not Events.choose(state, 0, same), "同じカードを 2 回は選べない")
	_check(Events.choose(state, 0, two), "2 枚を手放して英霊と契約できる")
	_check(state.deck.size() == size_before - 1, "2 枚減って 1 枚増える")
	_check(state.card(state.deck.size() - 1)["bond"] == Cards.Bond.HERO, "入れ替えで得るのは英霊")
	_check(not Events.choose(state, 1, none), "出来事で選べるのは 1 回だけ")
	state.free()
	# 2 枚のデッキでも、2 枚を手放して英霊 1 枚と契約できる (入れ替えの後に 1 枚残る)
	state = _state_at_event("nameless_grave")
	var pair: Array[Dictionary] = [{"id": "slash", "uses_left": 4}, {"id": "guard", "uses_left": 4}]
	state.deck = pair
	_check(Events.choose(state, 0, two), "2 枚のデッキでも入れ替えられる")
	_check(state.deck.size() == 1 and state.card(0)["bond"] == Cards.Bond.HERO, "入れ替えの後は英霊 1 枚")
	state.free()
	state = _state_at_event("blood_spring")
	_check(not Events.choose(state, 0, one), "減っていないカードの回数は戻さない")
	state.use_card(0)
	_check(Events.choose(state, 0, one), "体力を払って回数を戻せる")
	_check(state.hp == RunStateScript.START_HP - Events.BLOOD_PRICE, "体力を払う")
	_check(state.uses_left(0) == state.card(0)["max_uses"], "回数が最大に戻る")
	state.free()
	state = _state_at_event("blood_spring")
	state.use_card(0)
	state.hp = Events.BLOOD_PRICE
	_check(not Events.choose(state, 0, one), "体力が払う量以下なら選べない")
	_check(
		Events.choose(state, 1, none) and state.uses_left(0) == state.card(0)["max_uses"] - 1,
		"立ち去っても何も変わらない"
	)
	state.free()
	state = _state_at_event("lost_spirit")
	size_before = state.deck.size()
	_check(Events.choose(state, 0, none), "精霊と契約できる")
	_check(state.deck.size() == size_before + 1, "精霊が 1 枚増える")
	_check(state.card(size_before)["bond"] == Cards.Bond.SPIRIT, "得るのは精霊")
	state.free()
	state = _state_at_event("lost_spirit")
	_check(Events.choose(state, 1, none) and state.gold == Events.SPIRIT_GOLD, "精霊を送ると所持金を得る")
	state.free()


## 契約の一覧の並べ方: 強さ順はカードの強さの強い順 (同じ強さはデッキの順。雷槍の英霊と盾の英霊は 6、斬火は 3、
## 守りの風は 2.5)、残り回数順は残りの少ない順で同じ残りの中は強さ順
func _check_deck_sort() -> void:
	var deck: Array[Dictionary] = [
		{"id": "slash", "uses_left": 1},
		{"id": "hero_strike", "uses_left": 1},
		{"id": "guard", "uses_left": 4},
		{"id": "hero_wall", "uses_left": 0},
	]
	var strength: Array[int] = DeckListUiScript.sorted_indices(deck, DeckListUiScript.Order.STRENGTH)
	_check(strength == [1, 3, 0, 2], "強さ順: %s" % [strength])
	var uses: Array[int] = DeckListUiScript.sorted_indices(deck, DeckListUiScript.Order.USES_LEFT)
	_check(uses == [3, 1, 0, 2], "残り回数順: %s" % [uses])


## 設定: 無い保存先は既定値、保存と読み込みの往復で同じ値、範囲の外は収め、数でない値は既定値
func _check_settings() -> void:
	_remove_user_file(SELFCHECK_SETTINGS_PATH)
	var settings: SettingsScript = SettingsScript.new()
	settings.settings_path = SELFCHECK_SETTINGS_PATH
	settings.bgm_volume = 10
	settings.load_settings()
	_check(settings.bgm_volume == SettingsScript.DEFAULT_VOLUME, "保存が無ければ既定の音量")
	settings.bgm_volume = 35
	settings.se_volume = 60
	_check(settings.save_settings() == OK, "設定を保存できる")
	var other: SettingsScript = SettingsScript.new()
	other.settings_path = SELFCHECK_SETTINGS_PATH
	other.load_settings()
	_check(other.bgm_volume == 35 and other.se_volume == 60, "往復で音量が保たれる")
	var config: ConfigFile = ConfigFile.new()
	config.set_value(SettingsScript.SECTION, SettingsScript.BGM_KEY, 150)
	config.set_value(SettingsScript.SECTION, SettingsScript.SE_KEY, "x")
	config.save(SELFCHECK_SETTINGS_PATH)
	other.load_settings()
	_check(other.bgm_volume == SettingsScript.MAX_VOLUME, "範囲の外の音量は収める")
	_check(other.se_volume == SettingsScript.DEFAULT_VOLUME, "数でない音量は既定値")
	settings.free()
	other.free()
	_remove_user_file(SELFCHECK_SETTINGS_PATH)


## シード seed_value の地図で、kind の最初の節点に入った局面のラン (保存先は検証用)
func _state_at(kind: int, seed_value: int) -> RunStateScript:
	var state: RunStateScript = RunStateScript.new()
	state.save_path = SELFCHECK_SAVE_PATH
	state.new_run([], seed_value)
	var at: Vector2i = ActMap.find_kind(state.rows, kind)
	state.path = ActMap.route_to(state.rows, at.x, at.y)
	state.phase = RunFlow.KIND_PHASES[kind]
	return state


## event_id の出来事が出る節点に入った局面のラン (地図のシードを 1 から順に試す。見つからなければ失敗にして
## 最初の地図の出来事の節点のランを返す)
func _state_at_event(event_id: String) -> RunStateScript:
	for seed_value: int in range(1, 301):
		var state: RunStateScript = _state_at(ActMap.Kind.EVENT, seed_value)
		if Events.event_for(state.node_seed()) == event_id:
			return state
		state.free()
	_check(false, "出来事 %s が出る地図が見つかる" % event_id)
	return _state_at(ActMap.Kind.EVENT, 1)


## offers に無いカード ID (全カードが並んでいれば空文字)
func _card_not_in(offers: Array[String]) -> String:
	for card_id: String in Cards.CARDS:
		if not offers.has(card_id):
			return card_id
	return ""


## user:// のファイルを消す (無ければ何もしない)
func _remove_user_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.open(path.get_base_dir()).remove(path.get_file())
