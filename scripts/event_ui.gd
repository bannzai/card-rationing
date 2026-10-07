extends Control
## 出来事の画面。出来事の文と選択肢を並べ、カードを選ぶ選択肢 (契約の入れ替え・血の泉) はデッキから選んで
## 決める。選んだら結果をランに反映して地図へ戻る。処理は scripts/events.gd、選んでいる途中の選択肢と
## カードだけをここに持つ。

const AudioScript := preload("res://scripts/audio.gd")
const CardView := preload("res://scripts/card_view.gd")
const Events := preload("res://scripts/events.gd")
const NodeRules := preload("res://scripts/node_rules.gd")
const RunFlow := preload("res://scripts/run_flow.gd")
const RunStateScript := preload("res://scripts/run_state.gd")
const UiKit := preload("res://scripts/ui_kit.gd")

## ラン単位の状態 (autoload RunState)
var run_state: RunStateScript = null
## BGM と効果音 (autoload Audio)
var audio: AudioScript = null
## 今いる出来事の ID と定義
var event_id: String = ""
var event: Dictionary = {}
## カードを選んでいる選択肢 (-1 なら選択肢を選ぶ段階) と、選んだデッキの index
var pending_option: int = -1
var picks: Array[int] = []
## 今の段階の画面の中身 (段階が変わるたびに作り直す)
var content: VBoxContainer = null
## 選択肢の段階のボタンと、カードを選ぶ段階の格子・決めるボタン
var option_buttons: Array[Button] = []
var deck_grid: GridContainer = null
var confirm_button: Button = null


## 画面のノードを組み立てる
func _ready() -> void:
	run_state = get_tree().root.get_node_or_null("RunState")
	audio = get_tree().root.get_node_or_null("Audio")
	event_id = Events.event_for(run_state.node_seed())
	event = Events.EVENTS[event_id]
	var layout: VBoxContainer = UiKit.screen_layout(self, "出来事: %s" % event["title"])
	UiKit.add_note(layout, event["text"])
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	layout.add_child(content)
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


## カードを選ぶ段階でデッキの index 番目のカードを選ぶ・選び直す。作り直した格子でも、スクロールの位置を
## 保ち、いま選んだカードにフォーカスを残して見える位置に置く (キーボードで続けて選べるように)
func toggle_pick(index: int) -> void:
	var scroll_before: int = (deck_grid.get_parent() as ScrollContainer).scroll_vertical
	if picks.has(index):
		picks.erase(index)
	elif picks.size() < event["options"][pending_option]["picks"]:
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


## option_index 番目の選択肢を chosen のカードで決め、地図へ戻る (決められなければ何もしない)。残り使用回数を
## 戻す選択肢 (血の泉) なら回数の回復の効果音を鳴らす
func _decide(option_index: int, chosen: Array[int]) -> void:
	if Events.choose(run_state, option_index, chosen):
		if event["options"][option_index]["effect"] == Events.Effect.BLOOD_RESTORE:
			audio.play_se(AudioScript.Se.RESTORE)
		RunFlow.leave_node(run_state)


## 今の段階の画面の中身を作り直す
func _rebuild() -> void:
	UiKit.clear_children(content)
	option_buttons = []
	deck_grid = null
	confirm_button = null
	UiKit.add_label(content, UiKit.status_text(run_state))
	if pending_option < 0:
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
		button.disabled = not _can_start(option_index)
		option_buttons.append(button)
	for button: Button in option_buttons:
		if not button.disabled:
			button.grab_focus()
			break


## カードを選ぶ段階: デッキの格子 (選んだカードは印を付ける)、決める・戻るボタン
func _build_picks() -> void:
	var option: Dictionary = event["options"][pending_option]
	UiKit.add_label(
		content, "%s\nカードを %d 枚選ぶ (%d / %d)" % [
			option["label"], option["picks"], picks.size(), option["picks"]
		]
	)
	deck_grid = UiKit.add_deck_grid(content, run_state, _can_pick, toggle_pick)
	for index: int in picks:
		(deck_grid.get_child(index) as CardView).set_picked(true)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	content.add_child(row)
	confirm_button = UiKit.add_button(row, "決める", confirm)
	confirm_button.disabled = not Events.can_choose(run_state, pending_option, picks)
	UiKit.add_button(row, "戻る", cancel)


## option_index 番目の選択肢を今選び始められるか (カードを選ぶ選択肢は、選べるカードの組が 1 つでもあるか)
func _can_start(option_index: int) -> bool:
	var option: Dictionary = event["options"][option_index]
	if option["picks"] == 0:
		var no_picks: Array[int] = []
		return Events.can_choose(run_state, option_index, no_picks)
	if option["effect"] == Events.Effect.BLOOD_RESTORE:
		return run_state.hp > Events.BLOOD_PRICE and range(run_state.deck.size()).any(
			func(index: int) -> bool: return NodeRules.can_restore(run_state, index)
		)
	return (
		run_state.deck.size() >= option["picks"]
		and (
			Events.swapped_deck_size(run_state.deck.size(), option["picks"])
			>= NodeRules.MIN_DECK_SIZE
		)
	)


## カードを選ぶ段階で、デッキの index 番目のカードを選べるか (選んだものは選び直せる)
func _can_pick(index: int) -> bool:
	if picks.has(index):
		return true
	var option: Dictionary = event["options"][pending_option]
	if picks.size() >= option["picks"]:
		return false
	if option["effect"] == Events.Effect.BLOOD_RESTORE:
		return NodeRules.can_restore(run_state, index)
	return true
