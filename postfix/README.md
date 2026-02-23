# テスト用 postfix コンテナ

## 仕様

* リレーしない
  * 「virtual_mailbox_domains」にリストされていないドメインはエラー
    * `Recipient address rejected: mail for external network is not deliverable`
* virtual_mailbox_domains 宛ては dovecot へ配信
  * 全ての宛先について1アカウント(`receiver@mail.test`)に集約して配信 (virtual ファイルで設定)
* myhostname 宛てはローカル配信

## 設定

### dovecot のホスト名、LMTP のポート番号

* postfix/etc/postfix/main.cf
  * virtual_transport

```
virtual_transport = lmtp:inet:dovecot:24
```

* コンテナへの環境変数 `VIRTUAL_TRANSPORT` で置き換え可能

### ドメイン関連

#### postfix のサーバ名とドメイン名

* postfix/etc/postfix/main.cf
  * myhostname
  * mydomain

```
myhostname = postfix.mail.test
mydomain = mail.test
```

#### 送信先ドメインとそれらへのメールを代表して受信するアカウントの設定

* postfix/etc/postfix/main.cf
  * virtual_mailbox_domains

```
virtual_mailbox_domains = mail.test, mail.example, example.com, example.net, example.org
```

* /etc/postfix/virtual

```
@mail.test      receiver@mail.test
@mail.example   receiver@mail.test
@example.com    receiver@mail.test
@example.net    receiver@mail.test
@example.org    receiver@mail.test
```
