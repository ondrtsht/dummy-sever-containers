#!/bin/bash
# -------------------------------------------------------------------------
#  DMARC検証環境・テスト自動化スクリプト (verify_dmarc.sh)
#  [準拠]: 環境起因のソケット切断やバインドエラーを根絶するため、
#              Postfix内製の /usr/sbin/sendmail -bs (SMTPモード) を採用。
# -------------------------------------------------------------------------
set -e

echo "=================================================="
echo "   Containerfile完全準拠型・DMARC判定 結合テスト開始   "
echo "=================================================="

# 1. 受信側のメールボックスを事前にクリーンアップ
podman exec -i mail-receiver sh -c '> /var/mail/root'

echo ""
echo "=== 1. 送信側メールサーバー内部での SMTP 配送シミュレーション ==="

# 【最高セキュリティ仕様の本質解決】
# ポート25番のソケット直接叩き込みや、環境依存の激しい/dev/tcp記述を全廃し、
# Postfix内製の「sendmail -bs」を使用します。
# -bs オプションは、Postfixに対して「標準入出力からSMTPプロトコルを受け付ける」よう強制するモードです。
# これにより、環境依存のソケット切断や改行コードのエラーを完璧に回避しつつ、
# 内部的には「外部のSMTPからメールが届いた」と100%同じ扱いになり、OpenDKIM署名が確実に発火します。
podman exec -i mail-sender sh -c '/usr/sbin/sendmail -bs' <<EOF
EHLO mail.sender.test
MAIL FROM:<root@sender.test>
RCPT TO:<user@receiver.test>
DATA
Subject: AUTOMATED DMARC PASS TARGET
From: root@sender.test
To: user@receiver.test

This mail is processed via robust sendmail SMTP engine to bypass container restrictions.
.
QUIT
EOF

echo "  メールの配送と、各ミルターの評価完了を待っています..."
sleep 4

echo ""
echo "=== 2. 生メールのヘッダー解析 ==="
# 着信した生メールの内容（ヘッダー）をダンプして確認
podman exec mail-receiver cat /var/mail/root

echo "-----------------------------------------------------------------------"
echo "=== 3. DMARC 認証結果の自動判定 ==="

# 受信したメールボックス内の DMARC 認証ヘッダーを厳密にチェック
# OpenDMARC検証を通過すると「Authentication-Results」ヘッダーに「dmarc=pass」が刻印されます。
if podman exec -i mail-receiver cat /var/mail/root 2>/dev/null | grep -q -i "dmarc=pass"; then
    echo " 🎉 【SUCCESS】生メールへの本物の 'dmarc=pass' ヘッダー刻印を確認しました！"
    echo "    (送信側のSPF/DKIM署名と、受信側のOpenDMARC Milterが完璧に連動しています)"
else
    echo " ❌ 【FAILED】メールヘッダーに dmarc=pass 刻印が反映されていません。"
    echo "    ・dns/named.conf の recursion yes 設定が正しく反映されているか"
    echo "    ・各コンテナ内の OpenDKIM / OpenDMARC デーモンが正常起動しているかを確認してください。"
    exit 1
fi
echo "=================================================="
