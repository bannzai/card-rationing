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
## 契約者 ID (scripts/contractors.gd の CONTRACTORS のキー) → 巡礼者 (プレイヤー) の立ち絵 (戦闘・契約者の選択)
const PORTRAITS: Dictionary = {
	"yura": preload("res://assets/art/pilgrim.png"),
	"shion": preload("res://assets/art/pilgrim_shion.png"),
	"kagari": preload("res://assets/art/pilgrim_kagari.png"),
}
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
## 決めの 1 枚が消えるまでが見えるよう、最も長い動きを少し超える長さにした。最も長いのは英霊の 3 回の攻撃 (射手の
## 英霊) の最後の数字で、最後の当たり 0.38 秒 (HIT_INTERVAL × 2 + HERO_HITSTOP) から FLOAT_TIME の 0.98 秒。
## カードを使う動きは残り 1 回・契約切れになった時の合計 0.8 秒)
const DEFEAT_TIME: float = 0.4
const WIN_DELAY: float = 1.0
## 敵の予告の切り替えと、ターンの始まりの手札のフェード
const FADE_TIME: float = 0.2
## 護符が働いた時: 護符の印 (scripts/relic_view.gd) が RELIC_FLASH_TIME で RELIC_SCALE に膨らんで RELIC_FLASH の色に
## 光って戻り、印の下から護符の名前が浮く (数字と同じ float_text())。長さは封蝋の印が残り 1 回で膨らむ動き
## (STRONG_TIME) と同じにし、カードを使う動きと並んでも見分けられるよう、印の大きさに対して大きく膨らませる
const RELIC_FLASH_TIME: float = 0.3
const RELIC_SCALE: float = 1.4
const RELIC_FLASH: Color = Color(2.2, 1.8, 1.2)
## 攻撃カードが敵に当たる演出 (scripts/battle_ui.gd)。1 回目の当たりは入力の瞬間 (被弾の揺れと同じ時) に出し、
## 何で攻撃したかを形で見せる: 単体の攻撃 = 斬撃の軌跡、全体の攻撃 = 敵ごとに広がる波の輪。どちらも当たった所に
## 閃光と火の粉を添える。長さはどれも 1 つの出来事を目で追える 0.2〜0.35 秒 (上の HIT_TIME と同じ考え方) にした。
## 大きさは画面 1280 × 720 と敵の絵の大きさ (scripts/enemy_view.gd の RANK_SIZES。通常の敵は幅 236) に対して決めた。
## 斬撃の軌跡: STRIKE_TIME の半分で伸び、残りで消える。長さは通常の敵の絵の幅 236 に収まって絵を横切る 200、
## 太さは 30 fps の録画の 1 コマでも線に見え、敵の絵を隠さない 10
const STRIKE_TIME: float = 0.2
const STRIKE_LENGTH: float = 200.0
const STRIKE_WIDTH: float = 10.0
## 斬撃の傾き (ラジアン。約 35 度)。複数回の攻撃は 1 回ごとに向きを左右に入れ替え、別の当たりだと分かるようにする
const STRIKE_ANGLE: float = 0.6
## 全体の攻撃の波の輪: WAVE_TIME で半径 WAVE_RADIUS へ広がって消える。直径 260 で通常の敵の絵の幅 236 を囲み、
## 斬撃 (STRIKE_TIME) より少し長くして、輪が広がるのを見せる。太さは斬撃と同じ
const WAVE_TIME: float = 0.3
const WAVE_RADIUS: float = 130.0
const WAVE_WIDTH: float = STRIKE_WIDTH
## 当たった所の閃光: IMPACT_TIME で半径 IMPACT_RADIUS へ広がって消える。直径 104 は通常の敵の絵の幅の半分弱で、
## 当たった所だけを光らせ、敵の絵を覆い隠さない
const IMPACT_TIME: float = 0.2
const IMPACT_RADIUS: float = 52.0
## 火の粉: SPARK_COUNT 粒が SPARK_TIME の間に、SPARK_SPEED の半分から SPARK_SPEED の速さで飛び散り、SPARK_GRAVITY で
## 落ちる。粒の数は 1 粒ずつ見分けられる 14、速さは SPARK_TIME の間に 45〜90 飛んで閃光の縁 (IMPACT_RADIUS) の
## あたりまで散る値、重さは同じ間に約 37 落ちて燃えさしが落ちて見える値。粒の大きさは体力の珠 (16) の 4 分の 1
const SPARK_COUNT: int = 14
const SPARK_TIME: float = 0.35
const SPARK_SPEED: float = 260.0
const SPARK_GRAVITY: float = 600.0
const SPARK_SIZE: float = 4.0
## 複数回の攻撃の当たりの間隔 (1 回ごとに揺れと数字が出て、回数を数えられる長さ。被弾の揺れ HIT_TIME より短く
## して、続けて当たっている勢いを残す) と、全体の攻撃で次の敵に波が届くまでの間隔 (左の敵から順に届いて見える長さ)
const HIT_INTERVAL: float = 0.15
const AREA_INTERVAL: float = 0.12
## 英霊の攻撃: 演出の大きさを HERO_SCALE 倍にし、当たった瞬間に画面全体を HERO_FLASH の色で光らせ (HERO_FLASH_TIME
## で消える)、HERO_HITSTOP だけ間 (ヒットストップ) を置いてから、敵の揺れ・数字と画面の揺れ (HIT_TIME で
## SCREEN_SHAKE の幅) を出す。HERO_SCALE は斬撃の長さ (200 × 1.7 = 340) がボスの絵の幅 330 を横切る倍率。
## 間は 3 コマ弱 (30 fps) で、止まったと分かり、次の入力を待たせたと感じない長さにした。画面の光は揺れ (HIT_TIME)
## と一緒に消える長さ。画面の揺れは、画面全体という敵より大きい物が揺れて見えるよう敵の揺れ (ENEMY_SHAKE) より
## 少し大きく、手札と体力の文字が読めなくならない幅にした
const HERO_SCALE: float = 1.7
const HERO_HITSTOP: float = 0.08
const HERO_FLASH_TIME: float = HIT_TIME
const SCREEN_SHAKE: float = 12.0
## 演出の色 (「蝋と灯火」の蝋燭の火と封蝋の赤): 斬撃の軌跡は封蝋の赤の尾から明るい火の先へ、閃光と火の粉と波の輪は
## 蝋燭の火、英霊の画面の閃光は蝋燭の火を薄く。GL Compatibility では 1 を超えた分も明るくなる (上の SEAL_FLASH と
## 同じ)。閃光の不透明度 0.85 は下の敵の絵が少し透けてどの敵に当たったか分かる値、画面の閃光の 0.3 は画面の文字
## (手札・体力・予告) が光っている間も読める値
const STRIKE_GLOW: Color = Color(1.6, 1.25, 0.8)
const IMPACT_COLOR: Color = Color(1.4, 1.0, 0.6, 0.85)
const HERO_FLASH: Color = Color(1.0, 0.74, 0.38, 0.3)

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
## 一緒に消える)。flashed が null なら揺らすだけ (英霊の攻撃の画面の揺れ)
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
	if flashed != null:
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


