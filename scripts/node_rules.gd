extends RefCounted
## 地図の節点 (戦闘の報酬・契約の祠・商人) の品揃え・値段と、受け取る・払う処理 (戦闘に勝った時の契約者の個性を含む)。品揃えは節点のシード
## (RunState.node_seed()) から決まり、同じ節点に入り直しても同じになる。1 つの節点で済ませたことは
## RunState.visit に記録し、同じ節点で 2 回受け取れないようにする。数値の根拠は documents/DIRECTION.md
## 「決めたこと」で、自動テストプレイ (#10) の結果で見直す。

const ActMap := preload("res://scripts/act_map.gd")
const Cards := preload("res://scripts/cards.gd")
const Contractors := preload("res://scripts/contractors.gd")
const Relics := preload("res://scripts/relics.gd")
const RunStateScript := preload("res://scripts/run_state.gd")

## 戦闘 (通常・強敵) に勝った時に回復する体力 (護符を持たない時)
const BATTLE_HEAL: int = 5
## 戦闘に勝った時の所持金の範囲 [最小, 最大] (通常 / 強敵)
const REWARD_GOLD: Dictionary = {ActMap.Kind.BATTLE: [10, 20], ActMap.Kind.ELITE: [25, 35]}
## 報酬・祠・商人で並べるカードの枚数
const OFFER_COUNT: int = 3
## 商人の値段: カード (精霊 / 英霊)、1 枚の残り使用回数を最大まで戻す (護符を持たない時)、1 枚を外す、護符
const CARD_PRICES: Dictionary = {Cards.Bond.SPIRIT: 40, Cards.Bond.HERO: 75}
const RESTORE_PRICE: int = 35
const REMOVE_PRICE: int = 50
const RELIC_PRICE: int = 80
## 候補の比較用 (#60)。EXPIRED_LOCKED = 契約切れは戻せない、RENEW_USES = 最大まで戻す経路で戻す回数 (負は最大まで)
const EXPIRED_LOCKED: bool = true
const RENEW_USES: int = -1
## 契約を破棄する・外す時に残すデッキの最少の枚数 (空のデッキで戦闘に入らないため)
const MIN_DECK_SIZE: int = 1
## 品揃えの乱数を、同じ節点の所持金の乱数とずらす値 (同じシードの乱数列にしないためで、0 以外なら値に意味は無い)
const OFFER_SEED_OFFSET: int = 1
## 護符の選択の乱数を、同じ節点の所持金・品揃えの乱数とずらす値 (OFFER_SEED_OFFSET と同じく、ほかと違えば値に
## 意味は無い)
const RELIC_SEED_OFFSET: int = 2
## 品揃えを変える階の帯 (1 幕の地図の段を前半・中盤・後半に等分する) の数
const OFFER_BANDS: int = 3
## 品揃えに並ぶ確率の重み。精霊はどの帯でも SPIRIT_OFFER_WEIGHT、英霊は帯 (前半・中盤・後半の順) ごとの段の
## 重み。どの帯も英霊の重みの合計を 10 (精霊 1 枚の 10 倍) にして、品揃えの 1 枚目が英霊になる確率を
## 帯で変えない (引いたカードを戻さないので、2 枚目以降は帯でわずかに変わる)
const SPIRIT_OFFER_WEIGHT: int = 1
const HERO_OFFER_WEIGHTS: Array[Dictionary] = [
	{Cards.Tier.LOWER: 2, Cards.Tier.MIDDLE: 1, Cards.Tier.UPPER: 0},
	{Cards.Tier.LOWER: 1, Cards.Tier.MIDDLE: 1, Cards.Tier.UPPER: 1},
	{Cards.Tier.LOWER: 0, Cards.Tier.MIDDLE: 1, Cards.Tier.UPPER: 2},
]


## 戦闘 (kind が通常か強敵) に勝った時の所持金 (seed_value が同じなら同じ額)
static func reward_gold(seed_value: int, kind: int) -> int:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var span: Array = REWARD_GOLD[kind]
	return rng.randi_range(span[0], span[1])


