extends RefCounted
## 見た目「蝋と灯火」の素材 (絵・フォント・色) の置き場と、絵を並べる・戦闘の動きを付けるだけの小さな部品。方向の定義は
## documents/DIRECTION.md「デザインの方向」、素材の出典は assets/CREDITS.md。
## カードの絵は種別ごと、敵の絵は格ごと、地図の印は節点の種類ごとに共有する (1 枚ごと・1 体ごとの絵は #13)。
## autoload のスクリプト (scripts/run_state.gd・scripts/settings.gd) とそこから読まれるスクリプトには
## preload させない (初回の import では autoload が絵の import より先に読まれ、ERROR になるため)。

const ActMap := preload("res://scripts/act_map.gd")
const Cards := preload("res://scripts/cards.gd")
const Enemies := preload("res://scripts/enemies.gd")

## 全画面の既定フォント (日本語の字形を持つ明朝体)
const FONT: Font = preload("res://assets/fonts/ShipporiMincho-SemiBold.ttf")

## 戦闘の背景・戦闘以外の画面の背景 (戦闘の背景をぼかして暗くしたもの)・タイトルの絵
const BATTLE_BG: Texture2D = preload("res://assets/art/battle_bg.jpg")
const BACKDROP: Texture2D = preload("res://assets/art/backdrop.jpg")
const TITLE: Texture2D = preload("res://assets/art/title.jpg")
## 巡礼者 (プレイヤー) の立ち絵
const PILGRIM: Texture2D = preload("res://assets/art/pilgrim.png")
## カードの枠 (内側は白紙の羊皮紙) と、契約切れのカードから色を抜くシェーダー
const CARD_FRAME: Texture2D = preload("res://assets/art/card_frame.png")
const ASHEN_SHADER: Shader = preload("res://assets/shaders/ashen.gdshader")
## 封蝋の印 (残っている印 / 使って焼けた印)
const SEAL: Texture2D = preload("res://assets/art/seal.png")
const SEAL_BURNT: Texture2D = preload("res://assets/art/seal_burnt.png")
## スライダーのつまみに使う小さい封蝋の印 (theme のアイコンは絵の大きさのまま描かれるため、縮小した絵を持つ)
const SEAL_GRABBER: Texture2D = preload("res://assets/art/seal_grabber.png")
## 力 (エネルギー) を示す蝋燭 (灯っている / 消えた) と、体力を示す数珠の珠 (残っている / 失った)
const CANDLE_LIT: Texture2D = preload("res://assets/art/candle_lit.png")
const CANDLE_OUT: Texture2D = preload("res://assets/art/candle_out.png")
const BEAD: Texture2D = preload("res://assets/art/bead.png")
const BEAD_DULL: Texture2D = preload("res://assets/art/bead_dull.png")
## 文を載せる羊皮紙と、ボタンの木の札 (どちらも端を残して引き伸ばす)
const PARCHMENT: Texture2D = preload("res://assets/art/parchment.png")
const PLAQUE: Texture2D = preload("res://assets/art/plaque.png")
## カードの種別 → 絵
const CARD_ART: Dictionary = {
	Cards.Kind.ATTACK: preload("res://assets/art/card_attack.jpg"),
	Cards.Kind.GUARD: preload("res://assets/art/card_guard.jpg"),
	Cards.Kind.SKILL: preload("res://assets/art/card_skill.jpg"),
}
## 敵の格 → 絵
const ENEMY_ART: Dictionary = {
	Enemies.Rank.NORMAL: preload("res://assets/art/enemy_normal.png"),
	Enemies.Rank.ELITE: preload("res://assets/art/enemy_elite.png"),
	Enemies.Rank.BOSS: preload("res://assets/art/enemy_boss.png"),
}
## 地図の節点の種類 → 印
const MAP_ICONS: Dictionary = {
	ActMap.Kind.BATTLE: preload("res://assets/art/map_battle.png"),
	ActMap.Kind.ELITE: preload("res://assets/art/map_elite.png"),
	ActMap.Kind.EVENT: preload("res://assets/art/map_event.png"),
	ActMap.Kind.SHRINE: preload("res://assets/art/map_shrine.png"),
	ActMap.Kind.SHOP: preload("res://assets/art/map_shop.png"),
	ActMap.Kind.BOSS: preload("res://assets/art/map_boss.png"),
}

