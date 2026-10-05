extends SceneTree
## 実際の描画で代表画面を撮影する (headless では描画されないため、Makefile の screenshot target が
## --headless なしで起動する)。撮影した PNG は tmp/screenshot-<名前>.png に保存し、失敗したら quit(1) で終わる。
## 全部の撮影を終えたら「screenshot OK」の行を出して quit(0) する (Makefile はこの行と PNG の存在で判定する)。
## 画面や状態を増やす時は _capture_scenes() に撮影を足す。

const MainScript := preload("res://scripts/main.gd")
const RunStateScript := preload("res://scripts/run_state.gd")

## 撮影するメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
## 戦闘画面の撮影に使うシード。値に意味は無く、撮影のたびに手札の並びと敵の予告が変わらないように固定する
const BATTLE_SEED: int = 5


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら撮影するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	if await _capture_scenes():
		# #4 の実験 B: push_error の ERROR の行を出しつつ、OK の行と exit 0 で終える (ログの検査だけで失敗する状態)
		push_error("deliberate push_error for #4 experiment B")
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
	# 5 枚のデッキなら全カードが手札に来るので、残り 1 回 (斬撃) と契約切れ (英霊の一閃) が必ず映る
	var run_state: RunStateScript = root.get_node_or_null("RunState")
	if run_state == null:
		push_error("autoload RunState が無い")
		quit(1)
		return false
	run_state.new_run(["slash", "guard", "hero_strike", "breath", "spirit_arrow"])
	run_state.use_card(2)
	for _i: int in range(3):
		run_state.use_card(0)
	main.enter_battle(BATTLE_SEED)
	await create_timer(0.3).timeout
	if not await _capture("tmp/screenshot-battle.png"):
		return false
	main.queue_free()
	await process_frame
	return true


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
