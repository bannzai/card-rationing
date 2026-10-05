extends Node
## ラン (1 回の巡礼) 単位の状態の autoload (登録名 RunState)。デッキと各カードの残り使用回数・体力・所持金・
## 幕と階層を持つ。戦闘単位の状態 (山札・手札・捨て札) は scripts/battle.gd が持ち、戦闘の開始・終了で
## ここの残り使用回数を初期化しない (.claude/rules/card-uses-persist-across-run.md)。
## 残り使用回数を増やす経路は restore_uses() だけ。
## --script の検証から使う時は root.get_node_or_null("RunState") で取るか、このスクリプトを new() する。

## 保存データの読み込みの結果
enum LoadResult { LOADED, NOT_FOUND, CORRUPT }

const Cards := preload("res://scripts/cards.gd")
const Contractors := preload("res://scripts/contractors.gd")

## 新しいランの体力・最大体力。1 幕の前半の敵 (1 体の 1 ターンの攻撃 3〜7) の攻撃を 10 ターン前後受けられる値で、
## 自動テストプレイ (#10) の結果で見直す
const START_HP: int = 50
## 新しいランの所持金 (商人は #7 で作るため、まだ使い道が無く 0)
const START_GOLD: int = 0
## 保存データの形式。形式を変えたら上げる (違う版のデータは壊れたデータとして退避する)
const SAVE_VERSION: int = 1
## 本番の保存先
const SAVE_PATH: String = "user://run.json"

## デッキ。各要素は {"id": カード ID, "uses_left": 残り使用回数} で、同じ ID のカードも別の要素として持つ
var deck: Array[Dictionary] = []
## 巡礼者の体力と最大体力 (戦闘をまたいで持ち越す)
var hp: int = START_HP
var max_hp: int = START_HP
## 所持金 (商人は #7 で作る)
var gold: int = START_GOLD
## 幕 (1 始まり)
var act: int = 1
## 幕の中の階層 (0 始まり。戦闘に勝つたびに進む)
var floor_index: int = 0


## 起動時に新しいランを始める (途中からの再開はロードマップの画面の流れの issue で足す)
func _ready() -> void:
	new_run()


## 新しいランを始める。デッキは deck_ids のカードを最大使用回数で持つ (空なら最初の契約者の初期デッキ)
func new_run(deck_ids: Array[String] = []) -> void:
	deck = []
	var ids: Array[String] = deck_ids
	if ids.is_empty():
		ids = Contractors.starter_deck(Contractors.FIRST_CONTRACTOR)
	for card_id: String in ids:
		deck.append({"id": card_id, "uses_left": Cards.CARDS[card_id]["max_uses"]})
	hp = START_HP
	max_hp = START_HP
	gold = START_GOLD
	act = 1
	floor_index = 0


## デッキの index 番目のカードの定義
func card(index: int) -> Dictionary:
	return Cards.CARDS[deck[index]["id"]]


## デッキの index 番目のカードの残り使用回数
func uses_left(index: int) -> int:
	return deck[index]["uses_left"]


## デッキの index 番目のカードが使えるか (残りが 1 以上)。残り 0 は「契約切れ」でデッキに残るが使えない
func can_use(index: int) -> bool:
	return uses_left(index) >= 1


## デッキの index 番目のカードを使い、残り使用回数を 1 減らす。使えない時は false を返して減らさない
func use_card(index: int) -> bool:
	if not can_use(index):
		return false
	deck[index]["uses_left"] -= 1
	return true


## デッキの index 番目のカードの残り使用回数を amount 回戻す (負なら最大まで)。最大を超えない。
## 残り使用回数を増やす唯一の経路 (契約の更新)。戻した後の残り使用回数を返す
func restore_uses(index: int, amount: int = -1) -> int:
	var max_uses: int = card(index)["max_uses"]
	if amount < 0:
		deck[index]["uses_left"] = max_uses
	else:
		deck[index]["uses_left"] = mini(max_uses, uses_left(index) + amount)
	return uses_left(index)


