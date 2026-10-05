extends RefCounted
## 地図の節点 (戦闘の報酬・契約の祠・商人) の品揃え・値段と、受け取る・払う処理。品揃えは節点のシード
## (RunState.node_seed()) から決まり、同じ節点に入り直しても同じになる。1 つの節点で済ませたことは
## RunState.visit に記録し、同じ節点で 2 回受け取れないようにする。数値の根拠は documents/DIRECTION.md
## 「決めたこと」で、自動テストプレイ (#10) の結果で見直す。

const ActMap := preload("res://scripts/act_map.gd")
const Cards := preload("res://scripts/cards.gd")
const RunStateScript := preload("res://scripts/run_state.gd")

## 戦闘 (通常・強敵) に勝った時に回復する体力
const BATTLE_HEAL: int = 5
## 戦闘に勝った時の所持金の範囲 [最小, 最大] (通常 / 強敵)
const REWARD_GOLD: Dictionary = {ActMap.Kind.BATTLE: [10, 20], ActMap.Kind.ELITE: [25, 35]}
## 報酬・祠・商人で並べるカードの枚数
const OFFER_COUNT: int = 3
## 商人の値段: カード (精霊 / 英霊)、1 枚の残り使用回数を最大まで戻す、1 枚を外す
const CARD_PRICES: Dictionary = {Cards.Bond.SPIRIT: 40, Cards.Bond.HERO: 75}
const RESTORE_PRICE: int = 35
const REMOVE_PRICE: int = 50
## 契約を破棄する・外す時に残すデッキの最少の枚数 (空のデッキで戦闘に入らないため)
const MIN_DECK_SIZE: int = 1
## 品揃えの乱数を、同じ節点の所持金の乱数とずらす値 (同じシードの乱数列にしないためで、0 以外なら値に意味は無い)
const OFFER_SEED_OFFSET: int = 1


## 戦闘 (kind が通常か強敵) に勝った時の所持金 (seed_value が同じなら同じ額)
static func reward_gold(seed_value: int, kind: int) -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var span: Array = REWARD_GOLD[kind]
	return rng.randi_range(span[0], span[1])


## 報酬・祠・商人に並べる OFFER_COUNT 枚の、互いに違うカード ID (seed_value が同じなら同じ並び)。
## bond を指定するとその区分のカードだけから選ぶ
static func card_offers(seed_value: int, bond: int = -1) -> Array[String]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value + OFFER_SEED_OFFSET
	var pool: Array[String] = []
	for card_id: String in Cards.CARDS:
		if bond < 0 or Cards.CARDS[card_id]["bond"] == bond:
			pool.append(card_id)
	pool.sort()
	var offers: Array[String] = []
	while offers.size() < OFFER_COUNT and not pool.is_empty():
		offers.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return offers


## 商人でのカードの値段
static func card_price(card_id: String) -> int:
	return CARD_PRICES[Cards.CARDS[card_id]["bond"]]


## 戦闘の報酬で card_id のカードと契約する (並んだ 3 枚のどれかで、まだ受け取っていない時だけ)
static func take_reward_card(state: RunStateScript, card_id: String) -> bool:
	if state.visit.has("taken") or not card_offers(state.node_seed()).has(card_id):
		return false
	state.add_card(card_id)
	state.visit["taken"] = true
	return true


## 契約の祠で、デッキの index 番目のカードの契約を更新する (残り使用回数を最大まで戻す。代価なし。
## 減っているカードだけ)
static func shrine_renew(state: RunStateScript, index: int) -> bool:
	if state.visit.has("shrine_done") or not can_restore(state, index):
		return false
	state.restore_uses(index)
	state.visit["shrine_done"] = true
	return true


## 契約の祠で、デッキの index 番目のカードの契約を破棄する (デッキから外す。代価なし)
static func shrine_break(state: RunStateScript, index: int) -> bool:
	if state.visit.has("shrine_done") or not can_remove(state, index):
		return false
	state.remove_card(index)
	state.visit["shrine_done"] = true
	return true


## 契約の祠で、並んだ 3 体のうち card_id と新しく契約する (代価なし)
static func shrine_contract(state: RunStateScript, card_id: String) -> bool:
	if state.visit.has("shrine_done") or not card_offers(state.node_seed()).has(card_id):
		return false
	state.add_card(card_id)
	state.visit["shrine_done"] = true
	return true


## 商人で card_id のカードを買う (並んだカードで、まだ買っておらず、所持金が足りる時だけ)
static func buy_card(state: RunStateScript, card_id: String) -> bool:
	var sold: Array = state.visit.get("sold", [])
	if sold.has(card_id) or not card_offers(state.node_seed()).has(card_id):
		return false
	if state.gold < card_price(card_id):
		return false
	state.gold -= card_price(card_id)
	state.add_card(card_id)
	sold.append(card_id)
	state.visit["sold"] = sold
	return true


## 商人で、デッキの index 番目のカードの残り使用回数を最大まで戻す (1 回の訪問で 1 回、減っているカードだけ)
static func buy_restore(state: RunStateScript, index: int) -> bool:
	if state.visit.has("restored") or not can_restore(state, index):
		return false
	if state.gold < RESTORE_PRICE:
		return false
	state.gold -= RESTORE_PRICE
	state.restore_uses(index)
	state.visit["restored"] = true
	return true


## 商人で、デッキの index 番目のカードを外す (1 回の訪問で 1 回)
static func buy_removal(state: RunStateScript, index: int) -> bool:
	if state.visit.has("removed") or not can_remove(state, index):
		return false
	if state.gold < REMOVE_PRICE:
		return false
	state.gold -= REMOVE_PRICE
	state.remove_card(index)
	state.visit["removed"] = true
	return true


## デッキの index 番目のカードの残り使用回数を戻す意味があるか (最大より減っている)
static func can_restore(state: RunStateScript, index: int) -> bool:
	return _is_deck_index(state, index) and state.uses_left(index) < state.card(index)["max_uses"]


## デッキの index 番目のカードを外してよいか (外してもデッキが MIN_DECK_SIZE 枚以上残る)
static func can_remove(state: RunStateScript, index: int) -> bool:
	return _is_deck_index(state, index) and state.deck.size() > MIN_DECK_SIZE


## index がデッキの範囲内か
static func _is_deck_index(state: RunStateScript, index: int) -> bool:
	return index >= 0 and index < state.deck.size()
