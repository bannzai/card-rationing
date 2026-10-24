extends RefCounted
## 地図の「出来事」の定義と、選んだ選択肢の処理。どの出来事が出るかと、出来事で得るカードは節点のシード
## (RunState.node_seed()) から決まる。1 つの出来事の定義は EVENTS の 1 要素 (キーが出来事 ID) で、
## options の各選択肢は effect (処理の種類) と picks (選ぶデッキのカードの枚数) を持つ。
## 数値の根拠は documents/DIRECTION.md「決めたこと」で、自動テストプレイ (#10) の結果で見直す。

## 選択肢の処理の種類。SWAP = 選んだカードを手放して英霊 1 枚と契約する、BLOOD_RESTORE = 体力を払って
## 選んだカードの残り使用回数を最大まで戻す、SPIRIT = 精霊 1 枚と契約する、GOLD = 所持金を得る、LEAVE = 何もしない、
## RAISE_HERO = 体力を払って選んだ英霊の最大使用回数と残り使用回数を 1 増やす、RAISE_SPIRIT = 所持金を払って
## 選んだ精霊の最大使用回数と残り使用回数を 1 増やす、BLOOD_HERO = 体力を払って英霊 1 枚と契約する、
## GOLD_RESTORE = 所持金を払って選んだカードの残り使用回数を CANDLE_USES 回戻す、BURN_RESTORE = 最初に選んだ
## カードを手放し、続けて選んだ 2 枚の残り使用回数を最大まで戻す、GAMBLE = 選んだカードを賭け、当たれば残り使用回数を
## 最大まで戻し、外れればそのカードを失う、COPY_SPIRIT = 所持金を払って選んだ精霊と同じ精霊ともう 1 枚契約する、
## SELL = 選んだカードを手放して所持金を得る
enum Effect {
	SWAP,
	BLOOD_RESTORE,
	SPIRIT,
	GOLD,
	LEAVE,
	RAISE_HERO,
	RAISE_SPIRIT,
	BLOOD_HERO,
	GOLD_RESTORE,
	BURN_RESTORE,
	GAMBLE,
	COPY_SPIRIT,
	SELL,
}

const Cards := preload("res://scripts/cards.gd")
const NodeRules := preload("res://scripts/node_rules.gd")
const RunStateScript := preload("res://scripts/run_state.gd")

## 名もなき墓標で手放すカードの枚数、血の泉で払う体力、迷える精霊を送って得る所持金
const SWAP_PICKS: int = 2
const BLOOD_PRICE: int = 8
const SPIRIT_GOLD: int = 20
## 蝋の祭壇で英霊の最大使用回数を増やす時に払う体力と、精霊の最大使用回数を増やす時に払う所持金
const RAISE_HERO_PRICE: int = 10
const RAISE_SPIRIT_PRICE: int = 30
## 最大使用回数を増やす選択肢の処理 → 選べるカードの区分
const RAISE_BONDS: Dictionary = {
	Effect.RAISE_HERO: Cards.Bond.HERO, Effect.RAISE_SPIRIT: Cards.Bond.SPIRIT
}
## 英霊の塚で英霊と契約する時に払う体力
const HERO_BLOOD_PRICE: int = 12
## 灯売りの行商で払う所持金と、戻す残り使用回数
const CANDLE_PRICE: int = 20
const CANDLE_USES: int = 2
## 灰の炉で残り使用回数を最大まで戻すカードの枚数 (手放す 1 枚の後に選ぶ)
const BURN_RESTORES: int = 2
## 封蝋の骰子で当たる確率と、当たり外れの乱数を出来事の選択 (event_for()) の乱数とずらす値 (scripts/node_rules.gd の
## OFFER_SEED_OFFSET・RELIC_SEED_OFFSET と違えば値に意味は無い)
const GAMBLE_WIN_RATE: float = 0.5
const GAMBLE_SEED_OFFSET: int = 3
## 写し手の机で精霊を写す時に払う所持金と、影の質屋でカードを手放して得る所持金
const COPY_PRICE: int = 35
const PAWN_GOLD: int = 25
## 選んだカードを手放すことがある選択肢の処理 (手放した後もデッキに NodeRules.MIN_DECK_SIZE 枚残る時だけ選べる。
## 名もなき墓標の入れ替えは英霊 1 枚を得るので別に数える)
const RELEASE_EFFECTS: Array[int] = [Effect.BURN_RESTORE, Effect.GAMBLE, Effect.SELL]

