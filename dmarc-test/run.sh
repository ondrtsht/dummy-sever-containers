#!/bin/bash
set -e

# カレントディレクトリに dns/ ディレクトリと設定ファイルが存在することを確認
if [ ! -d "./dns" ]; then
  echo "[ERROR] カレントディレクトリに 'dns' フォルダ（named.conf等が入ったもの）が見つかりません。"
  exit 1
fi

echo "=== 1. カスタムネットワークを作成中 ==="
podman network create --subnet=10.89.0.0/24 test-mail-net

echo "=== 2. ホスト側で実存するEPEL 10の公式リリースRPMファイルを安全に事前取得中 ==="
curl -L -f -o ./epel-release-latest-10.noarch.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm

echo "=== 3. Postfixコンテナをビルド中（pypolicyd-spf対応決定版） ==="
# 送信側イメージのビルド
podman build --network=host --no-cache \
  --build-arg ROLE=sender -f Containerfile.postfix -t ubi-postfix-sender .

# 受信側イメージのビルド
podman build --network=host --no-cache \
  --build-arg ROLE=receiver -f Containerfile.postfix -t ubi-postfix-receiver .

# 使用済みのRPMファイルを速やかに削除してクリーンアップ
rm -f ./epel-release-latest-10.noarch.rpm

echo "=== 4. DNSサーバーコンテナ（BIND 9）を起動中 ==="
# 【大改修】トラブルの元になるボリューム作成とファイルコピーを全廃
# ホスト側の ./dns ディレクトリを直接読み取り専用(ro)でマウントすることで、パーミッションエラーを根絶
podman run -d --name dns-server \
  --network test-mail-net --ip 10.89.0.2 \
  -v ./dns:/etc/bind:ro,z \
  docker.io/internetsystemsconsortium/bind9:9.18

echo "=== 5. 送信側メールサーバー（mail-sender）を起動中 ==="
podman run -d --name mail-sender \
  --network test-mail-net --ip 10.89.0.3 \
  --dns 10.89.0.2 --no-hosts \
  ubi-postfix-sender

echo "=== 6. 受信側メールサーバー（mail-receiver）を起動中 ==="
podman run -d --name mail-receiver \
  --network test-mail-net --ip 10.89.0.4 \
  --dns 10.89.0.2 --no-hosts \
  ubi-postfix-receiver

echo ""
echo "======================================================================="
echo " ★ [SUCCESS] すべてのインフラ（pypolicyd-spf内包型）が正常に起動しました！ ★"
echo "======================================================================="
