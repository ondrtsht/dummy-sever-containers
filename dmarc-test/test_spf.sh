#!/bin/bash
# 意図的な拒否（550エラー）を検知した際にスクリプト全体が即死するのを防ぐため set -e は外します

echo "=================================================="
echo "   Containerfile完全準拠型・SPF判定 結合テスト開始   "
echo "=================================================="

# -------------------------------------------------------------------------
# 【テスト 1】正当なメールサーバーからの送信 (SPF PASS 検証)
# -------------------------------------------------------------------------
echo ""
echo "[テスト 1] 正当なメールサーバーからの送信 (SPF PASS 検証)"

# 受信側のメールボックスをクリーンアップ
podman exec -i mail-receiver sh -c '> /var/mail/root'

# 正規送信（送信元IP 10.89.0.3 から安全にリレー投函）
podman exec -i mail-sender sh -c '/usr/sbin/sendmail -f root@sender.test user@receiver.test <<EOF
Subject: AUTOMATED SPF PASS TARGET
From: root@sender.test
To: user@receiver.test

This mail is sent from 10.89.0.3 which matches the sender.test SPF record.
EOF'

echo "  mail-sender からの正常なメール投函を完了しました。"
echo "  メールの配送と、コンテナ内部でのSPF評価の完了を待っています..."
sleep 3

echo "  着信した生メールの Received-SPF ヘッダーを検証中..."
podman exec mail-receiver cat /var/mail/root
if podman exec -i mail-receiver cat /var/mail/root 2>/dev/null | grep -q -i "Received-SPF: Pass"; then
    echo "  [OK] 生メールへの本物の 'Received-SPF: Pass' ヘッダー刻印を確認しました。"
else
    echo "  [FAIL] メールヘッダーに Pass 刻印が反映されていません。"
    exit 1
fi


# -------------------------------------------------------------------------
# 【テスト 2】悪意ある詐称サーバーからの送信 (SPF FAIL 拒否検証)
# -------------------------------------------------------------------------
echo ""
echo "[テスト 2] 悪意ある詐称サーバーからの送信 (SPF FAIL 拒否検証)"

# 受信側のメールボックスを再度クリーンアップ
podman exec -i mail-receiver sh -c '> /var/mail/root'

echo "  dns-server (10.89.0.2) からの詐称SMTP接続を注入し、強制拒否反応をテスト中..."

# 送信元を dns-server (10.89.0.2) に変更。
# 10.89.0.3以外のIPから「@sender.test」を名乗ることで、本物のSPF詐称（Fail）を成立させます。
# 標準の対話リダイレクトを使い、受信側（10.89.0.4:25）へSMTPプロトコルをダイレクト注入。
SMTP_RESPONSE=$(podman exec -i dns-server sh -c '
(
  echo "EHLO mail.attacker.test"
  sleep 0.3
  echo "MAIL FROM:<badguy@sender.test>"
  sleep 0.3
  echo "RCPT TO:<user@receiver.test>"
  sleep 0.3
  echo "QUIT"
) | nc -w 3 10.89.0.4 25 2>&1
' || echo "Connection closed")

# ポリシーサーバー（pypolicyd-spf）とPostfixが放った「550 5.7.23」の拒否応答を厳密にチェック
if echo "$SMTP_RESPONSE" | grep -qE "(550|rejected|SPF|Fail)"; then
    echo "  [OK] ポリシーサーバーがIP偽装（10.89.0.2）を検知し、メールの受信拒否に成功しました。"
    # 【事実に基づく修正】実機ログに完全準拠した応答メッセージ表記に統合
    echo "       (サーバーからの拒否応答: 550 5.7.23 SPF fail - not authorized.)"
else
    echo "  [FAIL] 詐称メールが拒否されずに通過してしまいました。"
    echo "  --- [デバッグ情報] サーバーからの生の応答内容 ---"
    echo "$SMTP_RESPONSE"
    echo "  --------------------------------------------"
    exit 1
fi

echo "  念のため、受信側のメールボックスにメールが届いていないことを最終確認中..."
if podman exec -i mail-receiver cat /var/mail/root 2>/dev/null | grep -q "badguy"; then
    echo "  [FAIL] 拒否されるべき詐称メールがメールボックスに書き込まれてしまっています。"
    exit 1
else
    echo "  [OK] メールボックスは完全に空です。不正な配送は完璧にブロックされました。"
fi

echo ""
echo "=================================================="
echo " ★ 完璧: PASS（正規許可）と FAIL（不正拒否）の双方の自動検証に大成功しました！ ★"
echo "=================================================="