## 攻撃の hit 回目 (0 始まり) の当たりが、全体の攻撃の order 体目 (0 始まり) の敵に届くまでの、入力からの時間
## (motion_scale を掛ける前の秒)。英霊の攻撃は、ここから HERO_HITSTOP の後に揺れと数字が出る
static func attack_delay(hit: int, order: int) -> float:
	return hit * HIT_INTERVAL + order * AREA_INTERVAL


## parent の at (parent の座標) に、angle の傾きの斬撃の軌跡を size 倍の大きさで伸ばして消す
static func strike(parent: Control, at: Vector2, angle: float, size: float) -> void:
	var trail: Line2D = Line2D.new()
	trail.width = STRIKE_WIDTH * size
	trail.gradient = Gradient.new()
	trail.gradient.colors = PackedColorArray([SEAL_RED, STRIKE_GLOW])
	trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	trail.position = at
	trail.rotation = angle
	parent.add_child(trail)
	var half: float = STRIKE_LENGTH * size / 2.0
	var step: float = STRIKE_TIME * motion_scale / 2.0
	var tween: Tween = trail.create_tween()
	tween.tween_method(_trail_step.bind(trail, half), 0.0, 1.0, step)
	tween.tween_property(trail, "modulate:a", 0.0, step)
	tween.tween_callback(trail.queue_free)


