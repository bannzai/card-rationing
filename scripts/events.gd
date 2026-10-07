extends RefCounted
## 地図の「出来事」の定義と、選んだ選択肢の処理。どの出来事が出るかと、出来事で得るカードは節点のシード
## (RunState.node_seed()) から決まる。1 つの出来事の定義は EVENTS の 1 要素 (キーが出来事 ID) で、
## options の各選択肢は effect (処理の種類) と picks (選ぶデッキのカードの枚数) を持つ。
## 数値の根拠は documents/DIRECTION.md「決めたこと」で、自動テストプレイ (#10) の結果で見直す。

## 選択肢の処理の種類。SWAP = 選んだカードを手放して英霊 1 枚と契約する、BLOOD_RESTORE = 体力を払って
## 選んだカードの残り使用回数を最大まで戻す、SPIRIT = 精霊 1 枚と契約する、GOLD = 所持金を得る、LEAVE = 何もしない
enum Effect { SWAP, BLOOD_RESTORE, SPIRIT, GOLD, LEAVE }

const Cards := preload("res://scripts/cards.gd")
const NodeRules := preload("res://scripts/node_rules.gd")
const RunStateScript := preload("res://scripts/run_state.gd")

## 名もなき墓標で手放すカードの枚数、血の泉で払う体力、迷える精霊を送って得る所持金
const SWAP_PICKS: int = 2
const BLOOD_PRICE: int = 8
const SPIRIT_GOLD: int = 20

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
}


## seed_value の節点に出る出来事の ID (同じシードなら同じ出来事)
static func event_for(seed_value: int) -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var ids: Array = EVENTS.keys()
	ids.sort()
	return ids[rng.randi_range(0, ids.size() - 1)]


## 出来事の選択肢 effect で得るカードの ID (SWAP は英霊、SPIRIT は精霊。ほかは空文字)。seed_value が同じなら同じ
static func gained_card(effect: Effect, seed_value: int) -> String:
	if effect == Effect.SWAP:
		return NodeRules.card_offers(seed_value, Cards.Bond.HERO)[0]
	if effect == Effect.SPIRIT:
		return NodeRules.card_offers(seed_value, Cards.Bond.SPIRIT)[0]
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
	match option["effect"]:
		Effect.SWAP:
			return swapped_deck_size(state.deck.size(), picks.size()) >= NodeRules.MIN_DECK_SIZE
		Effect.BLOOD_RESTORE:
			return state.hp > BLOOD_PRICE and NodeRules.can_restore(state, picks[0])
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
			state.add_card(gained_card(effect, seed_value))
		Effect.BLOOD_RESTORE:
			state.take_damage(BLOOD_PRICE)
			state.restore_uses(picks[0])
		Effect.SPIRIT:
			state.add_card(gained_card(effect, seed_value))
		Effect.GOLD:
			state.gold += SPIRIT_GOLD
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
