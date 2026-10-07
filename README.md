# hondaword

XServer（レンタルサーバー）上の `leehongda.com` に、`git push` で自動デプロイするためのリポジトリです。

> ⚠️ このリポジトリは **Public** です。サーバーID・パスワード・秘密鍵などの認証情報は絶対にコミットしないでください。

## 現在の状態

- サイトのソースはまだ最小構成です。`index.html` を差し替えれば内容が更新されます。
- デプロイは **ローカルの Mac から rsync over SSH**（[`deploy.sh`](deploy.sh) + [`.githooks/pre-push`](.githooks/pre-push)）で行います。
- GitHub Actions の FTP ワークフローは**無効化（手動実行のみ）**しています。理由は後述。

## デプロイの仕組み

```
git push
   └─ .githooks/pre-push        main への push を検知
        └─ deploy.sh             rsync over SSH で転送
             ├─ 接続確認          $REMOTE_DIR が存在するか
             ├─ rsync -rltzv      差分だけ転送
             ├─ chmod 755/644     ← 必須（下記の落とし穴を参照）
             └─ curl で HTTP 200 を確認
```

デプロイに失敗すると **push 自体が中止されます**（GitHub と本番がズレたままになるのを防ぐため）。
push だけ通したい場合は `git push --no-verify`。

## セットアップ（初回のみ）

### 1. SSH 鍵を配置する

サーバーパネルからダウンロードした秘密鍵はパーミッションが `644` のため、そのままでは SSH が拒否します。

```bash
mkdir -p ~/.ssh
cp ~/Documents/sshKey/xs5418.key ~/.ssh/xs5418.key
chmod 600 ~/.ssh/xs5418.key
```

<!-- サーバーパネル →「サーバー」→「SSH設定」が ON であることも確認してください -->

### 2. フックを有効化する

```bash
git config core.hooksPath .githooks
chmod +x .githooks/pre-push deploy.sh
```

### 3. 手動で一度動作確認する

```bash
./deploy.sh
```

`✅ デプロイ完了 (HTTP 200)` が出れば、以降は `git push` だけで反映されます。

## 接続情報

| 項目 | 値 |
| --- | --- |
| ホスト | `sv17050.xserver.jp`（`xs5418.xsrv.jp` でも可） |
| ユーザー | `xs5418`（サーバーID） |
| ポート | `10022` |
| 鍵 | `~/.ssh/xs5418.key` |
| 転送先 | `/home/xs5418/leehongda.com/public_html` |

- 鍵のコメントが `xs5418@sv17050.xserver.jp` のものが**このサーバー用**です。同じフォルダにある `xs54188.key` は `xs54188@sv17097.xserver.jp`（別サーバー）なので使わないでください。
- 転送先が違っていたら [`deploy.sh`](deploy.sh) の `REMOTE_DIR` を書き換えてください。実際のパスは次で確認できます。

```bash
ssh -i ~/.ssh/xs5418.key -p 10022 xs5418@sv17050.xserver.jp 'ls -d ~/*/public_html'
```

## なぜ GitHub Actions を使っていないのか

**XServer の SSH には「国外アクセス制限」が既定で ON になっており、海外 IP で動く GitHub Actions のランナーは接続を弾かれます。**

- [SSHにおける国外IPアドレスからのアクセス制限実施のお知らせ](https://business.xserver.ne.jp/news/detail.php?view_id=13362)
- [国外IPアドレスからのアクセス制限が可能に！「SSH設定」機能を強化](https://business.xserver.ne.jp/news/detail.php?view_id=13361)

この制限は**アカウント単位**の設定です。回避するには制限を OFF にする（＝SSH の入り口を世界中に開ける）必要があるため、**国内 IP であるこの Mac から直接送る**方式にしました。制限は ON のままにできます。

なお **FTP はこの国外制限の対象外**です。GitHub Actions の FTP が `530 Login incorrect` で失敗していたのは、国外 IP ではなく認証（パスワード）の問題でした。

## 落とし穴

### `--no-perms` は macOS では効かない

macOS 26 標準の `/usr/bin/rsync` は **openrsync** で、`--no-perms` を**黙って無視**します（`--chmod` は `invalid argument` で拒否）。ソースの権限がそのままサーバーへ渡るため、手元のファイルが `600` などだと**画像や CSS が 403 で表示されなくなります**。

そのため [`deploy.sh`](deploy.sh) は転送後に必ず `chmod 755/644` を実行します。**この手順は省略しないでください。**

Homebrew の GNU rsync が `/opt/homebrew/bin/rsync` にあれば自動でそちらを使います（`brew install rsync`）。

### `chmod` は転送先配下の全ファイルに効く

[`deploy.sh`](deploy.sh) の `find ... chmod` は `REMOTE_DIR` 配下**すべて**を対象にします。同じ `public_html` に WordPress などを同居させる場合は、対象を絞ってください。

### `pre-push` フックの実装メモ

シェルの `read` は **EOF で非ゼロを返すときにも変数を空にします**。そのためフック内では、ループの外で参照する値を必ずループの中でフラグに落としています（`local_sha` をループの外で見ると常に空になり、push が削除扱いされます）。

## FTP 方式に戻したい場合

[`.github/workflows/deploy.yml`](.github/workflows/deploy.yml) は残してあり、`push:` トリガーをコメントアウトしてあります。戻す手順:

1. ワークフロー内の `push:` ブロックを有効化
2. GitHub Secrets（`FTP_SERVER` / `FTP_USERNAME` / `FTP_PASSWORD`）を正しい値に設定
   - `FTP_SERVER` = `sv17050.xserver.jp`（証明書が `*.xserver.jp` のみのため、`xs5418.xsrv.jp` は不可）
   - `FTP_USERNAME` = `xs5418`
   - `FTP_PASSWORD` = サーバーパネルのログインパスワード（`secure.xserver.ne.jp` のアカウント用パスワードとは別物）
3. `local-dir: ./`、`server-dir: ./leehongda.com/public_html/` はそのままで可

`dangerous-clean-slate` は使わないでください（`server-dir` の中身を丸ごと削除します）。
