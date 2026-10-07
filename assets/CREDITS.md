# 素材のクレジット

`assets/` に置く素材の出典とライセンス。記録の規約は `~/.claude/rules/coding-rules-general-assets-license.md`。

素材を追加・差し替えたら、同じ変更でここに記録する。各素材のファイルは `assets/` からの相対パスをバッククォートで囲んで書く (`make selfcheck` が、`assets/` の全ファイルがその形でここに書かれていることを検証する)。

## フォント

- ファイル: `fonts/NotoSansJP-Variable.ttf` (ライセンス全文は `fonts/OFL.txt`)
- 素材名・作者: Noto Sans JP (Variable) / Adobe・Google (Noto CJK プロジェクト)
- 入手 URL: https://github.com/google/fonts/blob/main/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf (2026-10-05 取得)
- ライセンス: SIL Open Font License 1.1 (全文を同梱し、エクスポートの include filter にも含める)。クレジット表記は不要
- 改変: ファイル名を `NotoSansJP[wght].ttf` から `NotoSansJP-Variable.ttf` に変えた (Godot のパスに `[` を入れないため)。中身は変えていない
- 用途: プロジェクト全体の既定フォント (`scripts/main.gd` がメインシーンの theme の `default_font` に設定する)。Godot の既定フォントは日本語の字形を持たず、CI の Linux ランナーには日本語のシステムフォントも無いため

## BGM と効果音

- 作者・入手元: 本プロジェクトで自作 (2026-10-07)。外部の素材・音源・生成 AI は使っていない
- 生成方法: `scripts/dev/generate_audio.py` が波形 (正弦波の重ね合わせ・はじいた弦の模擬 (Karplus-Strong 法)・ノイズ) を合成する。乱数の seed は固定で、同じスクリプトからは同じ波形になる。効果音は 16 bit モノラルの WAV、BGM は ffmpeg (libvorbis) で Ogg Vorbis にエンコードした。作り直す時はリポジトリのルートで `python3 scripts/dev/generate_audio.py` を実行する (Python 3 の標準ライブラリと、libvorbis を有効にした ffmpeg が要る)
- ライセンス: 本プロジェクトの一部。外部の素材を含まないため、クレジット表記は不要
- 改変: なし
- 用途: `scripts/audio.gd` が鳴らす。どの場面でどの音を鳴らすかは `documents/DIRECTION.md`「決めたこと」

| ファイル | 用途 |
|---|---|
| `audio/bgm_map.ogg` | 地図・報酬・契約の祠・商人・出来事の BGM (設定の画面でも音量を確かめるために鳴らす) |
| `audio/bgm_battle.ogg` | 戦闘・強敵の BGM |
| `audio/bgm_boss.ogg` | ボス戦の前の会話とボス戦の BGM |
| `audio/se_card_use.wav` | カードを使った (使った後の残り使用回数が 2 回以上) |
| `audio/se_last_one.wav` | カードを使って、残りが最後の 1 回になった |
| `audio/se_expired.wav` | カードの最後の 1 回を使って、契約が切れた |
| `audio/se_restore.wav` | 残り使用回数が戻った (契約の祠の更新・商人・出来事「血の泉」) |
| `audio/se_hit.wav` | 敵の攻撃で体力が減った |
| `audio/se_win.wav` | 戦闘に勝った |
| `audio/se_lose.wav` | 戦闘に負けた |
