extends Button
## カード 1 枚の見た目。枠の羊皮紙に、種別ごとに共有する絵・名前・効果・コストを載せ、残り使用回数を封蝋の印の
## 列で見せる (使った分は焼けた印)。契約切れ (残り 0) のカードは色を抜く。ボタンとして押せ、手札・報酬や商人の
## 品・デッキの格子・契約の一覧で同じものを使う。置く側が custom_minimum_size で大きさを決め、中身は基準の
## 大きさ (BASE_SIZE) で組んだものを実際の大きさに合わせて拡大・縮小する。
## 印は最大使用回数の分だけ並べ、数字は併記しない (理由は documents/DIRECTION.md「決めたこと」)。

const Art := preload("res://scripts/art.gd")
const Cards := preload("res://scripts/cards.gd")

## カードの基準の大きさ (枠の絵の縦横比に合わせる)
const BASE_SIZE: Vector2 = Vector2(176, 272)
## 基準の大きさでの各部の位置: 絵・名前・効果・補足の 1 行・封蝋の印の列
const ART_RECT: Rect2 = Rect2(19, 19, 138, 104)
const NAME_RECT: Rect2 = Rect2(16, 124, 144, 26)
const EFFECT_RECT: Rect2 = Rect2(18, 150, 140, 50)
const NOTE_RECT: Rect2 = Rect2(16, 200, 144, 20)
const SEAL_RECT: Rect2 = Rect2(16, 222, 144, 28)
## 封蝋の印 1 つの大きさと、効果の文に使える行の数
const SEAL_SIZE: Vector2 = Vector2(22, 22)
const EFFECT_MAX_LINES: int = 3
## 文字の大きさ: 名前・効果・補足と区分・コストと番号
const NAME_FONT_SIZE: int = 18
const EFFECT_FONT_SIZE: int = 14
const SMALL_FONT_SIZE: int = 13
const COST_FONT_SIZE: int = 17
## 押せないカード (契約切れでないもの) と、マウスを載せたカードの明るさ
const DISABLED_TONE: float = 0.58
const HOVER_TONE: float = 1.14
## 補足の文: 残り 1 回と契約切れ
const LAST_USE_NOTE: String = "最後の 1 回"
const EXHAUSTED_NOTE: String = "契約切れ"

## 見せているカードの ID と、残り使用回数
var card_id: String = ""
var uses_left: int = 0
## 基準の大きさで組んだ中身 (実際の大きさに合わせて拡大・縮小する)
var face: Control = null
## 絵・名前・効果・補足の 1 行・コストの数・区分・手札での番号・封蝋の印の列・選んだ印
var art: TextureRect = null
var name_label: Label = null
var effect_label: Label = null
var note_label: Label = null
var cost_label: Label = null
var bond_label: Label = null
var key_label: Label = null
var seal_row: HBoxContainer = null
var pick_mark: TextureRect = null


