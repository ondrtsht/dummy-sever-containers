#!/usr/bin/env bash
set -euox pipefail

# ==============================================================================
# 設定パラメータ
# ==============================================================================
IMAGE_NAME="localhost/ubi10-opendkim"
TAG="latest"
CONTAINER_NAME="opendkim-service"
HOST_DIR="${HOME}/.config/opendkim"  # ルートレス用に一般ユーザーのホーム配下に配置

echo "========================================================================"
echo "🚀 OpenDKIM (Podman / UBI 10 Minimal) のビルド＆クリーン起動を開始します"
echo "========================================================================"

# ==============================================================================
# 1. 既存の古いコンテナとビルドキャッシュ（宙ぶらりんイメージ）の削除
# ==============================================================================
if podman ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "🧹 古いコンテナ [${CONTAINER_NAME}] を停止・削除中..."
    podman rm -f "${CONTAINER_NAME}"
fi

# if podman images -f "dangling=true" -q | grep -q .; then
#     echo "🧹 不要なビルドキャッシュイメージを削除中..."
#     podman rmi $(podman images -f "dangling=true" -q)
# fi

# リポジトリ外からインストールする rpm パッケージ置き場
EXTRA_RPMS_DIR=$(pwd)/extra_rpms
mkdir -p ${EXTRA_RPMS_DIR}

# epel-release パッケージを取得
EPEL_RPM_URL=https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm
if [ ! -f ${EXTRA_RPMS_DIR}/$(basename ${EPEL_RPM_URL}) ]; then
    podman run --rm -v "${EXTRA_RPMS_DIR}:/dist:Z" registry.access.redhat.com/ubi10/ubi \
        dnf download --destdir=/dist ${EPEL_RPM_URL}
fi

# ==============================================================================
# 2. ルートレス対応の永続化ディレクトリ・デフォルト設定ファイルの配置
# ==============================================================================
echo "📂 ホスト側の設定ディレクトリを準備中: ${HOST_DIR}"
mkdir -p "${HOST_DIR}/keys"

if [ ! -f "${HOST_DIR}/opendkim.conf" ]; then
    echo "📝 最小構成の opendkim.conf を自動生成中..."
    cat << 'EOF' > "${HOST_DIR}/opendkim.conf"
BaseDirectory           /run/opendkim
Mode                    sv
SubDomains              no
Syslog                  yes
SyslogSuccess           yes
LogWhy                  yes
UserID                  opendkim:opendkim
Socket                  inet:8891@0.0.0.0
Canonicalization        relaxed/simple
# 必要に応じて以下を有効化してください
# KeyTable              /etc/opendkim/keys/keytable
# SigningTable          /etc/opendkim/keys/signingtable
# InternalHosts         /etc/opendkim/keys/trustedhosts
EOF
fi

# ==============================================================================
# 3. コンテナイメージのビルド
# ==============================================================================
echo "🏗️ 公式仕様に準拠した構成でイメージをビルド中..."
podman build -t "${IMAGE_NAME}:${TAG}" .

# 署名用の鍵作成
DKIM_KEYDIR=/etc/opendkim/keys
DKIM_KEYDIR_ON_HOST=$(pwd)/config${DKIM_KEYDIR}
if [ ! -d ${DKIM_KEYDIR_ON_HOST} ]; then
    mkdir -p ${DKIM_KEYDIR_ON_HOST}
    podman run --rm -v "$(pwd)/config${DKIM_KEYDIR}:${DKIM_KEYDIR}:Z" "${IMAGE_NAME}:${TAG}" /bin/sh -c '
/usr/sbin/opendkim-genkey -D "${DKIM_KEYDIR}/" -d "${MY_DOMAIN}" -s "${DKIM_SELECTOR}" -b 2048 -r -S -v --notestmode \
    && chown -R root:opendkim "${DKIM_KEYDIR}/" \
    && chmod 640 "${DKIM_KEYDIR}/${DKIM_SELECTOR}.private" \
    && chmod 644 "${DKIM_KEYDIR}/${DKIM_SELECTOR}.txt" \
    && chown -R root:opendkim /run/opendkim \
    && chmod g+rwx /run/opendkim
'
fi

# ==============================================================================
# 4. コンテナの起動
# ==============================================================================
echo "▶️ コンテナ [${CONTAINER_NAME}] をバックグラウンド起動中..."
podman run -d \
    --name "${CONTAINER_NAME}" \
    -p 8891:8891 \
    --restart unless-stopped \
    "${IMAGE_NAME}:${TAG}"
#   -v "${HOST_DIR}/opendkim.conf:/etc/opendkim/opendkim.conf:ro" \
#    -v "${HOST_DIR}/keys:/etc/opendkim/keys:ro" \

echo "========================================================================"
echo "🎉 処理が完了しました！"
echo "========================================================================"
echo "🔹 動作ログの確認:"
echo "   podman logs -f ${CONTAINER_NAME}"
echo "🔹 設定ファイルの配置場所（ホスト側）:"
echo "   ${HOST_DIR}/opendkim.conf"
echo "========================================================================"
