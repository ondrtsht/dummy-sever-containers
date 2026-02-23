#!/bin/bash -x

BACKUP_FILE=/mnt/postfix/var-postfix.tar.gz

# 停止処理
terminate() {
    echo terminate start

    # postfix の停止
    /usr/sbin/postfix stop
    while postfix status; do
        echo "Waiting for Postfix to shut down gracefully..."
        sleep 1
    done

    # データの退避
    mkdir -p /mnt/postfix
    tar cvfz ${BACKUP_FILE} /var/spool/postfix /var/lib/postfix

    echo terminate end
}

# SIGTERM, SIGINT(^C) を受信したら停止処理を実行する
trap 'terminate' TERM INT

# タイムゾーンを日本に設定
ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
export TZ=JST-9

# postfix のデータの復元
mkdir -p /var/postfix
chown -R vmail:vmail /var/postfix
if [ -f ${BACKUP_FILE} ]; then
    (cd /; tar xvfz  ${BACKUP_FILE})
fi

# postfix を起動
source /etc/sysconfig/network
/usr/libexec/postfix/aliasesdb
postmap /etc/postfix/virtual
if [ -n "${VIRTUAL_TRANSPORT}" ]; then
    /usr/sbin/postconf -e "virtual_transport = ${VIRTUAL_TRANSPORT}"
fi
/usr/sbin/postfix start-fg > /dev/stdout 2> /dev/stderr &
PID=$!
wait ${PID}
exit $?