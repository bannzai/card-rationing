extends SceneTree
## headless で実行する検証 (scripts/dev/selfcheck.gd と scripts/dev/integration.gd) が継承する土台。
## 検証の失敗の記録と、結果を exit code と完了の行で返す終わり方を持つ。
## release ビルドでは assert が消えるため、assert ではなく _check() と _finish() で結果を返す。

## 契約切れだけのデッキで戦闘を終わらせる時の、もがく + ターン終了の上限 (詰んだら検証を止めるため)。
## 影の野犬 (体力 14) をもがく (2 ダメージ、エネルギー 3 で 1 ターン 3 回) で倒すには 7 回 + ターン終了 2 回の
## 9 手で、その 6 倍強
const EXHAUSTED_BATTLE_STEP_LIMIT: int = 60
## 音を止めてから終了するまで待つ時間 (秒)。止めた BGM・効果音の再生は AudioServer がミキシングを数回進めてから
## 解放するため、待たずに終了すると再生がリークとして WARNING / ERROR に出る (bannzai/kageboshi の CI で実測した値。
## ミキシング数回分に余裕を持たせてある)。描画付きの scripts/dev/screenshot.gd もこの値で待つ
const AUDIO_RELEASE_TIME: float = 0.25

## 検証が 1 件でも失敗したか。true なら exit code 1 で終わる
var failed: bool = false


## cond が false なら label を ERROR として出し、失敗として記録する。
## ERROR の行頭には実行した検証のスクリプトの名前 (selfcheck / integration) を付ける
func _check(cond: bool, label: String) -> void:
	if not cond:
		push_error("%s FAIL: %s" % [_script_name(), label])
		failed = true


## 失敗が無ければ「<スクリプトの名前> OK」を出して exit code 0、あれば exit code 1 で終える。
## Makefile は exit code と OK の行の両方で成否を判定する
func _finish() -> void:
	if failed:
		quit(1)
		return
	print("%s OK" % _script_name())
	quit(0)


## 実行中の検証のスクリプトのファイル名 (拡張子なし)
func _script_name() -> String:
	return get_script().resource_path.get_file().get_basename()
