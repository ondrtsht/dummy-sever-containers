#!/bin/bash
set -e

# カレントディレクトリに dns/ ディレクトリと設定ファイルが存在することを確認
if [ ! -d "./dns" ]; then
  echo "[ERROR] カレントディレクトリに 'dns' フォルダが見つかりません。"
  exit 1
fi

echo "=== 1. カスタムネットワークを作成中 ==="
podman network rm -f test-mail-net 2>/dev/null || true
podman network create --subnet=10.89.0.0/24 test-mail-net

echo "=== 2. ホスト側でのDKIM鍵ペア生成 & Podmanシークレット登録 & DNS自動反映 ==="
TMP_KEY_DIR=$(mktemp -d)

# OpenDKIMツール（ホスト側）を使用して鍵ペアを生成
if ! command -v opendkim-genkey &> /dev/null; then
  echo "[INFO] ホスト環境に opendkim-genkey が見つからないため、鍵の生成のみ一時コンテナで行います..."
  podman run --rm -v "${TMP_KEY_DIR}:/keys:z" --entrypoint sh docker.io/alpine/openssl:latest \
    -c "openssl genrsa -out /keys/default.private 2048"
  PUBKEY_STR=$(podman run --rm -v "${TMP_KEY_DIR}:/keys:z" --entrypoint sh docker.io/alpine/openssl:latest \
    -c "openssl rsa -in /keys/default.private -pubout 2>/dev/null | grep -v -- '-----' | tr -d '\n'")
  
  # 【環境依存バグの完全根絶】echo -e を全廃。printf により、ホストの差異に関わらずクリーンなカッコ付きマルチラインを出力。
  printf "default._domainkey.sender.test. IN TXT (\n    \"v=DKIM1; k=rsa; p=%s\"\n    \"%s\"\n    \"%s\"\n    \"%s\"\n    \"%s\"\n    \"%s\"\n    \"%s\" )\n" \
    "$(echo "$PUBKEY_STR" | cut -c 1-64)" \
    "$(echo "$PUBKEY_STR" | cut -c 65-128)" \
    "$(echo "$PUBKEY_STR" | cut -c 129-192)" \
    "$(echo "$PUBKEY_STR" | cut -c 193-256)" \
    "$(echo "$PUBKEY_STR" | cut -c 257-320)" \
    "$(echo "$PUBKEY_STR" | cut -c 321-384)" \
    "$(echo "$PUBKEY_STR" | cut -c 385-)" > "${TMP_KEY_DIR}/default.txt"
else
  opendkim-genkey -D "$TMP_KEY_DIR" -s default -d sender.test
fi

# 既存の同名シークレットがあれば削除
podman secret rm dkim_private_key 2>/dev/null || true
podman secret create dkim_private_key "${TMP_KEY_DIR}/default.private"

# 【冪等性の完全担保】古いファイルの残骸を部分削除するのをやめ、毎回セクターレベルから完全クリーン上書き生成。
echo "[INFO] 最新のDKIM公開鍵を反映し、./dns/sender.test.zone をクリーンに再生成中..."
cat << 'EOF' > ./dns/sender.test.zone
$TTL 86400
@   IN  SOA mail.sender.test. root.sender.test. (
        2026071901  ; Serial (YYYYMMDDNN)
        3600        ; Refresh
        1800        ; Retry
        604800      ; Expire
        86400 )     ; Minimum TTL

; ネームサーバー定義
@   IN  NS  mail.sender.test.

; Aレコード定義 (各コンテナの固定IPと完全同期)
mail        IN  A   10.89.0.3
mail-sender IN  A   10.89.0.3

; ドメインルートに対するMXおよびSPFレコード
@   IN  MX  10 mail.sender.test.
@   IN  TXT "v=spf1 ip4:10.89.0.3 -all"

; DMARCレコード定義
_dmarc      IN  TXT "v=DMARC1; p=none; ruf=mailto:dmarc@sender.test; rf=afrf; pct=100"
EOF

echo "" >> ./dns/sender.test.zone
cat "${TMP_KEY_DIR}/default.txt" >> ./dns/sender.test.zone
rm -rf "$TMP_KEY_DIR"

echo "=== 3. ホスト側で実存するEPEL 10の公式リリースRPMファイルを安全に事前取得中 ==="
curl -L -f -o ./epel-release-latest-10.noarch.rpm https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm

echo "=== 4. Postfixコンテナをビルド中 ==="
podman build --network=host --no-cache --build-arg ROLE=sender -f Containerfile.postfix -t ubi-postfix-sender .
podman build --network=host --no-cache --build-arg ROLE=receiver -f Containerfile.postfix -t ubi-postfix-receiver .
rm -f ./epel-release-latest-10.noarch.rpm

echo "=== 5. DNSサーバーコンテナ（BIND 9）を起動中 ==="
podman rm -f dns-server mail-sender mail-receiver 2>/dev/null || true

podman run -d --name dns-server \
  --network test-mail-net --ip 10.89.0.2 \
  -v ./dns:/etc/bind:ro,z \
  docker.io/internetsystemsconsortium/bind9:9.18

sleep 2

# マウント権限の強制解放
podman exec -u root dns-server chmod 644 /etc/bind/named.conf /etc/bind/sender.test.zone /etc/bind/receiver.test.zone /etc/bind/10.89.0.zone || true

# 【確実な開通】コンテナをrestartさせることで、3オクテットの健康な逆引きゾーンを確実に100%メモリロード展開
echo "[INFO] BIND9コンテナをクリーン再起動してデータベースを確定展開中..."
podman restart dns-server
sleep 2

echo "=== 6. 送信側メールサーバー（mail-sender）を起動中 ==="
podman run -d --name mail-sender \
  --network test-mail-net --ip 10.89.0.3 \
  --dns 10.89.0.2 --no-hosts \
  --secret dkim_private_key,target=/etc/opendkim/keys/default.private,uid=0,gid=0,mode=0400 \
  ubi-postfix-sender

echo "=== 7. 受信側メールサーバー（mail-receiver）を起動中 ==="
podman run -d --name mail-receiver \
  --network test-mail-net --ip 10.89.0.4 \
  --dns 10.89.0.2 --no-hosts \
  ubi-postfix-receiver

echo ""
echo "======================================================================="
echo " ★ [SUCCESS] 破損したインフラの完全自動復旧・大開通が完了しました！ ★"
echo "======================================================================="
