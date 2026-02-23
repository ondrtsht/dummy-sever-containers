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

## 動作確認用コマンドメモ

### dovecot への連携確認

* 正常系

```
podman exec -it postfix /bin/bash
echo "Test mail body" | mail -s "Test Subject" -r sender@mail.test aaa@mail.test
echo "Test mail body" | mail -s "Test Subject" -r sender@mail.test bbb@mail.example
echo "Test mail body" | mail -s "Test Subject" -r sender@mail.test ccc@example.com
echo "Test mail body" | mail -s "Test Subject" -r sender@mail.test ddd@example.net
echo "Test mail body" | mail -s "Test Subject" -r sender@mail.test eee@example.org
```

* エラーケース:  `unknown user`

```
echo "Test mail body" | mail -s "Test Subject" -r sender@mail.test fff@postfix.mail.test
```

* エラーケース:  `mail for external network is not deliverable`

```
echo "Test mail body" | mail -s "Test Subject" -r sender@mail.test ggg@subdomain.mail.test
```
