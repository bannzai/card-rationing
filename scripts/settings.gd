extends Node
## 設定 (BGM・効果音の音量) の autoload (登録名 Settings)。起動時に読み込み、設定画面を閉じる時に保存する。
## 音そのものは BGM と効果音の issue (#12) で鳴らし、ここの値を使う。
## --script の検証から使う時は root.get_node_or_null("Settings") で取るか、このスクリプトを new() する。

## 本番の保存先
const SETTINGS_PATH: String = "user://settings.cfg"
## 音量の既定値 (最大より少し下げ、初めて起動した時に音が大きすぎないようにする)
const DEFAULT_VOLUME: int = 80
## 音量の最大値 (音量は 0〜MAX_VOLUME の整数で、百分率として読める値にする)
const MAX_VOLUME: int = 100
## 設定画面のスライダーの 1 段の幅 (矢印キーで 20 回押すと端から端まで動く)
const VOLUME_STEP: int = 5
## 保存ファイル (ConfigFile) の節と項目
const SECTION: String = "audio"
const BGM_KEY: String = "bgm_volume"
const SE_KEY: String = "se_volume"

## BGM の音量 (0〜MAX_VOLUME)
var bgm_volume: int = DEFAULT_VOLUME
## 効果音の音量 (0〜MAX_VOLUME)
var se_volume: int = DEFAULT_VOLUME
## 保存先 (検証は本番と別の保存先に差し替える)
var settings_path: String = SETTINGS_PATH


func _ready() -> void:
	load_settings()


## settings_path から読み込む。無い・読めない・数でない項目は既定値に、範囲の外は 0〜MAX_VOLUME に収める
func load_settings() -> void:
	bgm_volume = DEFAULT_VOLUME
	se_volume = DEFAULT_VOLUME
	if not FileAccess.file_exists(settings_path):
		return
	var config: ConfigFile = ConfigFile.new()
	if config.load(settings_path) != OK:
		return
	bgm_volume = _volume(config.get_value(SECTION, BGM_KEY, DEFAULT_VOLUME))
	se_volume = _volume(config.get_value(SECTION, SE_KEY, DEFAULT_VOLUME))


## settings_path に保存する
func save_settings() -> Error:
	var config: ConfigFile = ConfigFile.new()
	config.set_value(SECTION, BGM_KEY, bgm_volume)
	config.set_value(SECTION, SE_KEY, se_volume)
	return config.save(settings_path)


## 保存データの値を音量にする (数でなければ既定値、範囲の外は収める)
func _volume(value: Variant) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return DEFAULT_VOLUME
	return clampi(int(value), 0, MAX_VOLUME)
