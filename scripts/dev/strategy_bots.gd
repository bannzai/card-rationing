extends RefCounted
## 自動テストプレイ (make simulate / make playtest) の戦略 bot。戦闘でどのカードを使うかだけが戦略ごとに違い、
## 戦闘の外の選択 (地図の道・報酬・契約の祠・商人・出来事) は 3 つの戦略で同じ。方針としきい値の根拠は
## documents/DIRECTION.md「決めたこと」。判断の関数は状態 (RunState と戦闘) を読んで選んだものを返すだけで、
## 適用は呼ぶ側が行う (play_run() はゲームのロジックを直接呼び、scripts/dev/playtest.gd は画面を通す)。
## 乱数は使わず、同じ状態なら同じものを返す (同点は手札・デッキ・候補の並びの先のものを選ぶ)。

## 戦略。HOARD = 温存し続ける、SPEND = 出し惜しみしない、ADAPT = 状況で使い分ける
enum Strategy { HOARD, SPEND, ADAPT }
## 戦闘の 1 手。PLAY = 手札のカードを使う、STRUGGLE = もがく、END_TURN = ターンを終える
enum BattleMove { PLAY, STRUGGLE, END_TURN }

const ActMap := preload("res://scripts/act_map.gd")
const Battle := preload("res://scripts/battle.gd")
const Cards := preload("res://scripts/cards.gd")
const Contractors := preload("res://scripts/contractors.gd")
const Enemies := preload("res://scripts/enemies.gd")
const Events := preload("res://scripts/events.gd")
const NodeRules := preload("res://scripts/node_rules.gd")
const RunFlow := preload("res://scripts/run_flow.gd")
const RunStateScript := preload("res://scripts/run_state.gd")

## 集計の JSON のキーにする戦略の名前と、ログ・画面に出す名前
const STRATEGY_KEYS: Dictionary = {
	Strategy.HOARD: "hoard", Strategy.SPEND: "spend", Strategy.ADAPT: "adapt"
}
const STRATEGY_NAMES: Dictionary = {
	Strategy.HOARD: "温存し続ける",
	Strategy.SPEND: "出し惜しみしない",
	Strategy.ADAPT: "状況で使い分ける",
}
## 「回数の少ないカード」とみなす残り使用回数の上限 (issue #10 が例に挙げた値)
const LOW_USES: int = 2
## 体力が危険とみなす、最大体力に対する割合 (HOARD と ADAPT が回数の少ないカードを使い始める)。後半の敵の
## 1 ターンの攻撃 (9〜12) をあと 1〜2 回で倒れる体力
const DANGER_HP_RATE: float = 0.3
## ADAPT が戦闘を重いとみなす、最大体力に対する割合。血の泉で体力を払うのも、払った後にこの割合を超える時だけ
const HEAVY_HP_RATE: float = 0.5
## ADAPT が契約の祠を近いとみなす段数 (この段数以内に祠があれば、使った回数を祠で取り戻せるとみなす)
const SHRINE_NEAR_STEPS: int = 2
## 防ぐダメージ 1 を、与えるダメージ 1 の何倍に数えるか (体力は戦闘をまたいで持ち越し、敵の体力は持ち越さないため
## 重くする。1.5 なら、守りの風 (防御 5) が斬火 (攻撃 6) より先に出るのは受けるダメージが 5 以上の時)
const GUARD_WEIGHT: float = 1.5
## 新しく契約するカードを選ぶ時に保つ、デッキの攻撃の残り使用回数 ÷ 防御の残り使用回数 (1 ターンのエネルギー 3 を
## 攻撃 2・防御 1 に使う配分)。これを下回る間は攻撃を、そうでなければ防御を先に取る
const ATTACK_USES_PER_GUARD_USE: int = 2
## 地図で次の節点を選ぶ時の種類の優先順 (先のものほど優先)。戦闘は回数と体力を使うので、使わずに得るものがある
## 祠・出来事・商人を先にし、強敵は最後にする
const KIND_PRIORITY: Array[int] = [
	ActMap.Kind.SHRINE,
	ActMap.Kind.EVENT,
	ActMap.Kind.SHOP,
	ActMap.Kind.BATTLE,
	ActMap.Kind.ELITE,
	ActMap.Kind.BOSS,
]
## 「強いカード」とみなす強さ (Cards.strength()) の下限。基準の斬火 (3) の 2 倍で、英霊 10 種と灯の精が当たる
const STRONG_STRENGTH: float = 6.0
## 1 回の戦闘のターンの上限 (判断の不具合で戦闘が終わらない時に止める)。ボス (体力 150) をもがくだけ
## (1 ターン 6 ダメージ) で倒す 25 ターンの 4 倍
const TURN_LIMIT: int = 100


