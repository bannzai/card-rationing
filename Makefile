# Sigilbound の検証・ビルド入口。target 命名は ~/.claude/rules/makefile-target-naming.md に従う
# (`build-<対象>` = エクスポートだけ。`run` = エディタなしでの起動)。
# このマシンで実行してよい target は AGENTS.md「検証方法」を参照 (Godot を起動する target は CI で実行する)。
#
# GODOT は Godot 4.7 の実行ファイル。macOS ローカルの既定値は /Applications/Godot.app。CI では
# make の引数 (`make check GODOT=<Linux バイナリのパス>`) で Linux バイナリを渡す。
GODOT ?= /Applications/Godot.app/Contents/MacOS/Godot
LOG_DIR := tmp
# Godot 自身のログの出力先。指定しないと user:// に書こうとし、書き込みを拒否するサンドボックスでは
# 起動に失敗するため、すべての Godot 起動に付ける ($@ は実行中の target 名)
ENGINE_LOG = --log-file "$(CURDIR)/$(LOG_DIR)/$@.godot.log"

# --script で動かす検証 (selfcheck / integration / screenshot) の上限 (フレーム数)。検証スクリプトが実行時
# エラーで quit() に届かないと Godot が終わらず、CI の job が timeout-minutes まで待つため、
# `--quit-after` でこのフレーム数に達したら Godot を終わらせる (CI の Linux とローカルの macOS の両方で動く。
# macOS には timeout コマンドが無い)。上限で終わると exit code は 0 だが、各 target は完了の行 (`selfcheck OK` /
# `integration OK` / `screenshot OK`) も検査するので失敗になる。
# 6000 の根拠: headless は 1 フレームが数 ms で、正常な検証は数十フレームで終わる。描画付きの screenshot は
# llvmpipe の fps が読めず (数十〜数千 fps)、0.3 秒の待ちを撮影ごと (今は 3 回) に挟むため、速い環境でも数千
# フレームに収まる値にした (撮影を足して待ちの合計が 1 秒を超えるなら上限も見直す)。
# GDScript の無限ループはフレームが進まず止められないため、そちらは CI の timeout-minutes が最後の砦
SCRIPT_FRAME_LIMIT ?= 6000
SCRIPT_FLAGS = --quit-after $(SCRIPT_FRAME_LIMIT)

# Godot がログに出すエラー・警告の行頭 (core/io/logger.h の error_type_string: ERROR / WARNING / SCRIPT ERROR /
# SHADER ERROR。push_error は ERROR、GDScript の実行時エラーは SCRIPT ERROR)。stdout が端末でない時は色コードが
# 付かない (drivers/unix/os_unix.cpp の UnixTerminalLogger)。行頭で絞るため、カード名や print の文に error /
# warning の語があっても落ちない。続く「   at: ...」の行は対象外 (本体の行で検出できる)
LOG_ERROR_PATTERN := ^(SCRIPT |SHADER )?(ERROR|WARNING):

# 描画付きで起動する target (screenshot / movie) の共通オプション。headless では描画されないため付けない。
# CI の Linux では Xvfb + Mesa llvmpipe 上で実行する
WINDOWED_FLAGS := --audio-driver Dummy --rendering-driver opengl3 --resolution 1280x720 --windowed --position 0,0
# 描画付き起動でだけ出る、描画に影響しない OS / ドライバ由来の行。ログの WARNING / ERROR 検査から除外する
# (llvmpipe は V-Sync を設定できない WARNING を毎回 1 件出す。macOS は入力メソッドの mach port のエラーを稀に出す)
WINDOWED_LOG_NOISE := -e 'Could not set V-Sync mode' -e 'IMKCFRunLoopWakeUpReliable'
# movie target が録画するフレーム数 (30 fps 固定。150 = 5 秒)。操作なしの起動〜メインシーン表示の確認には
# 数秒あれば足り、CI の録画時間と artifact のサイズを抑えるため
MOVIE_FRAMES ?= 150

.PHONY: import check selfcheck integration lint test screenshot movie run build-macos build-windows build-linux build-all clean

# ログ・撮影の出力先。.gdignore を置き、撮影した PNG を Godot に import させない
$(LOG_DIR)/.gdignore:
	@mkdir -p $(LOG_DIR)
	@touch $@

# エクスポートの出力先。.gdignore を置き、成果物を Godot に読ませない
build/.gdignore:
	@mkdir -p build
	@touch $@

# アセットのインポート (初回・素材追加後)。.godot/ を生成する
import: $(LOG_DIR)/.gdignore
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --import > $(LOG_DIR)/import.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/import.log; \
	tail -n 1 $(LOG_DIR)/import.log | grep -q '^exit=0$$'
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/import.log

# 起動検証。メインシーンとスクリプトがロードでき、_ready が走ることを boot 出力で確認する
check: import
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --quit > $(LOG_DIR)/check.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/check.log; \
	grep -q '^card-rationing boot$$' $(LOG_DIR)/check.log
	tail -n 1 $(LOG_DIR)/check.log | grep -q '^exit=0$$'
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/check.log

# 純粋なロジックとプロジェクト設定の検証 (headless。検証の一覧は scripts/dev/selfcheck.gd)
selfcheck: import
	"$(GODOT)" --headless $(ENGINE_LOG) --path . $(SCRIPT_FLAGS) --script res://scripts/dev/selfcheck.gd > $(LOG_DIR)/selfcheck.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/selfcheck.log; \
	grep -q '^selfcheck OK$$' $(LOG_DIR)/selfcheck.log
	tail -n 1 $(LOG_DIR)/selfcheck.log | grep -q '^exit=0$$'
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/selfcheck.log

