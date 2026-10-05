extends Control
## 起動時に表示するメインシーン。今はタイトルの文字と、戦闘へ入る仮の入口 (Enter / クリック) だけを持つ。
## タイトル画面・地図はロードマップの子 issue で作る。

## 起動検証 (make check) が tmp/check.log から探す行
const BOOT_MESSAGE: String = "card-rationing boot"
const BATTLE_SCENE: PackedScene = preload("res://scenes/battle.tscn")
const BattleUiScript := preload("res://scripts/battle_ui.gd")

## 進行中の戦闘画面 (入る前は null)
var battle: BattleUiScript = null


## 標準出力に BOOT_MESSAGE を 1 行出す (make check がメインシーンのロードと _ready の実行を確かめる印)
func _ready() -> void:
	print(BOOT_MESSAGE)


## Enter / Space で戦闘に入る (戦闘に入った後のキーは戦闘画面が受ける)
func _unhandled_key_input(event: InputEvent) -> void:
	if battle != null or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: Key = (event as InputEventKey).keycode
	if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
		enter_battle()


## クリックで戦闘に入る (Background と Title はマウスを通すので、このノードが受ける)
func _gui_input(event: InputEvent) -> void:
	if battle != null or not (event is InputEventMouseButton):
		return
	if (event as InputEventMouseButton).pressed:
		enter_battle()


## 戦闘画面を子に足して、現在の階層の戦闘を始める。seed_value が負なら乱数のシードを使う (randi() は
## 非負なので、負の値を「指定なし」に使える)。戦闘画面のノードを返す (検証スクリプトが操作する)
func enter_battle(seed_value: int = -1) -> BattleUiScript:
	if battle != null:
		return battle
	battle = BATTLE_SCENE.instantiate()
	add_child(battle)
	$Title.visible = false
	$Hint.visible = false
	battle.start_battle(randi() if seed_value < 0 else seed_value)
	return battle
