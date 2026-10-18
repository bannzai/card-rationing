extends RefCounted
## 1 回の戦闘の状態 (山札・手札・捨て札・エネルギー・防御・敵) と進行。UI なしで呼べる (selfcheck と
## 自動テストプレイが直接使う)。カードの残り使用回数は持たず、RunState (run_state) のものを使って減らす。
## 山札の混ぜ直しと敵の行動の選択の乱数はシード付きで、同じシードなら同じ進行になる。
## 山札・手札・捨て札・発動中の加護の要素は run_state.deck の index (同じカードでも別の要素として扱う)。
## 持っている護符 (scripts/relics.gd) のうち戦闘で効くもの (ダメージ・防御・最初のターンのエネルギー・残り使用回数が
## 減らない) もここで効かせ、働いた護符を relic_triggers に残す (戦闘画面が発動を見せる)。

## 戦闘の結果
enum Outcome { NONE, WIN, LOSE }

const Cards := preload("res://scripts/cards.gd")
const Contractors := preload("res://scripts/contractors.gd")
const Enemies := preload("res://scripts/enemies.gd")
const Relics := preload("res://scripts/relics.gd")
const RunStateScript := preload("res://scripts/run_state.gd")

## 毎ターンの開始で得るエネルギーと引く枚数の基準 (契約者の個性で足す前の値)。issue #6 の指定 (Slay the Spire 型の
## 定番の値で、手札 5 枚に対してコスト 1 のカードを 3 枚使える比率)。数値は自動テストプレイ (#10) の結果で見直す
const ENERGY_PER_TURN: int = 3
const HAND_SIZE: int = 5
## 常に使える基本行動「もがく」のコストとダメージ (使えるカードが無くても詰まないための行動。
## documents/DIRECTION.md「決めたこと」)。コスト 1 で最弱の攻撃カード (火の粉 3) より弱くし、
## 契約切れだらけのデッキが弱いという結果を残す
const STRUGGLE_COST: int = 1
const STRUGGLE_DAMAGE: int = 2

## ラン単位の状態 (RunState)。残り使用回数と巡礼者の体力はここから読み書きする
var run_state: RunStateScript = null
## 戦闘の乱数 (山札の混ぜ直し・敵の行動の選択)。start() でシードを与える
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
## 山札 (末尾から引く)
var draw_pile: Array[int] = []
var hand: Array[int] = []
var discard_pile: Array[int] = []
## 使って発動中の加護 (使った順)。この戦闘の終わりまで山札・捨て札に戻らない。同じ加護を 2 枚使うと効果は重なる
var powers: Array[int] = []
## このターンに残っているエネルギー
var energy: int = 0
## 巡礼者の防御 (自分のターンの開始で 0 に戻る)
var block: int = 0
## 敵。各要素は {"id", "name", "hp", "max_hp", "block", "intent": {"move", "value", "hits"(省略可)},
## "next_move": 予告を順に繰り返す敵 (in_order) が次に予告する moves の index}
var enemies: Array[Dictionary] = []
## 何ターン目か (1 始まり)
var turn: int = 0
var outcome: Outcome = Outcome.NONE
## 直前の敵の行動で、巡礼者の防御が受けたダメージの合計 (戦闘画面が数字を見せるためだけの値で、進行には使わない)
var blocked_last_enemy_turn: int = 0
## 直前の操作 (戦闘の開始・カードを使う) で働いた護符の ID (戦闘画面が発動を見せるためだけの値で、進行には使わない。
## 戦闘画面は見せた後に空にする)
var relic_triggers: Array[String] = []
## 直前に使ったカードの攻撃が、生きている敵に当たった 1 回ずつの結果 (当たった順)。各要素は {"target": enemies の
## index, "hit": 何回目の当たりか (0 始まり), "order": 全体攻撃で何体目の敵か (0 始まり), "absorbed": 敵の防御が
## 受けた量, "lost": 減った体力}。戦闘画面が当たりごとの演出を見せるためだけの値で、進行には使わない
var last_play_hits: Array[Dictionary] = []


