#!/bin/bash
set -e

echo "[INFO] role=${ROLE}"

echo "nameserver 10.89.0.2" > /etc/resolv.conf


echo "[INFO] starting rsyslog"
/usr/sbin/rsyslogd || true


mkdir -p /var/spool/postfix/public
chmod 777 /var/spool/postfix/public


newaliases || true


postfix set-permissions || true


mkdir -p /var/spool/postfix/etc
mkdir -p /var/spool/postfix/lib64

echo "nameserver 10.89.0.2" > /var/spool/postfix/etc/resolv.conf

cp -f /etc/nsswitch.conf /var/spool/postfix/etc/ || true
cp -f /etc/services /var/spool/postfix/etc/ || true

cp -f /lib64/libnss_* /var/spool/postfix/lib64/ || true
cp -f /lib64/libresolv* /var/spool/postfix/lib64/ || true
cp -f /lib64/libcrypto* /var/spool/postfix/lib64/ || true
cp -f /lib64/libc.so* /var/spool/postfix/lib64/ || true


if [ "${ROLE}" = "sender" ]; then

echo "[INFO] OpenDKIM setup"

cat > /etc/opendkim.conf <<'DKIM'
Syslog yes
LogWhy yes
Mode s
Domain sender.test
Selector default
KeyFile /etc/opendkim/keys/default.private
Socket local:/var/spool/postfix/public/opendkim.sock
PidFile /var/spool/postfix/public/opendkim.pid
UserID opendkim:opendkim
UMask 002
Canonicalization relaxed/relaxed
OversignHeaders From
DKIM


chown opendkim:opendkim /etc/opendkim/keys/default.private || true
chmod 400 /etc/opendkim/keys/default.private || true


rm -f /var/spool/postfix/public/opendkim.sock

/usrusr/sbin/opendkim -f -x /etc/opendkim.conf &

fi


if [ "${ROLE}" = "receiver" ]; then

echo "[INFO] OpenDMARC setup"

cat > /etc/opendmarc.conf <<'DMARC'
Syslog true
AuthservID mail.receiver.test
Socket local:/var/spool/postfix/public/opendmarc.sock
PidFile /var/spool/postfix/public/opendmarc.pid
SoftwareHeader true
FailureReports false
RejectFailures false
UserID opendmarc:opendmarc
UMask 007
DMARC


rm -f /var/spool/postfix/public/opendmarc.sock

/usr/sbin/opendmarc -f -c /etc/opendmarc.conf &


fi


(
while true
do
    chmod 666 /var/spool/postfix/public/*.sock 2>/dev/null || true
    sleep 2
done
) &


sleep 3


echo "[INFO] starting postfix"

exec postfix start-fg
EOF