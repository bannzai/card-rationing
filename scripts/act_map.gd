extends RefCounted
## 1 幕の地図 (巡礼の道) の生成と問い合わせ。段 0 (出発) から段 BOSS_ROW (ボス) へ上に進む。同じシードなら
## 同じ地図になる (保存データは地図そのものではなくシードを持ち、読み込みで作り直す)。
## 生成の制約と数値の根拠は documents/DIRECTION.md「決めたこと」。
## 地図は段ごとの節点の並び (rows[段] は列の小さい順の Array)。1 つの節点は
## {"column": 列, "kind": Kind, "next": 次の段で行ける列の並び (小さい順)}。

## 節点の種類
enum Kind { BATTLE, ELITE, EVENT, SHRINE, SHOP, BOSS }

## 段の数 (最上段がボス) と列の数
const ROWS: int = 15
const COLUMNS: int = 5
const BOSS_ROW: int = ROWS - 1
## ボスの節点の列 (中央)
const BOSS_COLUMN: int = 2
## 生成で引く道の本数 (重なった節点と辺は 1 つにまとまる)
const PATHS: int = 4
## すべての節点が契約の祠になる段 (中ほどと、ボスの直前)。どの道を通っても 2 回は祠に立ち寄れる
const SHRINE_ROWS: Array[int] = [6, ROWS - 2]
## 乱数で祠が出てよい段 (すべてが祠の段と隣り合わない段)
const RANDOM_SHRINE_ROWS: Array[int] = [9, 10, 11]
## 強敵・商人が出始める段
const ELITE_MIN_ROW: int = 4
const SHOP_MIN_ROW: int = 2
## 敵が強くなる後半の始まりの段 (中ほどの祠の次)
const LATE_ROW: int = 7
## 段 1 から乱数で決める節点の種類の重み
const WEIGHTS: Dictionary = {
	Kind.BATTLE: 45,
	Kind.EVENT: 22,
	Kind.ELITE: 13,
	Kind.SHOP: 10,
	Kind.SHRINE: 10,
}
## 親子 (辺でつながる 2 つの節点) で続けない種類
const NO_REPEAT_KINDS: Array[int] = [Kind.ELITE, Kind.SHOP, Kind.SHRINE]
## 1 枚の地図に必ず出す種類。出なければ種類を引き直す (MAX_KIND_ATTEMPTS 回まで)
const REQUIRED_KINDS: Array[int] = [Kind.BATTLE, Kind.ELITE, Kind.EVENT, Kind.SHOP, Kind.SHRINE]
const MAX_KIND_ATTEMPTS: int = 100
## 種類の表示名と、地図の節点に出す 1 文字
const KIND_NAMES: Dictionary = {
	Kind.BATTLE: "戦闘",
	Kind.ELITE: "強敵",
	Kind.EVENT: "出来事",
	Kind.SHRINE: "契約の祠",
	Kind.SHOP: "商人",
	Kind.BOSS: "ボス",
}
const KIND_MARKS: Dictionary = {
	Kind.BATTLE: "戦",
	Kind.ELITE: "強",
	Kind.EVENT: "?",
	Kind.SHRINE: "祠",
	Kind.SHOP: "商",
	Kind.BOSS: "主",
}


## seed_value の地図を作る。PATHS 本の道を下から上へ 1 段ずつ (列は -1 / 0 / +1、辺は交差させない) 引き、
## 道が通った節点に種類を割り当てる
static func generate(seed_value: int) -> Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	# edges[段] は {出る列: {入る列: true}}
	var edges: Array[Dictionary] = []
	for _row: int in range(BOSS_ROW):
		edges.append({})
	var first_column: int = -1
	for path_index: int in range(PATHS):
		var column: int = rng.randi_range(0, COLUMNS - 1)
		# 2 本目は 1 本目と別の列から始める (出発の選択肢を 2 つ以上にする)
		while path_index == 1 and column == first_column:
			column = rng.randi_range(0, COLUMNS - 1)
		if path_index == 0:
			first_column = column
		for row: int in range(BOSS_ROW - 1):
			var candidates: Array[int] = []
			for step: int in [-1, 0, 1]:
				var to: int = column + step
				if to >= 0 and to < COLUMNS and not _crosses(edges[row], column, to):
					candidates.append(to)
			var next_column: int = candidates[rng.randi_range(0, candidates.size() - 1)]
			_add_edge(edges[row], column, next_column)
			column = next_column
		_add_edge(edges[BOSS_ROW - 1], column, BOSS_COLUMN)
	var rows: Array = []
	for row: int in range(BOSS_ROW):
		var nodes: Array = []
		var columns: Array = edges[row].keys()
		columns.sort()
		for node_column: int in columns:
			var next: Array = edges[row][node_column].keys()
			next.sort()
			nodes.append({"column": node_column, "kind": Kind.BATTLE, "next": next})
		rows.append(nodes)
	rows.append([{"column": BOSS_COLUMN, "kind": Kind.BOSS, "next": []}])
	for _attempt: int in range(MAX_KIND_ATTEMPTS):
		_assign_kinds(rows, rng)
		if _has_required_kinds(rows):
			break
	return rows


