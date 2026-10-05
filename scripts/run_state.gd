extends Node
## ラン (1 回の巡礼) 単位の状態の autoload (登録名 RunState)。契約者・デッキと各カードの残り使用回数・体力・
## 所持金・幕・地図 (シードと通った道)・進行の局面を持つ。戦闘単位の状態 (山札・手札・捨て札) は
## scripts/battle.gd が持ち、戦闘の開始・終了でここの残り使用回数を初期化しない
## (.claude/rules/card-uses-persist-across-run.md)。残り使用回数を増やす経路は restore_uses() だけ
## (新しい契約の add_card() もこれを通す)。局面の移り変わりと自動保存は scripts/run_flow.gd が行う。
## --script の検証から使う時は root.get_node_or_null("RunState") で取るか、このスクリプトを new() する。

## 局面が変わった (画面の切り替えの合図。scripts/main.gd が受ける)
signal phase_changed

## 保存データの読み込みの結果
enum LoadResult { LOADED, NOT_FOUND, CORRUPT }
## ランの局面。MAP は地図で次の節点を選ぶところ、REWARD は戦闘の後の報酬、DEFEAT / CLEAR はランの終わり
enum Phase { MAP, BATTLE, REWARD, SHRINE, SHOP, EVENT, DEFEAT, CLEAR }

const ActMap := preload("res://scripts/act_map.gd")
const Cards := preload("res://scripts/cards.gd")
const Characters := preload("res://scripts/characters.gd")

## 新しいランの体力・最大体力。動作確認用の敵 (攻撃 3〜7) の攻撃を 10 ターン前後受けられる値で、
## 自動テストプレイ (#10) の結果で見直す
const START_HP: int = 50
## 新しいランの所持金
const START_GOLD: int = 0
## 保存データの形式。形式を変えたら上げる (違う版のデータは壊れたデータとして退避する)
const SAVE_VERSION: int = 2
## 本番の保存先
const SAVE_PATH: String = "user://run.json"
## 保存してよい局面と、その局面で今いる節点に許す種類 (MAP は出発前を含めてどこでもよい)。ランの終わりの
## 局面は保存データを消すので保存しない
const SAVED_PHASE_KINDS: Dictionary = {
	Phase.MAP: [],
	Phase.BATTLE: [ActMap.Kind.BATTLE, ActMap.Kind.ELITE, ActMap.Kind.BOSS],
	Phase.REWARD: [ActMap.Kind.BATTLE, ActMap.Kind.ELITE],
	Phase.SHRINE: [ActMap.Kind.SHRINE],
	Phase.SHOP: [ActMap.Kind.SHOP],
	Phase.EVENT: [ActMap.Kind.EVENT],
}

## 契約者 ID (scripts/characters.gd)
var character_id: String = Characters.DEFAULT_CHARACTER
## デッキ。各要素は {"id": カード ID, "uses_left": 残り使用回数} で、同じ ID のカードも別の要素として持つ
var deck: Array[Dictionary] = []
## 巡礼者の体力と最大体力 (戦闘をまたいで持ち越す)
var hp: int = START_HP
var max_hp: int = START_HP
var gold: int = START_GOLD
## 幕 (1 始まり)
var act: int = 1
## 地図のシード。地図そのものは保存せず、このシードから作り直す
var map_seed: int = 0
## map_seed から作った地図 (scripts/act_map.gd の rows。map_seed を変える時に作り直す)
var rows: Array = []
## 通った道。段 0 から順に、入った節点の列 (空なら出発前)。最後の要素が今いる節点
var path: Array[int] = []
var phase: Phase = Phase.MAP
## ランの結果に出す数: 残り使用回数が 0 になった (契約を使い切った) 回数と、勝った戦闘の数
var exhausted_count: int = 0
var battles_won: int = 0
## 自動保存の保存先 (検証は本番と別の保存先に差し替える)
var save_path: String = SAVE_PATH
## 今いる節点での一時的な状態 (商人で買ったもの等)。保存せず、節点に入るたびに空にする
var visit: Dictionary = {}


## 起動時に新しいランを始める (タイトルの「続きから」は保存データを読み込んで置き換える)
func _ready() -> void:
	new_run()


