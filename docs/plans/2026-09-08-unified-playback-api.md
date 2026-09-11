# 準備・適用・再生制御を分離した再生API

This is the implementation record from 2026-09-08. Its UI, tempo, and edit
timing descriptions are historical. See the [scheduler guide](../../scheduler/README.mbt.md)
and [current playback contract](../salat-engine-technical-reference.md#browser-playback-preparation-and-application)
for the current API, including `acceptedAtSample`.

状態: 本体実装・ローカル検証済み。性能結果は `docs/performance/2026-09-08-unified-playback-api.md` を参照。
基点: PR #232のsquash merge `18b2a80bfe414dc785c6350b225e9f30ccb71288`。

## 目的

通常の編集、編集した曲の先頭からの再生、適用済みの曲の再スタートを、一つのsnapshot再生経路で処理する。解析とtransport変更を暗黙に結び付けず、失敗時や要求が競合したときの挙動を明示する。

ユーザーの設計方針は、**後方互換性より理想のAPIを優先する**ことである。旧eval/parse-and-set/update APIは削除し、互換ラッパーを残さず、通常画面・デモ・音声比較テストの呼び出し側を移行する。

## APIの契約

| 操作 | 契約 |
|---|---|
| `prepare_pattern_input` / `prepare_song_input` | 共通入力バッファから解析・検証・ルーティング・snapshot生成を行う。成功は正のtoken、失敗は0 |
| `apply_prepared_playback(token, restart)` | 準備済みsnapshotを、継続またはリセット付きで次の音声ブロックへ予約する。成功は0、拒否は1 |
| `discard_prepared_playback(token)` | 未使用の準備結果を破棄する。成功時true |
| `restart_playback()` | 適用済みsnapshotを再解析せず先頭へ戻す操作を予約する。成功は0、拒否は1 |

準備は演奏、transport、発音中の音、受理済みの保留中操作を変えない。準備結果はaudio ownerが一つだけ保持する。次の準備や準備失敗は古いtokenを無効にする。成功した適用はtokenを消費し、拒否した適用は再試行または破棄のためtokenを保持する。グラフ初期化・破棄でtokenを無効にし、世代番号は再利用しない。

準備結果はWASM内部に留め、関数を含むsnapshotをJSやWorkerへ転送しない。文字列は共通のUTF-16バッファ、失敗は共通エラーアクセサーを使う。workletのエラー通知には準備・適用・再スタート・プロトコルの失敗段階を含める。

## 状態遷移

| 操作 | 再生位置 | 発音中の音 | 適用する曲 |
|---|---|---|---|
| 継続適用 | 維持 | 維持 | 準備済みの新snapshot |
| リセット付き適用 | 先頭 | 停止 | 準備済みの新snapshot |
| 単独再スタート | 先頭 | 停止 | 適用済みsnapshot |

- 継続適用は、適用済みの曲が存在し、モード・曲配置・埋め込みBPMが現在の演奏と一致する場合に受理する。
- リセット付き適用は曲配置やBPM変更を許可する。埋め込みBPMの適用、全ルートのリセットとsnapshot差し替えを、どのルートのqueryよりも前に行う。
- 単独再スタートは保留中の差し替えを取り消し、適用済みの曲と現在のグローバルBPMを使う。入力と準備結果を参照しない。
- 最後に受理した操作が優先される。準備しただけでは操作を上書きしない。
- 失敗は適用済み・保留中の演奏を維持する。適用前の単独再スタートも失敗し、予約済みの初回再生を取り消さない。
- 曲末尾ではrelease tailを処理して無音になる。継続適用は過去のonsetを再発音しない。
- browser audioのsuspendはrenderを停止する。保留中の操作は次にrenderが実行されたブロックで適用する。

## 所有者と境界

`browser/internal/playback_host/live_update.mbt` に、明示的な入力から準備結果を作る処理と、純粋な受理・遷移判断を置く。準備slot、保留中操作、transport、voice lifecycleはaudio-owner shellが所有する。通常再生も再スタートも `process_playback_snapshot_block` を使う。

`web/playback-controller.js` を通常画面用とデモ用の両workletで共有する。`apply-score` はmode、text、revision、continue/restart方針を受け取り、準備と適用を同じハンドラーで行う。`restart-playback` はrequest revisionだけを受け取る。

受理は適用完了と区別する。最初のrender後にrequest/score revision、`appliedAtSample`、次ブロックの`samplePosition`を通知する。上書きされた要求には`playback-superseded`を返す。UIは実際に適用された曲の記録と、編集中のテキストに対する診断の表示を分離する。

通常画面には **Restart current** と **Apply from beginning** を用意する。前者は編集中のテキストが不正でも動作する。後者は入力が正しい場合だけ差し替えとリセットを適用する。

## 検証

本体の状態テストは、準備の非干渉、tokenの無効化・消費・破棄、失敗時の保持、発音継続、原子的なリセット、競合、テンポ・配置の拒否、曲末尾、周期差、セクション境界、決定的な音抜きを確認する。

通常画面は実際のWASM/AudioWorkletで操作を検証する。従来デモと独立した音声比較用fixtureも新APIへ移行して検査する。比較fixtureは固定された音声比較のためのもので、本体再生の代替実装ではない。

長い曲の準備、commit付きrender、通常render、再スタートを別々に測定する。ページ内のWASM測定をAudioWorkletの締切保証と混同しない。全MoonBitターゲット、ブラウザ、境界検査、CLAP smoke/validatorを確認し、失敗を無関係と推測して無視しない。

### ローカル検証結果

- `moon check --target all`、release wasm-gc build、通常画面のTypeScript/Vite buildは成功。
- 通常画面28件、デモ・音声比較・共有controllerの実WASM検証26件は成功。
- 再生hostの契約テスト15件、比較fixtureのテスト7件は成功。
- 全体テストはJS・wasm-gc・nativeの各ターゲットで1,072件すべて成功。seedの整数境界値を含む生成器の回帰テストを含む。
- public/architecture/incr/parity/browser ABIの境界チェック5種類は成功。
- CLAP smokeは成功。validatorは21件中13成功、8スキップ、失敗0。実DAWでのロード確認を意味しない。
- 既存ベンチマーク59件は成功。12セクション曲の準備はp95が3.3msで音声ブロックの2.667msを超え、リアルタイム性の制約が残る。

## 今回の範囲外

名前付きパターン、小節構文・小節境界の反映、ゲーム向け遷移規則、Worker移行、エフェクト、連続テンポ、任意位置へのseekは別の作業とする。schedulerの低水準pattern/song query APIは独立したライブラリ用途があるため、このbrowser再生統一で機械的に削除しない。

グローバルBPM操作は従来の非連続な位相挙動を持つ。解析・snapshot生成はaudio owner内でメモリ確保を伴う。これらを解消したという主張はしない。

### 全体テスト失敗の修正

4件のmono feedbackプロパティテスト失敗は、32bit整数最小値に対する
テスト生成器の `abs()` が負数のままになり、最大ディレイ長に負数を渡すことが原因だった。
製品のcompile validationはこの不正値を正しく拒否していた。
全生成器と関連するseed由来パラメーターを、符号付き整数全域で安全な正規化へ変更した。
境界値とトポロジーの各variantを直接検査し、生成失敗をスキップしない回帰テストを追加した。
JS・wasm-gc・nativeの全体テストをCIに追加し、PRで検出する。

### テストの構成

再生位置・出力・API結果でhostの契約を検査し、内部のpending/active slotやtoken世代番号を
直接assertしない。全ルートの時計・テンポの一致は、その不変条件を検査する補助関数に集約する。
純粋な曲の時間規則はaudio engineを初期化しない独立したテストファイルに置く。

通知テストは「適用後に通知」「失敗しても受理済み操作を保持」「再スタートで差し替えを取り消す」
の3つに分け、実WASMを共有の起動fixtureで用意する。UIテストも操作目的ごとに分け、
編集後の新しいrevisionの通知を待つことで、前の成功通知による誤った成功判定を防ぐ。

検出力の確認として「再スタートで保留中の曲を使う」「reset要求を無視する」という
一時的な変異を与え、それぞれ2件・12件が失敗することを確認した。変異は製品コードに残さない。