## 戦闘で次に取る 1 手。{"move": BattleMove, "hand_index": 使う手札の index, "target": 狙う敵の index}
## (使わない項目は -1)。使ってよいカードのうち、その場の効果が最も大きいもの (同じなら安いもの) を使い、
## 効果のあるカードが無ければ、エネルギーが残る間はもがき、尽きたらターンを終える
static func battle_move(strategy: int, battle: Battle, state: RunStateScript) -> Dictionary:
	var spends_low: bool = _spends_low_uses(strategy, battle, state)
	var best: Dictionary = {}
	for hand_index: int in range(battle.hand.size()):
		var deck_index: int = battle.hand[hand_index]
		if not battle.can_play(hand_index):
			continue
		if state.uses_left(deck_index) <= LOW_USES and not spends_low:
			continue
		var play: Dictionary = _play_value(battle, state, deck_index)
		play["hand_index"] = hand_index
		play["cost"] = state.card(deck_index)["cost"]
		if _is_better_play(play, best):
			best = play
	if not best.is_empty():
		return {
			"move": BattleMove.PLAY, "hand_index": best["hand_index"], "target": best["target"]
		}
	if battle.energy >= Battle.STRUGGLE_COST:
		return {"move": BattleMove.STRUGGLE, "hand_index": -1, "target": _weakest_enemy(battle)}
	return {"move": BattleMove.END_TURN, "hand_index": -1, "target": -1}


## 地図で次に進む列。KIND_PRIORITY の先の種類を選び、同じ種類なら列の小さい方。商人は、最も安い品
## (回数を戻す) を買える所持金が無ければ、戦闘の次に下げる
static func choose_column(state: RunStateScript) -> int:
	var best_column: int = -1
	var best_rank: float = INF
	for column: int in ActMap.next_columns(state.rows, state.path):
		var kind: int = ActMap.node_at(state.rows, state.path.size(), column)["kind"]
		var rank: float = KIND_PRIORITY.find(kind)
		if kind == ActMap.Kind.SHOP and state.gold < NodeRules.RESTORE_PRICE:
			rank = KIND_PRIORITY.find(ActMap.Kind.BATTLE) + 0.5
		if rank < best_rank:
			best_rank = rank
			best_column = column
	return best_column


## 戦闘の報酬で契約するカード (並んだ 3 枚から必ず 1 枚取る)
static func choose_reward(state: RunStateScript) -> String:
	return _choose_offer(state, NodeRules.card_offers(state.node_seed()))


## 契約の祠で選ぶもの。{"renew_index": 契約を更新するデッキの index (-1 なら新しい契約を結ぶ),
## "card_id": 新しく契約するカード}。更新で取り戻す強さの合計と、新しい契約で得る強さの合計を比べて、
## 大きい方 (同じなら更新) を選ぶ。破棄は選ばない (回数の合計が減るため)
static func choose_shrine(state: RunStateScript) -> Dictionary:
	var card_id: String = _choose_offer(state, NodeRules.card_offers(state.node_seed()))
	var renew_index: int = _best_restore(state)
	if renew_index >= 0 and _restore_gain(state, renew_index) >= _contract_gain(card_id):
		return {"renew_index": renew_index, "card_id": ""}
	return {"renew_index": -1, "card_id": card_id}


