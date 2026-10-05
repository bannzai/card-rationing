extends Control
## 起動時に表示するメインシーン。ゲームの画面 (タイトル・マップ・戦闘) はロードマップの子 issue で作る。

## 起動検証 (make check) が tmp/check.log から探す行
const BOOT_MESSAGE: String = "card-rationing boot"


## 標準出力に BOOT_MESSAGE を 1 行出す (make check がメインシーンのロードと _ready の実行を確かめる印)
func _ready() -> void:
	print(BOOT_MESSAGE)
