#!/bin/bash
# 終了ステータスが厳格な環境（set -e）でも確実に完走させる設定
set -e

echo "=================================================="
echo "          テスト環境の完全初期化を開始します          "
echo "=================================================="

# 1. コンテナの安全な停止と削除
# 個別に || true を適用し、かつ標準エラー出力を捨てることで不要な警告を非表示にします
podman stop mail-sender 2>/dev/null || true
podman stop mail-receiver 2>/dev/null || true
podman stop dns-server 2>/dev/null || true

podman rm mail-sender 2>/dev/null || true
podman rm mail-receiver 2>/dev/null || true
podman rm dns-server 2>/dev/null || true

# 2. ボリュームとネットワークの確実なクリーンアップ
podman volume rm dns-config 2>/dev/null || true
podman network rm test-mail-net 2>/dev/null || true

echo ""
echo "=== [SUCCESS] すべてのコンテナ、ボリューム、ネットワークを完全に初期化しました ==="
echo "=================================================="
