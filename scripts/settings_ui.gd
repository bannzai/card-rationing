extends Control
## 設定の画面。BGM と効果音の音量をスライダー (0〜100) で変えるたびに保存し (画面を閉じずにゲームを終えても
## 残るように)、「戻る」か Esc で closed を出す。値は autoload Settings (scripts/settings.gd) に持つ。

## 画面を閉じる (呼んだ側が次の画面を出す)
signal closed

const SettingsScript := preload("res://scripts/settings.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

## 設定 (autoload Settings)
var settings: SettingsScript = null
## BGM と効果音の音量のスライダー
var bgm_slider: HSlider = null
var se_slider: HSlider = null
## 前の画面へ戻るボタン
var back_button: Button = null


## 画面のノードを組み立てる
func _ready() -> void:
	settings = get_tree().root.get_node_or_null("Settings")
	var layout: VBoxContainer = UiKit.screen_layout(self, "設定")
	bgm_slider = _add_volume_row(layout, "BGM の音量", settings.bgm_volume, _on_bgm_changed)
	se_slider = _add_volume_row(layout, "効果音の音量", settings.se_volume, _on_se_changed)
	UiKit.add_label(layout, "← → で音量を変える。音そのものは今後の版で鳴る。", 16)
	back_button = UiKit.add_button(layout, "戻る (Esc)", closed.emit)
	bgm_slider.grab_focus()


## Esc で閉じる
func _unhandled_key_input(event: InputEvent) -> void:
	var key_event: InputEventKey = event as InputEventKey
	if key_event != null and key_event.pressed and key_event.keycode == KEY_ESCAPE:
		closed.emit()


## BGM の音量を変えて保存する
func _on_bgm_changed(value: float) -> void:
	settings.bgm_volume = int(value)
	_save()


## 効果音の音量を変えて保存する
func _on_se_changed(value: float) -> void:
	settings.se_volume = int(value)
	_save()


## 設定を保存する (失敗したら ERROR を出す)
func _save() -> void:
	var status: Error = settings.save_settings()
	if status != OK:
		push_error("設定の保存に失敗: %s (%s)" % [settings.settings_path, error_string(status)])


## 名前 title と音量のスライダー (値の表示付き) の行を parent に足し、スライダーを返す
func _add_volume_row(
	parent: Control, title: String, value: int, on_changed: Callable
) -> HSlider:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	# 行の中のラベルは折り返さない (幅の決まらない横並びでは 1 文字ずつ折り返してしまう)
	var name_label: Label = UiKit.add_label(row, title)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.custom_minimum_size = Vector2(200, 0)
	var slider: HSlider = HSlider.new()
	slider.min_value = 0
	slider.max_value = SettingsScript.MAX_VOLUME
	slider.step = SettingsScript.VOLUME_STEP
	slider.value = value
	slider.custom_minimum_size = Vector2(480, 32)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value_label: Label = UiKit.add_label(row, str(value))
	value_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	slider.value_changed.connect(on_changed)
	slider.value_changed.connect(
		func(new_value: float) -> void: value_label.text = str(int(new_value))
	)
	return slider