## 新しいランを始める。デッキは deck_ids のカードを最大使用回数で持つ (空なら既定の契約者の初期デッキ)。
## 地図は seed_value から作る (既定の 0 は地図を問わない検証と起動時のためで、本番の巡礼は
## scripts/run_flow.gd の start_run() が乱数のシードを渡す)
func new_run(deck_ids: Array[String] = [], seed_value: int = 0) -> void:
	character_id = Characters.DEFAULT_CHARACTER
	deck = []
	var ids: Array = Characters.CHARACTERS[character_id]["deck"] if deck_ids.is_empty() else deck_ids
	for card_id: String in ids:
		add_card(card_id)
	hp = START_HP
	max_hp = START_HP
	gold = START_GOLD
	act = 1
	map_seed = seed_value
	rows = ActMap.generate(map_seed)
	path = []
	phase = Phase.MAP
	exhausted_count = 0
	battles_won = 0
	visit = {}


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
	if deck[index]["uses_left"] == 0:
		exhausted_count += 1
	return true


## デッキの index 番目のカードの残り使用回数を amount 回戻す (負なら最大まで)。最大を超えない。
## 残り使用回数を増やす唯一の経路 (契約の更新・商人・出来事・新しい契約)。戻した後の残り使用回数を返す
func restore_uses(index: int, amount: int = -1) -> int:
	var max_uses: int = card(index)["max_uses"]
	if amount < 0:
		deck[index]["uses_left"] = max_uses
	else:
		deck[index]["uses_left"] = mini(max_uses, uses_left(index) + amount)
	return uses_left(index)


## card_id のカードと新しく契約してデッキの末尾に足す。回数は restore_uses() で最大まで入れる
## (回数を増やす経路を 1 つにするため)。足したカードの index を返す
func add_card(card_id: String) -> int:
	deck.append({"id": card_id, "uses_left": 0})
	var index: int = deck.size() - 1
	restore_uses(index)
	return index


## デッキの index 番目のカードとの契約を破棄してデッキから外す。戦闘中はデッキの index を山札・手札・捨て札が
## 持つため、戦闘の外でだけ呼ぶ
func remove_card(index: int) -> void:
	deck.remove_at(index)


## 巡礼者が damage を受ける (体力は 0 未満にしない)
func take_damage(damage: int) -> void:
	hp = maxi(0, hp - damage)


## 巡礼者の体力を amount 回復する (最大を超えない)
func heal(amount: int) -> void:
	hp = mini(max_hp, hp + amount)


## 今いる節点 (出発前は空の Dictionary)
func current_node() -> Dictionary:
	if path.is_empty():
		return {}
	return ActMap.node_at(rows, path.size() - 1, path.back())


## 今いる節点のシード。戦闘の乱数・報酬と品揃え・出来事の選択に使い、同じ節点なら同じ値になる
## (地図の段と列の組は 100 未満で重ならない)
func node_seed() -> int:
	if path.is_empty():
		return map_seed
	return map_seed * 100 + (path.size() - 1) * ActMap.COLUMNS + path.back()


## save_path に保存する (局面の変わり目と、戦闘でカードを使うたび・ターンの終わりに呼ぶ)
func autosave() -> Error:
	return save_to(save_path)


## save_path の保存データを消す (ランの終わり。無ければ何もしない)
func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.open(save_path.get_base_dir()).remove(save_path.get_file())


## 保存データの形にする
func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"character_id": character_id,
		"deck": deck.duplicate(true),
		"hp": hp,
		"max_hp": max_hp,
		"gold": gold,
		"act": act,
		"map_seed": map_seed,
		"path": path.duplicate(),
		"phase": phase,
		"exhausted_count": exhausted_count,
		"battles_won": battles_won,
	}


## 保存データから状態を戻す。形が合わないデータは false を返して状態を変えない
func from_dict(data: Variant) -> bool:
	if not _is_valid_save(data):
		return false
	var new_deck: Array[Dictionary] = []
	for entry: Dictionary in data["deck"]:
		new_deck.append({"id": entry["id"], "uses_left": int(entry["uses_left"])})
	character_id = data["character_id"]
	deck = new_deck
	hp = int(data["hp"])
	max_hp = int(data["max_hp"])
	gold = int(data["gold"])
	act = int(data["act"])
	map_seed = int(data["map_seed"])
	rows = ActMap.generate(map_seed)
	path = _int_array(data["path"])
	phase = int(data["phase"]) as Phase
	exhausted_count = int(data["exhausted_count"])
	battles_won = int(data["battles_won"])
	visit = {}
	return true


