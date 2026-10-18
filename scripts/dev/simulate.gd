extends SceneTree
## 戦略 bot の自動テストプレイ (headless。Makefile の simulate target)。契約者 (scripts/contractors.gd) ごとに、
## 3 つの戦略 (scripts/dev/strategy_bots.gd) に同じシードの 1 幕を SEED_COUNT ランずつ遊ばせ、戦略ごとの踏破率・
## 平均到達階層・使い切った契約の数・最後まで使わずに残った強いカードの数・攻撃が尽きる速さ (攻撃が尽きて始まった
## 戦闘の割合など) と、踏破率の差を OUTPUT_PATH に JSON で書く。トップの clear_rate_gap は契約者ごとの踏破率の差の
## 最小 (どの契約者でも「状況で使い分ける」が勝っているかを 1 つの値で読むため)。数値の読み方
## (判定基準としきい値) は documents/DIRECTION.md で、ここではしきい値で失敗にしない。
## 全部のランを終えたら「simulate OK」の行を出して quit(0) する (Makefile はこの行と JSON の存在で判定する)。
## 1 ランごとに 1 フレーム進める (途中の実行時エラーで止まった時に、Makefile の --quit-after が効くように)。

const Bots := preload("res://scripts/dev/strategy_bots.gd")
const Contractors := preload("res://scripts/contractors.gd")
const RunStateScript := preload("res://scripts/run_state.gd")

## 契約者と戦略の組ごとに遊ぶランの数と、最初のシード (シードは FIRST_SEED から SEED_COUNT 個の連番で、すべての組で
## 同じ)。ランの数は documents/DIRECTION.md の判定基準の「各 200 ラン」
const SEED_COUNT: int = 200
const FIRST_SEED: int = 1
## 集計の JSON の書き出し先 (CI の artifact card-rationing-simulate に入る)
const OUTPUT_PATH: String = "res://tmp/simulate.json"
## ランの間の自動保存の保存先 (本番の保存データを触らない)
const SIMULATE_SAVE_PATH: String = "user://simulate_run.json"


## フレームを進めながら遊ばせるので _initialize() の中では回さず、tree の準備が終わってから _run() を始める
func _initialize() -> void:
	_run.call_deferred()


