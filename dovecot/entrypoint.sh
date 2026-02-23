#!/bin/bash -x

BACKUP_FILE=/mnt/dovecot/var-dovecot.tar.gz

# 停止処理
terminate() {
    echo terminate start

    # dovecot の停止
    /usr/bin/doveadm stop

    # データの退避
    mkdir -p /mnt/dovecot
    tar cvfz ${BACKUP_FILE} /var/dovecot

    echo terminate end
}

# SIGTERM, SIGINT(^C) を受信したら停止処理を実行する
trap 'terminate' TERM INT

# タイムゾーンを日本に設定
ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
export TZ=JST-9

# メールボックス用のユーザーとグループを作成
groupadd -g 1000 vmail
useradd -u 1000 -g vmail -M -d /var/dovecot --shell /usr/sbin/nologin vmail

# メールボックス用ディレクトリの作成・復元
mkdir -p /var/dovecot
chown -R vmail:vmail /var/dovecot
if [ -f ${BACKUP_FILE} ]; then
    (cd /; tar xvfz  ${BACKUP_FILE})
fi

# dovecot を起動
/usr/sbin/dovecot -F > /dev/stdout 2> /dev/stderr &
PID=$!
wait ${PID}
exit $?