## 絵の上に載せる文字 (生成りの紙の色) と、その縁取り (夜の藍)
const PAPER: Color = Color(0.94, 0.88, 0.74)
const NIGHT: Color = Color(0.05, 0.05, 0.09)
## 羊皮紙の上に載せる文字 (墨)
const INK: Color = Color(0.17, 0.11, 0.07)
## 選べるもの・フォーカスを示す蝋燭の橙と、契約の印の封蝋の赤
const CANDLE: Color = Color(1.0, 0.74, 0.38)
const SEAL_RED: Color = Color(0.62, 0.11, 0.09)
## 押せないボタンの文字 (灰)
const ASH: Color = Color(0.56, 0.53, 0.5)
## 絵の上の文字の縁取りの太さ
const OUTLINE_SIZE: int = 4

## 戦闘の動きの長さ (秒) と強さ (scripts/battle_ui.gd・scripts/enemy_view.gd が使う)。動きは表示だけで、戦闘の
## 状態 (scripts/battle.gd) は動きを待たずに更新し、次の入力も待たせない (勝った時の画面の切り替えだけは
## WIN_DELAY 待つ)。長さは 1 つの出来事を目で追える 0.1〜0.4 秒 (issue #39 の目安) にした。
## カードを使う: 持ち上げ (CARD_LIFT_TIME で CARD_LIFT 上へ。カードの高さ 272 の 1 割強で、持ち上がったと分かり
## 上の敵の行には届かない) → 封蝋の印が光ってから焼ける (SEAL_FLASH_TIME) → 敵の方へ縮みながら消える
## (CARD_FLY_TIME で CARD_FLY_SCALE の大きさへ)。残り 1 回・契約切れになった時は、印が焼けた後に
## STRONG_TIME だけカードを STRONG_SCALE に膨らませて STRONG_FLASH の色で光らせる (普通の使用と見分けられる
## よう、印の光の 2 倍の長さにした)
const CARD_LIFT_TIME: float = 0.1
const CARD_LIFT: float = 36.0
const SEAL_FLASH_TIME: float = 0.15
const CARD_FLY_TIME: float = 0.25
const CARD_FLY_SCALE: float = 0.4
const STRONG_TIME: float = 0.3
const STRONG_SCALE: float = 1.15
## 光らせる色。GL Compatibility では 1 を超えた分も掛け算で明るくなる (封蝋の赤の印は橙に光る)
const SEAL_FLASH: Color = Color(2.4, 2.0, 1.4)
const STRONG_FLASH: Color = Color(1.7, 0.8, 0.6)
## 被弾: HIT_TIME で揺れて (敵は ENEMY_SHAKE、巡礼者は PLAYER_SHAKE。巡礼者の絵は敵より小さく、手札のすぐ上に
## あるので小さくする) HIT_FLASH の赤から元の色に戻る
const HIT_TIME: float = 0.25
const ENEMY_SHAKE: float = 10.0
const PLAYER_SHAKE: float = 6.0
const HIT_FLASH: Color = Color(1.0, 0.3, 0.3)
## 減った体力・防御で受けた量の数字: FLOAT_TIME で FLOAT_RISE 上へ浮きながら消える。数字を読めるよう、ほかの
## 動きより長い 0.6 秒にした (playtest の 1 手 0.2 秒の 3 手分。次の手の数字と重なっても読める高さだけ浮かせる)
const FLOAT_TIME: float = 0.6
const FLOAT_RISE: float = 48.0
const FLOAT_FONT_SIZE: int = 30
## 減った体力の数字 (赤) と、防御で受けた量の数字 (防御の印象の青)
const DAMAGE_COLOR: Color = Color(1.0, 0.38, 0.3)
const BLOCKED_COLOR: Color = Color(0.62, 0.8, 1.0)
## 倒した敵が倒した時の見た目へ薄くなる長さと、最後の敵を倒してから報酬・結果の画面へ移るまでの待ち (倒す動きと
## 決めの 1 枚が消えるまでが見えるよう、最も長いカードを使う動き (残り 1 回・契約切れになった時の合計 0.8 秒) を
## 少し超える長さにした)
const DEFEAT_TIME: float = 0.4
const WIN_DELAY: float = 0.9
## 敵の予告の切り替えと、ターンの始まりの手札のフェード
const FADE_TIME: float = 0.2
## 護符が働いた時: 護符の印 (scripts/relic_view.gd) が RELIC_FLASH_TIME で RELIC_SCALE に膨らんで RELIC_FLASH の色に
## 光って戻り、印の下から護符の名前が浮く (数字と同じ float_text())。長さは封蝋の印が残り 1 回で膨らむ動き
## (STRONG_TIME) と同じにし、カードを使う動きと並んでも見分けられるよう、印の大きさに対して大きく膨らませる
const RELIC_FLASH_TIME: float = 0.3
const RELIC_SCALE: float = 1.4
const RELIC_FLASH: Color = Color(2.2, 1.8, 1.2)

