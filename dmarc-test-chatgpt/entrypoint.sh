#!/bin/bash
set -e

ROLE="${ROLE:-unknown}"

echo "=== starting mail container role=${ROLE} ==="


# syslog
/usr/sbin/rsyslogd || true


# -------------------------
# OpenDKIM sender
# -------------------------

if [ "${ROLE}" = "sender" ]; then

    mkdir -p /run/opendkim
    mkdir -p /etc/opendkim/keys


    if [ -f /run/secrets/dkim_private_key ]; then

        install \
          -o opendkim \
          -g opendkim \
          -m 0600 \
          /run/secrets/dkim_private_key \
          /etc/opendkim/keys/default.private

    fi


    cat > /etc/opendkim.conf <<EOF
Syslog yes
Mode s
UserID opendkim:opendkim
Selector default
Domain sender.test
KeyFile /etc/opendkim/keys/default.private
Socket local:/run/opendkim/opendkim.sock
PidFile /run/opendkim/opendkim.pid
Canonicalization relaxed/relaxed
OversignHeaders From
EOF


    chown -R opendkim:opendkim /run/opendkim


    echo "starting OpenDKIM"

    /usr/sbin/opendkim \
        -f \
        -x /etc/opendkim.conf &

fi



# -------------------------
# OpenDMARC receiver
# -------------------------

if [ "${ROLE}" = "receiver" ]; then

    mkdir -p /run/opendmarc


    cat > /etc/opendmarc.conf <<EOF
AuthservID mail.receiver.test
Socket local:/run/opendmarc/opendmarc.sock
PidFile /run/opendmarc/opendmarc.pid
Syslog true
SoftwareHeader true
SPFIgnoreResults true
SPFSelfValidate true
RejectFailures false
EOF


    chown -R opendmarc:opendmarc /run/opendmarc


    echo "starting OpenDMARC"

    /usr/sbin/opendmarc \
        -f \
        -c /etc/opendmarc.conf &

fi



echo "initializing postfix"

newaliases || true

postfix set-permissions || true


echo "starting postfix"

exec postfix start-fg