#!/bin/bash -x

# タイムゾーンの設定
ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
export TZ=JST-9

# dovecot 用の設定
groupadd -g 1000 vmail
useradd -u 1000 -g vmail --home-dir /var/mail --shell /usr/sbin/nologin vmail

# dovecot をフォアグラウンドで起動する
exec /usr/sbin/dovecot -F