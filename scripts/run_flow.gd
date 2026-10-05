extends RefCounted
## ランの局面の移り変わり (巡礼を始める・地図で節点に入る・戦闘を終える・節点を出る) と、その区切りの自動保存。
## 状態は RunState (scripts/run_state.gd) に持ち、局面を変えたら RunState.phase_changed を出す (画面の切り替えは
## scripts/main.gd が受ける)。保存の区切りと戦闘の再開のしかたは documents/DIRECTION.md「決めたこと」:
## 局面が変わるたびに保存し (ランの終わりは保存データを消す)、戦闘中はカードを使うたびとターンの終わりに
## 戦闘画面が保存する。戦闘の途中から再開すると、その節点の戦闘を最初から (敵と山札を配り直して) 始めるが、
## 残り使用回数と体力は保存した値のまま。

const ActMap := preload("res://scripts/act_map.gd")
const Characters := preload("res://scripts/characters.gd")
const Enemies := preload("res://scripts/enemies.gd")
const NodeRules := preload("res://scripts/node_rules.gd")
const RunStateScript := preload("res://scripts/run_state.gd")

## 節点の種類 → 入った時の局面
const KIND_PHASES: Dictionary = {
	ActMap.Kind.BATTLE: RunStateScript.Phase.BATTLE,
	ActMap.Kind.ELITE: RunStateScript.Phase.BATTLE,
	ActMap.Kind.BOSS: RunStateScript.Phase.BATTLE,
	ActMap.Kind.SHRINE: RunStateScript.Phase.SHRINE,
	ActMap.Kind.SHOP: RunStateScript.Phase.SHOP,
	ActMap.Kind.EVENT: RunStateScript.Phase.EVENT,
}
## 戦闘の節点の種類 → 敵の格
const KIND_TIERS: Dictionary = {
	ActMap.Kind.BATTLE: Enemies.Tier.NORMAL,
	ActMap.Kind.ELITE: Enemies.Tier.ELITE,
	ActMap.Kind.BOSS: Enemies.Tier.BOSS,
}
## 節点を出て地図へ戻れる局面
const NODE_PHASES: Array = [
	RunStateScript.Phase.REWARD,
	RunStateScript.Phase.SHRINE,
	RunStateScript.Phase.SHOP,
	RunStateScript.Phase.EVENT,
]


## character_id の契約者で、地図を seed_value から作って新しい巡礼を始める (地図の局面で保存する)
static func start_run(state: RunStateScript, character_id: String, seed_value: int) -> void:
	var deck_ids: Array[String] = []
	deck_ids.assign(Characters.CHARACTERS[character_id]["deck"])
	state.new_run(deck_ids, seed_value)
	state.character_id = character_id
	_change_phase(state, RunStateScript.Phase.MAP)


## 地図で次の段の column 列の節点に入る。地図の局面で、次に選べる列の時だけ入って true を返す
static func enter_node(state: RunStateScript, column: int) -> bool:
	if state.phase != RunStateScript.Phase.MAP:
		return false
	if not ActMap.next_columns(state.rows, state.path).has(column):
		return false
	state.path.append(column)
	state.visit = {}
	_change_phase(state, KIND_PHASES[state.current_node()["kind"]])
	return true


## 今いる節点の戦闘の敵 ID の並び。節点の種類で格を、段で前半 / 後半を決め、節点のシードで選ぶ
## (出発前は最初の段の通常の戦闘として扱う)
static func encounter(state: RunStateScript) -> Array[String]:
	var node: Dictionary = state.current_node()
	var kind: int = node.get("kind", ActMap.Kind.BATTLE)
	var row: int = maxi(0, state.path.size() - 1)
	var tier: Enemies.Tier = KIND_TIERS.get(kind, Enemies.Tier.NORMAL)
	return Enemies.encounter(tier, row >= ActMap.LATE_ROW, state.node_seed())


## 戦闘を終える。負けたら敗北、ボスに勝ったら踏破、ほかの戦闘に勝ったら所持金と体力を受け取って報酬の局面へ。
## 戦闘の局面でなければ何もせず false
static func finish_battle(state: RunStateScript, won: bool) -> bool:
	if state.phase != RunStateScript.Phase.BATTLE:
		return false
	if not won:
		_change_phase(state, RunStateScript.Phase.DEFEAT)
		return true
	state.battles_won += 1
	var kind: int = state.current_node().get("kind", ActMap.Kind.BATTLE)
	if kind == ActMap.Kind.BOSS:
		_change_phase(state, RunStateScript.Phase.CLEAR)
		return true
	state.gold += NodeRules.reward_gold(state.node_seed(), kind)
	state.heal(NodeRules.BATTLE_HEAL)
	_change_phase(state, RunStateScript.Phase.REWARD)
	return true


## 報酬・祠・商人・出来事の節点を出て地図へ戻る。それらの局面でなければ何もせず false
static func leave_node(state: RunStateScript) -> bool:
	if not NODE_PHASES.has(state.phase):
		return false
	state.visit = {}
	_change_phase(state, RunStateScript.Phase.MAP)
	return true


## 局面を phase にして保存し (ランの終わりは保存データを消す)、phase_changed を出す
static func _change_phase(state: RunStateScript, phase: RunStateScript.Phase) -> void:
	state.phase = phase
	if phase == RunStateScript.Phase.DEFEAT or phase == RunStateScript.Phase.CLEAR:
		state.delete_save()
	else:
		var status: Error = state.autosave()
		if status != OK:
			push_error("自動保存に失敗: %s (%s)" % [state.save_path, error_string(status)])
	state.phase_changed.emit()