## 戦闘を始める。state のデッキ全体 (契約切れのカードを含む) から山札を作り、最初のターンを始める。
## 戦闘の始めに効く護符 (防御・最初のターンのエネルギー) は、最初のターンの開始の後に足す (ターンの開始で防御が
## 0 に戻り、エネルギーが戻るため)
func start(state: RunStateScript, enemy_ids: Array[String], seed_value: int) -> void:
	run_state = state
	rng.seed = seed_value
	draw_pile = []
	for index: int in range(run_state.deck.size()):
		draw_pile.append(index)
	_shuffle(draw_pile)
	hand = []
	discard_pile = []
	powers = []
	block = 0
	turn = 0
	outcome = Outcome.NONE
	blocked_last_enemy_turn = 0
	last_play_hits = []
	enemies = []
	for enemy_id: String in enemy_ids:
		var definition: Dictionary = Enemies.ENEMIES[enemy_id]
		var enemy: Dictionary = {
			"id": enemy_id,
			"name": definition["name"],
			"hp": definition["hp"],
			"max_hp": definition["hp"],
			"block": 0,
			"intent": {},
			"next_move": 0,
		}
		enemy["intent"] = _choose_intent(enemy)
		enemies.append(enemy)
	start_turn()
	relic_triggers = []
	if run_state.relics.has("wax_ward"):
		block += Relics.value(run_state.relics, "wax_ward", "block")
		relic_triggers.append("wax_ward")
	if run_state.relics.has("dawn_wick"):
		energy += Relics.value(run_state.relics, "dawn_wick", "energy")
		relic_triggers.append("dawn_wick")


## 巡礼者のターンの開始: エネルギーを energy_per_turn() に戻し、防御を消し、hand_size() 枚引く。発動中の加護の
## 毎ターンの防御・エネルギー・引く枚数は、防御を消した後に足す
func start_turn() -> void:
	turn += 1
	energy = energy_per_turn() + power_total("turn_energy")
	block = power_total("turn_block")
	draw(hand_size() + power_total("turn_draw"))


## 毎ターンの開始で得るエネルギー (基準に契約者の個性 energy_bonus を足す)
func energy_per_turn() -> int:
	return ENERGY_PER_TURN + Contractors.trait_value(run_state.character_id, "energy_bonus")


## 毎ターンの開始で引く枚数 (基準に契約者の個性 hand_bonus を足す)
func hand_size() -> int:
	return HAND_SIZE + Contractors.trait_value(run_state.character_id, "hand_bonus")


## count 枚引く。山札が尽きたら捨て札を混ぜ直す。両方空なら引ける分だけで止める。引いた枚数を返す
func draw(count: int) -> int:
	var drawn: int = 0
	for _i: int in range(count):
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break
			draw_pile = discard_pile
			discard_pile = []
			_shuffle(draw_pile)
		hand.append(draw_pile.pop_back())
		drawn += 1
	return drawn


## 手札の hand_index 番目のカードを使えるか (戦闘が続いていて、エネルギーが足り、契約切れでない)
func can_play(hand_index: int) -> bool:
	if outcome != Outcome.NONE or hand_index < 0 or hand_index >= hand.size():
		return false
	var deck_index: int = hand[hand_index]
	return energy >= run_state.card(deck_index)["cost"] and run_state.can_use(deck_index)


