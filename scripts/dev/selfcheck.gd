extends "res://scripts/dev/headless_check.gd"
## 純粋なロジックとプロジェクト設定の検証 (headless)。ゲームのルール (カードの残り使用回数・戦闘・マップ・
## イベント) の計算を足したら、ここに検証を足す。実行方法は AGENTS.md「検証方法」を参照。

const RunStateScript := preload("res://scripts/run_state.gd")
const BattleScript := preload("res://scripts/battle.gd")
const Cards := preload("res://scripts/cards.gd")
const Contractors := preload("res://scripts/contractors.gd")
const Enemies := preload("res://scripts/enemies.gd")

## 起動検証 (main_scene の --quit) ではロードされない遷移先も含めた全シーン
const SCENES: Array[String] = [
	"res://scenes/main.tscn",
	"res://scenes/battle.tscn",
	"res://scenes/boss_talk.tscn",
]
## 1 幕の中身の量 (issue #9 の指定): カードの種類の数・敵の格ごとの種類の数・ボスの台詞の行数・初期デッキの枚数
const CARD_COUNT_RANGE: Array[int] = [25, 30]
const RANK_COUNT_RANGES: Dictionary = {
	Enemies.Rank.NORMAL: [6, 8], Enemies.Rank.ELITE: [2, 2], Enemies.Rank.BOSS: [1, 1]
}
const TALK_LINES_RANGE: Array[int] = [2, 4]
const STARTER_DECK_SIZE_RANGE: Array[int] = [8, 12]
## 初期デッキの英霊の枚数の上限 (初期デッキは弱いが回数の多い精霊を中心にする)
const STARTER_HERO_LIMIT: int = 2
## 全カードに占める種別ごとの割合の範囲 (どの種別も 2 割以上・5 割以下)
const KIND_SHARE_RANGE: Array[float] = [0.2, 0.5]
## カードの定義の値の範囲 (キー → [最小, 最大])。最大使用回数は区分ごとの BOND_USES_RANGES でも絞る
const CARD_VALUE_RANGES: Dictionary = {
	"cost": [0, 3],
	"max_uses": [1, 6],
	"damage": [1, 30],
	"hits": [1, 4],
	"block": [1, 30],
	"draw": [1, 3],
	"energy": [1, 3],
}
## 契約の相手の区分ごとの最大使用回数の範囲 (精霊は回数が多め、英霊は少ない)
const BOND_USES_RANGES: Dictionary = {Cards.Bond.SPIRIT: [2, 6], Cards.Bond.HERO: [1, 2]}
## 敵の体力と、行動の値・回数の範囲
const ENEMY_HP_RANGE: Array[int] = [1, 300]
const MOVE_VALUE_RANGE: Array[int] = [1, 40]
const MOVE_HITS_RANGE: Array[int] = [1, 5]
## 短い文言 (カード・敵・契約者の名前、カードの効果の文) に使わない句読点
## (~/.claude/rules/coding-rules-general-user-facing-short-copy-punctuation.md)
const SHORT_COPY_PUNCTUATION: Array[String] = ["、", "。", "，", "．"]
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
	_check_strength_and_uses()
	_check_contractors()
	_check_enemies()
	_check_encounters()
	_check_run_state_uses()
	_check_save_and_load()
	_check_corrupt_save()
	_check_battle_turn()
	_check_battle_effects()
	_check_enemy_intent_order()
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


