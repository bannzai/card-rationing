# documents/design

関門 2 (デザイン) で bannzai が見た目と体験の方向を判断するためのモックと、Claude Design などから受け取ったデザインの置き場。決めた方向は `documents/DIRECTION.md`「デザインの方向」に書き、実装はロードマップの子 issue で反映する。

- `mock-<YYYY-MM-DD>/`: agent が Claude Design の canvas に作ったモック。`canvas.json` と artboard ごとの `*.dc.html` は canvas に公開する形式のファイルで、canvas の実行環境 (`./support.js`) が無いと単体では表示できない。canvas が開けなくなっても見られるように、同じディレクトリの `index.html` に全画面を縦に並べてある (ブラウザで開く)
- `mock-2026-10-05/`: 関門 2 (https://github.com/bannzai/card-rationing/issues/16 ) のモック。canvas: https://claude.ai/artifact/7eCmd3WcSqkTzGdRLoPzqZ
  - canvas は、このディレクトリから文言の修正 (commit 1059a79。祠の見出し・進行の表示・枚数の表示・守りの風の効果・通常の敵の名前) を除いた版のまま。このディレクトリの方が新しい
  - 残り 0 のカードを「契約切れ」として手札・デッキに残し、祠で戻せる見せ方は、モックで置いた案。採るかは関門 2 の返答と #5 で決め、`documents/DIRECTION.md`「決めたこと」に書く