## 手札の hand_index 番目のカードを使う。対象を取るカードは target (enemies の index) の敵を狙い、全体攻撃は
## 生きている敵すべてを狙う。エネルギーを払い、残り使用回数を 1 減らし (焼けぬ封蝋が働いたら減らさない)、効果を
## 出して捨て札へ送る (加護は捨て札へ送らず、発動中の加護に入れる)。ダメージと防御は護符と加護を足した値
## (card_damage()・card_block())。使えなければ false
func play(hand_index: int, target: int = -1) -> bool:
	if not can_play(hand_index):
		return false
	var deck_index: int = hand[hand_index]
	var card_id: String = run_state.deck[deck_index]["id"]
	if Cards.needs_target(card_id) and not is_alive(target):
		return false
	var card: Dictionary = run_state.card(deck_index)
	# 護符の効果は使う前の残り使用回数で決まる (最後の 1 回か・焼けぬ封蝋が効くか) ので、減らす前に読む
	var damage: int = card_damage(deck_index)
	var guard: int = card_block(deck_index)
	relic_triggers = _play_triggers(deck_index)
	if spares_use(deck_index):
		relic_triggers.append("unburnt_seal")
	else:
		run_state.use_card(deck_index)
	energy -= card["cost"]
	hand.remove_at(hand_index)
	if card["kind"] == Cards.Kind.POWER:
		powers.append(deck_index)
	else:
		discard_pile.append(deck_index)
	last_play_hits = []
	if card.has("damage"):
		var targets: Array[int] = [target]
		if card.get("area", false):
			targets = alive_enemies()
		for hit: int in range(card.get("hits", 1)):
			for order: int in range(targets.size()):
				var enemy: Dictionary = enemies[targets[order]]
				var hp_before: int = enemy["hp"]
				var block_before: int = enemy["block"]
				_damage_enemy(targets[order], damage)
				if hp_before > 0:
					last_play_hits.append(
						{
							"target": targets[order],
							"hit": hit,
							"order": order,
							"absorbed": block_before - enemy["block"],
							"lost": hp_before - enemy["hp"],
						}
					)
	if card.has("block"):
		block += guard
	if card.has("energy"):
		energy += card["energy"]
	if card.has("draw"):
		draw(card["draw"])
	_check_win()
	return true


## 基本行動「もがく」: STRUGGLE_COST のエネルギーで target の敵に struggle_damage() を与える。
## 契約を使わないので残り使用回数は減らない。使えなければ false
func struggle(target: int) -> bool:
	if outcome != Outcome.NONE or energy < STRUGGLE_COST or not is_alive(target):
		return false
	relic_triggers = []
	energy -= STRUGGLE_COST
	_damage_enemy(target, struggle_damage())
	_check_win()
	return true


## もがくのダメージ (STRUGGLE_DAMAGE に、発動中の加護のもがくの上乗せを足す)
func struggle_damage() -> int:
	return STRUGGLE_DAMAGE + power_total("struggle_bonus")


## 発動中の加護の key の効果 (Cards.POWER_TURN_POINTS のキー) の合計
func power_total(key: String) -> int:
	var total: int = 0
	for deck_index: int in powers:
		total += run_state.card(deck_index).get(key, 0)
	return total


## ターンを終える: 手札を捨て札へ、敵が予告した行動を実行、次の予告を選び、巡礼者の次のターンを始める。
## 巡礼者の体力が 0 になったら敗北で止まる
func end_turn() -> void:
	if outcome != Outcome.NONE:
		return
	discard_pile.append_array(hand)
	hand = []
	blocked_last_enemy_turn = 0
	relic_triggers = []
	for enemy: Dictionary in enemies:
		if enemy["hp"] <= 0:
			continue
		_act_enemy(enemy)
		if run_state.hp <= 0:
			outcome = Outcome.LOSE
			return
		enemy["intent"] = _choose_intent(enemy)
	start_turn()


## 生きている敵の enemies の index の並び
func alive_enemies() -> Array[int]:
	var alive: Array[int] = []
	for index: int in range(enemies.size()):
		if enemies[index]["hp"] > 0:
			alive.append(index)
	return alive


## target が生きている敵を指しているか
func is_alive(target: int) -> bool:
	return target >= 0 and target < enemies.size() and enemies[target]["hp"] > 0


## デッキの deck_index 番目のカードを今使う時に、焼けぬ封蝋で残り使用回数が減らないか。効くカードの時だけ判定を
## 1 回引き (run_state.relic_rolls を進める)、持っていないか効かないカードなら引かずに false
func spares_use(deck_index: int) -> bool:
	if (
		not run_state.relics.has("unburnt_seal")
		or not Relics.can_spare(run_state.deck[deck_index]["id"], run_state.uses_left(deck_index))
	):
		return false
	var spared: bool = Relics.roll_spare(run_state.map_seed, run_state.relic_rolls)
	run_state.relic_rolls += 1
	return spared


