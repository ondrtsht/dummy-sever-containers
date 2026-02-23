# テスト用 dovecot コンテナ

## 仕様

* LMTP で連携されたすべてのメールアドレスを受け入れ
* 全ユーザー(メールアドレス)のパスワードは共通で環境変数 `VMAIL_PASSWORD` で設定
* パスワードは平文
* データはコンテナ内に保存
  * コンテナ停止時にマウントしたディスクにバックアップファイル(tar.gz)を保存し、ファイルがあれば開始時に展開して復元

## 設定

### コンテナの環境変数

* VMAIL_PASSWORD に共通のパスワードを設定する

## ドメイン関連

### ユーザーのドメイン名が未指定の場合のドメインを設定

* /etc/dovecot/conf.d/10-auth.conf
  * auth_default_realm 

```
auth_default_realm = mail.test
```

### ポストマスターのアドレスを設定

* /etc/dovecot/conf.d/15-lda.conf
  * postmaster_address 

```
postmaster_address = postmaster@mail.test
```

## 動作確認用コマンドメモ

### nc コマンドを使ったプロトコルレベルでの確認

```
# nc -v localhost 110
Ncat: Version 7.92 ( https://nmap.org/ncat )
Ncat: Connected to 127.0.0.1:110.
+OK Dovecot ready.
USER test@example.com
+OK
PASS test
+OK Logged in.
STAT
+OK 0 0
LIST
+OK 0 messages:
.
QUIT
+OK Logging out.
Ncat: 47 bytes sent, 88 bytes received in 45.49 seconds.
#
```

### doveadm auth コマンドを使った確認

`doveadm [GLOBAL OPTIONS] auth test [-a auth_socket_path] [-A sasl_mech] [-x auth_info] user [password]`
https://doc.dovecot.org/main/core/man/doveadm-auth.1.html#auth-test

* ドメインあり

```
podman exec -it dovecot doveadm auth test test@example.com test
passdb: test@example.com auth succeeded
extra fields:
  user=test@example.com
#
```

* ドメインなし (auth_default_realm の確認)

```
# podman exec -it dovecot doveadm auth test test test
passdb: test auth succeeded
extra fields:
  user=test@mail.test
  original_user=test
#
```

### doveadm exec dovecot-lda コマンドを使った内部からのメール配置

```
# podman exec -it dovecot /bin/bash
# doveadm exec dovecot-lda -d test << EOF
Subject: Test Mail Subject
From: sender@example.com

Body
EOF
#
```

### postfix からの連携確認

```
# podman exec -it postfix /bin/bash
# echo "Test mail body" | mail -s "Test Subject" -r sender@mail.test test@mail.test
```