## カードの定義: 種類の数・各値の範囲・区分ごとの最大使用回数・種別の割合・名前と効果の文、効果のキーと種別の対応
func _check_cards() -> void:
	_check(_in_range(Cards.CARDS.size(), CARD_COUNT_RANGE), "カードが 25〜30 種")
	var kind_counts: Dictionary = {}
	for card_id: String in Cards.CARDS:
		var card: Dictionary = Cards.CARDS[card_id]
		for key: String in CARD_VALUE_RANGES:
			if card.has(key):
				_check(_in_range(card[key], CARD_VALUE_RANGES[key]), "%s が範囲内: %s" % [key, card_id])
		_check(
			_in_range(card["max_uses"], BOND_USES_RANGES[card["bond"]]),
			"最大使用回数が区分の範囲内: %s" % card_id
		)
		_check(not card["name"].is_empty(), "名前がある: %s" % card_id)
		_check(
			card.has("damage") or card.has("block") or card.has("draw") or card.has("energy"),
			"効果がある: %s" % card_id
		)
		_check(not Cards.effect_text(card_id).is_empty(), "効果の文がある: %s" % card_id)
		_check(
			_is_short_copy(card["name"]) and _is_short_copy(Cards.effect_text(card_id)),
			"名前と効果の文に句読点が無い: %s" % card_id
		)
		# battle.play() はダメージの適用を damage の有無で、対象の有無を needs_target で見る。攻撃だけがダメージを持ち、
		# hits と area はダメージの付け足しなので攻撃だけが持つ
		var attack: bool = card["kind"] == Cards.Kind.ATTACK
		_check(card.has("damage") == attack, "ダメージを持つのは攻撃だけで、攻撃はすべて持つ: %s" % card_id)
		_check(attack or not (card.has("hits") or card.has("area")), "hits と area は攻撃だけ: %s" % card_id)
		_check(
			Cards.needs_target(card_id) == (attack and not card.get("area", false)),
			"全体攻撃でない攻撃だけが対象を取る: %s" % card_id
		)
		kind_counts[card["kind"]] = kind_counts.get(card["kind"], 0) + 1
	for kind: int in [Cards.Kind.ATTACK, Cards.Kind.GUARD, Cards.Kind.SKILL]:
		var share: float = float(kind_counts.get(kind, 0)) / Cards.CARDS.size()
		_check(
			share >= KIND_SHARE_RANGE[0] and share <= KIND_SHARE_RANGE[1],
			"種別 %d のカードの割合が 2〜5 割 (%.2f)" % [kind, share]
		)
	# 強さの定義 (documents/DIRECTION.md「決めたこと」) の基準のカードと、全体攻撃・引く・エネルギーの点数
	_check(is_equal_approx(Cards.strength("slash"), 3.0), "斬火の強さが 3")
	_check(is_equal_approx(Cards.strength("hero_strike"), 6.0), "雷槍の英霊の強さが 6")
	_check(is_equal_approx(Cards.strength("ember_wave"), 3.0), "熾火の波 (全体攻撃 4) の強さが 3")
	_check(is_equal_approx(Cards.strength("lantern_row"), 4.5), "灯の連なり (2 枚引く + エネルギー 1) の強さが 4.5")


## 強さと最大使用回数の関係: 同じ種別の中で、強さが高いカードほど最大使用回数が多くならない (強さが同じなら
## 制約しない)。同じ種別の英霊はどの精霊よりも強い
func _check_strength_and_uses() -> void:
	for stronger: String in Cards.CARDS:
		for weaker: String in Cards.CARDS:
			var a: Dictionary = Cards.CARDS[stronger]
			var b: Dictionary = Cards.CARDS[weaker]
			if a["kind"] != b["kind"]:
				continue
			if Cards.strength(stronger) > Cards.strength(weaker):
				_check(
					a["max_uses"] <= b["max_uses"],
					"強い %s の最大使用回数が弱い %s 以下" % [stronger, weaker]
				)
			if a["bond"] == Cards.Bond.HERO and b["bond"] == Cards.Bond.SPIRIT:
				_check(
					Cards.strength(stronger) > Cards.strength(weaker),
					"英霊 %s が同じ種別の精霊 %s より強い" % [stronger, weaker]
				)