## デッキの deck_index 番目のカードを今使った時の 1 回のダメージ (攻撃でなければ 0)。熾火の刃と、発動中の加護の
## 攻撃の上乗せと、最後の 1 回 (残り 1 回) の時の最後の祈りの分を足す
func card_damage(deck_index: int) -> int:
	var card: Dictionary = run_state.card(deck_index)
	if not card.has("damage"):
		return 0
	var damage: int = (
		card["damage"]
		+ Relics.value(run_state.relics, "ember_edge", "damage")
		+ power_total("attack_bonus")
	)
	if run_state.uses_left(deck_index) == 1:
		damage += Relics.value(run_state.relics, "last_rite", "damage")
	return damage


## デッキの deck_index 番目のカードを今使った時の防御 (防御のカードでなければ 0)。最後の 1 回の時の最後の祈りの
## 分を足す
func card_block(deck_index: int) -> int:
	var card: Dictionary = run_state.card(deck_index)
	if not card.has("block"):
		return 0
	var guard: int = card["block"]
	if run_state.uses_left(deck_index) == 1:
		guard += Relics.value(run_state.relics, "last_rite", "block")
	return guard


## 手札に使えるカードがあるか (もがくとターン終了は常にできるので、無くても詰まない)
func has_playable_card() -> bool:
	for hand_index: int in range(hand.size()):
		if can_play(hand_index):
			return true
	return false


## target の敵に damage を与える。防御が先に受け、残りが体力を減らす
func _damage_enemy(target: int, damage: int) -> void:
	var enemy: Dictionary = enemies[target]
	var absorbed: int = mini(enemy["block"], damage)
	enemy["block"] -= absorbed
	enemy["hp"] = maxi(0, enemy["hp"] - (damage - absorbed))


## 敵が予告した行動を実行する。敵の防御は自分の行動の時に消え、防御の行動で付け直す
func _act_enemy(enemy: Dictionary) -> void:
	enemy["block"] = 0
	var intent: Dictionary = enemy["intent"]
	if intent["move"] == Enemies.Move.ATTACK:
		var damage: int = intent["value"]
		for _i: int in range(intent.get("hits", 1)):
			var absorbed: int = mini(block, damage)
			block -= absorbed
			blocked_last_enemy_turn += absorbed
			run_state.take_damage(damage - absorbed)
	elif intent["move"] == Enemies.Move.GUARD:
		enemy["block"] = intent["value"]


## 敵の次の行動を候補から選ぶ。予告を順に繰り返す敵 (in_order) は moves の順に、それ以外は乱数で選ぶ
func _choose_intent(enemy: Dictionary) -> Dictionary:
	var definition: Dictionary = Enemies.ENEMIES[enemy["id"]]
	var moves: Array = definition["moves"]
	var move_index: int = 0
	if definition.get("in_order", false):
		move_index = enemy["next_move"] % moves.size()
		enemy["next_move"] = move_index + 1
	else:
		move_index = rng.randi_range(0, moves.size() - 1)
	return moves[move_index].duplicate()


## デッキの deck_index 番目のカードを今使う時に、ダメージ・防御に効く護符の ID (焼けぬ封蝋は判定を引くまで
## 分からないので含めない)
func _play_triggers(deck_index: int) -> Array[String]:
	var card: Dictionary = run_state.card(deck_index)
	var triggers: Array[String] = []
	if card.has("damage") and run_state.relics.has("ember_edge"):
		triggers.append("ember_edge")
	var last_use: bool = run_state.uses_left(deck_index) == 1
	if last_use and (card.has("damage") or card.has("block")) and run_state.relics.has("last_rite"):
		triggers.append("last_rite")
	return triggers


## 敵をすべて倒していたら勝利にする
func _check_win() -> void:
	if alive_enemies().is_empty():
		outcome = Outcome.WIN


## 戦闘の乱数で pile を混ぜる (Array.shuffle はグローバルの乱数を使うため使わない)
func _shuffle(pile: Array[int]) -> void:
	for index: int in range(pile.size() - 1, 0, -1):
		var other: int = rng.randi_range(0, index)
		var swapped: int = pile[index]
		pile[index] = pile[other]
		pile[other] = swapped