## path に JSON で保存する
func save_to(file_path: String) -> Error:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return OK


## file_path の保存データを読み込む。無ければ NOT_FOUND で状態を変えない。壊れている (JSON でない・形が
## 合わない) なら読み込まずに file_path + ".corrupt" へ退避し、新しいランにして CORRUPT を返す
func load_from(file_path: String) -> LoadResult:
	if not FileAccess.file_exists(file_path):
		return LoadResult.NOT_FOUND
	var text: String = FileAccess.get_file_as_string(file_path)
	# JSON.parse_string() は失敗時に ERROR を出すため、エラーを出さない JSON.parse() で解釈する
	var json: JSON = JSON.new()
	if json.parse(text) == OK and from_dict(json.data):
		return LoadResult.LOADED
	var dir: DirAccess = DirAccess.open(file_path.get_base_dir())
	if dir != null:
		dir.rename(file_path.get_file(), file_path.get_file() + ".corrupt")
	new_run()
	return LoadResult.CORRUPT


## 保存データの形が合っているか (版・各項目が整数で範囲内・デッキの各カードが定義済みで残り回数が 0〜最大・
## 道が地図のとおり・局面が今いる節点と合う)
func _is_valid_save(data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var integer_keys: Array[String] = [
		"version", "hp", "max_hp", "gold", "act", "map_seed", "phase", "exhausted_count", "battles_won"
	]
	var keys: Array = ["character_id", "deck", "path"]
	keys.append_array(integer_keys)
	if not keys.all(func(key: String) -> bool: return data.has(key)):
		return false
	if not integer_keys.all(func(key: String) -> bool: return _is_integer(data[key])):
		return false
	if int(data["version"]) != SAVE_VERSION or typeof(data["deck"]) != TYPE_ARRAY:
		return false
	var hp_ok: bool = (
		int(data["max_hp"]) >= 1 and int(data["hp"]) >= 0 and int(data["hp"]) <= int(data["max_hp"])
	)
	var count_keys: Array[String] = ["gold", "exhausted_count", "battles_won"]
	var counts_ok: bool = count_keys.all(func(key: String) -> bool: return int(data[key]) >= 0)
	var character_ok: bool = (
		typeof(data["character_id"]) == TYPE_STRING
		and Characters.CHARACTERS.has(data["character_id"])
	)
	return (
		hp_ok
		and counts_ok
		and character_ok
		and int(data["act"]) >= 1
		and data["deck"].all(_is_valid_deck_entry)
		and _is_valid_progress(data)
	)


## 保存データの道と局面が、シードから作り直した地図と合っているか
func _is_valid_progress(data: Dictionary) -> bool:
	var raw_path: Variant = data["path"]
	if typeof(raw_path) != TYPE_ARRAY or not raw_path.all(_is_integer):
		return false
	var saved_path: Array[int] = _int_array(raw_path)
	var map_rows: Array = ActMap.generate(int(data["map_seed"]))
	if not ActMap.is_valid_path(map_rows, saved_path):
		return false
	var saved_phase: int = int(data["phase"])
	if not SAVED_PHASE_KINDS.has(saved_phase):
		return false
	var kinds: Array = SAVED_PHASE_KINDS[saved_phase]
	if kinds.is_empty():
		return true
	if saved_path.is_empty():
		return false
	var node: Dictionary = ActMap.node_at(map_rows, saved_path.size() - 1, saved_path.back())
	return kinds.has(node["kind"])


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


## 整数として検査済みの値の並びを Array[int] にする (JSON は数を float で読むため)
func _int_array(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	return result


## 値が整数か (JSON は数をすべて float で読むため、小数部の無い float も整数として受ける)。float は
## 整数を正確に表せる 2^53 未満だけを受ける (それ以上は int() の結果が環境で変わり得る)
func _is_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and value == floorf(value) and absf(value) < 9007199254740992.0
