#!/bin/bash
set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [ ! -d "${BASE_DIR}/dns" ]; then
  echo "[ERROR] dns directory not found"
  exit 1
fi

echo "=== 1. Podman network recreate ==="

podman network rm -f test-mail-net 2>/dev/null || true

podman network create \
  --subnet=10.89.0.0/24 \
  test-mail-net


echo "=== 2. Generate DKIM key and register secret ==="

TMP_KEY_DIR=$(mktemp -d)

if command -v opendkim-genkey >/dev/null 2>&1; then

  opendkim-genkey \
    -D "${TMP_KEY_DIR}" \
    -s default \
    -d sender.test

else

  echo "[INFO] opendkim-genkey unavailable, generating with openssl container"

  podman run --rm \
    -v "${TMP_KEY_DIR}:/keys:z" \
    --entrypoint sh \
    docker.io/alpine/openssl:latest \
    -c "openssl genrsa -out /keys/default.private 2048"

  PUBKEY_STR=$(
    podman run --rm \
      -v "${TMP_KEY_DIR}:/keys:z" \
      --entrypoint sh \
      docker.io/alpine/openssl:latest \
      -c "openssl rsa -in /keys/default.private -pubout 2>/dev/null | grep -v -- '-----' | tr -d '\n'"
  )

  cat > "${TMP_KEY_DIR}/default.txt" <<EOF
default._domainkey.sender.test. IN TXT (
"v=DKIM1; k=rsa; p=${PUBKEY_STR}"
)
EOF

fi


podman secret rm dkim_private_key 2>/dev/null || true

podman secret create \
  dkim_private_key \
  "${TMP_KEY_DIR}/default.private"


echo "=== 3. Generate sender DNS zone ==="

cat > "${BASE_DIR}/dns/sender.test.zone" <<EOF
\$TTL 86400

@ IN SOA mail.sender.test. root.sender.test. (
    2026071901
    3600
    1800
    604800
    86400
)

@ IN NS mail.sender.test.

mail        IN A 10.89.0.3
mail-sender IN A 10.89.0.3

@ IN MX 10 mail.sender.test.

@ IN TXT "v=spf1 ip4:10.89.0.3 -all"

_dmarc IN TXT "v=DMARC1; p=none; pct=100"

EOF


if [ -f "${TMP_KEY_DIR}/default.txt" ]; then
  cat "${TMP_KEY_DIR}/default.txt" \
    >> "${BASE_DIR}/dns/sender.test.zone"
fi


rm -rf "${TMP_KEY_DIR}"


echo "=== 4. Download EPEL release ==="

curl -L -f \
  -o "${BASE_DIR}/epel-release-latest-10.noarch.rpm" \
  https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm


echo "=== 5. Build postfix images ==="

podman build \
  --network=host \
  --no-cache \
  --build-arg ROLE=sender \
  -f Containerfile.postfix \
  -t ubi-postfix-sender \
  "${BASE_DIR}"


podman build \
  --network=host \
  --no-cache \
  --build-arg ROLE=receiver \
  -f Containerfile.postfix \
  -t ubi-postfix-receiver \
  "${BASE_DIR}"


rm -f "${BASE_DIR}/epel-release-latest-10.noarch.rpm"


echo "=== 6. Start DNS server ==="

podman rm -f \
  dns-server \
  mail-sender \
  mail-receiver \
  2>/dev/null || true


podman run -d \
  --name dns-server \
  --network test-mail-net \
  --ip 10.89.0.2 \
  -v "${BASE_DIR}/dns:/etc/bind:ro,z" \
  docker.io/internetsystemsconsortium/bind9:9.18


sleep 3


podman exec dns-server \
  chmod 644 \
  /etc/bind/*.zone \
  /etc/bind/named.conf \
  || true


podman restart dns-server

sleep 3
echo "=== 7. Start sender mail server ==="


podman run -d \
  --name mail-sender \
  --network test-mail-net \
  --ip 10.89.0.3 \
  --dns 10.89.0.2 \
  --no-hosts \
  --secret dkim_private_key,target=/etc/opendkim/keys/default.private,uid=0,gid=0,mode=0400 \
  ubi-postfix-sender



echo "=== 8. Start receiver mail server ==="


podman run -d \
  --name mail-receiver \
  --network test-mail-net \
  --ip 10.89.0.4 \
  --dns 10.89.0.2 \
  --no-hosts \
  ubi-postfix-receiver



echo ""
echo "=== 9. Wait for services ==="

sleep 5



echo ""
echo "=== 10. Verify containers ==="


echo "--- DNS ---"
podman ps \
  --filter name=dns-server


echo "--- Sender ---"
podman ps \
  --filter name=mail-sender


echo "--- Receiver ---"
podman ps \
  --filter name=mail-receiver



echo ""
echo "=== 11. Verify DKIM socket ==="


podman exec mail-sender \
  ls -l /var/spool/postfix/public/ \
  || true



echo ""
echo "=== 12. Verify DMARC socket ==="


podman exec mail-receiver \
  ls -l /var/spool/postfix/public/ \
  || true



echo ""
echo "=== 13. Postfix status ==="


podman exec mail-sender postfix status || true

podman exec mail-receiver postfix status || true



echo ""
echo "================================================================"
echo " SUCCESS"
echo " sender : mail.sender.test (10.89.0.3)"
echo " receiver : mail.receiver.test (10.89.0.4)"
echo " DNS : 10.89.0.2"
echo "================================================================"