## 中身のノードを組み立てる
func _init() -> void:
	custom_minimum_size = BASE_SIZE
	for style_name: String in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(style_name, StyleBoxEmpty.new())
	# フォーカスの枠はカードの外側に描く (内側はカードの絵が覆うため)
	var ring: StyleBoxFlat = StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = Art.CANDLE
	ring.set_border_width_all(3)
	ring.set_corner_radius_all(10)
	ring.set_expand_margin_all(3)
	add_theme_stylebox_override("focus", ring)
	face = Control.new()
	face.size = BASE_SIZE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(face)
	var frame: TextureRect = Art.picture(Art.CARD_FRAME)
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	_place(frame, Rect2(Vector2.ZERO, BASE_SIZE))
	art = Art.picture(null)
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_place(art, ART_RECT)
	# コストは、灯す蝋燭の絵と数で絵の左上に出す
	_place(Art.picture(Art.CANDLE_LIT), Rect2(ART_RECT.position + Vector2(4, 3), Vector2(14, 24)))
	cost_label = _add_text(Rect2(ART_RECT.position + Vector2(21, 1), Vector2(40, 24)), COST_FONT_SIZE)
	Art.on_picture(cost_label, Art.CANDLE)
	key_label = _add_text(
		Rect2(ART_RECT.end.x - 65, ART_RECT.position.y + 1, 60, 24), COST_FONT_SIZE
	)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	Art.on_picture(key_label)
	bond_label = _add_text(
		Rect2(ART_RECT.position.x + 5, ART_RECT.end.y - 22, 80, 20), SMALL_FONT_SIZE
	)
	Art.on_picture(bond_label)
	name_label = _add_text(NAME_RECT, NAME_FONT_SIZE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Art.on_parchment(name_label)
	effect_label = _add_text(EFFECT_RECT, EFFECT_FONT_SIZE)
	effect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	effect_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	effect_label.max_lines_visible = EFFECT_MAX_LINES
	effect_label.add_theme_constant_override("line_spacing", 0)
	Art.on_parchment(effect_label)
	note_label = _add_text(NOTE_RECT, SMALL_FONT_SIZE)
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Art.on_parchment(note_label, Art.SEAL_RED)
	seal_row = HBoxContainer.new()
	seal_row.alignment = BoxContainer.ALIGNMENT_CENTER
	seal_row.add_theme_constant_override("separation", 2)
	_place(seal_row, SEAL_RECT)
	pick_mark = Art.picture(Art.SEAL)
	pick_mark.visible = false
	_place(pick_mark, Rect2(ART_RECT.end - Vector2(50, 50), Vector2(46, 46)))
	resized.connect(_fit_face)
	_fit_face()


## 押せるか・マウスが載っているかで中身の明るさを変える (Button は状態が変わるたびに描き直す)
func _draw() -> void:
	var tone: float = 1.0
	if disabled and uses_left > 0:
		tone = DISABLED_TONE
	elif is_hovered() and not disabled:
		tone = HOVER_TONE
	face.modulate = Color(tone, tone, tone)


## デッキのカード id を、残り使用回数 uses で見せる。note は効果の下の 1 行で、空なら残り 1 回と契約切れを書く
func show_deck_card(id: String, uses: int, note: String = "") -> void:
	_show(id, uses, note if note != "" else state_note(uses))


## これから契約するカード id (回数は最大) を見せる。note は効果の下の 1 行 (値段など)
func show_offer(id: String, note: String = "") -> void:
	_show(id, Cards.CARDS[id]["max_uses"], note)


## 手札での番号 (数字キー。1 始まり) を絵の右上に出す
func set_key_number(number: int) -> void:
	key_label.text = str(number)


## 選んだ印 (封蝋) を絵の上に出す・消す
func set_picked(picked: bool) -> void:
	pick_mark.visible = picked


## 残り使用回数 uses のカードの補足の文 (残り 1 回と契約切れだけ書く)
static func state_note(uses: int) -> String:
	if uses == 0:
		return EXHAUSTED_NOTE
	return LAST_USE_NOTE if uses == 1 else ""


## カード id を残り uses 回・補足 note で見せる
func _show(id: String, uses: int, note: String) -> void:
	var card: Dictionary = Cards.CARDS[id]
	card_id = id
	uses_left = uses
	art.texture = Art.CARD_ART[card["kind"]]
	name_label.text = card["name"]
	effect_label.text = Cards.effect_text(id)
	note_label.text = note
	cost_label.text = str(card["cost"])
	bond_label.text = Cards.BOND_NAMES[card["bond"]]
	Art.set_icons(seal_row, Art.SEAL, Art.SEAL_BURNT, uses, card["max_uses"], SEAL_SIZE)
	# 契約切れのカードは色を抜く (中身の各ノードは use_parent_material で face の material を使う)
	if uses == 0 and face.material == null:
		var ashen: ShaderMaterial = ShaderMaterial.new()
		ashen.shader = Art.ASHEN_SHADER
		face.material = ashen
	elif uses > 0:
		face.material = null
	queue_redraw()


## 中身を実際の大きさに合わせて拡大・縮小する
func _fit_face() -> void:
	face.scale = size / BASE_SIZE


## node を中身の rect の位置に置く (マウスは通し、色を抜くシェーダーが効くようにする)
func _place(node: Control, rect: Rect2) -> void:
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.use_parent_material = true
	face.add_child(node)


## 中身の rect の位置に、文字の大きさ font_size のラベルを置く
func _add_text(rect: Rect2, font_size: int) -> Label:
	var label: Label = Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.clip_text = true
	_place(label, rect)
	return label
