extends Control
## タイトル画面。「巡礼を始める」「続きから」(保存データがある時だけ)「設定」「終了」を並べ、押されたら
## シグナルで scripts/main.gd に伝える。矢印キーと Enter でも選べる。

## 「巡礼を始める」が押された
signal start_requested
## 「続きから」が押された
signal continue_requested
## 「設定」が押された
signal settings_requested
## 「終了」が押された
signal quit_requested

const Art := preload("res://scripts/art.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

## ゲーム名の文字の大きさと縁取りの太さ (タイトルの絵の空の上に載せる)。仮の名前「Sigilbound」が LOGO_RECT の
## 幅に 1 行で収まる大きさで、縁取りは明るい夕焼けの雲の上でも字の形が埋もれない太さにした
const LOGO_FONT_SIZE: int = 92
const LOGO_OUTLINE_SIZE: int = 10
## ゲーム名と副題を置く範囲 (絵の、空が広く空いた中央の上) と、ボタンの列を置く範囲 (絵の、霧の谷の右下)
const LOGO_RECT: Rect2 = Rect2(290, 36, 700, 200)
const MENU_RECT: Rect2 = Rect2(930, 420, 300, 280)

## 保存データがあるか (add_child の前に scripts/main.gd が設定する)
var has_save: bool = false
## ボタンの上に出す知らせ (保存データが壊れていた時など。add_child の前に設定する)
var notice: String = ""

## タイトルのボタン (巡礼を始める / 続きから / 設定 / 終了)
var start_button: Button = null
var continue_button: Button = null
var settings_button: Button = null
var quit_button: Button = null


## 画面のノードを組み立てる
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Art.add_background(self, Art.TITLE)
	var heading: VBoxContainer = _add_column(LOGO_RECT, 0)
	# ゲーム名は仮の名前で変わり得るため、project.godot の表示名を正にする
	var logo: Label = UiKit.add_label(
		heading, ProjectSettings.get_setting("application/config/name"), LOGO_FONT_SIZE
	)
	logo.add_theme_constant_override("outline_size", LOGO_OUTLINE_SIZE)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle: Label = UiKit.add_label(heading, "契約の印 — 1 回の巡礼で命令できる回数は決まっている")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var menu: VBoxContainer = _add_column(MENU_RECT, 12)
	menu.alignment = BoxContainer.ALIGNMENT_END
	var notice_label: Label = UiKit.add_label(menu, notice, 16)
	notice_label.visible = notice != ""
	start_button = UiKit.add_button(menu, "巡礼を始める", start_requested.emit)
	continue_button = UiKit.add_button(menu, "続きから", continue_requested.emit)
	continue_button.visible = has_save
	settings_button = UiKit.add_button(menu, "設定", settings_requested.emit)
	quit_button = UiKit.add_button(menu, "終了", quit_requested.emit)
	# ボタンの木の札は列の幅に揃える
	for button: Button in [start_button, continue_button, settings_button, quit_button]:
		button.size_flags_horizontal = Control.SIZE_FILL
	(continue_button if has_save else start_button).grab_focus()


## rect の位置に、間隔 separation の縦並びを置く
func _add_column(rect: Rect2, separation: int) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.position = rect.position
	column.size = rect.size
	column.add_theme_constant_override("separation", separation)
	add_child(column)
	return column