## rows の row 段 column 列の節点 (無ければ空の Dictionary)
static func node_at(rows: Array, row: int, column: int) -> Dictionary:
	if row < 0 or row >= rows.size():
		return {}
	for node: Dictionary in rows[row]:
		if node["column"] == column:
			return node
	return {}


## path (段 0 から順に選んだ列) の次に選べる列。出発前 (path が空) は段 0 の全節点、ボスの後は無し
static func next_columns(rows: Array, path: Array[int]) -> Array[int]:
	var columns: Array[int] = []
	if path.is_empty():
		for node: Dictionary in rows[0]:
			columns.append(node["column"])
	elif path.size() < rows.size():
		columns.assign(node_at(rows, path.size() - 1, path.back())["next"])
	return columns


## path が段 0 から辺をたどって進める道か (空の道は出発前として正しい)
static func is_valid_path(rows: Array, path: Array[int]) -> bool:
	if path.size() > rows.size():
		return false
	var walked: Array[int] = []
	for column: int in path:
		if not next_columns(rows, walked).has(column):
			return false
		walked.append(column)
	return true


## row 段 column 列の節点へ入る辺を持つ、1 つ下の段の列の並び
static func parents(rows: Array, row: int, column: int) -> Array[int]:
	var columns: Array[int] = []
	if row <= 0:
		return columns
	for node: Dictionary in rows[row - 1]:
		if node["next"].has(column):
			columns.append(node["column"])
	return columns


## kind の節点のうち、段が最も低いもの (同じ段なら列の小さいもの) の位置。無ければ (-1, -1)
static func find_kind(rows: Array, kind: int) -> Vector2i:
	for row: int in range(rows.size()):
		for node: Dictionary in rows[row]:
			if node["kind"] == kind:
				return Vector2i(row, node["column"])
	return Vector2i(-1, -1)


## 段 0 から row 段 column 列の節点まで辺をたどる道 (各段の列。最後の要素が column)。各段で列の小さい親を選ぶ
static func route_to(rows: Array, row: int, column: int) -> Array[int]:
	var route: Array[int] = [column]
	var current: int = column
	for parent_row: int in range(row, 0, -1):
		current = parents(rows, parent_row, current)[0]
		route.push_front(current)
	return route


## row_edges に from → to の辺を足すと、既にある辺と交差するか
static func _crosses(row_edges: Dictionary, from: int, to: int) -> bool:
	for other_from: int in row_edges:
		for other_to: int in row_edges[other_from]:
			if (other_from < from and other_to > to) or (other_from > from and other_to < to):
				return true
	return false


## row_edges に from → to の辺を足す (既にあれば何もしない)
static func _add_edge(row_edges: Dictionary, from: int, to: int) -> void:
	if not row_edges.has(from):
		row_edges[from] = {}
	row_edges[from][to] = true


## 全節点に種類を割り当てる。段 0 は戦闘、SHRINE_ROWS は祠、ボスの段はボスのまま、ほかは重みで選ぶ
static func _assign_kinds(rows: Array, rng: RandomNumberGenerator) -> void:
	for row: int in range(BOSS_ROW):
		for node: Dictionary in rows[row]:
			if row == 0:
				node["kind"] = Kind.BATTLE
			elif SHRINE_ROWS.has(row):
				node["kind"] = Kind.SHRINE
			else:
				node["kind"] = _pick_kind(rows, row, node["column"], rng)


## row 段 column 列の節点の種類を、その段で許す種類の重みで選ぶ
static func _pick_kind(rows: Array, row: int, column: int, rng: RandomNumberGenerator) -> int:
	var parent_kinds: Array[int] = []
	for parent_column: int in parents(rows, row, column):
		parent_kinds.append(node_at(rows, row - 1, parent_column)["kind"])
	var allowed: Array[int] = []
	var total: int = 0
	for kind: int in WEIGHTS:
		if not _allowed_in_row(kind, row):
			continue
		if NO_REPEAT_KINDS.has(kind) and parent_kinds.has(kind):
			continue
		allowed.append(kind)
		total += WEIGHTS[kind]
	var roll: int = rng.randi_range(1, total)
	for kind: int in allowed:
		roll -= WEIGHTS[kind]
		if roll <= 0:
			return kind
	# roll は total 以下なので上で必ず返る。重みの表が空になる変更をした時だけ届き、最も普通の戦闘にする
	return Kind.BATTLE


## kind の節点を乱数で row 段に置いてよいか
static func _allowed_in_row(kind: int, row: int) -> bool:
	match kind:
		Kind.ELITE:
			return row >= ELITE_MIN_ROW
		Kind.SHOP:
			return row >= SHOP_MIN_ROW
		Kind.SHRINE:
			return RANDOM_SHRINE_ROWS.has(row)
	return true


## REQUIRED_KINDS がすべて地図に出ているか
static func _has_required_kinds(rows: Array) -> bool:
	var seen: Dictionary = {}
	for nodes: Array in rows:
		for node: Dictionary in nodes:
			seen[node["kind"]] = true
	return REQUIRED_KINDS.all(func(kind: int) -> bool: return seen.has(kind))