## 契約者の定義: 名前と設定があり、初期デッキが 8〜12 枚で定義済みのカードだけからなり、英霊が 2 枚以下で、
## 対象を選ぶ攻撃と最大使用回数 1 のカードを含む
func _check_contractors() -> void:
	_check(Contractors.CONTRACTORS.has(Contractors.FIRST_CONTRACTOR), "最初の契約者が定義済み")
	for contractor_id: String in Contractors.CONTRACTORS:
		var contractor: Dictionary = Contractors.CONTRACTORS[contractor_id]
		_check(
			not contractor["name"].is_empty() and _is_short_copy(contractor["name"]),
			"契約者の名前があり句読点が無い: %s" % contractor_id
		)
		_check(not contractor["story"].is_empty(), "契約者の設定がある: %s" % contractor_id)
		var deck: Array[String] = Contractors.starter_deck(contractor_id)
		_check(_in_range(deck.size(), STARTER_DECK_SIZE_RANGE), "初期デッキが 8〜12 枚: %s" % contractor_id)
		var heroes: int = 0
		var has_target_attack: bool = false
		var has_single_use: bool = false
		for card_id: String in deck:
			_check(Cards.CARDS.has(card_id), "初期デッキのカードが定義済み: %s" % card_id)
			if not Cards.CARDS.has(card_id):
				continue
			if Cards.CARDS[card_id]["bond"] == Cards.Bond.HERO:
				heroes += 1
			has_target_attack = has_target_attack or Cards.needs_target(card_id)
			has_single_use = has_single_use or Cards.CARDS[card_id]["max_uses"] == 1
		_check(heroes <= STARTER_HERO_LIMIT, "初期デッキの英霊が 2 枚以下: %s" % contractor_id)
		_check(has_target_attack, "初期デッキに対象を選ぶ攻撃がある: %s" % contractor_id)
		_check(has_single_use, "初期デッキに最大使用回数 1 のカードがある: %s" % contractor_id)


## 敵の定義: 格ごとの種類の数、名前、体力と行動の値の範囲、会話の台詞を持つのはボスだけで 2〜4 行
func _check_enemies() -> void:
	var rank_counts: Dictionary = {}
	for enemy_id: String in Enemies.ENEMIES:
		var enemy: Dictionary = Enemies.ENEMIES[enemy_id]
		_check(
			not enemy["name"].is_empty() and _is_short_copy(enemy["name"]),
			"敵の名前があり句読点が無い: %s" % enemy_id
		)
		_check(_in_range(enemy["hp"], ENEMY_HP_RANGE), "体力が範囲内: %s" % enemy_id)
		_check(not enemy["moves"].is_empty(), "行動の候補がある: %s" % enemy_id)
		for move: Dictionary in enemy["moves"]:
			var attack: bool = move["move"] == Enemies.Move.ATTACK
			_check(attack or move["move"] == Enemies.Move.GUARD, "行動の種別が定義済み: %s" % enemy_id)
			_check(_in_range(move["value"], MOVE_VALUE_RANGE), "行動の値が範囲内: %s" % enemy_id)
			_check(_in_range(move.get("hits", 1), MOVE_HITS_RANGE), "攻撃の回数が範囲内: %s" % enemy_id)
			_check(attack or not move.has("hits"), "hits は攻撃だけ: %s" % enemy_id)
		var rank: int = enemy["rank"]
		rank_counts[rank] = rank_counts.get(rank, 0) + 1
		_check(enemy.has("talk") == (rank == Enemies.Rank.BOSS), "会話の台詞を持つのはボスだけ: %s" % enemy_id)
		if enemy.has("talk"):
			_check(_in_range(enemy["talk"].size(), TALK_LINES_RANGE), "ボスの台詞が 2〜4 行: %s" % enemy_id)
			for line: String in enemy["talk"]:
				_check(not line.is_empty(), "ボスの台詞が空でない: %s" % enemy_id)
	for rank: int in RANK_COUNT_RANGES:
		_check(
			_in_range(rank_counts.get(rank, 0), RANK_COUNT_RANGES[rank]),
			"格 %d の敵の種類の数が範囲内 (%d)" % [rank, rank_counts.get(rank, 0)]
		)