## 商人で次に買うもの。{"card_id": 買うカード (空文字なら買わない), "restore_index": 残り使用回数を戻す
## デッキの index (-1 なら戻さない)}。買えるもののうち、所持金 1 あたりに得る強さの合計が最も大きいものを選び、
## 買えるものが無ければどちらも無しを返す (立ち去る)。外すは選ばない (回数の合計が減るため)
static func next_purchase(state: RunStateScript) -> Dictionary:
	var best: Dictionary = {"card_id": "", "restore_index": -1}
	var best_rate: float = 0.0
	var sold: Array = state.visit.get("sold", [])
	for card_id: String in NodeRules.card_offers(state.node_seed()):
		var price: int = NodeRules.card_price(card_id)
		if sold.has(card_id) or state.gold < price:
			continue
		var card_rate: float = _contract_gain(card_id) / price
		if card_rate > best_rate:
			best_rate = card_rate
			best = {"card_id": card_id, "restore_index": -1}
	var restore_index: int = _best_restore(state)
	if (
		restore_index >= 0
		and not state.visit.has("restored")
		and state.gold >= NodeRules.RESTORE_PRICE
		and _restore_gain(state, restore_index) / NodeRules.RESTORE_PRICE > best_rate
	):
		best = {"card_id": "", "restore_index": restore_index}
	return best


## 出来事で選ぶ選択肢。{"option": 選択肢の index, "picks": 選ぶデッキの index の並び (Array[int])}。
## 選択肢を上から順に見て、望ましく、選べる最初のものを選ぶ (どの出来事も、カードを選ばない選択肢が最後にある)
static func choose_event(state: RunStateScript) -> Dictionary:
	var seed_value: int = state.node_seed()
	var options: Array = Events.EVENTS[Events.event_for(seed_value)]["options"]
	for option_index: int in range(options.size()):
		var effect: int = options[option_index]["effect"]
		var picks: Array[int] = _event_picks(state, effect)
		if not _wants_event_option(state, effect, picks):
			continue
		if Events.can_choose(state, option_index, picks):
			return {"option": option_index, "picks": picks}
	var no_picks: Array[int] = []
	return {"option": -1, "picks": no_picks}


## 今いる節点から、辺をたどって着ける最も近い契約の祠までの段数 (先に祠が無ければ地図の段の数)
static func shrine_distance(state: RunStateScript) -> int:
	var columns: Array[int] = []
	if not state.path.is_empty():
		columns.append(state.path.back())
	for steps: int in range(1, ActMap.ROWS):
		var row: int = state.path.size() - 1 + steps
		var next_columns: Array[int] = []
		for column: int in columns:
			for next_column: int in ActMap.node_at(state.rows, row - 1, column).get("next", []):
				if not next_columns.has(next_column):
					next_columns.append(next_column)
		for column: int in next_columns:
			if ActMap.node_at(state.rows, row, column)["kind"] == ActMap.Kind.SHRINE:
				return steps
		columns = next_columns
	return ActMap.ROWS


## strategy の戦略で、battle の戦闘を勝敗が決まるまで進める (ゲームのロジックを直接呼ぶ)。勝ったら true
static func play_battle(strategy: int, battle: Battle, state: RunStateScript) -> bool:
	while battle.outcome == Battle.Outcome.NONE:
		if battle.turn > TURN_LIMIT:
			push_error("戦闘が %d ターンで終わらない (シード %d)" % [TURN_LIMIT, state.map_seed])
			return false
		var move: Dictionary = battle_move(strategy, battle, state)
		var applied: bool = false
		match move["move"]:
			BattleMove.PLAY:
				applied = battle.play(move["hand_index"], move["target"])
			BattleMove.STRUGGLE:
				applied = battle.struggle(move["target"])
		if not applied:
			battle.end_turn()
	return battle.outcome == Battle.Outcome.WIN


## strategy の戦略で、seed_value の 1 幕を最初の契約者でランの終わり (敗北か踏破) まで遊ぶ (ゲームのロジックを
## 直接呼ぶ。地図・敵・報酬・出来事・戦闘の山札の混ぜ直しはすべて seed_value から決まる)。run_result() を返す
static func play_run(strategy: int, state: RunStateScript, seed_value: int) -> Dictionary:
	RunFlow.start_run(state, Contractors.FIRST_CONTRACTOR, seed_value)
	# 1 つの節点で通る局面は多くて 3 つ (地図 → 戦闘 → 報酬)。その数だけ進めても終わらなければ不具合
	for _step: int in range(ActMap.ROWS * 3):
		if is_run_over(state):
			break
		_advance(strategy, state)
	if not is_run_over(state):
		push_error("ランが終わらない (シード %d)" % seed_value)
	return run_result(state)