## 戦闘の動きの長さに掛ける倍率。0 なら動きを作らない (tween・使ったカードの複製・数字を作らず、勝った時の
## 画面の切り替えも待たない)。fps が固定でない検証 (integration・screenshot) が 0 にして、同じ瞬間を確かめ・撮る
static var motion_scale: float = 1.0


## 画面の全面に texture の絵を敷く (縦横比を保って画面を覆う)。マウスは通す
static func add_background(parent: Control, texture: Texture2D) -> TextureRect:
	var background: TextureRect = picture(texture)
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(background)
	return background


## texture の絵を、置いた大きさに縦横比を保って収める TextureRect (マウスは通す)
static func picture(texture: Texture2D) -> TextureRect:
	var rect: TextureRect = TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## row の子を total 個の絵にし、先頭から lit 個を on、残りを off の絵にする (子は使い回し、呼ぶたびに同じ結果に
## なる)。封蝋の印の列・力の蝋燭・体力の数珠に使う
static func set_icons(
	row: BoxContainer, on: Texture2D, off: Texture2D, lit: int, total: int, icon_size: Vector2
) -> void:
	while row.get_child_count() < total:
		var icon: TextureRect = picture(null)
		# 契約切れのカードの色を抜くシェーダーを印にも効かせる
		icon.use_parent_material = true
		row.add_child(icon)
	for index: int in range(row.get_child_count()):
		var icon: TextureRect = row.get_child(index)
		icon.visible = index < total
		icon.custom_minimum_size = icon_size
		icon.texture = on if index < lit else off


## max_value のうち value が残っている量を total 個の珠で示す時に、残っている珠の数 (端数は切り上げ、value が
## 1 以上なら 1 つは残す。体力が残っているのに珠がすべて消えて見えないように)
static func lit_count(value: int, max_value: int, total: int) -> int:
	if value <= 0 or max_value <= 0:
		return 0
	return clampi(ceili(float(value) * total / max_value), 1, total)


## label を絵の上で読める文字にする (color の色に夜の藍の縁取り)。color を省くと、暗い絵の上で最も読みやすい
## 生成りの色にする
static func on_picture(label: Label, color: Color = PAPER) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", NIGHT)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)


## label を羊皮紙の上の文字にする (color の色で縁取りなし)。color を省くと、明るい羊皮紙の上で読みやすい
## 墨の色にする
static func on_parchment(label: Label, color: Color = INK) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 0)


## 戦闘の動きを作るか (motion_scale が 0 でない)
static func motion_on() -> bool:
	return motion_scale > 0.0


## 被弾の tween。前の動き previous を止め、HIT_TIME で shaken を位置 base から左右に distance の幅で 2 往復
## 揺らして (だんだん小さく) base に戻し、flashed を HIT_FLASH の赤から白に戻す (shaken に束ねるので、画面と
## 一緒に消える)
static func hit(
	shaken: Control, flashed: CanvasItem, previous: Tween, base: Vector2, distance: float
) -> Tween:
	if previous != null:
		previous.kill()
	var tween: Tween = shaken.create_tween()
	tween.tween_method(
		func(progress: float) -> void: _hit_step(progress, shaken, flashed, base, distance),
		0.0,
		1.0,
		HIT_TIME * motion_scale
	)
	return tween


## hit() の動きの進み progress (0〜1) の時点の、shaken の位置と flashed の色
static func _hit_step(
	progress: float, shaken: Control, flashed: CanvasItem, base: Vector2, distance: float
) -> void:
	shaken.position = base + Vector2(distance * sin(progress * TAU * 2.0) * (1.0 - progress), 0)
	flashed.self_modulate = HIT_FLASH.lerp(Color.WHITE, progress)


## parent の at (parent の座標) の上に text の数字を color で出し、FLOAT_RISE 上へ浮かせながら消す
static func float_text(parent: Control, at: Vector2, text: String, color: Color) -> void:
	var label: Label = Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", FLOAT_FONT_SIZE)
	on_picture(label, color)
	parent.add_child(label)
	label.position = at - label.get_combined_minimum_size() / 2.0
	var tween: Tween = label.create_tween().set_parallel()
	tween.tween_property(label, "position:y", label.position.y - FLOAT_RISE, FLOAT_TIME * motion_scale)
	tween.tween_property(label, "modulate:a", 0.0, FLOAT_TIME * motion_scale).set_ease(
		Tween.EASE_IN
	)
	tween.chain().tween_callback(label.queue_free)


## node を、前のフェード previous を止めて透明から FADE_TIME で現す tween
static func fade_in(node: CanvasItem, previous: Tween) -> Tween:
	if previous != null:
		previous.kill()
	node.modulate.a = 0.0
	var tween: Tween = node.create_tween()
	tween.tween_property(node, "modulate:a", 1.0, FADE_TIME * motion_scale)
	return tween