## 敵の組み合わせ: 候補が定義済みの同じ格の敵だけからなり、全部の敵がどこかに出て、後半の敵は前半より体力が多く、
## ボスはどの強敵より体力が多い。仮の道順 (地図ができるまで) はボスで終わる
func _check_encounters() -> void:
	var used: Dictionary = {}
	for late_half: bool in [false, true]:
		for rank: int in [Enemies.Rank.NORMAL, Enemies.Rank.ELITE, Enemies.Rank.BOSS]:
			var candidates: Array = Enemies.encounter_candidates(rank, late_half)
			_check(not candidates.is_empty(), "格 %d・後半 %s の候補がある" % [rank, late_half])
			for ids: Array in candidates:
				_check(not ids.is_empty(), "組み合わせに敵がいる: %s" % [ids])
				for enemy_id: String in ids:
					var defined: bool = Enemies.ENEMIES.has(enemy_id)
					_check(defined, "組み合わせの敵が定義済み: %s" % enemy_id)
					if defined:
						_check(Enemies.ENEMIES[enemy_id]["rank"] == rank, "組み合わせの格が敵の格と同じ: %s" % enemy_id)
						used[enemy_id] = true
	for enemy_id: String in Enemies.ENEMIES:
		_check(used.has(enemy_id), "敵が組み合わせのどこかに出る: %s" % enemy_id)
	_check(
		(
			_encounter_hps(Enemies.Rank.NORMAL, true).min()
			> _encounter_hps(Enemies.Rank.NORMAL, false).max()
		),
		"後半の敵はどれも前半の敵より体力が多い"
	)
	var late_elite: Array[int] = _encounter_hps(Enemies.Rank.ELITE, true)
	_check(
		late_elite.min() > _encounter_hps(Enemies.Rank.ELITE, false).max(),
		"後半の強敵は前半の強敵より体力が多い"
	)
	_check(
		_encounter_hps(Enemies.Rank.BOSS, false).min() > late_elite.max(),
		"ボスはどの強敵より体力が多い"
	)
	var route: Array = Enemies.provisional_route()
	for floor_index: int in range(route.size() + 1):
		var ids: Array[String] = Enemies.encounter_for_floor(floor_index)
		_check(not ids.is_empty(), "仮の道順の階層 %d に敵がいる" % floor_index)
		for enemy_id: String in ids:
			_check(Enemies.ENEMIES.has(enemy_id), "階層 %d の敵が定義済み: %s" % [floor_index, enemy_id])
	_check(
		Enemies.encounter_for_floor(route.size() - 1) == Enemies.BOSS_ENCOUNTER,
		"仮の道順の最後の階層がボス"
	)


