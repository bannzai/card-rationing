extends "res://scripts/dev/headless_check.gd"
## 純粋なロジックとプロジェクト設定の検証 (headless)。ゲームのルール (カードの残り使用回数・戦闘・マップ・
## イベント) の計算を足したら、ここに検証を足す。実行方法は AGENTS.md「検証方法」を参照。

## 起動検証 (main_scene の --quit) ではロードされない遷移先も含めた全シーン
const SCENES: Array[String] = [
	"res://scenes/main.tscn",
]
## 起動時に表示するシーン
const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
## ADR 0001 で決めたレンダラ (CI の Xvfb + Mesa llvmpipe で描画できるもの)
const RENDERING_METHOD: String = "gl_compatibility"


## すべての検証を順に行い、結果を exit code と「selfcheck OK」の行で返して終える (シーンを tree に置かないため
## _initialize() の中で完結する)
func _initialize() -> void:
	_check_project_settings()
	_check_scenes_load()
	_finish()


## project.godot の起動シーンとレンダラが ADR 0001 のとおりか
func _check_project_settings() -> void:
	_check(
		ProjectSettings.get_setting("application/run/main_scene") == MAIN_SCENE_PATH,
		"起動シーンが %s" % MAIN_SCENE_PATH
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
