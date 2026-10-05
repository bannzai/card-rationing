extends SceneTree
## headless で実行する検証 (scripts/dev/selfcheck.gd と scripts/dev/integration.gd) が継承する土台。
## 検証の失敗の記録と、結果を exit code と完了の行で返す終わり方を持つ。
## release ビルドでは assert が消えるため、assert ではなく _check() と _finish() で結果を返す。

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
