# Card Rationing

カードに 1 回の冒険 (ラン) あたりの使用回数制限があるローグライト・デッキ構築ゲーム (Godot 4.7 / Steam)。仕様・スコープは [documents/PROJECT.md](documents/PROJECT.md)、判断の根拠 (仮説・判定基準・決めたこと) は [documents/DIRECTION.md](documents/DIRECTION.md) を参照 (どちらも SSOT)。

## 制約

- C# (.NET 版 Godot) を導入しない。レンダラを GL Compatibility から変えない。サーバー・計測 SDK を追加しない。Steamworks SDK (GodotSteam 等) は別 ADR で決めてから追加する (根拠: [ADR 0001](documents/adr/0001-godot-gdscript-steam-desktop-no-backend.md))

## 検証方法

ビルド・Godot の起動 (headless を含む)・描画付きの撮影・ブラウザでの動作確認は、開発マシンの負荷を避けるため、このマシンでは実行せず外部のマシンに任せる。本リポジトリは public のため GitHub Actions のランナー (`.github/workflows/ci.yml`) を使う。Web エクスポートをブラウザで確かめる時は webtunnel skill (GitHub Actions の Linux ランナー上の Chromium)、iOS 版を作った時は simtunnel (ios-simulator skill) を使う。private リポジトリへ変える場合は、描画・ブラウザ・シミュレーターを伴う動作確認を Devin のセッションで行う (devin-macos-e2e skill)。

- このマシンで実行してよいのは `make lint` (gdlint) だけ。ユーザーが明示的に頼んだ時と、人が遊んで確かめる `make run` はこの限りでない
- 変更は push して PR を開き、CI の結果で成否を判断する。`gh pr checks <PR 番号> --watch` で完了を待ち、失敗したら `gh run view <run ID> --log-failed` と artifact `card-rationing-check-logs` の `tmp/*.log` を読む
- 見た目の確認は artifact `card-rationing-screenshot-and-movie` を `gh run download <run ID> -n card-rationing-screenshot-and-movie -D tmp/artifact` で取得し、PNG と、mp4 の末尾のフレーム (`ffmpeg -sseof -1 -i tmp/artifact/movie.mp4 -frames:v 1 tmp/artifact/movie-last.png`) を目視してから完了報告する

各 target の内容と成功条件 (CI が実行する。`GODOT` 未指定時の既定は macOS の `/Applications/Godot.app/Contents/MacOS/Godot`、CI では Linux バイナリを渡す):

| 目的 | コマンド | 成功条件 |
|---|---|---|
| lint | `make lint` (`gdlint scripts/`) | exit 0 |
| アセットインポート (初回・素材追加後) | `make import` | exit 0 かつ `tmp/import.log` に WARNING / ERROR 行がない |
| 起動検証 (メインシーン・スクリプトのロード) | `make check` | exit 0 かつ `tmp/check.log` に `card-rationing boot` が出力され、WARNING / ERROR 行がない |
| ロジック検証 (ゲームのルールの計算・プロジェクト設定・全シーンのロード。一覧は `scripts/dev/selfcheck.gd`) | `make selfcheck` | exit 0 かつ `tmp/selfcheck.log` に `selfcheck OK` が出力され、WARNING / ERROR 行がない |
| 入力統合テスト (メインシーンを動かし、画面の遷移と入力で変わる振る舞いを確かめる。一覧は `scripts/dev/integration.gd`) | `make integration` | exit 0 かつ `tmp/integration.log` に `integration OK` が出力され、WARNING / ERROR 行がない |
| headless 検証の一括実行 (lint → check → selfcheck → integration) | `make test` | exit 0 |
| スクリーンショット (代表画面。headless の検証では見た目の崩れを検出できない) | `make screenshot` | exit 0 かつ `tmp/screenshot.log` に `screenshot OK` が出力され、WARNING / ERROR 行がなく、`tmp/screenshot-*.png` が生成される |
| 起動の録画 (操作なしの起動〜メインシーンの表示。起動直後の描画崩れ・真っ黒を検出する) | `make movie` | exit 0 かつ `tmp/movie.mp4` が生成され、末尾のフレームの輝度平均が基準以上 (ffmpeg が必要) |
| ゲームをエディタなしで起動 (人が遊んで確かめる。アセットのインポートを含む) | `make run` | ウィンドウが開きメインシーンが表示される |
| デスクトップエクスポート | `make build-macos` / `make build-windows` / `make build-linux` / `make build-all` | exit 0 で `build/<platform>/` に成果物が生成される |

- 画面や状態を追加したら `scripts/dev/screenshot.gd` の `_capture_scenes()` に撮影を足し、入力で変わる振る舞いは `scripts/dev/integration.gd` に、純粋な計算は `scripts/dev/selfcheck.gd` に検証を足す
- Godot の起動にはすべて `--log-file` を付ける (Makefile の `ENGINE_LOG`)。付けないと Godot が `user://` にログを書こうとし、書き込みを拒否するサンドボックスでは起動に失敗する
- `--script` で動かす検証 (selfcheck / integration / screenshot と、以後足す target) には `--quit-after` の上限 (Makefile の `SCRIPT_FLAGS`) を付ける。検証スクリプトが実行時エラーで `quit()` に届かないと Godot が終わらず、CI の job が `timeout-minutes` まで待つため。上限で終わった時は exit code が 0 になるので、各 target は完了の行 (`selfcheck OK` 等) で失敗を検出する
- ログは `tmp/*.log` に保存して全文を WARNING / ERROR 検査する (`tail` で切り詰めて判定しない)。検査は Godot のメッセージの行頭 (`ERROR:` / `WARNING:` / `SCRIPT ERROR:` / `SHADER ERROR:`。Makefile の `LOG_ERROR_PATTERN`) に絞ってあり、カード名や `print` の文に error / warning の語が入っても落ちない
- スクリプト・素材を追加したら、Godot が生成する `.uid` / `.import` を commit する (`~/.claude/rules/coding-rules-godot-gdscript-and-project-layout.md`)。このマシンでは Godot を起動しないため、CI の check-and-export が未 commit の `.uid` / `.import` を見つけると失敗して artifact `card-rationing-generated` に上げる。`gh run download <run ID> -n card-rationing-generated -D .` で取り出して (`scripts/<名前>.gd.uid` 等の位置にそのまま入る) commit し、push し直す
- エクスポートには Godot 4.7 の export templates が要る。CI は `.github/actions/setup-godot` が tpz から必要なテンプレートだけを取り出してキャッシュする (キャッシュキーはテンプレートの一覧のハッシュ)

## 規約

- コーディング規約は `~/.claude/rules/` の Godot・素材ライセンスの規約と、[.claude/rules/](.claude/rules/) のプロジェクト固有の規約に従う

<!-- ai-review-config begin -->
<!--
このブロックは自動生成です。直接編集せず、テンプレートを更新してから再生成してください。
内容は AI コードレビュー時の挙動指示であり、コードベース自体への規約ではありません。
-->

## レビュー時の応答スタイル

- 応答は日本語で行う

## レビュー範囲外

以下は自動レビューで指摘しない (別の検出経路があるため):

- コンパイルエラー・型エラー (ローカル/CI のビルドで検出される)
- Lint/フォーマット違反 (リンター・フォーマッターで検出される)
<!-- ai-review-config end -->
