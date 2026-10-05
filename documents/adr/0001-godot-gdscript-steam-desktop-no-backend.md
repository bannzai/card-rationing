# 0001. Godot 4.7 + GDScript で Steam 向けデスクトップ版を作り、バックエンドを持たない

## Status

Accepted

## Context

カードに 1 回の冒険 (ラン) あたりの使用回数制限があるローグライト・デッキ構築ゲームを作る ( https://github.com/bannzai/IdeaMemo/issues/353 )。立ち上げ情報 (同 issue の new-app-config) でエンジンは Godot、リポジトリは public に決まっている。

- 1 人で遊ぶターン制のゲームで、オンライン機能 (ランキング・アカウント・マルチプレイ) は企画に無い
- 同ジャンルの代表作 (Slay the Spire 等) は PC (Steam) で売られている
- 開発マシン (macOS) の負荷を避けるため、ビルド・描画付きの検証は GitHub Actions で行う。Xvfb 上のソフトウェア GL (Mesa llvmpipe) で描画できるレンダラが要る
- Steam での販売は、購入者の契約相手が Valve になる (Steam 利用規約「お客様が、利用権に基づき Steam を介して行うあらゆる取引の相手方は Valve となります」 https://store.steampowered.com/subscriber_agreement/?l=japanese )

## Decision

- エンジンは Godot 4.7 系の stable、言語は GDScript にする。C# (.NET 版 Godot) は導入しない。.NET 版はエクスポートと CI の準備が増える一方、ターン制の 2D カードゲームで C# を要する理由がない
- レンダラは GL Compatibility にする。2D で Forward+ の機能を使わず、CI の Xvfb + llvmpipe でも描画できる
- エクスポート先は Windows x86_64 / macOS universal / Linux x86_64 の 3 つ
- バックエンド (DB・ストレージ・認証・サーバー) を持たない。セーブデータ (ランの途中経過・解放状況) はローカル (`user://`) に置く。ゲームに計測 SDK を入れない。公開後の判定に使う指標と計測元は `documents/DIRECTION.md`「判定基準」に書く。このため GCP の課金・エラーアラート、Crashlytics のアラート転送は対象外にする
- Steamworks SDK の連携 (GodotSteam 等による実績・クラウドセーブ・Steam Input) は、Steamworks のパートナー登録とアプリ登録の後に別 ADR で決める
- 特定商取引法に基づく表記は用意しない。Steam での販売は購入者の契約相手が Valve のため。Steam 以外で直接販売する判断をした時に見直す
- 法務ドキュメント (プライバシーポリシー・利用規約) と紹介ページは GitHub Pages (`docs/`) に置く

## Consequences

- 良い点: サーバーの運用費・障害対応が無い。検証は Linux ランナーで完結し、開発マシンで Godot を起動しなくてよい
- 悪い点: クラッシュや不具合の報告はユーザーからの連絡 (Steam のコミュニティ・メール) に頼る。遊ばれ方 (どのカードを温存したか・どこで負けたか) をゲームから集計できないため、ジレンマの手応えはテストプレイと関門 3 (触れる版) の判断で見る
- エージェントへの制約: C# を導入しない。レンダラを GL Compatibility から変えない。サーバー・計測 SDK を追加しない (根拠は本 ADR)。Steamworks SDK の追加は別 ADR を書いてから行う
