extends RefCounted
## 見た目「蝋と灯火」の素材 (絵・フォント・色) の置き場と、絵を並べるだけの小さな部品。方向の定義は
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