# メインシーンを tree に置いて動かす入力統合テスト (headless。検証の一覧は scripts/dev/integration.gd)
integration: import
	"$(GODOT)" --headless $(ENGINE_LOG) --path . $(SCRIPT_FLAGS) --script res://scripts/dev/integration.gd > $(LOG_DIR)/integration.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/integration.log; \
	grep -q '^integration OK$$' $(LOG_DIR)/integration.log
	tail -n 1 $(LOG_DIR)/integration.log | grep -q '^exit=0$$'
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/integration.log

# GDScript の lint (gdtoolkit の gdlint。設定は ./gdlintrc)
lint:
	gdlint scripts/

# headless 検証の一括実行 (CI の lint job と、check-and-export job のうちエクスポートを除いた部分。描画付きの
# screenshot / movie は含まない)
test: lint check selfcheck integration

# 実際の描画で代表画面を撮影する (headless の検証では見た目の崩れを検出できない)。撮影した PNG は目視してから
# 完了報告する。全部の撮影を終えた印の `screenshot OK` の行も検査する (上限で止まった時に、1 枚目の PNG だけで
# pass しないため)
screenshot: import
	rm -f $(LOG_DIR)/screenshot-*.png
	"$(GODOT)" $(ENGINE_LOG) --path . $(WINDOWED_FLAGS) $(SCRIPT_FLAGS) --script res://scripts/dev/screenshot.gd > $(LOG_DIR)/screenshot.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/screenshot.log; \
	grep -q '^screenshot OK$$' $(LOG_DIR)/screenshot.log
	tail -n 1 $(LOG_DIR)/screenshot.log | grep -q '^exit=0$$'
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/screenshot.log | grep -v $(WINDOWED_LOG_NOISE) | grep -q .
	ls $(LOG_DIR)/screenshot-*.png

# 操作を伴わない起動〜メインシーン表示を Movie Maker モードで録画して mp4 にする (起動直後の描画崩れ・真っ黒を
# 検出する。headless は dummy レンダラで落ちるため描画付きで起動する)。真っ黒な動画を成功と誤認しないよう、
# 終了 1 秒前のフレームの輝度平均 (Y。limited range のため真っ黒 = 16) が 32 以上であることも検査する
movie: import
	rm -f $(LOG_DIR)/movie.avi $(LOG_DIR)/movie.mp4
	"$(GODOT)" $(ENGINE_LOG) --path . $(WINDOWED_FLAGS) --write-movie $(LOG_DIR)/movie.avi --fixed-fps 30 --quit-after $(MOVIE_FRAMES) > $(LOG_DIR)/movie.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/movie.log; \
	tail -n 1 $(LOG_DIR)/movie.log | grep -q '^exit=0$$'
	! grep -E '$(LOG_ERROR_PATTERN)' $(LOG_DIR)/movie.log | grep -v $(WINDOWED_LOG_NOISE) | grep -q .
	ffmpeg -loglevel error -y -i $(LOG_DIR)/movie.avi -c:v libx264 -pix_fmt yuv420p $(LOG_DIR)/movie.mp4
	rm -f $(LOG_DIR)/movie.avi
	ffmpeg -v error -sseof -1 -i $(LOG_DIR)/movie.mp4 -frames:v 1 -vf signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=- -f null - \
	  | awk -F= '/YAVG/ { found = 1; exit ($$2 >= 32) ? 0 : 1 } END { if (!found) exit 1 }'

# エディタなしでゲームを起動する (人が遊んで確かめる)。先にアセットをインポートする (.godot/ が無い初回や素材の
# 追加後に、エディタを開かずに起動すると素材が読み込めず起動に失敗するため)
run: import
	"$(GODOT)" $(ENGINE_LOG) --path .

# デスクトップ向けエクスポート。プリセット名は export_presets.cfg と一致させる。
# 実行には Godot 4.7 の export templates が必要 (AGENTS.md「検証方法」参照)
build-macos: import build/.gdignore
	@mkdir -p build/macos
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --export-release "macOS" build/macos/card-rationing.zip
	test -f build/macos/card-rationing.zip

build-windows: import build/.gdignore
	@mkdir -p build/windows
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --export-release "Windows Desktop" build/windows/card-rationing.exe
	test -f build/windows/card-rationing.exe
	test -f build/windows/card-rationing.pck

build-linux: import build/.gdignore
	@mkdir -p build/linux
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --export-release "Linux" build/linux/card-rationing.x86_64
	test -f build/linux/card-rationing.x86_64
	test -f build/linux/card-rationing.pck

build-all: build-macos build-windows build-linux

# ビルド成果物と、この Makefile が tmp/ に書いたログ・撮影・録画だけを消す (tmp/ は agent の作業ファイルも置くため
# ディレクトリごとや *.log をまとめては消さない)。ログは target ごとの <target>.log と、ENGINE_LOG の <target>.godot.log
clean:
	rm -rf build
	rm -f $(foreach target,import check selfcheck integration screenshot movie run build-macos build-windows build-linux,$(LOG_DIR)/$(target).log $(LOG_DIR)/$(target).godot.log)
	rm -f $(LOG_DIR)/screenshot-*.png $(LOG_DIR)/movie.avi $(LOG_DIR)/movie.mp4

# 引数なしの make で動作確認 (verify) を実行する
.DEFAULT_GOAL := verify

.PHONY: verify
verify: test build-all
