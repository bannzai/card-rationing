extends SceneTree
## 「状況で使い分ける」戦略 bot (scripts/dev/strategy_bots.gd) が、メインシーンの画面を通して 1 幕を遊ぶ
## テストプレイ。Makefile の playtest target が描画付きで起動して Movie Maker モードで録画し、agent が録画と
## 静止画を目視する (実行方法は AGENTS.md「検証方法」)。判断は make simulate と同じ関数で、同じシードなら
## 同じ道・同じ手になる。地図・戦闘・契約の祠・ボス戦に最初に着いた時点を tmp/playtest-<場面>.png に撮る。
## ランの終わり (踏破か敗北) の結果の画面を映してから「playtest OK」の行を出して quit(0) する。踏破できずに
## 敗北しても失敗にはせず、到達した所までを録画する (ボス戦に着かなければボスの静止画は無い)。
## 画面を進められない時は quit(1) で終わる。保存データは本番と別の保存先に書き、ランの終わりに消える。

const ActMap := preload("res://scripts/act_map.gd")
const AudioScript := preload("res://scripts/audio.gd")
const BattleUiScript := preload("res://scripts/battle_ui.gd")
const BossTalkScript := preload("res://scripts/boss_talk.gd")
const Bots := preload("res://scripts/dev/strategy_bots.gd")
const Contractors := preload("res://scripts/contractors.gd")
const Enemies := preload("res://scripts/enemies.gd")
const EventUiScript := preload("res://scripts/event_ui.gd")
const HeadlessCheck := preload("res://scripts/dev/headless_check.gd")
const MainScript := preload("res://scripts/main.gd")
const MapUiScript := preload("res://scripts/map_ui.gd")
const NodeRules := preload("res://scripts/node_rules.gd")
const ResultUiScript := preload("res://scripts/result_ui.gd")
const RewardUiScript := preload("res://scripts/reward_ui.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const ShopUiScript := preload("res://scripts/shop_ui.gd")
const ShrineUiScript := preload("res://scripts/shrine_ui.gd")

## 遊ぶメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 遊ばせる戦略 (issue #10 の指定)
const STRATEGY: int = Bots.Strategy.ADAPT
## 遊ばせる地図のシード。make simulate でこの戦略が踏破したシードから選ぶ取り決め (issue #10)。敵の強さを調整
## (issue #33) した後の 2026-10-07 の集計 (CI run 37614347476) でこの戦略が踏破した 46 個のシードのうち最小のもの
## (1 幕の最後まで遊び、踏破の結果の画面までを録画に映すため)。敵・カード・戦略の判断を変えたら、踏破したシード
## から選び直す
const PLAYTEST_SEED: int = 7
## テストプレイの間に使う保存先 (本番の保存データを触らない)
const PLAYTEST_SAVE_PATH: String = "user://playtest_run.json"
## 録画に映すフレーム数 (録画の fps は Makefile の playtest target が決め、30 フレームが 1 秒)。
## SCREEN_FRAMES = 画面が切り替わった後とボスの台詞 1 行 (文を読める 1 秒)、MOVE_FRAMES = 戦闘の 1 手と出来事で
## カードを選ぶ 1 回 (何を使ったかを目で追える 0.2 秒。1 幕で数百手になるので短くする)、RESULT_FRAMES = ランの結果の
## 画面 (録画の末尾で結果を読める 3 秒)。合計が Makefile の PLAYTEST_FRAME_LIMIT に収まるようにする
const SCREEN_FRAMES: int = 30
const MOVE_FRAMES: int = 6
const RESULT_FRAMES: int = 90

## tree に置いた MAIN_SCENE のインスタンス (今の画面をここから読み、巡礼の開始もここを通す)
var main: MainScript = null
## ラン単位の状態 (autoload RunState)
var run_state: RunStateScript = null
## 撮影済みの場面の名前 (同じ場面は最初の 1 回だけ撮る)
var captured: Dictionary = {}


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## メインシーンを置いて PLAYTEST_SEED の巡礼を始め、ランの終わりまで遊ばせて、結果を exit code と「playtest OK」の
## 行で返して終える。フレームを進めながら遊ばせるため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	run_state = root.get_node_or_null("RunState")
	if run_state == null:
		push_error("autoload RunState が無い")
		quit(1)
		return
	run_state.save_path = PLAYTEST_SAVE_PATH
	main = MAIN_SCENE.instantiate()
	root.add_child(main)
	current_scene = main
	await _wait(SCREEN_FRAMES)
	main.start_run(Contractors.FIRST_CONTRACTOR, PLAYTEST_SEED)
	while not Bots.is_run_over(run_state):
		await _wait(SCREEN_FRAMES)
		if not await _play_phase():
			quit(1)
			return
	await _wait(RESULT_FRAMES)
	if not (main.screen is ResultUiScript):
		push_error("playtest FAIL: ランの終わりに結果の画面が出ない")
		quit(1)
		return
	var result: Dictionary = Bots.run_result(run_state)
	print(
		(
			"playtest: シード %d を %s (%d / %d 階、使い切った契約 %d 回、%d フレーム)"
			% [
				PLAYTEST_SEED,
				"踏破" if result["cleared"] else "敗北",
				result["floor"],
				ActMap.ROWS,
				result["exhausted"],
				Engine.get_process_frames(),
			]
		)
	)
	# 遊んでいる間に鳴らした BGM・効果音を止め、解放を待ってから終える (待たないとリークの WARNING が出る)
	(root.get_node("Audio") as AudioScript).stop_all()
	await create_timer(HeadlessCheck.AUDIO_RELEASE_TIME).timeout
	print("playtest OK")
	quit(0)


## ランの今の局面の画面を、戦略の判断で 1 つ進める。画面が局面と合わず進められなければ false
func _play_phase() -> bool:
	var played: bool = true
	match run_state.phase:
		RunStateScript.Phase.MAP:
			played = _choose_node()
		RunStateScript.Phase.BATTLE:
			played = await _play_battle()
		RunStateScript.Phase.REWARD:
			played = _take_reward()
		RunStateScript.Phase.SHRINE:
			played = await _visit_shrine()
		RunStateScript.Phase.SHOP:
			played = await _visit_shop()
		RunStateScript.Phase.EVENT:
			played = await _visit_event()
	return played


## 地図で、戦略が選んだ次の節点に入る
func _choose_node() -> bool:
	var map_ui: MapUiScript = main.screen as MapUiScript
	if map_ui == null or not _capture_once("map"):
		return _fail("地図の画面が出ない")
	map_ui.choose(Bots.choose_column(run_state))
	return true


## 戦闘の報酬で、戦略が選んだカードと契約して地図へ戻る
func _take_reward() -> bool:
	var reward: RewardUiScript = main.screen as RewardUiScript
	if reward == null:
		return _fail("報酬の画面が出ない")
	reward.take(Bots.choose_reward(run_state))
	return true


## 今いる節点の戦闘を、勝敗が決まるまで戦闘画面の操作で進める。ボスの節点では先に会話を最後まで進める
func _play_battle() -> bool:
	var boss: bool = main.screen is BossTalkScript
	if boss:
		var talk: BossTalkScript = main.screen as BossTalkScript
		for _line: int in range(Enemies.ENEMIES[talk.boss_id]["talk"].size()):
			talk.advance()
			await _wait(SCREEN_FRAMES)
	var battle_ui: BattleUiScript = main.screen as BattleUiScript
	if battle_ui == null or not _capture_once("boss" if boss else "battle"):
		return _fail("戦闘の画面が出ない")
	while run_state.phase == RunStateScript.Phase.BATTLE:
		if battle_ui.battle.turn > Bots.TURN_LIMIT:
			return _fail("戦闘が %d ターンで終わらない" % Bots.TURN_LIMIT)
		var move: Dictionary = Bots.battle_move(STRATEGY, battle_ui.battle, run_state)
		match move["move"]:
			Bots.BattleMove.PLAY:
				battle_ui.request_card(move["hand_index"])
			Bots.BattleMove.STRUGGLE:
				battle_ui.request_struggle()
			Bots.BattleMove.END_TURN:
				battle_ui.end_turn()
		# 敵が 2 体以上いる時、対象を取るカードともがくは対象の選択に入る
		if battle_ui.pending_hand_index != -1:
			await _wait(MOVE_FRAMES)
			battle_ui.choose_target(move["target"])
		await _wait(MOVE_FRAMES)
	return true


## 契約の祠で、戦略が選んだ方 (契約の更新か新しい契約) の段階を映してから選ぶ
func _visit_shrine() -> bool:
	var shrine: ShrineUiScript = main.screen as ShrineUiScript
	if shrine == null or not _capture_once("shrine"):
		return _fail("契約の祠の画面が出ない")
	var choice: Dictionary = Bots.choose_shrine(run_state)
	if choice["renew_index"] >= 0:
		shrine.show_mode(ShrineUiScript.Mode.RENEW)
		await _wait(SCREEN_FRAMES)
		shrine.renew(choice["renew_index"])
	else:
		shrine.show_mode(ShrineUiScript.Mode.CONTRACT)
		await _wait(SCREEN_FRAMES)
		shrine.contract(choice["card_id"])
	return true


## 商人で、戦略が買うものが無くなるまで買ってから立ち去る
func _visit_shop() -> bool:
	var shop: ShopUiScript = main.screen as ShopUiScript
	if shop == null:
		return _fail("商人の画面が出ない")
	for _purchase: int in range(NodeRules.OFFER_COUNT + 1):
		var purchase: Dictionary = Bots.next_purchase(run_state)
		var card_id: String = purchase["card_id"]
		if not card_id.is_empty():
			shop.buy(card_id)
		elif purchase["restore_index"] >= 0:
			shop.restore(purchase["restore_index"])
		else:
			break
		await _wait(SCREEN_FRAMES)
	shop.leave()
	return true


## 出来事で、戦略が選んだ選択肢を選ぶ (カードを選ぶ選択肢は、カードを 1 枚ずつ選んでから決める)
func _visit_event() -> bool:
	var event_ui: EventUiScript = main.screen as EventUiScript
	var choice: Dictionary = Bots.choose_event(run_state)
	if event_ui == null or choice["option"] < 0:
		return _fail("出来事の画面で選べる選択肢が無い")
	var picks: Array[int] = choice["picks"]
	event_ui.select_option(choice["option"])
	if picks.is_empty():
		return true
	for index: int in picks:
		await _wait(MOVE_FRAMES)
		# toggle_pick() は格子を作り直した次のフレームにスクロールの位置を戻すので、終わりを待つ
		await event_ui.toggle_pick(index)
	await _wait(SCREEN_FRAMES)
	event_ui.confirm()
	return true


## frames フレーム進める (Movie Maker モードは 1 フレームが録画の 1 コマ)
func _wait(frames: int) -> void:
	for _frame: int in range(frames):
		await process_frame


## 今の画面を tmp/playtest-<scene_name>.png に撮る (同じ場面は最初の 1 回だけ)。保存に失敗したら false
func _capture_once(scene_name: String) -> bool:
	if captured.has(scene_name):
		return true
	captured[scene_name] = true
	var path: String = "tmp/playtest-%s.png" % scene_name
	var status: Error = root.get_viewport().get_texture().get_image().save_png(path)
	if status != OK:
		push_error("playtest FAIL: %s を保存できない (%s)" % [path, error_string(status)])
		return false
	print("playtest: " + path)
	return true


## 失敗の理由を ERROR として出して false を返す (_play_phase() の戻り値にそのまま使う)
func _fail(reason: String) -> bool:
	push_error("playtest FAIL: %s (%d 階)" % [reason, run_state.path.size()])
	return false