## 残り使用回数: 使うと 1 減り、0 (契約切れ) では使えず、回復で戻る (最大を超えない)。体力は 0 未満にならない
func _check_run_state_uses() -> void:
	var state: RunStateScript = RunStateScript.new()
	state.new_run()
	var starter: Array[String] = Contractors.starter_deck(Contractors.FIRST_CONTRACTOR)
	_check(state.deck.size() == starter.size(), "新しいランのデッキが最初の契約者の初期デッキと同じ枚数")
	var single: int = starter.find("hero_strike")
	var slash: int = starter.find("slash")
	var slash_max: int = Cards.CARDS["slash"]["max_uses"]
	_check(state.uses_left(single) == 1 and state.can_use(single), "最大使用回数 1 のカードが使える")
	_check(state.use_card(single), "使うと true")
	_check(state.uses_left(single) == 0 and not state.can_use(single), "残り 0 で契約切れ (使えない)")
	_check(not state.use_card(single), "契約切れのカードは使えず false")
	_check(state.uses_left(single) == 0, "契約切れのカードを使おうとしても減らない")
	_check(state.restore_uses(single, 1) == 1 and state.can_use(single), "1 回の回復で使えるようになる")
	_check(state.use_card(slash) and state.use_card(slash), "斬火を 2 回使える")
	_check(state.uses_left(slash) == slash_max - 2, "斬火の残りが 2 減る")
	_check(state.restore_uses(slash, 1) == slash_max - 1, "1 回の回復で 1 戻る")
	_check(state.restore_uses(slash, 99) == slash_max, "回復は最大使用回数を超えない")
	_check(state.restore_uses(slash) == slash_max, "回数を省いた回復は最大まで戻す")
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
	state.use_card(Contractors.starter_deck(Contractors.FIRST_CONTRACTOR).find("hero_strike"))
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
## (Windows、root で実行される環境) では検証を飛ばす (CI の ubuntu-24.04 ランナーは root でないため飛ばさない)
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
	_check(
		state.uses_left(0) == Cards.CARDS["slash"]["max_uses"] - 1, "READ_ERROR では状態を変えない"
	)
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
	_check(battle.enemies.size() == 1 and battle.enemies[0]["hp"] == 14, "影の野犬の体力 14")
	battle.enemies[0]["block"] = 4
	_check(battle.play(_hand_index_of(battle, state, "slash"), 0), "斬火を使える")
	_check(battle.enemies[0]["hp"] == 12 and battle.enemies[0]["block"] == 0, "防御 4 が先に受けて体力 12")
	_check(
		battle.energy == 2 and state.uses_left(0) == Cards.CARDS["slash"]["max_uses"] - 1,
		"コスト 1 を払い残り使用回数が 1 減る"
	)
	var deck_before_struggle: Array[Dictionary] = state.deck.duplicate(true)
	_check(battle.struggle(0) and battle.enemies[0]["hp"] == 10, "もがくで 2 ダメージ")
	_check(state.deck == deck_before_struggle, "もがくは残りのあるカードの残り使用回数も減らさない")
	_check(battle.energy == 1, "もがくのコスト 1")
	battle.energy = 2
	_check(battle.hand.size() == 4 and battle.discard_pile.size() == 1, "使ったカードは捨て札へ")
	_check(battle.play(_hand_index_of(battle, state, "guard")), "守りの風を使える")
	_check(battle.block == 5 and battle.energy == 1, "防御 5・エネルギー 1")
	_check(not battle.can_play(_hand_index_of(battle, state, "hero_strike")), "コスト 2 は払えない")
	_check(battle.play(_hand_index_of(battle, state, "breath")), "灯の精を使える")
	_check(battle.hand.size() == 4 and battle.discard_pile.is_empty(), "捨て札を混ぜ直して 2 枚引く")
	_check(battle.play(_hand_index_of(battle, state, "spirit_arrow"), 0), "火の粉を使える")
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


## 効果の種類: 複数回の攻撃 (hits)・全体攻撃 (area)・エネルギーを得る (energy)・敵の複数回の攻撃
func _check_battle_effects() -> void:
	var state: RunStateScript = RunStateScript.new()
	state.new_run(["twin_flame", "ember_wave", "candle_flame", "guard", "guard"])
	var battle: BattleScript = BattleScript.new()
	battle.start(state, ["wild_dog", "skeleton"], 1)
	_check(battle.play(_hand_index_of(battle, state, "twin_flame"), 1), "双つ灯を使える")
	_check(battle.enemies[1]["hp"] == 14, "双つ灯は骸の巡礼者に 4 を 2 回与えて体力 14")
	_check(Cards.needs_target("twin_flame") and not Cards.needs_target("ember_wave"), "全体攻撃は対象を取らない")
	_check(battle.play(_hand_index_of(battle, state, "ember_wave")), "熾火の波は対象を選ばずに使える")
	_check(
		battle.enemies[0]["hp"] == 10 and battle.enemies[1]["hp"] == 10,
		"熾火の波は生きている敵すべてに 4 を与える"
	)
	_check(battle.energy == 1, "コスト 1 を 2 枚使ってエネルギー 1")
	_check(battle.play(_hand_index_of(battle, state, "candle_flame")), "蝋燭の火を使える")
	_check(battle.energy == 2, "蝋燭の火でエネルギーが 1 増える")
	# 予告を固定して、攻撃 2×3 の 1 回ずつを防御 3 が先に受けることを確かめる (2 + 1 を防いで 3 を受ける)
	battle.block = 3
	battle.enemies[0]["intent"] = {"move": Enemies.Move.ATTACK, "value": 2, "hits": 3}
	battle.enemies[1]["intent"] = {"move": Enemies.Move.GUARD, "value": 1}
	var hp_before: int = state.hp
	battle.end_turn()
	_check(state.hp == hp_before - 3, "攻撃 2×3 を防御 3 が受けて体力が 3 減る")
	# 境界: 複数回の攻撃は 1 回ごとに敵の防御が先に受け、全体攻撃は倒した敵を飛ばし、全員を倒したら勝利
	state.new_run(["twin_flame", "ember_wave"])
	var finisher: BattleScript = BattleScript.new()
	finisher.start(state, ["wild_dog", "skeleton"], 2)
	finisher.enemies[0]["hp"] = 0
	finisher.enemies[1]["block"] = 3
	_check(finisher.play(_hand_index_of(finisher, state, "twin_flame"), 1), "双つ灯を防御 3 の敵に使える")
	_check(
		finisher.enemies[1]["hp"] == 17 and finisher.enemies[1]["block"] == 0,
		"双つ灯の 1 回目を防御 3 が受け、2 回目は体力に届く (22 → 17)"
	)
	finisher.enemies[1]["hp"] = 4
	_check(finisher.play(_hand_index_of(finisher, state, "ember_wave")), "熾火の波を使える")
	_check(finisher.enemies[0]["hp"] == 0 and finisher.enemies[1]["hp"] == 0, "倒した敵は 0 のまま")
	_check(finisher.outcome == BattleScript.Outcome.WIN, "全体攻撃で全員を倒したら勝利")
	state.free()


