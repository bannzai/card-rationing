extends Control
## ボス戦の前の会話の画面 (仮の見た目。見た目は関門 2 で決めた方向を #11 で反映する)。ボスの台詞
## (scripts/enemies.gd の talk) を Enter / Space / クリックで 1 行ずつ出し、最後の行の後に「戦う」で finished を出す。
## 地図のボスの節点 → この会話 → 戦闘 の接続は画面の流れの issue (#7・#8) で行う。
## 日本語のフォントはメインシーンの theme が持つため、メインシーンの子に置いて使う。

## 最後の台詞の後に「戦う」を選んだ (1 回の会話で 1 度だけ出す)
signal finished

const Enemies := preload("res://scripts/enemies.gd")

## 会話するボスの敵 ID
var boss_id: String = Enemies.BOSS_ENCOUNTER[0]
## 表示中の台詞の index
var line_index: int = 0
## finished を出した後か
var done: bool = false

## scenes/boss_talk.tscn のノード
@onready var boss_name_label: Label = $Layout/BossNameLabel
@onready var line_label: Label = $Layout/LinePanel/LineLabel
@onready var hint_label: Label = $Layout/BottomRow/HintLabel
@onready var fight_button: Button = $Layout/BottomRow/FightButton


func _ready() -> void:
	fight_button.pressed.connect(advance)
	refresh()


## boss_id のボスとの会話を最初の台詞から始める
func start(boss: String) -> void:
	boss_id = boss
	line_index = 0
	done = false
	refresh()


## 次の台詞へ進む。最後の台詞なら「戦う」を選んだとして finished を出す
func advance() -> void:
	if done:
		return
	if line_index < _lines().size() - 1:
		line_index += 1
		refresh()
		return
	done = true
	finished.emit()


## Enter / Space で次へ
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: Key = (event as InputEventKey).keycode
	if key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
		advance()


## クリックで次へ (背景と文字はマウスを通すので、このノードが受ける)
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var click: InputEventMouseButton = event
	if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		advance()


## 表示中の台詞を画面に反映する。「戦う」は最後の台詞でだけ出す
func refresh() -> void:
	var lines: Array = _lines()
	var last: bool = line_index >= lines.size() - 1
	boss_name_label.text = Enemies.ENEMIES[boss_id]["name"]
	line_label.text = lines[line_index]
	hint_label.text = "" if last else "次へ  Enter / クリック  %d / %d" % [line_index + 1, lines.size()]
	fight_button.visible = last


## ボスの台詞の並び
func _lines() -> Array:
	return Enemies.ENEMIES[boss_id]["talk"]
