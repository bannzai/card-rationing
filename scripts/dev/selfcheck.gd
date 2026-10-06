extends "res://scripts/dev/headless_check.gd"
## 純粋なロジックとプロジェクト設定の検証 (headless)。ゲームのルール (カードの残り使用回数・戦闘・マップ・
## イベント) の計算を足したら、ここに検証を足す。実行方法は AGENTS.md「検証方法」を参照。

const RunStateScript := preload("res://scripts/run_state.gd")
const BattleScript := preload("res://scripts/battle.gd")
const Cards := preload("res://scripts/cards.gd")
const Enemies := preload("res://scripts/enemies.gd")

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


## 敵の定義: 2 種類以上あり、体力が 1 以上、行動の候補があり、階層ごとの組み合わせが定義済みの敵だけからなる
func _check_enemies() -> void:
	_check(Enemies.ENEMIES.size() >= 2, "敵が 2 種類以上ある")
	for enemy_id: String in Enemies.ENEMIES:
		var enemy: Dictionary = Enemies.ENEMIES[enemy_id]
		_check(enemy["hp"] >= 1, "体力が 1 以上: %s" % enemy_id)
		_check(not enemy["moves"].is_empty(), "行動の候補がある: %s" % enemy_id)
	_check(not Enemies.ENCOUNTERS.is_empty(), "敵の組み合わせが定義されている")
	for floor_index: int in range(Enemies.ENCOUNTERS.size() + 1):
		var ids: Array[String] = Enemies.encounter_for_floor(floor_index)
		_check(not ids.is_empty(), "階層 %d に敵がいる" % floor_index)
		for enemy_id: String in ids:
			_check(Enemies.ENEMIES.has(enemy_id), "階層 %d の敵が定義済み: %s" % [floor_index, enemy_id])


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
	state.use_card(0)
	state.use_card(0)
	state.use_card(Cards.STARTER_DECK.find("hero_strike"))
	state.take_damage(7)
	state.advance_floor()
	state.gold = 12
	_check(state.save_to(SELFCHECK_SAVE_PATH) == OK, "保存できる")
	_check(
		other.load_from(SELFCHECK_SAVE_PATH) == RunStateScript.LoadResult.LOADED, "保存データを読み込める"
	)
	_check(other.deck == state.deck, "往復で残り使用回数が保たれる")
	_check(other.hp == 43 and other.max_hp == 50, "往復で体力が保たれる")
	_check(other.gold == 12 and other.floor_index == 1 and other.act == 1, "往復で所持金・階層が保たれる")
	_remove_user_file(SELFCHECK_SAVE_PATH)
	state.free()
	other.free()


## 壊れた保存データ (JSON でない・形が合わない) は読み込まずに .corrupt へ退避し、新しいランになる
func _check_corrupt_save() -> void:
	var corrupt_path: String = SELFCHECK_SAVE_PATH + ".corrupt"
	# 全キーが揃った正しい形を土台に、欠陥を 1 つだけ入れる (検査の各分岐を 1 つずつ通す)
	var base: Dictionary = {
		"version": 1, "deck": [], "hp": 1, "max_hp": 1, "gold": 0, "act": 1, "floor_index": 0
	}
	var broken: Array[Dictionary] = [
		{"version": 99},
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
		{"floor_index": -1},
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
	state.free()
	# 上のループが最後に退避した .corrupt が残っているため、読めないデータの検証の前に消す
	_remove_user_file(corrupt_path)
	_check_unreadable_save(corrupt_path)
	_remove_user_file(SELFCHECK_SAVE_PATH)
	_remove_user_file(corrupt_path)


## 読めない保存データ (chmod 000) は READ_ERROR で、退避も状態の変更もしない。chmod が効かない環境
## (Windows、root で実行される CI) では検証を飛ばす
func _check_unreadable_save(corrupt_path: String) -> void:
	var global_path: String = ProjectSettings.globalize_path(SELFCHECK_SAVE_PATH)
	if OS.execute("chmod", ["000", global_path]) != 0:
		print("selfcheck note: chmod が使えないため、読めない保存データの検証を飛ばす")
		return
	var probe: FileAccess = FileAccess.open(SELFCHECK_SAVE_PATH, FileAccess.READ)
	if probe != null:
		probe.close()
		OS.execute("chmod", ["644", global_path])
		print("selfcheck note: chmod 000 でも読めるため (root 等)、読めない保存データの検証を飛ばす")
		return
	var state: RunStateScript = RunStateScript.new()
	state.new_run()
	state.use_card(0)
	var result: RunStateScript.LoadResult = state.load_from(SELFCHECK_SAVE_PATH)
	_check(result == RunStateScript.LoadResult.READ_ERROR, "読めない保存データは READ_ERROR")
	_check(state.uses_left(0) == 3, "READ_ERROR では状態を変えない")
	OS.execute("chmod", ["644", global_path])
	_check(FileAccess.file_exists(SELFCHECK_SAVE_PATH), "読めない保存データは退避されず残る")
	_check(not FileAccess.file_exists(corrupt_path), "読めない保存データは .corrupt を作らない")
	state.free()


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
