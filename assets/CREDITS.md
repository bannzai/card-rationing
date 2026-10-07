# 素材のクレジット

`assets/` に置く外部素材の出典とライセンス。記録の規約は `~/.claude/rules/coding-rules-general-assets-license.md`。

## フォント

- 素材名・作者: Shippori Mincho (しっぽり明朝) SemiBold / The Shippori Mincho Project Authors (FONTDASU)
- 入手 URL: https://github.com/google/fonts/blob/main/ofl/shipporimincho/ShipporiMincho-SemiBold.ttf (2026-10-07 取得。取得時点の最新コミットは d0b2d1307ad5d6b579d627a6e5abd25952484b96)
- ライセンス: SIL Open Font License 1.1 (`assets/fonts/OFL.txt`。全文を同梱し、エクスポートの include filter にも含める)。クレジット表記は不要
- 改変: なし
- 用途: プロジェクト全体の既定フォント (`scripts/art.gd` の `FONT`。`scripts/ui_kit.gd` の `build_theme()` が theme の `default_font` に設定する)。Godot の既定フォントは日本語の字形を持たず、CI の Linux ランナーには日本語のシステムフォントも無いため同梱する。見た目の方向「蝋と灯火」(`documents/DIRECTION.md`「デザインの方向」) に合わせ、2026-10-07 に Noto Sans JP から差し替えた

## 生成した絵 (`assets/art/`)

