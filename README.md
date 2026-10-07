# hondaword

XServer（レンタルサーバー）上の `leehongda.com` に、GitHub への push で自動デプロイするためのリポジトリです。

> ⚠️ このリポジトリは **Public** です。サーバーID・パスワードなどの認証情報は絶対にコミットしないでください。必ず GitHub Secrets に入れてください。
> ワークフローのログも誰でも閲覧できます。

## 現在の状態

- サイトのソースは**まだ入っていません**。`index.html` などをリポジトリ直下に置けば、そのままデプロイされます。
- デプロイ先の `public_html` はまだ空で、`https://leehongda.com/` は XServer のデフォルト 403 ページを返します。

## 必要な Secrets

`Settings > Secrets and variables > Actions` に以下の 3 つを登録してください。

| Secret 名 | 入れる値 | 注意 |
| --- | --- | --- |
| `FTP_SERVER` | サーバーのホスト名（`sv*****.xserver.jp`） | **ドメイン名や IP ではダメ**。サーバーパネル「サーバー情報」で確認 |
| `FTP_USERNAME` | メイン FTP アカウントなら**サーバーID**（`xs********`） | ドメイン名を入れると 530 でログイン失敗します |
| `FTP_PASSWORD` | FTP パスワード（サーバーパネルと同一） | |

- このドメインのサーバーは DNS の PTR から `sv17050.xserver.jp` と確認できます（サーバーパネルで再確認してください）。
- **サブ FTP アカウント**を使う場合、ユーザー名は `xxx@leehongda.com` 形式になり、ログイン後の起点ディレクトリも変わります。その場合は `deploy.yml` の `server-dir` を `./` に変更してください。

## デプロイの仕組み

[`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) が `main` への push で動作します（Actions タブから手動実行も可能）。

1. コードをチェックアウト
2. Secrets の有無と形式をセルフチェック（値そのものはログに出しません）
3. **FTPS**（explicit TLS, port 21）で `leehongda.com/public_html/` に同期

### 注意点

- `dangerous-clean-slate` は**使わないでください**。`server-dir` の中身を丸ごと削除するため、WordPress などの同居ファイルも消えます。既定の動作では「過去にこの Action が配置したファイルのうち、今回なくなったもの」だけが削除されます。
- Actions は毎回まっさらな状態でチェックアウトするため、同期状態ファイル（`.ftp-deploy-sync-state.json`）は引き継がれません。結果として**毎回ほぼ全ファイルが再アップロード**され、ビルド成果物の古いファイル（Vite のハッシュ付きファイル名など）はサーバーに残り続けます。
- ビルドが必要な構成（Vite / React など）に変える場合は、`deploy.yml` 内のコメントアウトされた Node ステップを有効化し、`local-dir` を `./dist/` に変更してください。