## ランが終わったか (敗北か踏破)
static func is_run_over(state: RunStateScript) -> bool:
	return (
		state.phase == RunStateScript.Phase.DEFEAT or state.phase == RunStateScript.Phase.CLEAR
	)


## 今のランの結果。{"cleared": 踏破したか, "floor": 到達した階層, "exhausted": 契約を使い切った回数,
## "unused_strong": 残り使用回数が 1 以上残っている強いカードの枚数}
static func run_result(state: RunStateScript) -> Dictionary:
	var unused_strong: int = 0
	for index: int in range(state.deck.size()):
		if state.can_use(index) and Cards.strength(state.deck[index]["id"]) >= STRONG_STRENGTH:
			unused_strong += 1
	return {
		"cleared": state.phase == RunStateScript.Phase.CLEAR,
		"floor": state.path.size(),
		"exhausted": state.exhausted_count,
		"unused_strong": unused_strong,
	}


## ランの今の局面を 1 つ進める (地図なら次の節点に入り、節点なら用を済ませて地図へ戻る)
static func _advance(strategy: int, state: RunStateScript) -> void:
	match state.phase:
		RunStateScript.Phase.MAP:
			RunFlow.enter_node(state, choose_column(state))
		RunStateScript.Phase.BATTLE:
			var battle: Battle = Battle.new()
			battle.start(state, RunFlow.encounter(state), state.node_seed())
			RunFlow.finish_battle(state, play_battle(strategy, battle, state))
		RunStateScript.Phase.REWARD:
			NodeRules.take_reward_card(state, choose_reward(state))
			RunFlow.leave_node(state)
		RunStateScript.Phase.SHRINE:
			var shrine: Dictionary = choose_shrine(state)
			if shrine["renew_index"] >= 0:
				NodeRules.shrine_renew(state, shrine["renew_index"])
			else:
				NodeRules.shrine_contract(state, shrine["card_id"])
			RunFlow.leave_node(state)
		RunStateScript.Phase.SHOP:
			_shop(state)
			RunFlow.leave_node(state)
		RunStateScript.Phase.EVENT:
			var event: Dictionary = choose_event(state)
			var picks: Array[int] = event["picks"]
			Events.choose(state, event["option"], picks)
			RunFlow.leave_node(state)


## 商人で、買うものが無くなるまで買う。1 回の訪問で買えるのは、並んだカードと回数を戻す 1 回まで
static func _shop(state: RunStateScript) -> void:
	for _purchase: int in range(NodeRules.OFFER_COUNT + 1):
		var purchase: Dictionary = next_purchase(state)
		var card_id: String = purchase["card_id"]
		if not card_id.is_empty():
			NodeRules.buy_card(state, card_id)
		elif purchase["restore_index"] >= 0:
			NodeRules.buy_restore(state, purchase["restore_index"])
		else:
			return


## strategy の戦略が、今の戦闘で回数の少ないカード (残り LOW_USES 以下) を使うか
static func _spends_low_uses(strategy: int, battle: Battle, state: RunStateScript) -> bool:
	if strategy == Strategy.SPEND:
		return true
	if state.hp <= state.max_hp * DANGER_HP_RATE or _incoming_damage(battle) >= state.hp:
		return true
	if strategy == Strategy.HOARD:
		return false
	var kind: int = state.current_node().get("kind", ActMap.Kind.BATTLE)
	return (
		kind == ActMap.Kind.ELITE
		or kind == ActMap.Kind.BOSS
		or state.hp <= state.max_hp * HEAVY_HP_RATE
		or shrine_distance(state) <= SHRINE_NEAR_STEPS
	)