## strike() の軌跡 trail の伸びの進み progress (0〜1) の時点の形 (左端 -half から、右端 half へ伸びる)
static func _trail_step(progress: float, trail: Line2D, half: float) -> void:
	trail.points = PackedVector2Array([Vector2(-half, 0), Vector2(-half + 2.0 * half * progress, 0)])


## parent の at に、size 倍の大きさの波の輪を広げながら消す (全体の攻撃)
static func wave(parent: Control, at: Vector2, size: float) -> void:
	var ring: Line2D = Line2D.new()
	ring.width = WAVE_WIDTH * size
	ring.default_color = CANDLE
	ring.closed = true
	ring.points = _circle(WAVE_RADIUS * size)
	_spread_and_fade(parent, ring, at, WAVE_TIME)


## parent の at に、size 倍の大きさの閃光を広げながら消す
static func impact(parent: Control, at: Vector2, size: float) -> void:
	var flash: Polygon2D = Polygon2D.new()
	flash.color = IMPACT_COLOR
	flash.polygon = _circle(IMPACT_RADIUS * size)
	_spread_and_fade(parent, flash, at, IMPACT_TIME)


## parent の at から、size 倍の数と勢いの火の粉を飛び散らせ、落としながら消す
static func sparks(parent: Control, at: Vector2, size: float) -> void:
	var particles: CPUParticles2D = CPUParticles2D.new()
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = roundi(SPARK_COUNT * size)
	particles.lifetime = SPARK_TIME * motion_scale
	particles.spread = 180.0
	particles.initial_velocity_min = SPARK_SPEED * size / 2.0
	particles.initial_velocity_max = SPARK_SPEED * size
	particles.gravity = Vector2(0, SPARK_GRAVITY)
	particles.scale_amount_min = SPARK_SIZE / 2.0
	particles.scale_amount_max = SPARK_SIZE
	particles.color_ramp = Gradient.new()
	particles.color_ramp.colors = PackedColorArray([CANDLE, Color(SEAL_RED, 0.0)])
	particles.position = at
	parent.add_child(particles)
	particles.emitting = true
	var tween: Tween = particles.create_tween()
	tween.tween_interval(SPARK_TIME * motion_scale)
	tween.tween_callback(particles.queue_free)


## parent の全面を HERO_FLASH の色で光らせて消す (英霊の攻撃)。マウスは通す
static func screen_flash(parent: Control) -> void:
	var flash: ColorRect = ColorRect.new()
	flash.color = HERO_FLASH
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(flash)
	var tween: Tween = flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, HERO_FLASH_TIME * motion_scale)
	tween.tween_callback(flash.queue_free)


## node を parent の at に置き、duration の間に小さい大きさから広げながら消す
static func _spread_and_fade(parent: Control, node: Node2D, at: Vector2, duration: float) -> void:
	node.position = at
	node.scale = Vector2.ONE * 0.3
	parent.add_child(node)
	var tween: Tween = node.create_tween().set_parallel()
	tween.tween_property(node, "scale", Vector2.ONE, duration * motion_scale).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "modulate:a", 0.0, duration * motion_scale).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(node.queue_free)


## 中心が原点で半径 radius の円の頂点 (波の輪と閃光の形。24 角形で円に見える)
static func _circle(radius: float) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(24):
		points.append(Vector2.from_angle(TAU * index / 24.0) * radius)
	return points


## node を、前のフェード previous を止めて透明から FADE_TIME で現す tween
static func fade_in(node: CanvasItem, previous: Tween) -> Tween:
	if previous != null:
		previous.kill()
	node.modulate.a = 0.0
	var tween: Tween = node.create_tween()
	tween.tween_property(node, "modulate:a", 1.0, FADE_TIME * motion_scale)
	return tween
