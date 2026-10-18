extends Control
## 出来事の画面。出来事の絵の横に文と選択肢を並べ、カードを選ぶ選択肢 (契約の入れ替え・血の泉・蝋の祭壇など) は
## デッキから選んで決める (デッキの格子に幅を譲るため、カードを選ぶ間は絵を隠す)。選んだら結果をランに反映して
## 地図へ戻る。当たり外れのある選択肢 (封蝋の骰子) は、地図へ戻った局面として保存してから結果を見せ、「進む」で
## 地図へ戻る。処理は scripts/events.gd、選んでいる途中の選択肢とカードと、見せている結果だけをここに持つ。

const Art := preload("res://scripts/art.gd")
const AudioScript := preload("res://scripts/audio.gd")
const CardView := preload("res://scripts/card_view.gd")
const Events := preload("res://scripts/events.gd")
const RunFlow := preload("res://scripts/run_flow.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

## 回数の回復の効果音を鳴らす選択肢の処理 (デッキのカードの残り使用回数が増えるもの。封蝋の骰子は当たった時だけ)
const RESTORE_SOUND_EFFECTS: Array[int] = [
	Events.Effect.BLOOD_RESTORE,
	Events.Effect.RAISE_HERO,
	Events.Effect.RAISE_SPIRIT,
	Events.Effect.GOLD_RESTORE,
	Events.Effect.BURN_RESTORE,
]
## 出来事の絵の大きさ (生成した絵と同じ 4:3)。高さは、見出しの下に文・状態・選択肢 3 つを並べた右の列の高さに
## 収まる 324、幅は右の列に最も長い選択肢の文が 1 行で収まる幅を残す 432
const PICTURE_SIZE: Vector2 = Vector2(432, 324)
## 絵と右の列の間隔
const BODY_SEPARATION: int = 24
## 右の列の羊皮紙に載せる文の幅 (画面の縦並びの幅から、絵・間隔・羊皮紙の余白を引いた幅)
const COLUMN_NOTE_WIDTH: float = (
	1280.0 - 2 * UiKit.LAYOUT_MARGIN - PICTURE_SIZE.x - BODY_SEPARATION - 2 * UiKit.PARCHMENT_MARGIN.x
)

## ラン単位の状態 (autoload RunState)
var run_state: RunStateScript = null
## BGM と効果音 (autoload Audio)
var audio: AudioScript = null
## 今いる出来事の ID と定義
var event_id: String = ""
var event: Dictionary = {}
## カードを選んでいる選択肢 (-1 なら選択肢を選ぶ段階) と、選んだデッキの index (選んだ順)
var pending_option: int = -1
var picks: Array[int] = []
## 当たり外れのある選択肢を決めた後に見せる結果の文 (空なら結果の段階ではない)
var result_text: String = ""
## 出来事の絵と、出来事の文を載せたラベル
var picture: TextureRect = null
var note: Label = null
## 今の段階の画面の中身 (段階が変わるたびに作り直す)
var content: VBoxContainer = null
## 選択肢の段階のボタン、カードを選ぶ段階の格子・決めるボタン、結果の段階の地図へ戻るボタン
var option_buttons: Array[Button] = []
var deck_grid: GridContainer = null
var confirm_button: Button = null
var proceed_button: Button = null


## 画面のノードを組み立てる
func _ready() -> void:
	run_state = get_tree().root.get_node_or_null("RunState")
	audio = get_tree().root.get_node_or_null("Audio")
	event_id = Events.event_for(run_state.node_seed())
	event = Events.EVENTS[event_id]
	var layout: VBoxContainer = UiKit.screen_layout(self, "出来事: %s" % event["title"])
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", BODY_SEPARATION)
	layout.add_child(body)
	picture = Art.picture(Art.EVENT_ART[event_id])
	picture.custom_minimum_size = PICTURE_SIZE
	picture.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(picture)
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	body.add_child(column)
	note = UiKit.add_note(column, event["text"], UiKit.BODY_FONT_SIZE, COLUMN_NOTE_WIDTH)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	column.add_child(content)
	_rebuild()


## option_index 番目の選択肢を選ぶ。カードを選ぶ選択肢ならカードを選ぶ段階に入り、そうでなければ決める
func select_option(option_index: int) -> void:
	if event["options"][option_index]["picks"] > 0:
		pending_option = option_index
		picks = []
		_rebuild()
	else:
		var no_picks: Array[int] = []
		_decide(option_index, no_picks)


## カードを選ぶ段階でデッキの index 番目のカードを選ぶ・選び直す (灰の炉は選んだ順に役が決まるので、選び直した
## カードより後に選んだカードも外す)。作り直した格子でも、スクロールの位置を保ち、いま選んだカードにフォーカスを
## 残して見える位置に置く (キーボードで続けて選べるように)
func toggle_pick(index: int) -> void:
	var scroll_before: int = (deck_grid.get_parent() as ScrollContainer).scroll_vertical
	var option: Dictionary = event["options"][pending_option]
	if picks.has(index):
		if option["effect"] == Events.Effect.BURN_RESTORE:
			picks.resize(picks.find(index))
		else:
			picks.erase(index)
	elif picks.size() < option["picks"]:
		picks.append(index)
	_rebuild()
	var button: Button = deck_grid.get_child(index)
	if not button.disabled:
		button.grab_focus()
	# 作り直した格子のレイアウトは次のフレームで決まるため、その後にスクロールの位置を戻す
	await get_tree().process_frame
	if not is_instance_valid(button) or not button.is_inside_tree():
		return
	var scroll: ScrollContainer = button.get_parent().get_parent() as ScrollContainer
	scroll.scroll_vertical = scroll_before
	scroll.ensure_control_visible(button)


## 選んだカードで決める
func confirm() -> void:
	_decide(pending_option, picks)


## 選択肢の段階に戻る
func cancel() -> void:
	pending_option = -1
	picks = []
	_rebuild()


## 結果の段階から地図へ戻る
func proceed() -> void:
	RunFlow.leave_node(run_state)


## option_index 番目の選択肢を chosen のカードで決める (決められなければ何もしない)。デッキのカードの残り使用回数が
## 増える選択肢なら回数の回復の効果音を鳴らして地図へ戻る。封蝋の骰子は、当たれば回数の回復の、外れれば契約切れの
## 効果音を鳴らし、結果を見せる段階に入る
func _decide(option_index: int, chosen: Array[int]) -> void:
	var effect: int = event["options"][option_index]["effect"]
	var card_name: String = run_state.card(chosen[0])["name"] if not chosen.is_empty() else ""
	if not Events.choose(run_state, option_index, chosen):
		return
	if effect == Events.Effect.GAMBLE:
		var won: bool = Events.gamble_wins(run_state.node_seed())
		audio.play_se(AudioScript.Se.RESTORE if won else AudioScript.Se.EXPIRED)
		result_text = (
			"当たり。「%s」の残り使用回数が最大まで戻った" % card_name
			if won
			else "外れ。「%s」の契約を失った" % card_name
		)
		_save_as_left()
		pending_option = -1
		picks = []
		_rebuild()
		return
	if RESTORE_SOUND_EFFECTS.has(effect):
		audio.play_se(AudioScript.Se.RESTORE)
	RunFlow.leave_node(run_state)


## 結果を見せている間に終了しても、賭けの結果を見てから選び直せないよう、節点を出て地図へ戻った局面として
## 保存する (局面は結果の画面のまま。「進む」で RunFlow.leave_node() が同じ内容を保存し直す)
func _save_as_left() -> void:
	var phase: RunStateScript.Phase = run_state.phase
	run_state.phase = RunStateScript.Phase.MAP
	var status: Error = run_state.autosave()
	run_state.phase = phase
	if status != OK:
		push_error("自動保存に失敗: %s (%s)" % [run_state.save_path, error_string(status)])


## 今の段階の画面の中身を作り直す (カードを選ぶ段階だけ絵を隠す)
func _rebuild() -> void:
	UiKit.clear_children(content)
	option_buttons = []
	deck_grid = null
	confirm_button = null
	proceed_button = null
	picture.visible = pending_option < 0
	UiKit.add_label(content, UiKit.status_text(run_state))
	if not result_text.is_empty():
		_build_result()
	elif pending_option < 0:
		_build_options()
	else:
		_build_picks()


## 選択肢のボタン (今選べないものは押せない)
func _build_options() -> void:
	var options: Array = event["options"]
	for option_index: int in range(options.size()):
		var option: Dictionary = options[option_index]
		var button: Button = UiKit.add_button(
			content, option["label"], select_option.bind(option_index)
		)
		button.disabled = not Events.can_start(run_state, option_index)
		option_buttons.append(button)
	for button: Button in option_buttons:
		if not button.disabled:
			button.grab_focus()
			break


## カードを選ぶ段階: 次に選ぶカードの説明、デッキの格子 (選んだカードは印を付ける)、決める・戻るボタン
func _build_picks() -> void:
	var option: Dictionary = event["options"][pending_option]
	var slot: int = mini(picks.size(), option["picks"] - 1)
	var lines: PackedStringArray = [
		option["label"],
		"%sを選ぶ (%d / %d)" % [
			Events.pick_prompt(option["effect"], slot), picks.size(), option["picks"]
		],
	]
	if option["effect"] == Events.Effect.BURN_RESTORE and not picks.is_empty():
		lines.append("炉にくべる: %s" % run_state.card(picks[0])["name"])
	UiKit.add_label(content, "\n".join(lines))
	deck_grid = UiKit.add_deck_grid(content, run_state, _can_pick, toggle_pick)
	for index: int in picks:
		(deck_grid.get_child(index) as CardView).set_picked(true)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	confirm_button = UiKit.add_button(row, "決める", confirm)
	confirm_button.disabled = not Events.can_choose(run_state, pending_option, picks)
	UiKit.add_button(row, "戻る", cancel)


## 結果の段階: 結果の文と、地図へ戻るボタン
func _build_result() -> void:
	UiKit.add_note(content, result_text, UiKit.BODY_FONT_SIZE, COLUMN_NOTE_WIDTH)
	proceed_button = UiKit.add_button(content, "進む", proceed)
	proceed_button.grab_focus()


## カードを選ぶ段階で、デッキの index 番目のカードを選べるか (選んだものは選び直せる。次に選ぶ順番の役で判定する)
func _can_pick(index: int) -> bool:
	if picks.has(index):
		return true
	var option: Dictionary = event["options"][pending_option]
	if picks.size() >= option["picks"]:
		return false
	return Events.can_pick(run_state, option["effect"], index, picks.size())
