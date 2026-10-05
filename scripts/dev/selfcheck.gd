extends "res://scripts/dev/headless_check.gd"
## 純粋なロジックとプロジェクト設定の検証 (headless)。ゲームのルール (カードの残り使用回数・戦闘・マップ・
## イベント) の計算を足したら、ここに検証を足す。実行方法は AGENTS.md「検証方法」を参照。

const ActMap := preload("res://scripts/act_map.gd")
const BattleScript := preload("res://scripts/battle.gd")
const Cards := preload("res://scripts/cards.gd")
const Characters := preload("res://scripts/characters.gd")
const DeckListUiScript := preload("res://scripts/deck_list_ui.gd")
const Enemies := preload("res://scripts/enemies.gd")
const Events := preload("res://scripts/events.gd")
const NodeRules := preload("res://scripts/node_rules.gd")
const RunFlow := preload("res://scripts/run_flow.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const SettingsScript := preload("res://scripts/settings.gd")

## 起動検証 (main_scene の --quit) ではロードされない遷移先も含めた全シーン
const SCENES: Array[String] = [
	"res://scenes/main.tscn",
	"res://scenes/battle.tscn",
]
## 起動時に表示するシーン
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
## ADR 0001 で決めたレンダラ (CI の Xvfb + Mesa llvmpipe で描画できるもの)
const RENDERING_METHOD: String = "gl_compatibility"
## 保存と読み込みの検証に使う保存先 (本番の RunState.SAVE_PATH とは別)
const SELFCHECK_SAVE_PATH: String = "user://selfcheck_save.json"
## 設定の保存と読み込みの検証に使う保存先 (本番の Settings.SETTINGS_PATH とは別)
const SELFCHECK_SETTINGS_PATH: String = "user://selfcheck_settings.cfg"
## 地図の生成の制約を確かめるシードの数 (シード 1〜MAP_SEEDS。issue #7 が例に挙げた 100 個)
const MAP_SEEDS: int = 100


## すべての検証を順に行い、結果を exit code と「selfcheck OK」の行で返して終える (シーンを tree に置かないため
## _initialize() の中で完結する)
func _initialize() -> void:
	_check_project_settings()
	_check_scenes_load()
	_check_cards()
	_check_enemies()
	_check_run_state_uses()
	_check_save_and_load()
	_check_corrupt_save()
	_check_battle_turn()
	_check_battle_outcomes()
	_check_battle_keeps_uses()
	_check_draw_with_small_deck()
	_check_exhausted_deck_battle()
	_check_map_generation()
	_check_run_flow()
	_check_battle_rewards()
	_check_shrine()
	_check_shop()
	_check_events()
	_check_deck_sort()
	_check_settings()
	# Makefile の WARNING / ERROR 検査が行頭の接頭辞だけを見ることの回帰検査 (この行で落ちてはいけない)
	print("selfcheck note: a normal line may mention error and warning words")
	_finish()


## project.godot の起動シーンとレンダラが ADR 0001 のとおりか (起動シーンが uid:// で保存されていてもパスで比べる)
func _check_project_settings() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	_check(
		ResourceUID.ensure_path(main_scene) == MAIN_SCENE_PATH,
		"起動シーンが %s (設定値: %s)" % [MAIN_SCENE_PATH, main_scene]
	)
	_check(
		ProjectSettings.get_setting("rendering/renderer/rendering_method") == RENDERING_METHOD,
		"レンダラが %s" % RENDERING_METHOD
	)


## SCENES のすべてがロードでき、インスタンス化できるか。インスタンスは tree に入れないため検証後に free する
func _check_scenes_load() -> void:
	for path: String in SCENES:
		var packed: PackedScene = load(path)
		_check(packed != null, "シーンのロード: %s" % path)
		if packed == null:
			continue
		var node: Node = packed.instantiate()
		_check(node != null, "シーンのインスタンス化: %s" % path)
		if node != null:
			node.free()


## カードの定義: 1 枚以上あり、最大使用回数が 1 以上、種別が揃い、初期デッキが定義済みのカードだけからなる
func _check_cards() -> void:
	_check(Cards.CARDS.size() >= 1, "カードが 1 枚以上ある")
	var kinds: Dictionary = {}
	for card_id: String in Cards.CARDS:
		var card: Dictionary = Cards.CARDS[card_id]
		_check(card["max_uses"] >= 1, "最大使用回数が 1 以上: %s" % card_id)
		_check(card["cost"] >= 0, "コストが 0 以上: %s" % card_id)
		_check(not card["name"].is_empty(), "名前がある: %s" % card_id)
		_check(
			card.has("damage") or card.has("block") or card.has("draw"), "効果がある: %s" % card_id
		)
		_check(not Cards.effect_text(card_id).is_empty(), "効果の文がある: %s" % card_id)
		# battle.play() は対象の有無を needs_target で、ダメージの適用を damage の有無で見るため、両者を一致させる
		_check(card.has("damage") == Cards.needs_target(card_id), "ダメージを持つのは攻撃だけ: %s" % card_id)
		kinds[card["kind"]] = true
	for kind: int in [Cards.Kind.ATTACK, Cards.Kind.GUARD, Cards.Kind.SKILL]:
		_check(kinds.has(kind), "種別 %d のカードがある" % kind)
	_check(not Cards.STARTER_DECK.is_empty(), "初期デッキが定義されている")
	var has_target_attack: bool = false
	var has_single_use: bool = false
	for card_id: String in Cards.STARTER_DECK:
		_check(Cards.CARDS.has(card_id), "初期デッキのカードが定義済み: %s" % card_id)
		if not Cards.CARDS.has(card_id):
			continue
		has_target_attack = has_target_attack or Cards.needs_target(card_id)
		has_single_use = has_single_use or Cards.CARDS[card_id]["max_uses"] == 1
	_check(has_target_attack, "初期デッキに対象を選ぶ攻撃がある")
	_check(has_single_use, "初期デッキに最大使用回数 1 のカードがある")


## 敵の定義: 2 種類以上あり、体力が 1 以上、行動の候補があり、格と前半 / 後半ごとの組み合わせの候補が
## 定義済みの敵だけからなり、同じシードなら同じ組み合わせを選ぶ
func _check_enemies() -> void:
	_check(Enemies.ENEMIES.size() >= 2, "敵が 2 種類以上ある")
	for enemy_id: String in Enemies.ENEMIES:
		var enemy: Dictionary = Enemies.ENEMIES[enemy_id]
		_check(enemy["hp"] >= 1, "体力が 1 以上: %s" % enemy_id)
		_check(not enemy["moves"].is_empty(), "行動の候補がある: %s" % enemy_id)
	for tier: Enemies.Tier in [Enemies.Tier.NORMAL, Enemies.Tier.ELITE, Enemies.Tier.BOSS]:
		for late: bool in [false, true]:
			var pool: Array = Enemies.candidates(tier, late)
			_check(not pool.is_empty(), "格 %d (後半 %s) の組み合わせがある" % [tier, late])
			for ids: Array in pool:
				_check(not ids.is_empty(), "格 %d の組み合わせに敵がいる" % tier)
				for enemy_id: String in ids:
					_check(Enemies.ENEMIES.has(enemy_id), "格 %d の敵が定義済み: %s" % [tier, enemy_id])
			var first_pick: Array[String] = Enemies.encounter(tier, late, 42)
			var second_pick: Array[String] = Enemies.encounter(tier, late, 42)
			_check(first_pick == second_pick, "同じシードなら同じ組み合わせ (格 %d)" % tier)


## 残り使用回数: 使うと 1 減り、0 (契約切れ) では使えず、回復で戻る (最大を超えない)。体力は 0 未満にならない
func _check_run_state_uses() -> void:
	var state: RunStateScript = RunStateScript.new()
	state.new_run()
	_check(state.deck.size() == Cards.STARTER_DECK.size(), "新しいランのデッキが初期デッキと同じ枚数")
	var single: int = Cards.STARTER_DECK.find("hero_strike")
	var slash: int = Cards.STARTER_DECK.find("slash")
	_check(state.uses_left(single) == 1 and state.can_use(single), "最大使用回数 1 のカードが使える")
	_check(state.use_card(single), "使うと true")
	_check(state.uses_left(single) == 0 and not state.can_use(single), "残り 0 で契約切れ (使えない)")
	_check(not state.use_card(single), "契約切れのカードは使えず false")
	_check(state.uses_left(single) == 0, "契約切れのカードを使おうとしても減らない")
	_check(state.restore_uses(single, 1) == 1 and state.can_use(single), "1 回の回復で使えるようになる")
	_check(state.use_card(slash) and state.use_card(slash), "斬撃を 2 回使える")
	_check(state.uses_left(slash) == 2, "斬撃の残りが 2")
	_check(state.restore_uses(slash, 1) == 3, "1 回の回復で 3")
	_check(state.restore_uses(slash, 99) == 4, "回復は最大使用回数を超えない")
	_check(state.restore_uses(slash) == 4, "回数を省いた回復は最大まで戻す")
	state.take_damage(10)
	_check(state.hp == 40, "10 のダメージで体力 40")
	state.take_damage(100)
	_check(state.hp == 0, "体力は 0 未満にならない")
	state.free()


## 保存と読み込みの往復で残り使用回数・体力・階層が保たれ、無い保存先は NOT_FOUND で状態を変えない
func _check_save_and_load() -> void:
	_remove_user_file(SELFCHECK_SAVE_PATH)
	var state: RunStateScript = RunStateScript.new()
	state.new_run()
	var other: RunStateScript = RunStateScript.new()
	other.new_run()
	_check(
		other.load_from(SELFCHECK_SAVE_PATH) == RunStateScript.LoadResult.NOT_FOUND,
		"無い保存先は NOT_FOUND"
	)
	_check(other.deck == state.deck, "NOT_FOUND では状態を変えない")
	state.new_run([], 7)
	state.use_card(0)
	state.use_card(0)
	state.use_card(Cards.STARTER_DECK.find("hero_strike"))
	state.take_damage(7)
	state.path.append(ActMap.next_columns(state.rows, state.path)[0])
	state.phase = RunStateScript.Phase.BATTLE
	state.gold = 12
	state.battles_won = 2
	_check(state.save_to(SELFCHECK_SAVE_PATH) == OK, "保存できる")
	_check(
		other.load_from(SELFCHECK_SAVE_PATH) == RunStateScript.LoadResult.LOADED, "保存データを読み込める"
	)
	_check(other.deck == state.deck, "往復で残り使用回数が保たれる")
	_check(other.hp == 43 and other.max_hp == 50, "往復で体力が保たれる")
	_check(other.gold == 12 and other.act == 1, "往復で所持金・幕が保たれる")
	_check(other.map_seed == 7 and other.rows == state.rows, "往復で地図 (シード) が保たれる")
	_check(other.path == state.path and other.phase == state.phase, "往復で通った道と局面が保たれる")
	_check(other.exhausted_count == 1 and other.battles_won == 2, "往復でランの結果の数が保たれる")
	_check(other.character_id == Characters.DEFAULT_CHARACTER, "往復で契約者が保たれる")
	_remove_user_file(SELFCHECK_SAVE_PATH)
	state.free()
	other.free()


## 壊れた保存データ (JSON でない・形が合わない) は読み込まずに .corrupt へ退避し、新しいランになる
func _check_corrupt_save() -> void:
	var corrupt_path: String = SELFCHECK_SAVE_PATH + ".corrupt"
	# 全キーが揃った正しい形を土台に、欠陥を 1 つだけ入れる (検査の各分岐を 1 つずつ通す)
	var base: Dictionary = {
		"version": RunStateScript.SAVE_VERSION,
		"character_id": Characters.DEFAULT_CHARACTER,
		"deck": [],
		"hp": 1,
		"max_hp": 1,
		"gold": 0,
		"act": 1,
		"map_seed": 0,
		"path": [],
		"phase": RunStateScript.Phase.MAP,
		"exhausted_count": 0,
		"battles_won": 0,
	}
	# シード 0 の地図の段 0 の最初の列 (戦闘) と、そこから行けない列
	var rows: Array = ActMap.generate(0)
	var first: int = rows[0][0]["column"]
	var unreachable: int = -1
	var no_path: Array[int] = []
	for column: int in range(ActMap.COLUMNS):
		if not ActMap.next_columns(rows, no_path).has(column):
			unreachable = column
	var broken: Array[Dictionary] = [
		{"version": 1},
		{"version": []},
		{"hp": "x"},
		{"hp": 1.5},
		{"gold": 123456.5},
		{"gold": 1e20},
		{"hp": 2},
		{"hp": -1},
		{"max_hp": 0},
		{"gold": -1},
		{"act": 0},
		{"exhausted_count": -1},
		{"battles_won": -1},
		{"character_id": "nope"},
		{"character_id": 1},
		{"map_seed": 0.5},
		{"path": "x"},
		{"path": [0.5]},
		{"path": [first, 99]},
		{"path": [unreachable]},
		{"phase": 99},
		{"phase": RunStateScript.Phase.DEFEAT},
		{"phase": RunStateScript.Phase.BATTLE},
		{"path": [first], "phase": RunStateScript.Phase.SHOP},
		{"deck": "x"},
		{"deck": [1]},
		{"deck": [{"id": "nope", "uses_left": 1}]},
		{"deck": [{"id": "slash", "uses_left": 99}]},
		{"deck": [{"id": "slash", "uses_left": -1}]},
		{"deck": [{"id": "slash"}]},
	]
	var texts: Array[String] = ["{not json", '{"version": 1, "deck": "x"}']
	for defect: Dictionary in broken:
		var data: Dictionary = base.duplicate(true)
		data.merge(defect, true)
		texts.append(JSON.stringify(data))
	for text: String in texts:
		_remove_user_file(SELFCHECK_SAVE_PATH)
		_remove_user_file(corrupt_path)
		var file: FileAccess = FileAccess.open(SELFCHECK_SAVE_PATH, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		var state: RunStateScript = RunStateScript.new()
		state.new_run()
		state.use_card(0)
		_check(
			state.load_from(SELFCHECK_SAVE_PATH) == RunStateScript.LoadResult.CORRUPT,
			"壊れた保存データは CORRUPT: %s" % text
		)
		_check(not FileAccess.file_exists(SELFCHECK_SAVE_PATH), "壊れた保存データは元の場所に残らない")
		_check(FileAccess.file_exists(corrupt_path), "壊れた保存データは .corrupt へ退避される")
		_check(state.uses_left(0) == Cards.CARDS["slash"]["max_uses"], "壊れた保存データの後は新しいラン")
		state.free()
	# 欠陥の無い土台はそのまま読み込める (上の検査が壊れたデータだけを弾いていることの対照)
	var file: FileAccess = FileAccess.open(SELFCHECK_SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(base))
	file.close()
	var state: RunStateScript = RunStateScript.new()
	_check(state.load_from(SELFCHECK_SAVE_PATH) == RunStateScript.LoadResult.LOADED, "土台の保存データは読み込める")
	_check(state.hp == 1 and state.deck.is_empty(), "土台の保存データの値が入る")
	# 段 0 の戦闘の節点で戦闘の局面にいる保存データも読み込める
	var in_battle: Dictionary = base.duplicate(true)
	in_battle.merge({"path": [first], "phase": RunStateScript.Phase.BATTLE}, true)
	file = FileAccess.open(SELFCHECK_SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(in_battle))
	file.close()
	_check(state.load_from(SELFCHECK_SAVE_PATH) == RunStateScript.LoadResult.LOADED, "戦闘中の保存データは読み込める")
	_check(
		state.path.size() == 1 and state.path[0] == first and state.phase == RunStateScript.Phase.BATTLE,
		"戦闘中の局面と道が入る"
	)
	state.free()
	_remove_user_file(SELFCHECK_SAVE_PATH)
	_remove_user_file(corrupt_path)


## 1 ターンの流れ: ドロー・エネルギー・攻撃 (防御が先に受ける)・防御・ドローの効果・混ぜ直し・敵の行動
func _check_battle_turn() -> void:
	var state: RunStateScript = RunStateScript.new()
	state.new_run(["slash", "guard", "breath", "spirit_arrow", "hero_strike"])
	var battle: BattleScript = BattleScript.new()
	battle.start(state, ["wild_dog"], 1)
	_check(battle.hand.size() == 5 and battle.draw_pile.is_empty(), "開始時に 5 枚引く")
	_check(battle.energy == 3 and battle.turn == 1, "開始時のエネルギー 3・ターン 1")
	_check(battle.enemies.size() == 1 and battle.enemies[0]["hp"] == 14, "野犬の体力 14")
	battle.enemies[0]["block"] = 4
	_check(battle.play(_hand_index_of(battle, state, "slash"), 0), "斬撃を使える")
	_check(battle.enemies[0]["hp"] == 12 and battle.enemies[0]["block"] == 0, "防御 4 が先に受けて体力 12")
	_check(battle.energy == 2 and state.uses_left(0) == 3, "コスト 1 を払い残り使用回数が 3")
	var deck_before_struggle: Array[Dictionary] = state.deck.duplicate(true)
	_check(battle.struggle(0) and battle.enemies[0]["hp"] == 10, "もがくで 2 ダメージ")
	_check(state.deck == deck_before_struggle, "もがくは残りのあるカードの残り使用回数も減らさない")
	_check(battle.energy == 1, "もがくのコスト 1")
	battle.energy = 2
	_check(battle.hand.size() == 4 and battle.discard_pile.size() == 1, "使ったカードは捨て札へ")
	_check(battle.play(_hand_index_of(battle, state, "guard")), "守りを使える")
	_check(battle.block == 5 and battle.energy == 1, "防御 5・エネルギー 1")
	_check(not battle.can_play(_hand_index_of(battle, state, "hero_strike")), "コスト 2 は払えない")
	_check(battle.play(_hand_index_of(battle, state, "breath")), "深呼吸を使える")
	_check(battle.hand.size() == 4 and battle.discard_pile.is_empty(), "捨て札を混ぜ直して 2 枚引く")
	_check(battle.play(_hand_index_of(battle, state, "spirit_arrow"), 0), "精霊の矢を使える")
	_check(battle.enemies[0]["hp"] == 7, "体力 7")
	# 予告を固定して、防御 5 を超えた攻撃 7 の分だけ体力が減ることを確かめる
	battle.enemies[0]["intent"] = {"move": Enemies.Move.ATTACK, "value": 7}
	battle.end_turn()
	_check(state.hp == 48, "攻撃 7 を防御 5 が受けて体力が 2 減る")
	_check(battle.turn == 2 and battle.energy == 3 and battle.block == 0, "次のターン: エネルギー 3・防御 0")
	battle.enemies[0]["intent"] = {"move": Enemies.Move.GUARD, "value": 4}
	battle.end_turn()
	_check(state.hp == 48 and battle.enemies[0]["block"] == 4, "予告どおりに防御する (体力は減らない)")
	_check(battle.hand.size() == 5 and battle.discard_pile.is_empty(), "手札を捨てて 5 枚引く")
	state.free()


## 勝敗: 敵をすべて倒したら勝利、体力 0 で敗北。勝利の後の戦闘は残り使用回数を引き継ぐ (同じシードで同じ進行)
func _check_battle_outcomes() -> void:
	var state: RunStateScript = RunStateScript.new()
	state.new_run(["hero_strike", "guard"])
	var battle: BattleScript = BattleScript.new()
	battle.start(state, ["wild_dog"], 2)
	_check(battle.play(_hand_index_of(battle, state, "hero_strike"), 0), "英霊の一閃を使える")
	_check(battle.outcome == BattleScript.Outcome.WIN, "敵を倒して勝利")
	_check(not battle.play(_hand_index_of(battle, state, "guard")), "勝利の後はカードを使えない")
	_check(not battle.struggle(0), "勝利の後はもがけない")
	var replay: BattleScript = BattleScript.new()
	var replay_state: RunStateScript = RunStateScript.new()
	replay_state.new_run()
	replay.start(replay_state, ["wild_dog", "skeleton"], 2)
	var again: BattleScript = BattleScript.new()
	again.start(replay_state, ["wild_dog", "skeleton"], 2)
	_check(replay.hand == again.hand, "同じシードなら同じ並びで引く")
	_check(replay.enemies == again.enemies, "同じシードなら同じ行動を予告する")
	state.new_run(["guard"])
	state.take_damage(49)
	battle.start(state, ["wild_dog", "skeleton"], 3)
	for _i: int in range(10):
		if battle.outcome != BattleScript.Outcome.NONE:
			break
		battle.end_turn()
	_check(battle.outcome == BattleScript.Outcome.LOSE and state.hp == 0, "体力 0 で敗北")
	state.free()
	replay_state.free()


## 戦闘の開始・終了で残り使用回数が初期化されない (.claude/rules/card-uses-persist-across-run.md)
func _check_battle_keeps_uses() -> void:
	var state: RunStateScript = RunStateScript.new()
	state.new_run()
	state.use_card(0)
	var battle: BattleScript = BattleScript.new()
	battle.start(state, ["wild_dog"], 4)
	_check(state.uses_left(0) == 3, "戦闘の開始で残り使用回数が戻らない")
	battle.end_turn()
	_check(state.uses_left(0) == 3, "ターンの終了で残り使用回数が戻らない")
	var before: Array[Dictionary] = state.deck.duplicate(true)
	battle.start(state, ["wild_dog"], 5)
	_check(state.deck == before, "次の戦闘の開始でも残り使用回数が戻らない")
	state.free()


## 山札と捨て札が両方空の時のドローは、引ける分だけ引いて止まる (デッキが 5 枚未満でも落ちない)
func _check_draw_with_small_deck() -> void:
	var state: RunStateScript = RunStateScript.new()
	state.new_run(["slash", "guard", "breath"])
	var battle: BattleScript = BattleScript.new()
	battle.start(state, ["wild_dog"], 6)
	_check(battle.hand.size() == 3, "3 枚のデッキでは 3 枚だけ引く")
	_check(battle.draw(5) == 0 and battle.hand.size() == 3, "両方空なら 0 枚")
	state.free()


## デッキの全カードが契約切れでも、もがくとターン終了で戦闘が勝敗まで進む (詰まない)
func _check_exhausted_deck_battle() -> void:
	var state: RunStateScript = RunStateScript.new()
	state.new_run(["slash", "guard", "breath"])
	for index: int in range(state.deck.size()):
		while state.use_card(index):
			pass
	var battle: BattleScript = BattleScript.new()
	battle.start(state, ["wild_dog"], 7)
	_check(battle.hand.size() == 3, "契約切れのカードも手札に来る")
	_check(not battle.has_playable_card() and not battle.can_play(0), "契約切れのカードは使えない")
	_check(not battle.play(0, 0), "契約切れのカードを使おうとしても false")
	_check(battle.struggle(0), "もがける")
	_check(battle.enemies[0]["hp"] == 12 and battle.energy == 2, "もがくで 2 ダメージ・コスト 1")
	var steps: int = 0
	while battle.outcome == BattleScript.Outcome.NONE and steps < EXHAUSTED_BATTLE_STEP_LIMIT:
		if not battle.struggle(0):
			battle.end_turn()
		steps += 1
	_check(battle.outcome != BattleScript.Outcome.NONE, "契約切れだけのデッキでも勝敗まで進む")
	state.free()


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
	RunFlow.start_run(state, Characters.DEFAULT_CHARACTER, 11)
	_check(state.phase == RunStateScript.Phase.MAP and state.path.is_empty(), "巡礼の開始は出発前の地図")
	_check(state.map_seed == 11 and state.rows == ActMap.generate(11), "巡礼の開始で地図をシードから作る")
	_check(state.deck.size() == Cards.STARTER_DECK.size(), "巡礼の開始は契約者の初期デッキ")
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
		Enemies.candidates(Enemies.Tier.NORMAL, false).has(RunFlow.encounter(state)),
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
		Enemies.candidates(Enemies.Tier.ELITE, false).has(RunFlow.encounter(elite)), "強敵の節点は強敵"
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
		Enemies.candidates(Enemies.Tier.NORMAL, true).has(RunFlow.encounter(late)),
		"後半の戦闘は後半の通常の敵"
	)
	_check(RunFlow.finish_battle(late, false), "負けて戦闘を終えられる")
	_check(late.phase == RunStateScript.Phase.DEFEAT, "負けると敗北")
	_check(not FileAccess.file_exists(SELFCHECK_SAVE_PATH), "敗北で保存データを消す")
	late.free()
	var boss: RunStateScript = _state_at(ActMap.Kind.BOSS, 11)
	_check(Enemies.candidates(Enemies.Tier.BOSS, false).has(RunFlow.encounter(boss)), "ボスの節点はボス")
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
	_check(Events.choose(state, 1, none) and state.uses_left(0) == 3, "立ち去っても何も変わらない")
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


## 契約の一覧の並べ方: 強さ順は英霊が先で最大使用回数の少ない順、残り回数順は残りの少ない順
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


## battle の手札の中で card_id のカードがある位置 (無ければ -1)
func _hand_index_of(battle: BattleScript, state: RunStateScript, card_id: String) -> int:
	for hand_index: int in range(battle.hand.size()):
		if state.deck[battle.hand[hand_index]]["id"] == card_id:
			return hand_index
	return -1


## user:// のファイルを消す (無ければ何もしない)
func _remove_user_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.open(path.get_base_dir()).remove(path.get_file())