## 今いる節点の戦闘 (kind が通常か強敵) に勝った時に受け取る所持金 (旅の銭袋の分を含む)
static func battle_gold(state: RunStateScript, kind: int) -> int:
	return reward_gold(state.node_seed(), kind) + Relics.value(state.relics, "coin_pouch", "gold")


## 戦闘に勝った時に回復する体力 (巡礼の数珠の分を含む)
static func battle_heal(state: RunStateScript) -> int:
	return BATTLE_HEAL + Relics.value(state.relics, "pilgrim_beads", "heal")


## 商人で 1 枚の残り使用回数を最大まで戻す値段 (繕いの帳面を持っていればその値段)
static func restore_price(state: RunStateScript) -> int:
	if state.relics.has("mended_ledger"):
		return Relics.value(state.relics, "mended_ledger", "restore_price")
	return RESTORE_PRICE


## 今いる強敵の節点に勝った時に、持っていない護符から 1 つを節点のシードで選んで手に入れる (すべて持っていれば
## 何もしない)。手に入れた護符の ID を返す (無ければ空文字)
static func grant_elite_relic(state: RunStateScript) -> String:
	var relic_id: String = Relics.pick_unowned(state.relics, state.node_seed() + RELIC_SEED_OFFSET)
	if relic_id.is_empty():
		return ""
	state.add_relic(relic_id)
	return relic_id


## 強敵の報酬の画面に見せる、この強敵で手に入れた護符 (手に入れた護符は最後に足されるので、最後の護符。
## 強敵の節点の報酬の局面でだけ呼ぶ。護符をすべて持って強敵に勝った時は何も得ていないが、最後の護符を返す)
static func elite_relic(state: RunStateScript) -> String:
	return "" if state.relics.is_empty() else state.relics.back()


## 商人に並べる護符 (持っていない護符から節点のシードで選ぶ。この訪問で買った後は買った護符。すべて持っていれば空文字)
static func shop_relic(state: RunStateScript) -> String:
	if state.visit.has("relic_sold"):
		return state.visit["relic_sold"]
	return Relics.pick_unowned(state.relics, state.node_seed() + RELIC_SEED_OFFSET)


## 商人で並んだ護符を買う (まだ買っておらず、所持金が足りる時だけ)
static func buy_relic(state: RunStateScript) -> bool:
	var relic_id: String = shop_relic(state)
	if relic_id.is_empty() or state.visit.has("relic_sold") or state.gold < RELIC_PRICE:
		return false
	state.gold -= RELIC_PRICE
	state.add_relic(relic_id)
	state.visit["relic_sold"] = relic_id
	return true


## 報酬・祠・商人に並べる OFFER_COUNT 枚の、互いに違うカード ID (seed_value と row が同じなら同じ並び)。
## row (地図の段) の帯の重み (offer_weight()) で選ぶ。bond を指定するとその区分のカードだけから選ぶ
static func card_offers(seed_value: int, row: int, bond: int = -1) -> Array[String]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value + OFFER_SEED_OFFSET
	var pool: Array[String] = []
	for card_id: String in Cards.CARDS:
		if (bond < 0 or Cards.CARDS[card_id]["bond"] == bond) and offer_weight(card_id, row) > 0:
			pool.append(card_id)
	pool.sort()
	var offers: Array[String] = []
	while offers.size() < OFFER_COUNT and not pool.is_empty():
		var total: int = 0
		for card_id: String in pool:
			total += offer_weight(card_id, row)
		var roll: int = rng.randi_range(0, total - 1)
		var index: int = 0
		while roll >= offer_weight(pool[index], row):
			roll -= offer_weight(pool[index], row)
			index += 1
		offers.append(pool.pop_at(index))
	return offers


## 地図の段 row の品揃えの帯 (0 = 前半、1 = 中盤、2 = 後半。15 段の 1 幕では段 0〜4・5〜9・10〜14。
## 出発前の -1 は前半)
static func offer_band(row: int) -> int:
	return clampi(floori(float(row) * OFFER_BANDS / ActMap.ROWS), 0, OFFER_BANDS - 1)


