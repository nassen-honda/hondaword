#!/bin/sh
#
# leehongda.com を Xserver (sv17050) へ rsync over SSH でデプロイする
#
#   ./deploy.sh      手動で実行
#   git push         すると .githooks/pre-push 経由で自動実行される
#
# 前提: サーバーパネル →「サーバー」→「SSH設定」が ON であること。
#       GitHub Actions からは使えない（国外アクセス制限が既定 ON のため）。
#
set -eu

# ---------------------------- 設定 ----------------------------
SSH_KEY="${DEPLOY_SSH_KEY:-$HOME/.ssh/xs5418.key}"
SSH_USER="xs5418"
SSH_HOST="sv17050.xserver.jp"        # xs5418.xsrv.jp でも可
SSH_PORT="10022"
REMOTE_DIR="/home/xs5418/leehongda.com/public_html"
VERIFY_URL="https://leehongda.com/"
# --------------------------------------------------------------

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR"

die() {
  echo "" >&2
  echo "❌ $1" >&2
  shift
  for line in "$@"; do echo "   $line" >&2; done
  echo "" >&2
  exit 1
}

# --- rsync の選択 ---------------------------------------------------------
# macOS 26 標準の /usr/bin/rsync は openrsync で、--no-perms を黙って無視し
# --chmod も受け付けない。Homebrew の GNU rsync があればそちらを優先する。
RSYNC=rsync
for c in /opt/homebrew/bin/rsync /opt/homebrew/opt/rsync/bin/rsync /usr/local/bin/rsync; do
  if [ -x "$c" ]; then RSYNC="$c"; break; fi
done

# --- 事前チェック ---------------------------------------------------------
[ -f "$SSH_KEY" ] || die "SSH 秘密鍵が見つかりません: $SSH_KEY" \
  "準備:" \
  "  mkdir -p ~/.ssh" \
  "  cp ~/Documents/sshKey/xs5418.key ~/.ssh/xs5418.key" \
  "  chmod 600 ~/.ssh/xs5418.key"

PERM=$(stat -f '%Lp' "$SSH_KEY" 2>/dev/null || stat -c '%a' "$SSH_KEY")
if [ "$PERM" != "600" ]; then
  die "SSH 鍵のパーミッションが $PERM です。SSH は 600 以外を拒否します。" \
    "chmod 600 $SSH_KEY"
fi

SSH_OPTS="-i $SSH_KEY -p $SSH_PORT -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

echo "▶ 1/4  接続確認   $SSH_USER@$SSH_HOST:$SSH_PORT"
if ! ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" "test -d '$REMOTE_DIR'"; then
  die "リモートのディレクトリが存在しません: $REMOTE_DIR" \
    "実際のパスを確認してください:" \
    "  ssh $SSH_OPTS $SSH_USER@$SSH_HOST 'ls -d ~/*/public_html'" \
    "（パスが違う場合は deploy.sh の REMOTE_DIR を書き換えてください）"
fi

echo "▶ 2/4  転送（$RSYNC）"
# -rltzv にしているのは権限コピー(-p)を避けるため。
# ただし openrsync は -p 無しでもソースの権限を持っていくので、
# 次の 3/4 の chmod が必須。省くと画像や CSS が 403 になる。
"$RSYNC" -rltzv --human-readable \
  --exclude='.git/' \
  --exclude='.github/' \
  --exclude='.githooks/' \
  --exclude='.DS_Store' \
  --exclude='.gitignore' \
  --exclude='deploy.sh' \
  --exclude='README.md' \
  --exclude='node_modules/' \
  --exclude='dist/' \
  -e "ssh $SSH_OPTS" \
  ./ "$SSH_USER@$SSH_HOST:$REMOTE_DIR/"

echo "▶ 3/4  パーミッションを 755 / 644 に統一"
# 注意: ここは $REMOTE_DIR 配下の全ファイルに効く。
#       同居させたい別サイト(WordPress 等)がある場合は範囲を絞ること。
ssh $SSH_OPTS "$SSH_USER@$SSH_HOST" \
  "find '$REMOTE_DIR' -type d -exec chmod 755 {} + ; find '$REMOTE_DIR' -type f -exec chmod 644 {} +"

echo "▶ 4/4  配信確認   $VERIFY_URL"
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$VERIFY_URL" || echo 000)
case "$CODE" in
  200) echo "✅ デプロイ完了 (HTTP $CODE)" ;;
  403) die "HTTP 403 — パーミッション異常です。3/4 の chmod が実行されたか確認してください。" ;;
  *)   die "HTTP $CODE — 転送先パスか権限を確認してください。" ;;
esac