## 出来事 ID → 定義
const EVENTS: Dictionary = {
	"nameless_grave":
	{
		"title": "名もなき墓標",
		"text": "朽ちた墓標の前で、英霊がささやく。「その契約を 2 つ捨てるなら、我が力を貸そう」",
		"options":
		[
			{
				"label": "契約を 2 つ破棄し、英霊と契約する",
				"effect": Effect.SWAP,
				"picks": SWAP_PICKS,
			},
			{"label": "立ち去る", "effect": Effect.LEAVE, "picks": 0},
		],
	},
	"blood_spring":
	{
		"title": "血の泉",
		"text": "泉に血を注げば、薄れた契約の印がもう一度灯るという。",
		"options":
		[
			{
				"label": "体力 %d を払い、1 枚の残り使用回数を最大まで戻す" % BLOOD_PRICE,
				"effect": Effect.BLOOD_RESTORE,
				"picks": 1,
			},
			{"label": "立ち去る", "effect": Effect.LEAVE, "picks": 0},
		],
	},
	"lost_spirit":
	{
		"title": "迷える精霊",
		"text": "行き場を失った精霊が、新しい主を探している。",
		"options":
		[
			{"label": "精霊と契約する", "effect": Effect.SPIRIT, "picks": 0},
			{
				"label": "精霊を送り出し、所持金 %d を得る" % SPIRIT_GOLD,
				"effect": Effect.GOLD,
				"picks": 0,
			},
		],
	},
	"wax_altar":
	{
		"title": "蝋の祭壇",
		"text": "祭壇に溶けた蝋が溜まっている。印に蝋を足せば、契約の回数そのものが増えるという。",
		"options":
		[
			{
				"label": "体力 %d を払い、英霊 1 枚の最大と残りの使用回数を 1 増やす" % RAISE_HERO_PRICE,
				"effect": Effect.RAISE_HERO,
				"picks": 1,
			},
			{
				"label": "所持金 %d を払い、精霊 1 枚の最大と残りの使用回数を 1 増やす" % RAISE_SPIRIT_PRICE,
				"effect": Effect.RAISE_SPIRIT,
				"picks": 1,
			},
			{"label": "立ち去る", "effect": Effect.LEAVE, "picks": 0},
		],
	},
	"hero_barrow":
	{
		"title": "英霊の塚",
		"text": "古い塚の奥で、名を失った英霊が膝をついている。「血で誓うなら、この剣をもう一度振るおう」",
		"options":
		[
			{
				"label": "体力 %d を払い、英霊と契約する" % HERO_BLOOD_PRICE,
				"effect": Effect.BLOOD_HERO,
				"picks": 0,
			},
			{"label": "立ち去る", "effect": Effect.LEAVE, "picks": 0},
		],
	},
	"candle_peddler":
	{
		"title": "灯売りの行商",
		"text": "蝋燭を背負った行商人が、薄れた印に灯を足してやろうと言う。",
		"options":
		[
			{
				"label": "所持金 %d を払い、1 枚の残り使用回数を %d 戻す" % [CANDLE_PRICE, CANDLE_USES],
				"effect": Effect.GOLD_RESTORE,
				"picks": 1,
			},
			{"label": "立ち去る", "effect": Effect.LEAVE, "picks": 0},
		],
	},
	"ash_furnace":
	{
		"title": "灰の炉",
		"text": "崩れた祠の炉が、くべた契約を喰らって燃えている。その熱で、ほかの印がもう一度灯るという。",
		"options":
		[
			{
				"label": "1 枚を炉にくべ、%d 枚の残り使用回数を最大まで戻す" % BURN_RESTORES,
				"effect": Effect.BURN_RESTORE,
				"picks": 1 + BURN_RESTORES,
			},
			{"label": "立ち去る", "effect": Effect.LEAVE, "picks": 0},
		],
	},
	"seal_dice":
	{
		"title": "封蝋の骰子",
		"text": "骨の骰子を転がす賭け手が笑う。「契約を 1 つ賭けな。当たれば印を灯し直し、外れれば頂く」",
		"options":
		[
			{"label": "使いかけの 1 枚を賭ける", "effect": Effect.GAMBLE, "picks": 1},
			{"label": "立ち去る", "effect": Effect.LEAVE, "picks": 0},
		],
	},
	"scribe_desk":
	{
		"title": "写し手の机",
		"text": "契約の写本が開かれている。代価を払えば、精霊との契約をもう 1 枚書き写せるという。",
		"options":
		[
			{
				"label": "所持金 %d を払い、精霊 1 枚を写す" % COPY_PRICE,
				"effect": Effect.COPY_SPIRIT,
				"picks": 1,
			},
			{"label": "立ち去る", "effect": Effect.LEAVE, "picks": 0},
		],
	},
	"shadow_pawn":
	{
		"title": "影の質屋",
		"text": "路地の奥の質屋が、もう要らない契約を買い取ると言う。",
		"options":
		[
			{
				"label": "1 枚を手放し、所持金 %d を得る" % PAWN_GOLD,
				"effect": Effect.SELL,
				"picks": 1,
			},
			{"label": "立ち去る", "effect": Effect.LEAVE, "picks": 0},
		],
	},
}