## デッキの deck_index 番目のカードを今使った時の効果の点数と、狙う敵。{"value": 点数, "target": 敵の index
## (対象を取らないカードは -1)}。点数は、敵の体力を減らす量 + 防ぐダメージ × GUARD_WEIGHT (倒した敵が予告していた
## 攻撃を含む) + 引く枚数とエネルギーの点 (Cards.strength() と同じ点)。引く効果は、引いたカードを使う
## エネルギーが残る時だけ数える
static func _play_value(battle: Battle, state: RunStateScript, deck_index: int) -> Dictionary:
	var card: Dictionary = state.card(deck_index)
	var incoming: int = _incoming_damage(battle)
	var value: float = 0.0
	var target: int = -1
	if card.has("damage"):
		var damage: int = card["damage"] * card.get("hits", 1)
		var best_hit: float = -1.0
		for enemy_index: int in battle.alive_enemies():
			var hit: float = _attack_value(battle.enemies[enemy_index], damage, incoming)
			if card.get("area", false):
				value += hit
			elif hit > best_hit:
				best_hit = hit
				target = enemy_index
		if target >= 0:
			value += best_hit
	if card.has("block"):
		value += mini(card["block"], incoming) * GUARD_WEIGHT
	var energy_after: int = battle.energy - card["cost"] + card.get("energy", 0)
	var can_draw: bool = not (battle.draw_pile.is_empty() and battle.discard_pile.is_empty())
	if card.has("draw") and energy_after > 0 and can_draw:
		value += card["draw"] * Cards.DRAW_POINTS
	if card.has("energy"):
		value += card["energy"] * Cards.ENERGY_POINTS
	return {"value": value, "target": target}


## enemy に合計 damage の攻撃をした時の点数 (防御を引いて体力を減らす量。倒せるなら、その敵が予告していた
## 攻撃のうちこのターンに受けるはずだった分を、防いだダメージとして足す)
static func _attack_value(enemy: Dictionary, damage: int, incoming: int) -> float:
	var dealt: int = mini(maxi(0, damage - enemy["block"]), enemy["hp"])
	var value: float = dealt
	if dealt >= enemy["hp"]:
		value += mini(_intent_damage(enemy), incoming) * GUARD_WEIGHT
	return value


## play が best より良い手か (効果が無い手は選ばない。best が空なら効果があれば良い手。同じ効果なら安い方)
static func _is_better_play(play: Dictionary, best: Dictionary) -> bool:
	if play["value"] <= 0.0:
		return false
	if best.is_empty() or play["value"] > best["value"]:
		return true
	return is_equal_approx(play["value"], best["value"]) and play["cost"] < best["cost"]


## このターンの終わりに受けるダメージ (生きている敵が予告している攻撃の合計から、今の防御を引いた量)
static func _incoming_damage(battle: Battle) -> int:
	var total: int = 0
	for enemy_index: int in battle.alive_enemies():
		total += _intent_damage(battle.enemies[enemy_index])
	return maxi(0, total - battle.block)


## enemy が予告している攻撃のダメージの合計 (攻撃でなければ 0)
static func _intent_damage(enemy: Dictionary) -> int:
	var intent: Dictionary = enemy["intent"]
	if intent["move"] != Enemies.Move.ATTACK:
		return 0
	return intent["value"] * intent.get("hits", 1)


## 生きている敵のうち体力が最も少ない敵の index (もがくの対象。いなければ -1)
static func _weakest_enemy(battle: Battle) -> int:
	var weakest: int = -1
	for enemy_index: int in battle.alive_enemies():
		if weakest < 0 or battle.enemies[enemy_index]["hp"] < battle.enemies[weakest]["hp"]:
			weakest = enemy_index
	return weakest


## offers (カード ID の並び) から新しく契約する 1 枚。デッキに足りない種別 (_kind_order() の先のもの) を先に取り、
## 同じ種別の中では得る強さの合計が最も大きいもの
static func _choose_offer(state: RunStateScript, offers: Array[String]) -> String:
	var order: Array[int] = _kind_order(state)
	var best_id: String = ""
	var best_rank: int = order.size()
	for card_id: String in offers:
		var rank: int = order.find(Cards.CARDS[card_id]["kind"])
		var better_in_kind: bool = rank == best_rank and _contract_gain(card_id) > _contract_gain(best_id)
		if rank < best_rank or better_in_kind:
			best_rank = rank
			best_id = card_id
	return best_id


