
## テスト

### pop3

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

```
podman exec -it dovecot doveadm auth test test@example.com test
passdb: test@example.com auth succeeded
extra fields:
  user=test@example.com
#
```

```
# podman exec -it dovecot doveadm auth test test test
passdb: test auth succeeded
extra fields:
  user=test@mail.test
  original_user=test
#
```

```
doveadm mailbox status -u test@example.com messages INBOX
```

```
doveadm mailbox status -u test messages INBOX
```

```
# podman exec -it dovecot /bin/bash
# doveadm exec dovecot-lda -d test << EOF
Subject: Test Mail Subject
From: sender@example.com

Body
EOF
#
```

```
# podman exec -it postfix /bin/bash
# echo "Test mail body" | mail -s "Test Subject" -r sender@mail.test test@mail.test
```