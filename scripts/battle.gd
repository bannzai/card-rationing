extends RefCounted
## 1 回の戦闘の状態 (山札・手札・捨て札・エネルギー・防御・敵) と進行。UI なしで呼べる (selfcheck と
## 自動テストプレイが直接使う)。カードの残り使用回数は持たず、RunState (run_state) のものを使って減らす。
## 山札の混ぜ直しと敵の行動の選択の乱数はシード付きで、同じシードなら同じ進行になる。
## 山札・手札・捨て札の要素は run_state.deck の index (同じカードでも別の要素として扱う)。

## 戦闘の結果
enum Outcome { NONE, WIN, LOSE }

const Cards := preload("res://scripts/cards.gd")
const Enemies := preload("res://scripts/enemies.gd")
const RunStateScript := preload("res://scripts/run_state.gd")

## 毎ターンの開始で得るエネルギーと引く枚数。issue #6 の指定 (Slay the Spire 型の定番の値で、手札 5 枚に
## 対してコスト 1 のカードを 3 枚使える比率)。数値は自動テストプレイ (#10) の結果で見直す
const ENERGY_PER_TURN: int = 3
const HAND_SIZE: int = 5
## 常に使える基本行動「もがく」のコストとダメージ (使えるカードが無くても詰まないための行動。
## documents/DIRECTION.md「決めたこと」)。コスト 1 で最弱の攻撃カード (精霊の矢 3) より弱くし、
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
## このターンに残っているエネルギー
var energy: int = 0
## 巡礼者の防御 (自分のターンの開始で 0 に戻る)
var block: int = 0
## 敵。各要素は {"id", "name", "hp", "max_hp", "block", "intent": {"move", "value"}}
var enemies: Array[Dictionary] = []
## 何ターン目か (1 始まり)
var turn: int = 0
var outcome: Outcome = Outcome.NONE


## 戦闘を始める。state のデッキ全体 (契約切れのカードを含む) から山札を作り、最初のターンを始める
func start(state: RunStateScript, enemy_ids: Array[String], seed_value: int) -> void:
	run_state = state
	rng.seed = seed_value
	draw_pile = []
	for index: int in range(run_state.deck.size()):
		draw_pile.append(index)
	_shuffle(draw_pile)
	hand = []
	discard_pile = []
	block = 0
	turn = 0
	outcome = Outcome.NONE
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
		}
		enemy["intent"] = _choose_intent(enemy)
		enemies.append(enemy)
	start_turn()


## 巡礼者のターンの開始: エネルギーを戻し、防御を消し、HAND_SIZE 枚引く
func start_turn() -> void:
	turn += 1
	energy = ENERGY_PER_TURN
	block = 0
	draw(HAND_SIZE)


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


## 手札の hand_index 番目のカードを使う。対象を取るカードは target (enemies の index) の敵を狙う。
## エネルギーを払い、残り使用回数を 1 減らし、効果を出して捨て札へ送る。使えなければ false
func play(hand_index: int, target: int = -1) -> bool:
	if not can_play(hand_index):
		return false
	var deck_index: int = hand[hand_index]
	var card_id: String = run_state.deck[deck_index]["id"]
	if Cards.needs_target(card_id) and not is_alive(target):
		return false
	var card: Dictionary = run_state.card(deck_index)
	run_state.use_card(deck_index)
	energy -= card["cost"]
	hand.remove_at(hand_index)
	discard_pile.append(deck_index)
	if card.has("damage"):
		_damage_enemy(target, card["damage"])
	if card.has("block"):
		block += card["block"]
	if card.has("draw"):
		draw(card["draw"])
	_check_win()
	return true


## 基本行動「もがく」: STRUGGLE_COST のエネルギーで target の敵に STRUGGLE_DAMAGE を与える。
## 契約を使わないので残り使用回数は減らない。使えなければ false
func struggle(target: int) -> bool:
	if outcome != Outcome.NONE or energy < STRUGGLE_COST or not is_alive(target):
		return false
	energy -= STRUGGLE_COST
	_damage_enemy(target, STRUGGLE_DAMAGE)
	_check_win()
	return true


## ターンを終える: 手札を捨て札へ、敵が予告した行動を実行、次の予告を選び、巡礼者の次のターンを始める。
## 巡礼者の体力が 0 になったら敗北で止まる
func end_turn() -> void:
	if outcome != Outcome.NONE:
		return
	discard_pile.append_array(hand)
	hand = []
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
		var absorbed: int = mini(block, damage)
		block -= absorbed
		run_state.take_damage(damage - absorbed)
	elif intent["move"] == Enemies.Move.GUARD:
		enemy["block"] = intent["value"]


## 敵の次の行動を候補から乱数で選ぶ
func _choose_intent(enemy: Dictionary) -> Dictionary:
	var moves: Array = Enemies.ENEMIES[enemy["id"]]["moves"]
	var move: Dictionary = moves[rng.randi_range(0, moves.size() - 1)]
	return move.duplicate()


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
