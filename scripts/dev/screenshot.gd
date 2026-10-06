extends SceneTree
## 実際の描画で代表画面を撮影する (headless では描画されないため、Makefile の screenshot target が
## --headless なしで起動する)。撮影した PNG は tmp/screenshot-<名前>.png に保存し、失敗したら quit(1) で終わる。
## 全部の撮影を終えたら「screenshot OK」の行を出して quit(0) する (Makefile はこの行と PNG の存在で判定する)。
## 画面や状態を増やす時は _capture_scenes() に撮影を足す。

const BattleUiScript := preload("res://scripts/battle_ui.gd")
const BossTalkScript := preload("res://scripts/boss_talk.gd")
const Cards := preload("res://scripts/cards.gd")
const Enemies := preload("res://scripts/enemies.gd")
const MainScript := preload("res://scripts/main.gd")
const RunStateScript := preload("res://scripts/run_state.gd")

## 撮影するメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## ボス戦の前の会話の画面 (地図と画面の流れ (#7・#8) につなぐまでは単体で撮る)
const BOSS_TALK_SCENE: PackedScene = preload("res://scenes/boss_talk.tscn")
## 戦闘画面の撮影に使うシード。値に意味は無く、撮影のたびに手札の並びと敵の予告が変わらないように固定する
const BATTLE_SEED: int = 5


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら撮影するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	if await _capture_scenes():
		print("screenshot OK")
		quit(0)


## 撮影する画面の並び。失敗した撮影は _capture() が quit(1) 済みなので、false を受けたらそのまま抜ける
func _capture_scenes() -> bool:
	var main: MainScript = MAIN_SCENE.instantiate()
	root.add_child(main)
	current_scene = main
	await create_timer(0.3).timeout
	if not await _capture("tmp/screenshot-title.png"):
		return false
	var run_state: RunStateScript = root.get_node_or_null("RunState")
	if run_state == null:
		push_error("autoload RunState が無い")
		quit(1)
		return false
	if not await _capture_battle_scenes(main, run_state):
		return false
	if not await _capture_boss_scenes(main, run_state):
		return false
	main.queue_free()
	await process_frame
	return true


## 戦闘画面 (残り 1 回と契約切れのカード、ドローで 6 枚に増えた手札) を撮る。撮影に失敗したら false
func _capture_battle_scenes(main: MainScript, run_state: RunStateScript) -> bool:
	# 5 枚のデッキなら全カードが手札に来るので、残り 1 回 (斬火) と契約切れ (雷槍の英霊) が必ず映る
	run_state.new_run(["slash", "guard", "hero_strike", "breath", "spirit_arrow"])
	run_state.use_card(2)
	for _i: int in range(Cards.CARDS["slash"]["max_uses"] - 1):
		run_state.use_card(0)
	main.enter_battle(BATTLE_SEED)
	await create_timer(0.3).timeout
	if not await _capture("tmp/screenshot-battle.png"):
		return false
	# ドローで手札が 6 枚に増えた画面 (手札が画面の幅に収まることを見る)。灯の精が手札に来るシードを順に探す
	run_state.new_run(["breath", "slash", "slash", "guard", "guard", "guard", "spirit_arrow", "slash"])
	for seed_value: int in range(1, 51):
		main.battle.start_battle(seed_value)
		var breath_hand: int = _hand_index_of(main.battle, run_state, "breath")
		if breath_hand >= 0:
			main.battle.request_card(breath_hand)
			break
	if main.battle.battle.hand.size() != 6:
		push_error("灯の精で手札を 6 枚にできない (手札 %d 枚)" % main.battle.battle.hand.size())
		quit(1)
		return false
	await create_timer(0.3).timeout
	return await _capture("tmp/screenshot-battle-drawn.png")


## 仮の道順の最後 (ボス) の戦闘と、ボス戦の前の会話の画面を撮る。撮影に失敗したら false
func _capture_boss_scenes(main: MainScript, run_state: RunStateScript) -> bool:
	# 敵の格の表示と、複数回の攻撃の予告 (ボスの最初の予告) を見る
	run_state.new_run()
	run_state.floor_index = Enemies.provisional_route().size() - 1
	main.battle.start_battle(BATTLE_SEED)
	await create_timer(0.3).timeout
	if not await _capture("tmp/screenshot-battle-boss.png"):
		return false
	# ボス戦の前の会話の最後の台詞 (「戦う」が出る)。日本語のフォントはメインシーンの theme が持つため、その子に置く
	var talk: BossTalkScript = BOSS_TALK_SCENE.instantiate()
	main.add_child(talk)
	for _i: int in range(Enemies.ENEMIES[talk.boss_id]["talk"].size() - 1):
		talk.advance()
	await create_timer(0.3).timeout
	return await _capture("tmp/screenshot-boss-talk.png")


## 戦闘画面の手札の中で card_id のカードがある位置 (無ければ -1)
func _hand_index_of(battle_ui: BattleUiScript, run_state: RunStateScript, card_id: String) -> int:
	for hand_index: int in range(battle_ui.battle.hand.size()):
		if run_state.deck[battle_ui.battle.hand[hand_index]]["id"] == card_id:
			return hand_index
	return -1


## 描画が反映されるまで 2 フレーム待ってから viewport を path に PNG で保存する。失敗したら quit(1) する
func _capture(path: String) -> bool:
	await process_frame
	await process_frame
	var status: Error = root.get_viewport().get_texture().get_image().save_png(path)
	if status != OK:
		push_error("スクリーンショット保存失敗: %s (%s)" % [path, error_string(status)])
		quit(1)
		return false
	print("screenshot: " + path)
	return true