## 新しく契約するカードの種別の優先順。デッキの攻撃の残り使用回数が、防御の ATTACK_USES_PER_GUARD_USE 倍を
## 下回る間は攻撃 → 防御、そうでなければ防御 → 攻撃。技は最後 (敵を倒すのも身を守るのも攻撃と防御のため)
static func _kind_order(state: RunStateScript) -> Array[int]:
	var uses: Dictionary = {Cards.Kind.ATTACK: 0, Cards.Kind.GUARD: 0, Cards.Kind.SKILL: 0}
	for index: int in range(state.deck.size()):
		uses[state.card(index)["kind"]] += state.uses_left(index)
	var attack_first: Array[int] = [Cards.Kind.ATTACK, Cards.Kind.GUARD, Cards.Kind.SKILL]
	var guard_first: Array[int] = [Cards.Kind.GUARD, Cards.Kind.ATTACK, Cards.Kind.SKILL]
	if uses[Cards.Kind.ATTACK] < uses[Cards.Kind.GUARD] * ATTACK_USES_PER_GUARD_USE:
		return attack_first
	return guard_first


## card_id のカードと新しく契約して得る強さの合計 (強さ × 最大使用回数。空文字は 0)
static func _contract_gain(card_id: String) -> float:
	if card_id.is_empty():
		return 0.0
	return Cards.strength(card_id) * Cards.CARDS[card_id]["max_uses"]


## デッキの index 番目のカードの残り使用回数を最大まで戻して取り戻す強さの合計 (強さ × 減っている回数)
static func _restore_gain(state: RunStateScript, index: int) -> float:
	var missing: int = state.card(index)["max_uses"] - state.uses_left(index)
	return Cards.strength(state.deck[index]["id"]) * missing


## 残り使用回数を戻して取り戻す強さの合計が最も大きいカードのデッキの index (減っているカードが無ければ -1)
static func _best_restore(state: RunStateScript) -> int:
	var best_index: int = -1
	var best_gain: float = 0.0
	for index: int in range(state.deck.size()):
		var gain: float = _restore_gain(state, index)
		if gain > best_gain:
			best_gain = gain
			best_index = index
	return best_index


## 出来事の effect の選択肢で選ぶデッキの index の並び。契約の入れ替えは残りの強さの合計 (強さ × 残り使用回数)
## が小さい順に手放す枚数、体力と引き換えの回復は取り戻す強さの合計が最も大きい 1 枚、ほかは空
static func _event_picks(state: RunStateScript, effect: int) -> Array[int]:
	var picks: Array[int] = []
	if effect == Events.Effect.BLOOD_RESTORE and _best_restore(state) >= 0:
		picks.append(_best_restore(state))
	if effect == Events.Effect.SWAP:
		for _pick: int in range(mini(Events.SWAP_PICKS, state.deck.size())):
			var lowest: int = -1
			for index: int in range(state.deck.size()):
				if picks.has(index):
					continue
				var remaining: float = _remaining_strength(state, index)
				if lowest < 0 or remaining < _remaining_strength(state, lowest):
					lowest = index
			picks.append(lowest)
	return picks


## 出来事の effect の選択肢を picks で選びたいか。契約の入れ替えは、得る英霊の強さの合計が、手放すカードの
## 残りの強さの合計より大きい時だけ。体力と引き換えの回復は、払った後の体力が最大の HEAVY_HP_RATE を超える時だけ
static func _wants_event_option(state: RunStateScript, effect: int, picks: Array[int]) -> bool:
	if effect == Events.Effect.SWAP:
		var released: float = 0.0
		for index: int in picks:
			released += _remaining_strength(state, index)
		var hero_id: String = Events.gained_card(Events.Effect.SWAP, state.node_seed())
		return _contract_gain(hero_id) > released
	if effect == Events.Effect.BLOOD_RESTORE:
		return state.hp - Events.BLOOD_PRICE > state.max_hp * HEAVY_HP_RATE
	return true


## デッキの index 番目のカードの残りの強さの合計 (強さ × 残り使用回数)
static func _remaining_strength(state: RunStateScript, index: int) -> float:
	return Cards.strength(state.deck[index]["id"]) * state.uses_left(index)
