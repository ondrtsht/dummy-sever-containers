#!/bin/bash
# エラーが発生した場合はその場で中断
set -e

# 出力に色を付けるためのカラーコード定義
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # 色リセット

echo -e "${GREEN}=== 1. DNS名前解決（正引き）の整合性をチェック中 ===${NC}"
# 送信側コンテナから受信側のAレコード（IP）が引けるか検証
RESOLVED_IP=$(podman exec -it mail-sender getent hosts mail.receiver.test | awk '{print $1}' | tr -d '\r')

if [ "$RESOLVED_IP" = "10.89.0.4" ]; then
    echo -e "  [${GREEN}OK${NC}] mail.receiver.test の解決結果: $RESOLVED_IP (正常)"
else
    echo -e "  [${RED}FAIL${NC}] 名前解決に失敗、またはIPが不正です: $RESOLVED_IP"
    exit 1
fi

echo -e "\n${GREEN}=== 2. 受信側コンテナ内の初期メールボックスの状態を確認 ===${NC}"
# 古いテストデータによる誤判定を防ぐため、現在のメールボックスのサイズや実存を確認
if podman exec -it mail-receiver [ -f /var/mail/root ]; then
    # 既存のメールボックスがある場合はサイズを取得
    MBOX_SIZE=$(podman exec -it mail-receiver stat -c %s /var/mail/root | tr -d '\r')
    echo "  現在のメールボックス (/var/mail/root) のサイズ: $MBOX_SIZE バイト"
else
    MBOX_SIZE=0
    echo "  メールボックスはまだ空です (正常)"
fi

echo -e "\n${GREEN}=== 3. 通常のテストメールを送信中（MTAサブミッション） ===${NC}"
# 以前のレビューで確定した、警告の出ないPostfix内蔵sendmailコマンドを叩く
# -f オプションでエンベロープFromを確実に固定
podman exec -it mail-sender bash -c '/usr/sbin/sendmail -f root@sender.test user@receiver.test <<EOF
Subject: Automated Sandbox Verification
From: root@sender.test
To: user@receiver.test

MTA native delivery protocol integration successful.
EOF'
echo "  mail-sender から user@receiver.test 宛てにメールを投入しました。"

echo -e "\n${GREEN}=== 4. メール配送処理の完了を待機中（3秒） ===${NC}"
sleep 3

echo -e "\n${GREEN}=== 5. 受信側（mail-receiver）の着信ログを確認 ===${NC}"
# 着信が成功しているか、ログから status=sent の文字列を実存確認
if podman logs mail-receiver | grep -q "status=sent"; then
    echo -e "  [${GREEN}OK${NC}] 受信側Postfixのログに 'status=sent' を検知しました。"
else
    echo -e "  [${RED}FAIL${NC}] ログに配送成功レコードが見つかりません。キュー詰まりの可能性があります。"
    podman logs mail-receiver | tail -n 10
    exit 1
fi

echo -e "\n${GREEN}=== 6. 受信メールボックス（Mbox生データ）の実存チェック ===${NC}"
# メールファイルが正しく更新（追記）されたか、ファイルサイズの変化で実証
if podman exec -it mail-receiver [ -f /var/mail/root ]; then
    NEW_SIZE=$(podman exec -it mail-receiver stat -c %s /var/mail/root | tr -d '\r')
    
    if [ "$NEW_SIZE" -gt "$MBOX_SIZE" ]; then
        echo -e "  [${GREEN}OK${NC}] メールファイルの実質的な増加を確認: $MBOX_SIZE -> $NEW_SIZE バイト"
        echo "  --- 届いた生メールのヘッダー（抜粋） ---"
        podman exec -it mail-receiver cat /var/mail/root | grep -E '^(Return-Path:|X-Original-To:|Received:|Subject:)' | head -n 5
        echo "  ----------------------------------------"
    else
        echo -e "  [${RED}FAIL${NC}] メールファイルが更新されていません。"
        exit 1
    fi
else
    echo -e "  [${RED}FAIL${NC}] 受信メールファイル (/var/mail/root) が実存しません。"
    exit 1
fi

echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}★ 動作確認の全工程が100%成功しました！インフラは完全無欠です ★${NC}"
echo -e "${GREEN}==================================================${NC}"