## seed_value の節点に出る出来事の ID (同じシードなら同じ出来事)
static func event_for(seed_value: int) -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var ids: Array = EVENTS.keys()
	ids.sort()
	return ids[rng.randi_range(0, ids.size() - 1)]


## state の今いる出来事で、選択肢 effect で得るカードの ID (SWAP・BLOOD_HERO は英霊、SPIRIT は精霊。ほかは
## 空文字)。報酬と同じく今いる節点のシードと段の帯 (NodeRules.offers_here()) で決まる
static func gained_card(effect: Effect, state: RunStateScript) -> String:
	if effect == Effect.SWAP or effect == Effect.BLOOD_HERO:
		return NodeRules.offers_here(state, Cards.Bond.HERO)[0]
	if effect == Effect.SPIRIT:
		return NodeRules.offers_here(state, Cards.Bond.SPIRIT)[0]
	return ""


## 契約の入れ替え (deck_size 枚のデッキから released 枚を手放し、英霊 1 枚と契約する) の後のデッキの枚数
static func swapped_deck_size(deck_size: int, released: int) -> int:
	return deck_size - released + 1


## 今いる出来事の option_index 番目の選択肢を、picks (選んだデッキの index) で選べるか
static func can_choose(state: RunStateScript, option_index: int, picks: Array[int]) -> bool:
	var options: Array = EVENTS[event_for(state.node_seed())]["options"]
	if state.visit.has("event_done") or option_index < 0 or option_index >= options.size():
		return false
	var option: Dictionary = options[option_index]
	if not _are_distinct_deck_indices(state, picks) or picks.size() != option["picks"]:
		return false
	var effect: Effect = option["effect"]
	if effect == Effect.SWAP:
		return swapped_deck_size(state.deck.size(), picks.size()) >= NodeRules.MIN_DECK_SIZE
	if RELEASE_EFFECTS.has(effect) and state.deck.size() - 1 < NodeRules.MIN_DECK_SIZE:
		return false
	return can_pay(state, effect) and range(picks.size()).all(
		func(slot: int) -> bool: return can_pick(state, effect, picks[slot], slot)
	)


## 今いる出来事の option_index 番目の選択肢を今選び始められるか (カードを選ぶ選択肢は、選べるカードの組が 1 つでも
## あるか)。出来事の画面が押せるボタンを決め、戦略 bot は選ぶ前に見る
static func can_start(state: RunStateScript, option_index: int) -> bool:
	var option: Dictionary = EVENTS[event_for(state.node_seed())]["options"][option_index]
	var effect: Effect = option["effect"]
	if option["picks"] == 0:
		var no_picks: Array[int] = []
		return can_choose(state, option_index, no_picks)
	if state.visit.has("event_done") or state.deck.size() < option["picks"]:
		return false
	if effect == Effect.SWAP:
		return swapped_deck_size(state.deck.size(), option["picks"]) >= NodeRules.MIN_DECK_SIZE
	if RELEASE_EFFECTS.has(effect) and state.deck.size() - 1 < NodeRules.MIN_DECK_SIZE:
		return false
	if not can_pay(state, effect):
		return false
	# 灰の炉は、手放す 1 枚はどのカードでもよいので、戻せるカードが戻す枚数だけあり、ほかに手放す 1 枚が残ればよい
	var slot: int = 1 if effect == Effect.BURN_RESTORE else 0
	var pickable: int = range(state.deck.size()).filter(
		func(index: int) -> bool: return can_pick(state, effect, index, slot)
	).size()
	return pickable >= option["picks"] - slot


## effect の選択肢の代価を今払えるか (体力は払った後に 1 以上残る時だけ払える)
static func can_pay(state: RunStateScript, effect: Effect) -> bool:
	match effect:
		Effect.BLOOD_RESTORE:
			return state.hp > BLOOD_PRICE
		Effect.RAISE_HERO:
			return state.hp > RAISE_HERO_PRICE
		Effect.RAISE_SPIRIT:
			return state.gold >= RAISE_SPIRIT_PRICE
		Effect.BLOOD_HERO:
			return state.hp > HERO_BLOOD_PRICE
		Effect.GOLD_RESTORE:
			return state.gold >= CANDLE_PRICE
		Effect.COPY_SPIRIT:
			return state.gold >= COPY_PRICE
	return true


