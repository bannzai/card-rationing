extends Control
## 起動時に表示するメインシーン。今はタイトルの文字と、戦闘へ入る仮の入口 (Enter / クリック) だけを持つ。
## タイトル画面・地図はロードマップの子 issue で作る。

## 起動検証 (make check) が tmp/check.log から探す行
const BOOT_MESSAGE: String = "card-rationing boot"
const BATTLE_SCENE: PackedScene = preload("res://scenes/battle.tscn")
const BattleUiScript := preload("res://scripts/battle_ui.gd")
## 全画面の既定フォント (日本語の字形を持つ。出典は assets/CREDITS.md)。project.godot の gui/theme/custom_font
## で指定すると、初回の import でフォントの import より先に読もうとして ERROR になるため、起動後にこのノードの
## theme の default_font として設定する (子の戦闘画面にも効く。ThemeDB.fallback_font は既定テーマがフォントを
## 持つため効かなかった)
const DEFAULT_FONT: Font = preload("res://assets/fonts/NotoSansJP-Variable.ttf")

## 進行中の戦闘画面 (入る前は null)
var battle: BattleUiScript = null


## 起動の入口。BOOT_MESSAGE は make check がメインシーンのロードと _ready の実行を確かめる印
func _ready() -> void:
	var app_theme: Theme = Theme.new()
	app_theme.default_font = DEFAULT_FONT
	theme = app_theme
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