見た目の方向「蝋と灯火」の絵。カードの絵は種別ごと、敵の絵は格ごと、地図の印は節点の種類ごとに共有する (1 枚ごと・1 体ごとの絵は https://github.com/bannzai/card-rationing/issues/13 )。

- 生成に使ったツール: OpenAI Codex CLI v0.156.0 の組み込み画像生成 (モデルは gpt-6-astra)。game-art-reference skill の `generate-reference.sh` (`--generator imagegen`) から実行した。参考画像は渡していない (`--reference` を使わず、`documents/design/art-reference-2026-10-06/references.json` の approved のプロンプトと同じ言い回しで揃えた)
- 生成日: 2026-10-07
- 利用規約上の帰属: OpenAI の Terms of Use ( https://openai.com/policies/row-terms-of-use/ ) は、生成物 (Output) の権利を利用者が持つと定める (2026-10-07 に Web 検索の結果で確認。ページ本体は自動取得を拒否するため本文は開いていない)。クレジット表記は不要。他者の商標・原作の名称・ロゴは指示にも生成物にも含めていない
- 文字は絵に入れていない (名前・数値は Godot の Label で載せる)
- 加工はすべて ImageMagick 7 で行った (縮小・透過の余白の除去・シートからの切り出し・JPEG への変換)

### `battle_bg.jpg`・`backdrop.jpg`

- 用途: `battle_bg.jpg` は戦闘とボス戦の前の会話の背景。`backdrop.jpg` は戦闘以外の画面 (地図・報酬・契約の祠・商人・出来事・契約の一覧・設定・結果・契約者の選択) の背景
- 改変: `battle_bg.jpg` は 1600x900 に縮小して JPEG (品質 88) にした。`backdrop.jpg` は同じ絵を 1280x720 に縮小し、ぼかし (半径 2) と明るさ 70%・彩度 90% を掛けて JPEG (品質 86) にした (上に載せる文とカードを読みやすくするため)
- プロンプト: Empty battle background for a 2D deck-building roguelike on PC, hand-painted dark fantasy illustration with visible brush strokes and paper grain: a ruined shrine road at dusk lit by candlelight, a small stone shrine with a weathered veiled statue and stone steps in the middle distance, broken pillars, tattered dark red banners, misty forested hills and a low setting sun behind clouds, wet cobblestones reflecting the candle light, clusters of small lit candles along the road. The left third and the right third of the road are open empty ground at mid-height where characters will be placed later. Across the bottom third: the near edge of an old wooden table covered with a dark worn cloth, empty, calm and in shadow. No people, no creatures, no cards, no objects on the table. Warm candle orange against deep indigo and moss green. No legible text or numbers, no flat rectangular UI panels, no top menu bar, no metal or chrome or neon gloss, no 3D render, no anime style.

### `title.jpg`

- 用途: タイトルの絵
- 改変: 1600x900 に縮小して JPEG (品質 88) にした
- プロンプト: Title screen key art for a 2D deck-building roguelike, hand-painted dark fantasy illustration with visible brush strokes and paper grain: a lone hooded pilgrim seen from behind walking up a candle-lit ruined shrine road at dusk, staff hung with wax-sealed contract scrolls, faint translucent pale spirits of a stag-headed knight and beasts following behind like a procession, a huge red wax seal glowing dimly in the sky like a setting sun. Calm empty area of sky in the upper center reserved for a logo. Warm candle orange against deep indigo and moss green. No text, no letters, no logo, no UI, no metal or chrome or neon gloss, no 3D render, no anime style.

### `pilgrim.png`

- 用途: 巡礼者 (プレイヤー) の立ち絵 (戦闘・契約者の選択)
- 改変: 透過の余白を除き、高さ 560 に縮小した
- プロンプト: Game character sprite for a 2D deck-building roguelike, hand-painted dark fantasy illustration with visible brush strokes and paper grain: a hooded pilgrim, full body from head to feet, standing in three-quarter view facing right, holding a tall wooden staff hung with wax-sealed contract scrolls and a small candle lantern, worn brown and grey travel robes with a dark red sash, face in shadow under the hood. Lit by warm candle orange from the right with deep indigo shadows. Fully transparent background (PNG with alpha channel), nothing else in the image, no ground, no cast shadow. No legible text or numbers, no metal or chrome or neon gloss, no 3D render, no anime style.

### `enemy_normal.png`

- 用途: 敵の絵 (通常の敵で共有)
- 改変: 透過の余白を除き、高さ 340 に縮小した
- プロンプト: Game enemy sprite for a 2D deck-building roguelike, hand-painted dark fantasy illustration with visible brush strokes and paper grain: a feral shadow hound, full body, snarling and crouched, facing left, ash-matted dark fur, thin ribs, ember-orange eyes, a torn red rag around its neck. Lit by warm candle orange from the left with deep indigo shadows. Fully transparent background (PNG with alpha channel), nothing else in the image, no ground, no cast shadow. No legible text or numbers, no metal or chrome or neon gloss, no 3D render, no anime style.

### `enemy_elite.png`

- 用途: 敵の絵 (強敵で共有)
- 改変: 透過の余白を除き、高さ 480 に縮小した
- プロンプト: Game enemy sprite for a 2D deck-building roguelike, hand-painted dark fantasy illustration with visible brush strokes and paper grain: a hulking stone guardian, full body from head to feet, facing left, a crown of lit dripping candles on its faceless helm, cracked mossy stone armor, a great stone slab shield carved with a seal and a heavy stone mace. Lit by warm candle orange with deep indigo shadows. Fully transparent background (PNG with alpha channel), nothing else in the image, no ground, no cast shadow. No legible text or numbers, no metal or chrome or neon gloss, no 3D render, no anime style.

### `enemy_boss.png`

- 用途: 敵の絵 (ボス。戦闘とボス戦の前の会話)
- 改変: 透過の余白を除き、高さ 560 に縮小した
- プロンプト: Game boss sprite for a 2D deck-building roguelike, hand-painted dark fantasy illustration with visible brush strokes and paper grain: a towering gaunt priest in tattered dark vestments, full body from head to the hem of the robes, facing left, a hollow hood with no face, long thin hands lifting a snuffed candle to where its mouth would be as if eating the flame, a ring of extinguished smoking candles floating around its shoulders, a huge cracked dark red wax seal hanging behind its head like a halo. Lit by dim candle orange from below with deep indigo shadows. Fully transparent background (PNG with alpha channel), nothing else in the image, no ground, no cast shadow. No legible text or numbers, no metal or chrome or neon gloss, no 3D render, no anime style.

### `card_frame.png`

- 用途: カードの枠 (内側の羊皮紙に絵・名前・効果・封蝋の印を載せる)
- 改変: 透過の余白を除き、幅 360 に縮小した
- プロンプト: Game asset for a 2D deck-building roguelike, hand-painted dark fantasy illustration with visible brush strokes and paper grain: one blank tarot-like card seen straight from the front, portrait orientation, upright and not tilted, filling the whole image height. A thin carved wooden frame with a worn ornamental line border and small corner flourishes surrounds an interior of aged blank parchment. The parchment interior is completely empty: no picture, no symbols, no ornaments inside, slightly stained and a little darker toward the edges. Fully transparent background outside the card (PNG with alpha channel), nothing else in the image, no cast shadow. No legible text or numbers, no metal or chrome or neon gloss, no 3D render, no anime style.

### `card_attack.jpg`

- 用途: カードの絵 (攻撃のカードで共有)
- 改変: 280x210 に縮小して JPEG (品質 88) にした
- プロンプト: Small card illustration for a 2D deck-building roguelike, hand-painted dark fantasy illustration with visible brush strokes and paper grain, the picture fills the whole image edge to edge with no border and no frame: a fierce spirit made of candle flame swinging a blazing blade in a wide slash, sparks and embers flying, against a deep indigo night with moss green shadows. Warm candle orange as the main light. No legible text or numbers, no metal or chrome or neon gloss, no 3D render, no anime style.

### `card_guard.jpg`

- 用途: カードの絵 (防御のカードで共有)
- 改変: 280x210 に縮小して JPEG (品質 88) にした
- プロンプト: Small card illustration for a 2D deck-building roguelike, hand-painted dark fantasy illustration with visible brush strokes and paper grain, the picture fills the whole image edge to edge with no border and no frame: a translucent pale stag-headed knight spirit bracing behind a tall shield, mist and wind curling around it like a wall, a few small candles at its feet, against deep moss green and indigo shadows. Soft pale light with a little warm candle orange. No legible text or numbers, no metal or chrome or neon gloss, no 3D render, no anime style.

### `card_skill.jpg`

- 用途: カードの絵 (技のカードで共有)
- 改変: 280x210 に縮小して JPEG (品質 88) にした
- プロンプト: Small card illustration for a 2D deck-building roguelike, hand-painted dark fantasy illustration with visible brush strokes and paper grain, the picture fills the whole image edge to edge with no border and no frame: a raven spirit perched on a hanging candle lantern, a faint ring of pale light behind it, thin wisps of smoke forming loose spirals, against a deep indigo night with moss green shadows. Warm candle orange glow from the lantern. No legible text or numbers, no metal or chrome or neon gloss, no 3D render, no anime style.

### `seal.png`・`seal_burnt.png`・`seal_grabber.png`

- 用途: 封蝋の印。`seal.png` は残っている印 (カードの残り使用回数・出来事で選んだカードの印)、`seal_burnt.png` は使って焼けた印 (地図の通った節点にも使う)、`seal_grabber.png` は設定のスライダーのつまみ
- 改変: 1 枚のシートを左右に等分し、2 つに共通の外接矩形で切り出して高さ 48 に縮小した。`seal_grabber.png` は `seal.png` を高さ 30 に縮小した
- プロンプト: Game asset sprite sheet for a 2D deck-building roguelike, hand-painted dark fantasy illustration with visible brush strokes and paper grain: exactly two round wax seals side by side with a wide gap between them, seen straight from the front, each filling about one third of the image width. Left: an intact glossy-free deep red wax seal with an embossed small tree emblem and an irregular melted rim, lit by warm candlelight. Right: the same seal burnt out, charred black and cracked like coal with a few faint dying orange embers in the cracks. Fully transparent background (PNG with alpha channel), nothing else in the image, no shadow on the ground. No legible text or numbers, no metal or chrome or neon gloss, no 3D render, no anime style.

### `candle_lit.png`・`candle_out.png`

- 用途: 力 (エネルギー) を示す蝋燭 (灯っている / 消えた)。灯っている蝋燭はカードのコストの印にも使う
- 改変: 1 枚のシートを左右に等分し、2 つに共通の外接矩形で切り出して高さ 110 に縮小した
- プロンプト: Game asset sprite sheet for a 2D deck-building roguelike, hand-painted dark fantasy illustration with visible brush strokes and paper grain: exactly two short thick wax candles standing side by side with a wide gap between them, seen from the front, each filling about one quarter of the image width. Left: a lit candle with a warm steady flame and melted wax drips. Right: the same candle extinguished, with a blackened wick and a thin grey wisp of smoke rising. Fully transparent background (PNG with alpha channel), nothing else in the image, no ground, no cast shadow. No legible text or numbers, no metal or chrome or neon gloss, no 3D render, no anime style.

### `bead.png`・`bead_dull.png`

- 用途: 体力を示す数珠の珠 (残っている / 失った)。巡礼者と敵の体力に使う
- 改変: 1 枚のシートを左右に等分し、2 つに共通の外接矩形で切り出して高さ 32 に縮小した
- プロンプト: Game asset sprite sheet for a 2D deck-building roguelike, hand-painted dark fantasy illustration with visible brush strokes and paper grain: exactly two single round prayer beads side by side with a wide gap between them, seen from the front, each filling about one quarter of the image width. Left: a polished amber wooden bead with fine carved lines, catching warm candlelight. Right: the same bead dull, cracked and ash grey, with no light. Fully transparent background (PNG with alpha channel), nothing else in the image, no ground, no cast shadow. No legible text or numbers, no metal or chrome or neon gloss, no 3D render, no anime style.

### `parchment.png`

- 用途: 文を載せる羊皮紙 (説明の文・ボスの台詞・地図の下地)。破れた端を残して引き伸ばして使う
- 改変: 透過の余白を除き、幅 512 に縮小した
- プロンプト: Game asset for a 2D deck-building roguelike, hand-painted dark fantasy illustration with visible brush strokes and paper grain: one blank sheet of aged parchment seen straight from the front, upright, landscape orientation, filling most of the image. Torn and slightly burnt ragged edges, subtle stains and fibers, an even warm tan tone in the center, darker toward the edges. Completely empty: no writing, no drawings, no seals. Fully transparent background outside the sheet (PNG with alpha channel), nothing else in the image, no cast shadow. No legible text or numbers, no metal or chrome or neon gloss, no 3D render, no anime style.

### `plaque.png`

- 用途: ボタンの木の札。左右の端を残して引き伸ばして使う
- 改変: 透過の余白を除き、幅 320 に縮小した
- プロンプト: Game asset for a 2D deck-building roguelike, hand-painted dark fantasy illustration with visible brush strokes and paper grain: one blank dark weathered wooden plaque (a wide horizontal plank sign) seen straight from the front, upright, filling most of the image width. Worn chipped edges, a simple shallow carved groove running along the border, dark stained oak with faint warm candlelight on the grain. Completely empty: no carving in the middle, no nails, no chains, no rope. Fully transparent background outside the plaque (PNG with alpha channel), nothing else in the image, no cast shadow. No legible text or numbers, no metal or chrome or neon gloss, no 3D render, no anime style.

### `token_battle.png`・`token_elite.png`・`token_event.png`・`token_shrine.png`・`token_shop.png`・`token_boss.png`

- 用途: 地図の節点の印 (戦闘・強敵・出来事・契約の祠・商人・ボス)
- 改変: 1 枚のシートを横に 6 等分し、6 つに共通の外接矩形で切り出して高さ 72 に縮小した
- プロンプト: Game asset sprite sheet for a 2D deck-building roguelike, hand-painted dark fantasy illustration with visible brush strokes and paper grain: exactly six round map tokens in a single horizontal row with clear gaps between them, all the same size, seen straight from the front. Each token is a disc of dark worn wax with an irregular melted rim and one simple emblem painted in warm candle orange. From left to right the emblems are: two crossed blades; a horned beast skull; a drifting wisp of flame with a spiral; a small shrine arch with one lit candle; a tied coin pouch; a crown above a dripping round seal. Fully transparent background (PNG with alpha channel), nothing else in the image, no ground, no cast shadow. No legible text or numbers, no metal or chrome or neon gloss, no 3D render, no anime style.

