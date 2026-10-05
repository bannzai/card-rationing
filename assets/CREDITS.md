# 素材のクレジット

`assets/` に置く外部素材の出典とライセンス。記録の規約は `~/.claude/rules/coding-rules-general-assets-license.md`。

## フォント

- 素材名・作者: Noto Sans JP (Variable) / Adobe・Google (Noto CJK プロジェクト)
- 入手 URL: https://github.com/google/fonts/blob/main/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf (2026-10-05 取得)
- ライセンス: SIL Open Font License 1.1 (`assets/fonts/OFL.txt`。全文を同梱し、エクスポートの include filter にも含める)。クレジット表記は不要
- 改変: ファイル名を `NotoSansJP[wght].ttf` から `NotoSansJP-Variable.ttf` に変えた (Godot のパスに `[` を入れないため)。中身は変えていない
- 用途: プロジェクト全体の既定フォント (`scripts/main.gd` が `ThemeDB.fallback_font` に設定する)。Godot の既定フォントは日本語の字形を持たず、CI の Linux ランナーには日本語のシステムフォントも無いため