## 契約者ごとに 3 つの戦略を順に遊ばせ、集計を OUTPUT_PATH に書いて、結果を exit code と「simulate OK」の行で
## 返して終える。フレームを進めながら遊ばせるため、同じ実行中に重ねて呼び出さない
func _run() -> void:
	var state: RunStateScript = root.get_node_or_null("RunState")
	if state == null:
		push_error("autoload RunState が無い")
		quit(1)
		return
	state.save_path = SIMULATE_SAVE_PATH
	var started_msec: int = Time.get_ticks_msec()
	var contractors: Dictionary = {}
	var min_gap: float = INF
	# 一時的な調整用 (最大体力の掃引)。値を決めたら消す
	var sweep: Dictionary = {"yura": [40, 42, 46, 48], "shion": [28, 32], "kagari": [32, 36]}
	for variant: String in _variants(sweep):
		var contractor_id: String = variant.get_slice("@", 0)
		var hp_override: int = int(variant.get_slice("@", 1))
		var bots: Dictionary = {}
		for strategy: int in Bots.Strategy.values():
			bots[Bots.STRATEGY_KEYS[strategy]] = await _simulate(
				state, strategy, contractor_id, hp_override
			)
		var others_best: float = maxf(
			bots[Bots.STRATEGY_KEYS[Bots.Strategy.HOARD]]["clear_rate"],
			bots[Bots.STRATEGY_KEYS[Bots.Strategy.SPEND]]["clear_rate"]
		)
		var gap: float = snappedf(
			bots[Bots.STRATEGY_KEYS[Bots.Strategy.ADAPT]]["clear_rate"] - others_best, 0.01
		)
		min_gap = minf(min_gap, gap)
		contractors[variant] = {
			"name": Contractors.CONTRACTORS[contractor_id]["name"], "bots": bots, "clear_rate_gap": gap
		}
		print(
			(
				"simulate: %s 最大体力 %d 踏破率 %.1f / %.1f / %.1f 差 %.1f ポイント"
				% [
					Contractors.CONTRACTORS[contractor_id]["name"],
					hp_override,
					bots["hoard"]["clear_rate"],
					bots["spend"]["clear_rate"],
					bots["adapt"]["clear_rate"],
					gap,
				]
			)
		)
	state.delete_save()
	var summary: Dictionary = {
		"act": state.act,
		"first_seed": FIRST_SEED,
		"seed_count": SEED_COUNT,
		"contractors": contractors,
		"clear_rate_gap": min_gap,
	}
	var file: FileAccess = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("%s を書けない (%s)" % [OUTPUT_PATH, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	file.store_string(JSON.stringify(summary, "\t") + "\n")
	file.close()
	print(
		(
			"simulate: 踏破率の差の契約者ごとの最小 %.1f ポイント" % summary["clear_rate_gap"]
		)
	)
	print("simulate: %.1f 秒" % ((Time.get_ticks_msec() - started_msec) / 1000.0))
	print("simulate OK")
	quit(0)


## 一時的な調整用: sweep (契約者 ID → 最大体力の並び) を「契約者 ID@最大体力」の並びにする
func _variants(sweep: Dictionary) -> Array[String]:
	var variants: Array[String] = []
	for contractor_id: String in sweep:
		for hp: int in sweep[contractor_id]:
			variants.append("%s@%d" % [contractor_id, hp])
	return variants


## strategy の戦略に contractor_id の契約者で SEED_COUNT ラン遊ばせた集計。{"name": 戦略の名前, "runs": ランの数,
## "clears": 踏破した数,
## "clear_rate": 踏破率 (%), "average_floor": 平均到達階層, "average_exhausted": 契約を使い切った回数の平均,
## "average_unused_strong": ランの終わりに残り使用回数が残っていた強いカードの枚数の平均,
## "average_relics": ランの終わりに持っていた護符の数の平均, "relic_runs": 護符を 1 つ以上持って終えたランの数,
## "attackless_battle_rate": 攻撃が尽きて始まった戦闘 (デッキの攻撃カードの残り使用回数の合計が 0) の、戦った
## 戦闘に占める割合 (%), "attackless_turn_rate": 手札に残り使用回数のある攻撃カードが無いまま始まったターンの、
## 戦ったターンに占める割合 (%), "struggle_rate": もがいた回数の、使ったカードともがいた回数の合計に占める割合 (%),
## "attackless_struggle_rate": 手札に攻撃カードが無かった時にもがいた回数の、使ったカードともがいた回数の合計に
## 占める割合 (%。struggle_rate の内訳で、温存のためのもがくを除く),
## "average_struggles": 1 ランでもがいた回数の平均, "attack_out_runs": 攻撃が尽きたランの数,
## "average_attack_out_floor": 攻撃が尽きたランで、初めて尽きた戦闘の階層の平均 (尽きたランが無ければ -1),
## "cleared_seeds": 踏破したシードの並び, "reached_floors": シードの順 (FIRST_SEED から) に並べた到達階層}。
## 後ろの 2 つは、make playtest で遊ばせるシードを選ぶのと、どの階層で倒れているかを読むのに使う
func _simulate(
	state: RunStateScript, strategy: int, contractor_id: String, hp_override: int = 0
) -> Dictionary:
	var cleared_seeds: Array[int] = []
	var reached_floors: Array[int] = []
	var floors: int = 0
	var exhausted: int = 0
	var unused_strong: int = 0
	var relics: int = 0
	var relic_runs: int = 0
	var counts: Dictionary = Bots.new_counts()
	var attack_out_runs: int = 0
	var attack_out_floors: int = 0
	for seed_value: int in range(FIRST_SEED, FIRST_SEED + SEED_COUNT):
		var result: Dictionary = Bots.play_run(
			strategy, state, seed_value, contractor_id, hp_override
		)
		if result["cleared"]:
			cleared_seeds.append(seed_value)
		reached_floors.append(result["floor"])
		floors += result["floor"]
		exhausted += result["exhausted"]
		unused_strong += result["unused_strong"]
		relics += result["relics"]
		relic_runs += 1 if result["relics"] > 0 else 0
		for key: String in counts:
			if key != "attack_out_floor":
				counts[key] += result[key]
		if result["attack_out_floor"] >= 0:
			attack_out_runs += 1
			attack_out_floors += result["attack_out_floor"]
		await process_frame
	var moves: int = counts["plays"] + counts["struggles"]
	var stats: Dictionary = {
		"name": Bots.STRATEGY_NAMES[strategy],
		"runs": SEED_COUNT,
		"clears": cleared_seeds.size(),
		"clear_rate": snappedf(cleared_seeds.size() * 100.0 / SEED_COUNT, 0.01),
		"average_floor": snappedf(float(floors) / SEED_COUNT, 0.01),
		"average_exhausted": snappedf(float(exhausted) / SEED_COUNT, 0.01),
		"average_unused_strong": snappedf(float(unused_strong) / SEED_COUNT, 0.01),
		"average_relics": snappedf(float(relics) / SEED_COUNT, 0.01),
		"relic_runs": relic_runs,
		"attackless_battle_rate": _percent(counts["attackless_battles"], counts["battles"]),
		"attackless_turn_rate": _percent(counts["attackless_turns"], counts["turns"]),
		"struggle_rate": _percent(counts["struggles"], moves),
		"attackless_struggle_rate": _percent(counts["attackless_struggles"], moves),
		"average_struggles": snappedf(float(counts["struggles"]) / SEED_COUNT, 0.01),
		"attack_out_runs": attack_out_runs,
		"average_attack_out_floor":
		snappedf(float(attack_out_floors) / attack_out_runs, 0.01) if attack_out_runs > 0 else -1.0,
		"cleared_seeds": cleared_seeds,
		"reached_floors": reached_floors,
	}
	var label: String = "%s %s" % [Contractors.CONTRACTORS[contractor_id]["name"], stats["name"]]
	print(
		(
			(
				"simulate: %s 踏破率 %.1f%% (%d / %d) 平均到達階層 %.2f 使い切った契約 %.2f 残った強いカード %.2f "
				+ "護符 %.2f (持って終えたラン %d)"
			)
			% [
				label,
				stats["clear_rate"],
				stats["clears"],
				SEED_COUNT,
				stats["average_floor"],
				stats["average_exhausted"],
				stats["average_unused_strong"],
				stats["average_relics"],
				stats["relic_runs"],
			]
		)
	)
	print(
		(
			(
				"simulate: %s 攻撃が尽きて始まった戦闘 %.1f%% 手札に攻撃が無いターン %.1f%% "
				+ "もがく %.1f%% (手札に攻撃が無かった時 %.1f%%) 攻撃が尽きたラン %d (初めて尽きた階層の平均 %.2f)"
			)
			% [
				label,
				stats["attackless_battle_rate"],
				stats["attackless_turn_rate"],
				stats["struggle_rate"],
				stats["attackless_struggle_rate"],
				stats["attack_out_runs"],
				stats["average_attack_out_floor"],
			]
		)
	)
	return stats


## part が whole に占める割合 (%。whole が 0 なら 0)
func _percent(part: int, whole: int) -> float:
	if whole == 0:
		return 0.0
	return snappedf(part * 100.0 / whole, 0.01)