## 予告を順に繰り返す敵 (in_order) は、moves を先頭から順に予告し、最後の後は先頭に戻る
func _check_enemy_intent_order() -> void:
	var state: RunStateScript = RunStateScript.new()
	state.new_run(["guard"])
	var battle: BattleScript = BattleScript.new()
	battle.start(state, ["moth"], 8)
	var moves: Array = Enemies.ENEMIES["moth"]["moves"]
	_check(Enemies.ENEMIES["moth"].get("in_order", false), "煤蛾は予告を順に繰り返す")
	_check(battle.enemies[0]["intent"] == moves[0], "最初は moves の先頭を予告する")
	battle.end_turn()
	_check(battle.enemies[0]["intent"] == moves[1], "次は moves の 2 番目を予告する")
	battle.end_turn()
	_check(battle.enemies[0]["intent"] == moves[0], "最後の後は先頭に戻る")
	state.free()


## 勝敗: 敵をすべて倒したら勝利、体力 0 で敗北。勝利の後の戦闘は残り使用回数を引き継ぐ (同じシードで同じ進行)
func _check_battle_outcomes() -> void:
	var state: RunStateScript = RunStateScript.new()
	state.new_run(["hero_strike", "guard"])
	var battle: BattleScript = BattleScript.new()
	battle.start(state, ["wild_dog"], 2)
	_check(battle.play(_hand_index_of(battle, state, "hero_strike"), 0), "雷槍の英霊を使える")
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
	var used_once: int = Cards.CARDS["slash"]["max_uses"] - 1
	_check(state.uses_left(0) == used_once, "戦闘の開始で残り使用回数が戻らない")
	battle.end_turn()
	_check(state.uses_left(0) == used_once, "ターンの終了で残り使用回数が戻らない")
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


## value が bounds ([最小, 最大]) の範囲内か
func _in_range(value: Variant, bounds: Array) -> bool:
	return value >= bounds[0] and value <= bounds[1]


## 短い文言に句読点が無いか (SHORT_COPY_PUNCTUATION のどれも含まない)
func _is_short_copy(text: String) -> bool:
	for mark: String in SHORT_COPY_PUNCTUATION:
		if text.contains(mark):
			return false
	return true


## 敵の格と幕の前半・後半ごとの組み合わせの候補に出る敵の体力の並び
func _encounter_hps(rank: int, late_half: bool) -> Array[int]:
	var hps: Array[int] = []
	for ids: Array in Enemies.encounter_candidates(rank, late_half):
		for enemy_id: String in ids:
			hps.append(Enemies.ENEMIES[enemy_id]["hp"])
	return hps


## user:// のファイルを消す (無ければ何もしない)
func _remove_user_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.open(path.get_base_dir()).remove(path.get_file())
