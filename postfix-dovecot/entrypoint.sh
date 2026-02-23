#!/bin/bash -x
# Postfix と rsyslog を起動します

# rsyslog の pid ファイル (デフォルトと同じ)
RSYSLOG_PID_FILE=/var/run/rsyslogd.pid

# このコンテナのデータ退避ディレクトリ
BACKUP_DIR=/mnt/postfix
test ! -d ${BACKUP_DIR} && mkdir -p ${BACKUP_DIR}

# rsyslog のデータ退避ファイル
RSYSLOG_BACKUP_FILE=${BACKUP_DIR}/var-lib-rsyslog.tar.gz

# postfix のデータ退避ファイル
POSTFIX_BACKUP_FILE=${BACKUP_DIR}/var-spool-postfix.tar.gz

# 配送されたメールの退避ファイル
MAIL_BACKUP_FILE=${BACKUP_DIR}/var-spool-mail.tar.gz

# 停止処理
terminate() {
    echo terminate start

    # postfix の停止
    /usr/sbin/postfix stop

    # dovecot の停止
    /usr/bin/doveadm stop

    # rsyslog の停止
    if [ -f ${RSYSLOG_PID_FILE} ]; then
        kill -TERM $(cat ${RSYSLOG_PID_FILE})
        # 停止まで待つ
        while kill -0 $(cat ${RSYSLOG_PID_FILE}); do
            sleep 1
        done
        # データディレクトリを退避
        tar cvfz ${RSYSLOG_BACKUP_FILE} /var/lib/rsyslog
    fi

    echo terminate end
}

# SIGTERM, SIGINT(^C) を受信したら停止する
trap 'terminate' TERM INT

# タイムゾーンの設定
ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
export TZ=JST-9

# dovecot 用の設定
useradd --home-dir /var/mail/ --shell /usr/sbin/nologin vmail
chown vmail:vmail /var/mail/
chmod 700 /var/mail/

# rsyslog のデータ退避ファイルがあれば展開
test -f ${RSYSLOG_BACKUP_FILE} && tar -C / -xvfz ${RSYSLOG_BACKUP_FILE}

# rsyslog をバックグラウンドで起動
source /etc/sysconfig/rsyslog
/usr/sbin/rsyslogd -n -i ${RSYSLOG_PID_FILE} &

# dovecot をフォアグラウンドで起動する
/usr/sbin/dovecot -F &

# postfix のデータ退避ファイルがあれば展開
test -f ${POSTFIX_BACKUP_FILE} && tar -C / -xvfz ${POSTFIX_BACKUP_FILE}

# postfix をフォアグラウンドで起動する
source /etc/sysconfig/network
/usr/libexec/postfix/aliasesdb
/usr/sbin/postfix start-fg &
POSTFIX_PID=$!
wait ${POSTFIX_PID}

# postfix が終了した場合
# postfix のデータディレクトリを退避
tar cvfz ${POSTFIX_BACKUP_FILE} /var/spool/postfix
# 配送されたメールを退避
tar cvfz ${MAIL_BACKUP_FILE} /var/spool/mail

exit 0
