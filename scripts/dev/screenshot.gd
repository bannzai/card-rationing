extends SceneTree
## 実際の描画で代表画面を撮影する (headless では描画されないため、Makefile の screenshot target が
## --headless なしで起動する)。撮影した PNG は tmp/screenshot-<名前>.png に保存し、失敗したら quit(1) で終わる。
## 全部の撮影を終えたら「screenshot OK」の行を出して quit(0) する (Makefile はこの行と PNG の存在で判定する)。
## 画面や状態を増やす時は _capture_scenes() に撮影を足す。ランの状態は検証用の保存先に保存し、撮影の後に消す。

const ActMap := preload("res://scripts/act_map.gd")
const AudioScript := preload("res://scripts/audio.gd")
const BattleUiScript := preload("res://scripts/battle_ui.gd")
const BossTalkScript := preload("res://scripts/boss_talk.gd")
const Cards := preload("res://scripts/cards.gd")
const Contractors := preload("res://scripts/contractors.gd")
const Enemies := preload("res://scripts/enemies.gd")
const HeadlessCheck := preload("res://scripts/dev/headless_check.gd")
const MainScript := preload("res://scripts/main.gd")
const RunFlow := preload("res://scripts/run_flow.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const ShrineUiScript := preload("res://scripts/shrine_ui.gd")

## 撮影するメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 地図のシード。値に意味は無く、撮影のたびに地図・手札の並び・敵の予告・品揃えが変わらないように固定する
const MAP_SEED: int = 5
## 地図の画面で、道をこの段まで進めて撮る (通った道の色と、先の契約の祠が見えるように)
const MAP_PROGRESS_ROW: int = 3
## 撮影の間に使う保存先 (本番の保存データを触らない)
const SCREENSHOT_SAVE_PATH: String = "user://screenshot_run.json"

## 撮影するメインシーンと、ラン単位の状態 (autoload RunState)
var main: MainScript = null
## ラン単位の状態 (autoload RunState)
var run_state: RunStateScript = null


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら撮影するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	run_state = root.get_node_or_null("RunState")
	if run_state == null:
		push_error("autoload RunState が無い")
		quit(1)
		return
	run_state.save_path = SCREENSHOT_SAVE_PATH
	if await _capture_scenes():
		run_state.delete_save()
		# 撮影の間に鳴らした BGM・効果音を止め、解放を待ってから終える (待たないとリークの WARNING が出る)
		(root.get_node("Audio") as AudioScript).stop_all()
		await create_timer(HeadlessCheck.AUDIO_RELEASE_TIME).timeout
		print("screenshot OK")
		quit(0)


## 撮影する画面の並び。各要素は [画面を用意する関数 (用意できなければ false), 撮影の名前]。失敗した撮影は
## _capture() が quit(1) 済みなので、false を受けたらそのまま抜ける
func _capture_scenes() -> bool:
	main = MAIN_SCENE.instantiate()
	root.add_child(main)
	current_scene = main
	# 最初の撮影だけ、フォントの読み込みと最初の描画を時間で待つ
	await create_timer(0.3).timeout
	var steps: Array[Array] = [
		[func() -> bool: return true, "title"],
		[_show_character_select, "character-select"],
		[_show_map, "map"],
		[_show_deck_list, "deck-list"],
		[_show_battle, "battle"],
		[_show_battle_drawn, "battle-drawn"],
		[_show_reward, "reward"],
		[_show_shrine, "shrine"],
		[_show_shrine_renew, "shrine-renew"],
		[_show_shop, "shop"],
		[_show_event, "event"],
		[_show_boss_talk, "boss-talk"],
		[_show_boss_battle, "battle-boss"],
		[_show_settings, "settings"],
		[_show_defeat, "defeat"],
		[_show_clear, "clear"],
	]
	for step: Array in steps:
		if not step[0].call():
			quit(1)
			return false
		if not await _capture("tmp/screenshot-%s.png" % step[1]):
			return false
	main.queue_free()
	await process_frame
	return true


## 契約者の選択
func _show_character_select() -> bool:
	main.show_character_select()
	return true


## 地図 (道を MAP_PROGRESS_ROW 段まで進めたところ)
func _show_map() -> bool:
	main.start_run(Contractors.FIRST_CONTRACTOR, MAP_SEED)
	_show_at_row(MAP_PROGRESS_ROW, RunStateScript.Phase.MAP)
	return true


## 地図に重ねた契約の一覧
func _show_deck_list() -> bool:
	main.open_deck_list()
	return true


## 戦闘。5 枚のデッキなら全カードが手札に来るので、残り 1 回 (斬火) と契約切れ (雷槍の英霊) が必ず映る
func _show_battle() -> bool:
	_set_deck(["slash", "guard", "hero_strike", "breath", "spirit_arrow"])
	run_state.use_card(2)
	for _i: int in range(Cards.CARDS["slash"]["max_uses"] - 1):
		run_state.use_card(0)
	_show_at_row(0, RunStateScript.Phase.BATTLE)
	return true


## ドローで手札が 6 枚に増えた戦闘 (手札が画面の幅に収まることを見る)。灯の精が手札に来るシードを順に探す
func _show_battle_drawn() -> bool:
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	_set_deck(["breath", "slash", "slash", "guard", "guard", "guard", "spirit_arrow", "slash"])
	for seed_value: int in range(1, 51):
		battle_ui.start_battle(seed_value)
		var breath_hand: int = _hand_index_of(battle_ui, "breath")
		if breath_hand >= 0:
			battle_ui.request_card(breath_hand)
			break
	if battle_ui.battle.hand.size() != 6:
		push_error("灯の精で手札を 6 枚にできない (手札 %d 枚)" % battle_ui.battle.hand.size())
		return false
	return true


## 戦闘に勝った後の報酬
func _show_reward() -> bool:
	return RunFlow.finish_battle(run_state, true)


## 契約の祠の 3 択
func _show_shrine() -> bool:
	_show_at_kind(ActMap.Kind.SHRINE, RunStateScript.Phase.SHRINE)
	return true


## 契約の祠で更新するカードを選ぶところ (残りの減ったカードだけ押せる)
func _show_shrine_renew() -> bool:
	run_state.use_card(0)
	run_state.use_card(1)
	(main.screen as ShrineUiScript).show_mode(ShrineUiScript.Mode.RENEW)
	return true


## 商人 (所持金 120 で、買えるものと買えないものが並ぶ)
func _show_shop() -> bool:
	run_state.gold = 120
	_show_at_kind(ActMap.Kind.SHOP, RunStateScript.Phase.SHOP)
	return true


## 出来事
func _show_event() -> bool:
	_show_at_kind(ActMap.Kind.EVENT, RunStateScript.Phase.EVENT)
	return true


## ボスの節点に入り、ボス戦の前の会話を最後の台詞 (「戦う」が出る) まで進める。会話が出なければ false
func _show_boss_talk() -> bool:
	_show_at_kind(ActMap.Kind.BOSS, RunStateScript.Phase.BATTLE)
	var talk: BossTalkScript = main.screen as BossTalkScript
	if talk == null:
		push_error("ボスの節点でボス戦の前の会話が出ない")
		return false
	for _i: int in range(Enemies.ENEMIES[talk.boss_id]["talk"].size() - 1):
		talk.advance()
	return true


## 会話の後のボス戦 (敵の格の表示と、複数回の攻撃の予告を見る)
func _show_boss_battle() -> bool:
	(main.screen as BossTalkScript).advance()
	return main.screen is BattleUiScript


## 設定
func _show_settings() -> bool:
	main.show_settings()
	return true


## 敗北の結果
func _show_defeat() -> bool:
	run_state.phase = RunStateScript.Phase.DEFEAT
	main.show_run_phase()
	return true


## 踏破の結果 (ボスまで進んだ道)
func _show_clear() -> bool:
	_show_at_kind(ActMap.Kind.BOSS, RunStateScript.Phase.CLEAR)
	return true


## 道を段 row の最初の節点まで進め、局面を phase にして画面を出す
func _show_at_row(row: int, phase: RunStateScript.Phase) -> void:
	_show_route(ActMap.route_to(run_state.rows, row, run_state.rows[row][0]["column"]), phase)


## 道を kind の最初の節点まで進め、局面を phase にして画面を出す
func _show_at_kind(kind: ActMap.Kind, phase: RunStateScript.Phase) -> void:
	var at: Vector2i = ActMap.find_kind(run_state.rows, kind)
	_show_route(ActMap.route_to(run_state.rows, at.x, at.y), phase)


## 道を route にし、局面を phase にして画面を出す (節点での一時的な状態は空にする)
func _show_route(route: Array[int], phase: RunStateScript.Phase) -> void:
	run_state.path = route
	run_state.phase = phase
	run_state.visit = {}
	main.show_run_phase()


## デッキを ids のカード (最大使用回数) にする (局面と道はそのまま)
func _set_deck(ids: Array[String]) -> void:
	run_state.deck.clear()
	for card_id: String in ids:
		run_state.add_card(card_id)


## 戦闘画面の手札の中で card_id のカードがある位置 (無ければ -1)
func _hand_index_of(battle_ui: BattleUiScript, card_id: String) -> int:
	for hand_index: int in range(battle_ui.battle.hand.size()):
		if run_state.deck[battle_ui.battle.hand[hand_index]]["id"] == card_id:
			return hand_index
	return -1


## コンテナのレイアウトと描画が反映されるまで 4 フレーム待ってから viewport を path に PNG で保存する。
## 失敗したら quit(1) する
func _capture(path: String) -> bool:
	for _i: int in range(4):
		await process_frame
	var status: Error = root.get_viewport().get_texture().get_image().save_png(path)
	if status != OK:
		push_error("スクリーンショット保存失敗: %s (%s)" % [path, error_string(status)])
		quit(1)
		return false
	print("screenshot: " + path)
	return true
