extends Node
## BGM と効果音を鳴らす autoload (登録名 Audio)。BGM は 1 曲ずつ繰り返し鳴らし、効果音は種類ごとのプレイヤーで
## 重ねて鳴らす。音量は autoload Settings (scripts/settings.gd) の値を BGM・効果音のバスに反映する。
## どの場面でどの音を鳴らすかは documents/DIRECTION.md「決めたこと」。素材の出典は assets/CREDITS.md。
## 素材は preload せず実行時に load する (autoload のスクリプトは初回の import でエディタが先に読むため、
## import 前の素材を preload すると ERROR になる)。
## --script の検証から使う時は root.get_node_or_null("Audio") で取る。

## BGM の曲 (NONE は無音)
enum Bgm { NONE, MAP, BATTLE, BOSS }
## 効果音。CARD_USE・LAST_ONE・EXPIRED はカードを使った後の残り使用回数で鳴らし分ける (card_use_se())
enum Se { CARD_USE, LAST_ONE, EXPIRED, RESTORE, HIT, WIN, LOSE }

const ActMap := preload("res://scripts/act_map.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const SettingsScript := preload("res://scripts/settings.gd")

## BGM と効果音のバス (設定の音量を反映する。無ければ起動時に Master へ送るバスとして作る)
const BGM_BUS: StringName = &"BGM"
const SE_BUS: StringName = &"SE"
## 曲・効果音 → 素材のパス
const BGM_PATHS: Dictionary = {
	Bgm.MAP: "res://assets/audio/bgm_map.ogg",
	Bgm.BATTLE: "res://assets/audio/bgm_battle.ogg",
	Bgm.BOSS: "res://assets/audio/bgm_boss.ogg",
}
const SE_PATHS: Dictionary = {
	Se.CARD_USE: "res://assets/audio/se_card_use.wav",
	Se.LAST_ONE: "res://assets/audio/se_last_one.wav",
	Se.EXPIRED: "res://assets/audio/se_expired.wav",
	Se.RESTORE: "res://assets/audio/se_restore.wav",
	Se.HIT: "res://assets/audio/se_hit.wav",
	Se.WIN: "res://assets/audio/se_win.wav",
	Se.LOSE: "res://assets/audio/se_lose.wav",
}

## 今鳴らしている BGM
var bgm: Bgm = Bgm.NONE
## BGM のプレイヤー
var bgm_player: AudioStreamPlayer = null
## 効果音のプレイヤー (Se → AudioStreamPlayer)
var se_players: Dictionary = {}
## 設定 (autoload Settings)
var settings: SettingsScript = null


func _ready() -> void:
	add_buses()
	bgm_player = _add_player(BGM_BUS)
	for se: int in SE_PATHS:
		var player: AudioStreamPlayer = _add_player(SE_BUS)
		player.stream = load(SE_PATHS[se])
		se_players[se] = player
	settings = get_tree().root.get_node_or_null("Settings")
	if settings == null:
		push_error("autoload Settings が無い")
		return
	settings.volume_changed.connect(_apply_settings)
	_apply_settings()


## track の BGM を繰り返し鳴らす (NONE なら止める)。今鳴らしている曲と同じなら鳴らし直さない (地図 → 報酬 →
## 地図のように同じ曲が続く画面の切り替えで、曲を頭に戻さないため)
func play_bgm(track: Bgm) -> void:
	if track == bgm:
		return
	bgm = track
	if track == Bgm.NONE:
		bgm_player.stop()
		return
	bgm_player.stream = bgm_stream(track)
	bgm_player.play()


## se の効果音を鳴らす。冪等でない: 鳴っている途中に呼ぶと頭から鳴らし直す (続けて使ったカードの 1 枚ごとに
## 音を返すため)
func play_se(se: Se) -> void:
	(se_players[se] as AudioStreamPlayer).play()


## BGM と効果音をすべて止める
func stop_all() -> void:
	play_bgm(Bgm.NONE)
	for player: AudioStreamPlayer in se_players.values():
		player.stop()


## ランの局面 phase と今いる節点の種類 node_kind (ActMap.Kind) で鳴らす BGM。戦闘はボスの節点 (ボス戦の前の
## 会話を含む) だけボスの曲、ランの終わり (敗北・踏破) は無音、ほか (地図・報酬・祠・商人・出来事) は地図の曲
static func bgm_for(phase: RunStateScript.Phase, node_kind: int) -> Bgm:
	match phase:
		RunStateScript.Phase.DEFEAT, RunStateScript.Phase.CLEAR:
			return Bgm.NONE
		RunStateScript.Phase.BATTLE:
			return Bgm.BOSS if node_kind == ActMap.Kind.BOSS else Bgm.BATTLE
	return Bgm.MAP


## カードを使った後の残り使用回数 uses_left で鳴らす効果音 (0 = 契約切れ、1 = 最後の 1 回が残った、
## 2 以上 = 使った)
static func card_use_se(uses_left: int) -> Se:
	if uses_left <= 0:
		return Se.EXPIRED
	if uses_left == 1:
		return Se.LAST_ONE
	return Se.CARD_USE


## track の BGM の素材。Ogg Vorbis の読み込み設定 (.import) は繰り返しが既定で無効で、エディタを開かずに
## 設定を変えられないため、ここで繰り返しを有効にする
static func bgm_stream(track: Bgm) -> AudioStreamOggVorbis:
	var stream: AudioStreamOggVorbis = load(BGM_PATHS[track])
	stream.loop = true
	return stream


## BGM_BUS と SE_BUS のうち無いバスを、Master へ送るバスとして足す。あるバスはそのままにする
static func add_buses() -> void:
	for bus: StringName in [BGM_BUS, SE_BUS]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, &"Master")


## bus の音量を volume (0〜SettingsScript.MAX_VOLUME) にする。0 はミュートにする (linear_to_db(0) が -inf に
## なるため)
static func apply_volume(bus: StringName, volume: int) -> void:
	var index: int = AudioServer.get_bus_index(bus)
	AudioServer.set_bus_mute(index, volume <= 0)
	if volume > 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(float(volume) / SettingsScript.MAX_VOLUME))


## 設定の音量を BGM と効果音のバスに反映する
func _apply_settings() -> void:
	apply_volume(BGM_BUS, settings.bgm_volume)
	apply_volume(SE_BUS, settings.se_volume)


## bus で鳴らすプレイヤーを子に足して返す
func _add_player(bus: StringName) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player