## 巡礼者が damage を受ける (体力は 0 未満にしない)
func take_damage(damage: int) -> void:
	hp = maxi(0, hp - damage)


## 戦闘に勝って次の階層へ進む
func advance_floor() -> void:
	floor_index += 1


## 保存データの形にする
func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"deck": deck.duplicate(true),
		"hp": hp,
		"max_hp": max_hp,
		"gold": gold,
		"act": act,
		"floor_index": floor_index,
	}


## 保存データから状態を戻す。形が合わないデータは false を返して状態を変えない
func from_dict(data: Variant) -> bool:
	if not _is_valid_save(data):
		return false
	var new_deck: Array[Dictionary] = []
	for entry: Dictionary in data["deck"]:
		new_deck.append({"id": entry["id"], "uses_left": int(entry["uses_left"])})
	deck = new_deck
	hp = int(data["hp"])
	max_hp = int(data["max_hp"])
	gold = int(data["gold"])
	act = int(data["act"])
	floor_index = int(data["floor_index"])
	return true


## path に JSON で保存する
func save_to(path: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return OK


## path の保存データを読み込む。無ければ NOT_FOUND で状態を変えない。壊れている (JSON でない・形が合わない) なら
## 読み込まずに path + ".corrupt" へ退避し、新しいランにして CORRUPT を返す
func load_from(path: String) -> LoadResult:
	if not FileAccess.file_exists(path):
		return LoadResult.NOT_FOUND
	var text: String = FileAccess.get_file_as_string(path)
	# JSON.parse_string() は失敗時に ERROR を出すため、エラーを出さない JSON.parse() で解釈する
	var json: JSON = JSON.new()
	if json.parse(text) == OK and from_dict(json.data):
		return LoadResult.LOADED
	var dir: DirAccess = DirAccess.open(path.get_base_dir())
	if dir != null:
		dir.rename(path.get_file(), path.get_file() + ".corrupt")
	new_run()
	return LoadResult.CORRUPT


## 保存データの形が合っているか (版・各項目が整数で範囲内・デッキの各カードが定義済みで残り回数が 0〜最大)
func _is_valid_save(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	for key: String in ["version", "deck", "hp", "max_hp", "gold", "act", "floor_index"]:
		if not data.has(key):
			return false
	for key: String in ["version", "hp", "max_hp", "gold", "act", "floor_index"]:
		if not _is_integer(data[key]):
			return false
	if int(data["version"]) != SAVE_VERSION or typeof(data["deck"]) != TYPE_ARRAY:
		return false
	var hp: int = int(data["hp"])
	var max_hp: int = int(data["max_hp"])
	var hp_ok: bool = max_hp >= 1 and hp >= 0 and hp <= max_hp
	var progress_ok: bool = (
		int(data["gold"]) >= 0 and int(data["act"]) >= 1 and int(data["floor_index"]) >= 0
	)
	return hp_ok and progress_ok and data["deck"].all(_is_valid_deck_entry)


## 保存データのデッキの 1 要素の形が合っているか
func _is_valid_deck_entry(entry: Variant) -> bool:
	if typeof(entry) != TYPE_DICTIONARY or not entry.has("id") or not entry.has("uses_left"):
		return false
	if typeof(entry["id"]) != TYPE_STRING or not Cards.CARDS.has(entry["id"]):
		return false
	if not _is_integer(entry["uses_left"]):
		return false
	var uses: int = int(entry["uses_left"])
	return uses >= 0 and uses <= Cards.CARDS[entry["id"]]["max_uses"]


## 値が整数か (JSON は数をすべて float で読むため、小数部の無い float も整数として受ける)。float は
## 整数を正確に表せる 2^53 未満だけを受ける (それ以上は int() の結果が環境で変わり得る)
func _is_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and value == floorf(value) and absf(value) < 9007199254740992.0
