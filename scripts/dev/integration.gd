extends "res://scripts/dev/headless_check.gd"
## メインシーンを tree に置いて動かす入力統合テスト (headless)。画面の遷移やキー・クリックで変わる振る舞いを
## 足したら、ここに検証を足す。実行方法は AGENTS.md「検証方法」を参照。

## 起動時に表示するメインシーン
const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")


## tree の準備が終わってから _run() を始める (シーンの追加は _initialize() の後でないとできない)
func _initialize() -> void:
	_run.call_deferred()


## フレームを進めながら検証するため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	var main: Control = MAIN_SCENE.instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame
	_check(main.is_inside_tree(), "メインシーンが tree に入る")
	_check(main.get_node("Title").is_visible_in_tree(), "タイトルが表示される")
	main.queue_free()
	await process_frame
	_finish()
