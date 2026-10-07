extends Control
## 起動時に表示するメインシーン。タイトル・契約者の選択・設定と、ランの局面 (RunState.phase) に応じた画面
## (地図・戦闘・報酬・契約の祠・商人・出来事・敗北 / 踏破) を 1 つだけ子に置いて切り替える。ランの状態は
## autoload RunState に持ち、ここは表示する画面を選ぶだけ。ランの間は契約の一覧を D キーか右下のボタンで
## いつでも重ねて開ける。画面に合わせて BGM も切り替える (曲の割り当ては scripts/audio.gd の bgm_for())。

const BOOT_MESSAGE: String = "card-rationing boot"
const BATTLE_SCENE: PackedScene = preload("res://scenes/battle.tscn")
const BOSS_TALK_SCENE: PackedScene = preload("res://scenes/boss_talk.tscn")
const ActMap := preload("res://scripts/act_map.gd")
const AudioScript := preload("res://scripts/audio.gd")
const BattleUiScript := preload("res://scripts/battle_ui.gd")
const BossTalkScript := preload("res://scripts/boss_talk.gd")
const CharacterSelectUiScript := preload("res://scripts/character_select_ui.gd")
const DeckListUiScript := preload("res://scripts/deck_list_ui.gd")
const EventUiScript := preload("res://scripts/event_ui.gd")
const MapUiScript := preload("res://scripts/map_ui.gd")
const ResultUiScript := preload("res://scripts/result_ui.gd")
const RewardUiScript := preload("res://scripts/reward_ui.gd")
const RunFlow := preload("res://scripts/run_flow.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const SettingsUiScript := preload("res://scripts/settings_ui.gd")
const ShopUiScript := preload("res://scripts/shop_ui.gd")
const ShrineUiScript := preload("res://scripts/shrine_ui.gd")
const TitleUiScript := preload("res://scripts/title_ui.gd")
const UiKit := preload("res://scripts/ui_kit.gd")
## 保存データが壊れていた時のタイトルの知らせ
const CORRUPT_NOTICE: String = "保存データが壊れていたため読み込まずに退避した。新しい巡礼を始めてほしい。"
## 保存データを開けなかった時のタイトルの知らせ (保存データは退避せず残っているが、「巡礼を始める」は
## 保存データがあっても上書きする (DIRECTION.md「決めたこと」) ため、そのことも伝える)
const READ_ERROR_NOTICE: String = (
	"保存データを読めなかった。ファイルは残してあるが、新しい巡礼を始めると上書きされる。"
)

## ラン単位の状態 (autoload RunState)
var run_state: RunStateScript = null
## BGM と効果音 (autoload Audio)
var audio: AudioScript = null
## 今表示している画面 (タイトル・地図・戦闘など。常に 1 つ)
var screen: Control = null
## 重ねて開いている契約の一覧 (閉じていれば null)
var deck_list: DeckListUiScript = null
## 契約の一覧を開くボタン (ランの画面でだけ見せる)
var deck_button: Button = null
## 契約の一覧を開く前にフォーカスがあった下の画面のコントロール (閉じる時に戻す。無ければ null)
var focus_before_deck_list: Control = null


## 起動の入口。BOOT_MESSAGE は make check がメインシーンのロードと _ready の実行を確かめる印
func _ready() -> void:
	# 全画面の見た目 (フォントを含む) は、このノードの theme として設定する (子の画面にも効く)。フォントを
	# project.godot の gui/theme/custom_font で指定すると、初回の import でフォントの import より先に読もうとして
	# ERROR になる (ThemeDB.fallback_font は既定テーマがフォントを持つため効かなかった)
	theme = UiKit.build_theme()
	run_state = get_tree().root.get_node_or_null("RunState")
	audio = get_tree().root.get_node_or_null("Audio")
	if run_state == null or audio == null:
		push_error("autoload RunState か Audio が無い")
		return
	run_state.phase_changed.connect(show_run_phase)
	deck_button = Button.new()
	deck_button.text = "契約の一覧 (D)"
	deck_button.focus_mode = Control.FOCUS_NONE
	deck_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	deck_button.add_theme_font_size_override("font_size", 16)
	deck_button.offset_left = -176
	deck_button.offset_top = -56
	deck_button.offset_right = -16
	deck_button.offset_bottom = -12
	deck_button.pressed.connect(open_deck_list)
	add_child(deck_button)
	show_title()
	print(BOOT_MESSAGE)


## ランの画面で D キーを押すと契約の一覧を開く (開いている間のキーは契約の一覧が受け止める)
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if (event as InputEventKey).keycode == KEY_D and deck_button.visible:
		open_deck_list()


## タイトル画面を出す (BGM は鳴らさない)。notice はボタンの上に出す知らせ
func show_title(notice: String = "") -> void:
	audio.play_bgm(AudioScript.Bgm.NONE)
	var title: TitleUiScript = TitleUiScript.new()
	title.has_save = FileAccess.file_exists(run_state.save_path)
	title.notice = notice
	title.start_requested.connect(show_character_select)
	title.continue_requested.connect(continue_run)
	title.settings_requested.connect(show_settings)
	title.quit_requested.connect(get_tree().quit)
	_set_screen(title, false)


## 巡礼の開始の契約者の選択画面を出す
func show_character_select() -> void:
	var select: CharacterSelectUiScript = CharacterSelectUiScript.new()
	select.chosen.connect(start_run)
	select.back_requested.connect(show_title)
	_set_screen(select, false)


## 設定画面を出す (閉じたらタイトルへ)。変えた BGM の音量を聞いて確かめられるよう、開いている間は地図の曲を鳴らす
func show_settings() -> void:
	audio.play_bgm(AudioScript.Bgm.MAP)
	var settings_ui: SettingsUiScript = SettingsUiScript.new()
	settings_ui.closed.connect(show_title)
	_set_screen(settings_ui, false)


## character_id の契約者で新しい巡礼を始める (地図の画面は局面の変化で出る)。seed_value が負なら乱数で
## 地図を作る (randi() は非負なので、負の値を「指定なし」に使える)
func start_run(character_id: String, seed_value: int = -1) -> void:
	RunFlow.start_run(run_state, character_id, randi() if seed_value < 0 else seed_value)


## 保存データを読み込んで、保存した局面の画面から再開する。壊れていたらタイトルで知らせる
func continue_run() -> void:
	match run_state.load_from(run_state.save_path):
		RunStateScript.LoadResult.LOADED:
			show_run_phase()
		RunStateScript.LoadResult.CORRUPT:
			show_title(CORRUPT_NOTICE)
		RunStateScript.LoadResult.READ_ERROR:
			show_title(READ_ERROR_NOTICE)
		_:
			show_title()


## ランの今の局面の画面を出す。戦闘は今いる節点の戦闘を最初から始め (戦闘の途中から再開した時も同じ)、
## ボスの節点ではボス戦の前の会話を先に出す
func show_run_phase() -> void:
	var node_kind: int = run_state.current_node().get("kind", ActMap.Kind.BATTLE)
	audio.play_bgm(AudioScript.bgm_for(run_state.phase, node_kind))
	match run_state.phase:
		RunStateScript.Phase.MAP:
			_set_screen(MapUiScript.new(), true)
		RunStateScript.Phase.BATTLE:
			if node_kind == ActMap.Kind.BOSS:
				_show_boss_talk()
			else:
				show_battle()
		RunStateScript.Phase.REWARD:
			_set_screen(RewardUiScript.new(), true)
		RunStateScript.Phase.SHRINE:
			_set_screen(ShrineUiScript.new(), true)
		RunStateScript.Phase.SHOP:
			_set_screen(ShopUiScript.new(), true)
		RunStateScript.Phase.EVENT:
			_set_screen(EventUiScript.new(), true)
		_:
			var result: ResultUiScript = ResultUiScript.new()
			result.closed.connect(show_title)
			_set_screen(result, false)


## 今いる節点の戦闘の画面を出す (戦闘は最初のターンから始まる。ボス戦の前の会話の「戦う」からも呼ぶ)
func show_battle() -> void:
	var battle_ui: BattleUiScript = BATTLE_SCENE.instantiate()
	_set_screen(battle_ui, true)
	battle_ui.start_battle(run_state.node_seed())


## ボス戦の前の会話の画面を出す。最後の台詞の後の「戦う」で戦闘に入る (戦闘の途中から再開した時も会話から)
func _show_boss_talk() -> void:
	var talk: BossTalkScript = BOSS_TALK_SCENE.instantiate()
	talk.finished.connect(show_battle)
	# 会話の「戦う」ボタンが右下に出て契約の一覧のボタンと重なるため、会話の間は契約の一覧のボタンを出さない
	_set_screen(talk, false)
	talk.start(RunFlow.encounter(run_state)[0])


## 契約の一覧を重ねて開く (開いていれば何もしない)
func open_deck_list() -> void:
	if deck_list != null:
		return
	focus_before_deck_list = get_viewport().gui_get_focus_owner()
	deck_list = DeckListUiScript.new()
	deck_list.closed.connect(close_deck_list)
	add_child(deck_list)


## 契約の一覧を閉じ、開く前にフォーカスがあった下の画面のボタンへフォーカスを戻す (Enter で続けて選べるように)
func close_deck_list() -> void:
	if deck_list == null:
		return
	_discard(deck_list)
	deck_list = null
	if is_instance_valid(focus_before_deck_list) and focus_before_deck_list.is_visible_in_tree():
		focus_before_deck_list.grab_focus()
	focus_before_deck_list = null


## 表示する画面を next にする。前の画面は入力を止めて隠し、フレームの終わりに解放する (前の画面の入力の
## 処理の中から呼ばれても安全なように)。in_run なら契約の一覧のボタンを見せる
func _set_screen(next: Control, in_run: bool) -> void:
	close_deck_list()
	if screen != null:
		_discard(screen)
	screen = next
	add_child(screen)
	# 背景の次に置き、契約の一覧のボタンと契約の一覧を上に重ねる
	move_child(screen, 1)
	deck_button.visible = in_run


## node を入力から外して隠し、フレームの終わりに解放する
func _discard(node: Control) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	node.visible = false
	node.queue_free()