## effect の選択肢で、slot 番目 (0 始まり) に選ぶカードとしてデッキの index 番目のカードを選べるか。血の泉・
## 灯売りの行商・封蝋の骰子と、灰の炉の 2 番目からは残りの減った契約切れでないカード (NodeRules.can_restore())、
## 蝋の祭壇はその区分の最大使用回数をまだ増やせる契約切れでないカード、写し手の机は精霊。契約の入れ替え・灰の炉の
## 最初 (手放す 1 枚)・影の質屋はどのカードも選べる
static func can_pick(state: RunStateScript, effect: Effect, index: int, slot: int = 0) -> bool:
	if index < 0 or index >= state.deck.size():
		return false
	match effect:
		Effect.BLOOD_RESTORE, Effect.GOLD_RESTORE:
			return NodeRules.can_restore(state, index)
		Effect.BURN_RESTORE:
			return slot == 0 or NodeRules.can_restore(state, index)
		Effect.GAMBLE:
			return NodeRules.can_restore(state, index)
		Effect.COPY_SPIRIT:
			return state.card(index)["bond"] == Cards.Bond.SPIRIT
	if RAISE_BONDS.has(effect):
		return (
			state.can_use(index)
			and state.card(index)["bond"] == RAISE_BONDS[effect]
			and Cards.deck_max_uses(state.deck[index]) < Cards.uses_limit(state.deck[index]["id"])
		)
	return true


## effect の選択肢で slot 番目 (0 始まり) に選ぶカードの説明 (カードを選ぶ画面の見出し)
static func pick_prompt(effect: Effect, slot: int) -> String:
	if effect == Effect.BURN_RESTORE:
		return "炉にくべるカード" if slot == 0 else "残り使用回数を最大まで戻すカード"
	return "カード"


## シードが seed_value の節点 (RunState.node_seed()) の封蝋の骰子が当たりか (同じ節点なら同じ結果で、入り直しても
## 変わらない)
static func gamble_wins(seed_value: int) -> bool:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value + GAMBLE_SEED_OFFSET
	return rng.randf() < GAMBLE_WIN_RATE


## state のデッキの index 番目のカードの最大使用回数を 1 増やし、残り使用回数も restore_uses() で 1 増やす
## (蝋の祭壇)。最大が Cards.uses_limit() に届いていて増やせなければ false を返して何も変えない
static func raise_max_uses(state: RunStateScript, index: int) -> bool:
	var entry: Dictionary = state.deck[index]
	if Cards.deck_max_uses(entry) >= Cards.uses_limit(entry["id"]):
		return false
	entry["bonus_uses"] = entry.get("bonus_uses", 0) + 1
	state.restore_uses(index, 1)
	return true


## 今いる出来事の option_index 番目の選択肢を picks (選んだデッキの index) で選び、結果をランに反映する。
## 選べなければ false を返して何も変えない
static func choose(state: RunStateScript, option_index: int, picks: Array[int]) -> bool:
	if not can_choose(state, option_index, picks):
		return false
	var seed_value: int = state.node_seed()
	var effect: Effect = EVENTS[event_for(seed_value)]["options"][option_index]["effect"]
	match effect:
		Effect.SWAP:
			var descending: Array[int] = picks.duplicate()
			descending.sort()
			descending.reverse()
			for index: int in descending:
				state.remove_card(index)
			state.add_card(gained_card(effect, state))
		Effect.BLOOD_RESTORE:
			state.take_damage(BLOOD_PRICE)
			state.restore_uses(picks[0])
		Effect.SPIRIT:
			state.add_card(gained_card(effect, state))
		Effect.GOLD:
			state.gold += SPIRIT_GOLD
		Effect.RAISE_HERO:
			state.take_damage(RAISE_HERO_PRICE)
			raise_max_uses(state, picks[0])
		Effect.RAISE_SPIRIT:
			state.gold -= RAISE_SPIRIT_PRICE
			raise_max_uses(state, picks[0])
		Effect.BLOOD_HERO:
			state.take_damage(HERO_BLOOD_PRICE)
			state.add_card(gained_card(effect, state))
		Effect.GOLD_RESTORE:
			state.gold -= CANDLE_PRICE
			state.restore_uses(picks[0], CANDLE_USES)
		Effect.BURN_RESTORE:
			# 戻してから手放す (手放すと後ろのカードの index がずれるため)
			for slot: int in range(1, picks.size()):
				state.restore_uses(picks[slot])
			state.remove_card(picks[0])
		Effect.GAMBLE:
			if gamble_wins(seed_value):
				state.restore_uses(picks[0])
			else:
				state.remove_card(picks[0])
		Effect.COPY_SPIRIT:
			state.gold -= COPY_PRICE
			state.add_card(state.deck[picks[0]]["id"])
		Effect.SELL:
			state.remove_card(picks[0])
			state.gold += PAWN_GOLD
	state.visit["event_done"] = true
	return true


## picks がデッキの範囲内の互いに違う index か
static func _are_distinct_deck_indices(state: RunStateScript, picks: Array[int]) -> bool:
	var seen: Dictionary = {}
	for index: int in picks:
		if index < 0 or index >= state.deck.size() or seen.has(index):
			return false
		seen[index] = true
	return true
