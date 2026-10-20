# Read Book

[![Build iOS IPA](https://github.com/tinyStepGames/read_book/actions/workflows/build-ios.yml/badge.svg)](https://github.com/tinyStepGames/read_book/actions/workflows/build-ios.yml)

Web小説を検索・閲覧・保存するための個人向けFlutterアプリです。

作品とエピソードを端末へ保存し、オフラインでも本文や挿絵を読むことができます。

## 対応サイト

- 小説家になろう
- カクヨム

## 主な機能

### 検索と管理

- 作品検索
- 作品詳細、あらすじ、目次の表示
- お気に入り
- 読書履歴
- 既読管理
- 検索条件の保存
- サイト別の書庫
- 長編作品の100話単位の目次表示

### Reader

- 前話・次話への移動
- 文字サイズの変更
- ライトモード・ダークモード
- 読書位置と文字サイズの自動保存
- アプリ再起動後の読書状態復元
- 前書き・本文・あとがきの区分表示
- ルビ、傍点、圏点
- 太字、斜体、下線、取り消し線
- 小説家になろうの「みてみん」挿絵表示

ルビや傍点を安定して表示するため、Reader本文の文字選択とコピーは無効です。

### オフライン閲覧

- エピソード単位のダウンロード
- 全話の一括ダウンロード
- 未ダウンロード話の追加取得
- ダウンロード済み本文のオフライン閲覧
- オフライン状態での前話・次話への移動
- 挿絵のローカル保存とオフライン表示
- 欠落した挿絵の自動再取得
- 作品単位・話単位のダウンロード削除

iOSではバックグラウンドURLSessionを使用します。アプリをApp Switcherから明示的に強制終了した場合、バックグラウンド転送の継続は保証されません。

### バックアップと復元

次のデータをZIPファイルへバックアップできます。

- 作品情報
- お気に入り
- 読書履歴
- 既読情報
- 保存した検索条件
- ダウンロード済み本文
- ダウンロード情報
- オフライン保存した挿絵

挿絵を含まない旧形式のバックアップも復元できます。

## 挿絵の保存

小説家になろうの本文に含まれる、許可された「みてみん」の画像をアプリ専用領域へ保存します。

保存時には次の検証を行います。

- HTTPSと許可されたドメインのみ使用
- Content-Typeと画像データを検証
- 画像サイズ、枚数、話ごとの合計容量を制限
- 一時ファイルへ書き込んだ後に保存
- バックアップ復元時の不正なパスを拒否

画像を取得できなかった場合でも、保存済み本文は引き続き表示します。

## 開発

### セットアップ

```bash

git clone https://github.com/tinyStepGames/read_book.git

cd read_book

flutter pub get

```

### 解析とテスト

```bash

flutter analyze

flutter test --reporter expanded

```

### 実行

```bash

flutter run

```

必要なFlutter・Dartのバージョンと依存関係は[`pubspec.yaml`](pubspec.yaml)を確認してください。

## iOS IPAのビルド

GitHub ActionsからiOSビルドを手動実行できます。

1. [Build iOS IPA](https://github.com/tinyStepGames/read_book/actions/workflows/build-ios.yml)を開く
2. `Run workflow`を押す
3. Branchに`main`を指定
4. 完了後、Artifactsから`read-book-ipa`をダウンロード

ワークフローは`.github/workflows/build-ios.yml`にあります。

現在生成されるIPAは未署名です。通常のiPhoneへのインストール、TestFlight、App Storeへの提出にはApple Developer用の署名設定が必要です。

## データと注意事項

作品情報、履歴、お気に入り、既読情報、本文、挿絵は端末内へ保存されます。

アプリを削除すると保存データも削除される場合があります。必要なデータは事前にバックアップしてください。

掲載サイトのHTMLやAPIが変更された場合、検索・目次・本文の取得が利用できなくなる可能性があります。各掲載サイトの利用規約と作品の著作権を尊重してください。

## 変更履歴

詳細は[`CHANGELOG.md`](CHANGELOG.md)を確認してください。

## ライセンス

現在、このリポジトリにはライセンスファイルが設定されていません。ソースコードの再利用や再配布を希望する場合は、リポジトリ所有者へ確認してください。
