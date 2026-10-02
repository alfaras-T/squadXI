# Squad XI — iOS アプリ

https://squadxi.futbol/ を読み込む iOS アプリ（Capacitor 製の「殻」）です。
Google Drive「football lineup【2】/iOSアプリ化_引き渡し」の `squadxi-ios/` と `README_ビルド手順.md` をもとにしています。

**Mac も Xcode も使わずにリリースできる構成**にしてあります。ビルドとアップロードは GitHub Actions の macOS 環境（Xcode 入り）で行います。

## 設定済みのもの（手順書 §3〜§4）

手順書で Xcode を開いて手入力する設定は、すべてプロジェクトのファイルに書き込み済みです。

| 手順書 | 内容 | ファイル |
|---|---|---|
| §3 | `npx cap add ios` で iOS プロジェクトを生成 | `squadxi-ios/ios/` |
| §4-1 | 表示名 `Squad XI`／Bundle ID `futbol.squadxi.app`／Version `1.0.0`／Build `1`／iOS 15.0 以上／iPhone のみ／縦向きのみ | `project.pbxproj`, `Info.plist`, `Podfile` |
| §4-2 | `WKAppBoundDomains`、`ITSAppUsesNonExemptEncryption = NO`、写真保存・カメラの説明文、ステータスバー白文字 | `ios/App/App/Info.plist` |
| §4-3 | アイコン（1024×1024）。ビルド時に CI が配置します（下記「アイコン」） | `.github/workflows/ios.yml` |
| §4-4 | 起動画面の背景 `#0A0E0C`、ロゴなし | `ios/App/App/Base.lproj/LaunchScreen.storyboard` |

## アプリ専用の動き（共有プレビュー）

ウェブ版の iOS では「画像を保存」「Instagram」が共有シートを開きますが、アプリでは共有シートを使わず次のように動きます。

| ボタン | アプリでの動き |
|---|---|
| 画像を保存 | 写真アプリに直接保存 |
| Instagram | 写真に保存して、Instagram の新規投稿画面をその画像で開く |
| X | 写真に保存してから、X の投稿画面（本文・リンク入り）を開く。画像は X 側で添付する（X は他アプリからの画像の受け渡しに対応していない） |

仕組み: `ios/App/App/SquadXIPlugin.swift` のネイティブ処理と、ページに差し込むスクリプトで実現しています。スクリプトはウェブ側の共有プレビューのボタン ID（`#shDl` `#shIG` `#shX`）と、`navigator.share` / `a[download]` / `window.open` の呼び方に合わせてあります。**ウェブ側でこれらを変えた場合、アプリは自動的にウェブ版と同じ動き（共有シート）に戻ります**。合わせ直すには `SquadXIPlugin.swift` を更新して再ビルドします。

## リリースまでの流れ（Mac なし）

アプリは**友人（ビルド担当）の Apple Developer アカウント名義**で公開します（手順書 §5 の合意どおり）。

### 1. 友人のアカウントで App Store Connect にアプリを登録（手順書 §5 後半と同じ）

1. https://appstoreconnect.apple.com/ → マイApp → 「+」→ 新規App
   - プラットフォーム: iOS／名前: `Squad XI - スカッドイレブン`／プライマリ言語: 日本語／Bundle ID: `futbol.squadxi.app`／SKU: `squadxi-ios-001`
   - Bundle ID が候補に出ない場合は、先に https://developer.apple.com/account/resources/identifiers で `futbol.squadxi.app`（Explicit）を登録します。
2. Users and Access → 「+」で村山を **App Manager** として招待。
3. TestFlight → 内部テスターに自分と村山を追加。

### 2. 友人が App Store Connect API キーを発行し、GitHub に登録

CI が友人のアカウントで署名・アップロードするために使います。

1. App Store Connect → Users and Access → **Integrations** → App Store Connect API → Team Keys → 「+」
   - 名前: `squadxi-github-actions`／アクセス: **Admin**（署名用の証明書を CI 上で自動作成するのに必要）
2. 発行後に次の 4 つを控えます。`.p8` ファイルは**一度しかダウンロードできません**。
   - Issuer ID（キー一覧の上部）
   - Key ID
   - `AuthKey_XXXXXXXXXX.p8`（テキストファイル。中身をそのまま使う）
   - Team ID（https://developer.apple.com/account → メンバーシップの詳細）
3. GitHub のこのリポジトリ → Settings → Secrets and variables → Actions → New repository secret で登録します。

| Secret 名 | 値 |
|---|---|
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID |
| `APP_STORE_CONNECT_API_KEY_P8` | `.p8` ファイルの中身（`-----BEGIN PRIVATE KEY-----` から `-----END PRIVATE KEY-----` まで全部） |
| `APPLE_TEAM_ID` | Team ID |

> Admin の API キーは、友人のアカウントでアプリ・証明書を操作できる強い権限です。友人に了承をもらい、可能なら**友人自身に Secrets を登録してもらってください**（登録後は誰も値を読み出せません）。不要になったら App Store Connect でキーを取り消せば、すぐに無効になります。

### 3. ビルドして TestFlight へアップロード

1. GitHub → **Actions** → **iOS build** → **Run workflow**
2. 「TestFlight にアップロードする」にチェックを入れて実行（20 分前後）。
3. 成功から 10〜30 分後、App Store Connect の TestFlight にビルドが出ます。iPhone の TestFlight アプリから入れて、手順書 §6 のチェック項目を確認します。

ビルド番号は自動で毎回増えます（実行番号を使用）。手動で指定する場合は、前回より大きい数を入れてください。

### 4. 審査へ提出（手順書 §7）

掲載文・スクリーンショット・プライバシー申告は `store-listing_ja.md`（Drive）のとおり村山が入力し、「審査へ提出」は友人が押します。

## アイコン

`squadxi-ios/resources/icon-1024.png`（サイトの `docs/icon-1024.png` と同じもの）を CI がアプリに組み込みます。無い場合は https://squadxi.futbol/icon-1024.png を取得して使います。どちらの場合も CI が 1024×1024・透過なしであることを確認します。

## 以後の更新（手順書 §9）

選手データやウェブ側の修正は**ビルド不要**です（アプリはウェブを読み込むだけ）。アイコン・アプリ名・ネイティブ機能を変えたときだけ、`squadxi-ios/` を更新して「3. ビルドして TestFlight へアップロード」をやり直します。新しいバージョンとして出すときは `project.pbxproj` の `MARKETING_VERSION` を上げてください。

## Mac で作業する場合

設定は済んでいるので、手順書の §4 は不要です。

```bash
cd squadxi-ios
npm ci
npx cap sync ios   # pod install も実行されます
npx cap open ios   # Signing & Capabilities で Team を選び、Product → Archive
```

アイコンは `ios/App/App/Assets.xcassets/AppIcon.appiconset/AppIcon-512@2x.png` を `icon-1024.png` で置き換えてください（リポジトリ内のものは Capacitor の仮アイコンです）。
