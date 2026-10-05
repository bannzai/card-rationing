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

const UiKit := preload("res://scripts/ui_kit.gd")

## 保存データがあるか (add_child の前に scripts/main.gd が設定する)
var has_save: bool = false
## ボタンの下に出す知らせ (保存データが壊れていた時など。add_child の前に設定する)
var notice: String = ""

## タイトルのボタン (巡礼を始める / 続きから / 設定 / 終了)
var start_button: Button = null
var continue_button: Button = null
var settings_button: Button = null
var quit_button: Button = null


## 画面のノードを組み立てる
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column: VBoxContainer = VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BOTH
	column.custom_minimum_size = Vector2(420, 0)
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	var title: Label = UiKit.add_label(column, "Card Rationing", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle: Label = UiKit.add_label(column, "契約の印 — 1 回の巡礼で命令できる回数は決まっている")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_button = UiKit.add_button(column, "巡礼を始める", start_requested.emit)
	continue_button = UiKit.add_button(column, "続きから", continue_requested.emit)
	continue_button.visible = has_save
	settings_button = UiKit.add_button(column, "設定", settings_requested.emit)
	quit_button = UiKit.add_button(column, "終了", quit_requested.emit)
	var notice_label: Label = UiKit.add_label(column, notice)
	notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	(continue_button if has_save else start_button).grab_focus()