## card_id のカードが、地図の段 row の品揃えに並ぶ確率の重み (0 なら並ばない)
static func offer_weight(card_id: String, row: int) -> int:
	var card: Dictionary = Cards.CARDS[card_id]
	if card["bond"] == Cards.Bond.SPIRIT:
		return SPIRIT_OFFER_WEIGHT
	return HERO_OFFER_WEIGHTS[offer_band(row)][card["tier"]]


## state の今いる節点に並べるカード (card_offers() に今いる節点のシードと段を渡す)
static func offers_here(state: RunStateScript, bond: int = -1) -> Array[String]:
	return card_offers(state.node_seed(), state.current_row(), bond)


## 商人でのカードの値段
static func card_price(card_id: String) -> int:
	return CARD_PRICES[Cards.CARDS[card_id]["bond"]]


## 戦闘の報酬で card_id のカードと契約する (並んだ 3 枚のどれかで、まだ受け取っていない時だけ)
static func take_reward_card(state: RunStateScript, card_id: String) -> bool:
	if state.visit.has("taken") or not offers_here(state).has(card_id):
		return false
	state.add_card(card_id)
	state.visit["taken"] = true
	return true


## 戦闘 (通常・強敵) に勝った時の契約者の個性 win_restore (scripts/contractors.gd): 契約切れでない精霊のうち最大
## 使用回数 (出来事で増やした分を含む) から
## 減っている回数が最も多いカード 1 枚 (同じならデッキの先) の残り使用回数を win_restore 回戻し、その index を
## RunState.visit["win_restored"] に記録して返す (報酬の画面が見せる)。英霊は戻さない (強く回数の少ない英霊を
## いつ切るかの判断を残すため)。契約切れの精霊も戻さない (使い切ってから戻るなら、使い切らずに残す判断が要らなく
## なるため)。個性が無いか、減っている精霊が無ければ何もせず -1
static func win_restore(state: RunStateScript) -> int:
	var amount: int = Contractors.trait_value(state.character_id, "win_restore")
	var best_index: int = -1
	var best_missing: int = 0
	for index: int in range(state.deck.size()):
		if state.card(index)["bond"] != Cards.Bond.SPIRIT or state.uses_left(index) == 0:
			continue
		var missing: int = Cards.deck_max_uses(state.deck[index]) - state.uses_left(index)
		if missing > best_missing:
			best_missing = missing
			best_index = index
	if amount <= 0 or best_index < 0:
		return -1
	state.restore_uses(best_index, amount)
	state.visit["win_restored"] = best_index
	return best_index


## 契約の祠で、デッキの index 番目のカードの契約を更新する (残り使用回数を最大まで戻す。代価なし。
## 減っているカードだけ)
static func shrine_renew(state: RunStateScript, index: int) -> bool:
	if state.visit.has("shrine_done") or not can_restore(state, index):
		return false
	state.restore_uses(index, RENEW_USES)
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
	if state.visit.has("shrine_done") or not offers_here(state).has(card_id):
		return false
	state.add_card(card_id)
	state.visit["shrine_done"] = true
	return true


## 商人で card_id のカードを買う (並んだカードで、まだ買っておらず、所持金が足りる時だけ)
static func buy_card(state: RunStateScript, card_id: String) -> bool:
	var sold: Array = state.visit.get("sold", [])
	if sold.has(card_id) or not offers_here(state).has(card_id):
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
	if state.gold < restore_price(state):
		return false
	state.gold -= restore_price(state)
	state.restore_uses(index, RENEW_USES)
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


## デッキの index 番目のカードの残り使用回数を戻す意味があるか (出来事で増やした後の最大より減っている)
static func can_restore(state: RunStateScript, index: int) -> bool:
	return (
		_is_deck_index(state, index)
		and state.uses_left(index) < Cards.deck_max_uses(state.deck[index])
		and (not EXPIRED_LOCKED or state.can_use(index))
	)


## デッキの index 番目のカードを外してよいか (外してもデッキが MIN_DECK_SIZE 枚以上残る)
static func can_remove(state: RunStateScript, index: int) -> bool:
	return _is_deck_index(state, index) and state.deck.size() > MIN_DECK_SIZE


## index がデッキの範囲内か
static func _is_deck_index(state: RunStateScript, index: int) -> bool:
	return index >= 0 and index < state.deck.size()
