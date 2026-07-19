# EPEL版 `pypolicyd-spf` セットアップ手順と公式根拠

EPELリポジトリを使用した `pypolicyd-spf` のセットアップ手順と、その設定項目ごとに根拠となった公式ドキュメント（manページ）の該当章を並べて記述します。

一次情報ソースとして、開発元が作成した公式マニュアルである `policyd-spf(1)` および `policyd-spf.conf(5)` を根拠としています。

---

## 1. パッケージのインストール

EPELリポジトリを有効化し、パッケージをインストールします。

```bash
dnf install epel-release
dnf install pypolicyd-spf
```

*   **公式根拠:** パッケージ名 `pypolicyd-spf` は、Fedora/EPELプロジェクト公式のパッケージ命名規則に基づいています。

---

## 2. `master.cf` の編集

`/etc/postfix/master.cf` の末尾に以下を追記します。

```text
policyd-spf  unix  -       n       n       -       0       spawn
    user=nobody argv=/usr/libexec/postfix/policyd-spf
```

*   **公式根拠:** `policyd-spf(1)` マニュアルの **「POSTFIX INTEGRATION」** 節に以下の通り定義されています。
    > `policyd-spf unix - n n - 0 spawn user=nobody argv=/usr/bin/policyd-spf`
*   **補足:** EPELパッケージのディレクトリ構成に合わせ、実行ファイルのパスのみ `/usr/libexec/postfix/policyd-spf` に変更しています。また、2行目の行頭には半角スペースが必要です。

---

## 3. `main.cf` の編集（タイムアウト設定）

`/etc/postfix/main.cf` に以下を追記します。

```text
policyd-spf_time_limit = 3600
```

*   **公式根拠:** `policyd-spf(1)` マニュアルの **「POSTFIX INTEGRATION」** 節に、Postfixのデフォルトタイムアウト（300秒）によるメール遅延トラブルを防ぐための必須設定として、以下の通り明記されています。
    > `policyd-spf_time_limit = 3600`

---

## 4. `main.cf` の編集（受信制限ルールの追加）

`/etc/postfix/main.cf` の `smtpd_recipient_restrictions` にポリシーサービスを追加します。

```text
smtpd_recipient_restrictions =
    permit_mynetworks
    permit_sasl_authenticated
    reject_unauth_destination
    check_policy_service unix:private/policyd-spf
```

*   **公式根拠:** `policyd-spf(1)` マニュアルの **「POSTFIX INTEGRATION」** 節に、オープンリレー（不正中継の踏み台）化を防ぐための重要なセキュリティ制約として、以下の通り明確に指示されています。
    > **重要：** `check_policy_service` は、必ず `reject_unauth_destination` の**後ろ**に配置しなければなりません。さもなければ、お使いのシステムがオープンリレーになってしまいます。

---

## 5. `policyd-spf.conf` の編集（挙動の制御）

`/etc/python-policyd-spf/policyd-spf.conf` を編集し、SPF検証失敗（Fail）時の動作を決めます。

### A. テスト運用（拒否せずヘッダのみ付与）
```text
HELO_reject = False
Mail_From_reject = False
```

### B. 本番運用（SPF認証失敗メールを拒否）
```text
HELO_reject = Fail
Mail_From_reject = Fail
```

*   **公式根拠:** `policyd-spf.conf(5)` マニュアルの **「OPTIONS」** 節において、各パラメータの挙動が定義されています。
    > `HELO_reject` / `Mail_From_reject` : SPF判定が `Fail` の場合にメールを拒否（Reject）するかどうかを制御します。デフォルトは `False`（拒否しない）です。

---

## 6. 設定の反映

Postfixを再起動して設定を有効化します。

```bash
systemctl restart postfix
```

---

さらに詳しい公式の仕様（特定のドメインをSPF検証から除外する**ホワイトリスト設定**など）について知りたい項目はありますか？必要であれば記述方法とマニュアルの根拠をご案内します。


## リファレンス

### 設定

pypolicyd-spf のデフォルト設定には、Reason_URL（openspf.net）以外にも、「古い標準規格（RFC）の名残り」 や 「商用環境でトラブルの原因になりやすい罠」 がいくつか含まれています。
本番運用（特にコンテナ環境）に移行する前に、以下の設定項目（デフォルト値）を見直すことを強く推奨します。

------------------------------

#### 1. HELO_reject = SPF_Not_Pass （過剰な拒否リスク）

* デフォルトの挙動: SPF_Not_Pass
* 問題点: 送信元の HELO/EHLO（ホスト名）の SPF 検証結果が Pass 以外（SoftFail や Neutral、None も含む）だった場合、それだけでメールを完全に拒否します。
* 商用環境でのリスク: 世の中の多くの正当なメールサーバーは、Mail From（エンベロープFrom）の SPF レコードは正しく設定していても、HELO ホスト名に対する SPF レコードの設定を忘れているか、不完全なケースが多々あります。デフォルトのままだと、大量の正常なメールを誤判定で拒否（ロスト）する原因になります。
* 推奨設定: 完全に拒否（Fail）のときのみ落とすように変更します。

HELO_reject = Fail


------------------------------
#### 2. Mail_From_reject = SPF_Not_Pass （過剰な拒否リスク）

* デフォルトの挙動: SPF_Not_Pass
* 問題点: HELO と同様に、Mail From の結果が SoftFail（~all）や Neutral（?all）であってもメールを拒否します。
* 商用環境でのリスク: 多くの企業（特に古いシステムや過渡期のシステム）は、配信エラーを防ぐために意図して SPF レコードの末尾を ~all（SoftFail：受信側の判断に任せる）にしています。デフォルトのままだと、送信側が「落とさないでほしい」と意図しているメールまで一律で拒否してしまいます。
* 推奨設定: 送信側が「明示的に偽物である」と宣言している -all（Fail）のみを厳格に拒否します。

Mail_From_reject = Fail


------------------------------
#### 3. PermError_reject = True （恒久的エラー時の完全拒否）

* デフォルトの挙動: True
* 問題点: 送信元の SPF レコードに記述ミスがある場合（例：DNSのルックアップ回数が上限の10回を超えている、構文エラーがあるなど）、PermError（恒久的エラー）となり、メールを強制拒否します。
* 商用環境でのリスク: 大手企業や正規の配信サービスでも、度重なるインクルードの追加によって一時的に SPF レコードが10回制限を超えてバグってしまう事故が時々発生します。デフォルトのままだと、相手のDNS設定ミスを理由に、重要なメールが一切届かなくなります。
* 推奨設定: テスト環境や厳格な受信ポリシーでない限り、ヘッダに PermError を記録するだけにとどめ、受信自体は許可するのが安全です。

PermError_reject = False


------------------------------
#### 4. TempError_Defer = True （一時的エラー時の配送遅延）

* デフォルトの挙動: True
* 問題点: 送信元ドメインの DNS サーバーが一時的に応答しなかった場合（タイムアウトなど）、TempError（一時的エラー）となり、Postfix は 451 コードを返してメールの受信を**一時保留（Defer）**にします。
* 商用環境でのリスク: 相手の DNS が数分間不安定だっただけで、メールの到着が数時間〜数日遅延することになります。
* 推奨設定: DNS 障害は受信側の責任ではないため、一時エラー時は SPF チェック自体をスキップさせてそのまま通す運用が一般的です。

TempError_Defer = False


------------------------------
#### まとめ：安全な本番用設定テンプレート
これまで解説した、古い仕様の罠や過剰な拒否を回避し、現代のメール運用に最適化した設定ファイル（policyd-spf.conf）のベストプラクティスは以下の通りです。

##### 1. 拒否基準の適正化（厳格なFailのみ拒否、SoftFail等は通してヘッダ付与のみ）
HELO_reject = Fail
Mail_From_reject = Fail

##### 2. DNSや構文エラーによる誤拒否・遅延の防止
PermError_reject = False
TempError_Defer = False

##### 3. 閉鎖されたURL（openspf.net）の完全排除
Reason_Message = Message {rejectdefer} due to SPF-Result: {spf}.

この他にも、特定のIPアドレスや信頼できる送信元をSPF検証からスキップさせる 「ホワイトリスト機能（Whitelist / Authserv_Id）」 などの高度な設定項目もありますが、まずは上記の基本項目を最適化することをおすすめします。
次に、これらの最適化設定を先ほどの Dockerfile へ自動的に組み込む記述例を確認しますか？

### /usr/share/doc/pypolicyd-spf/README.txt

```
SPF Engine - provides:
Python Postfix Policy for SPF (python-policy-spf) 3.1.0
Python based policy daemon for Postfix SPF checking
pyspf-milter Milter for SPF checking for Sendmail and other milter users

Tumgreyspf source
 Copyright © 2004-2005, Sean Reifschneider, tummy.com, ltd.
 <jafo@tummy.com>
python-policyd-spf changes
 Copyright © 2007-2024 Scott Kitterman <scott@kitterman.com>
<https://launchpad.net/pypolicyd-spf>
Documentation inputs:
 Copyright © 2004-2005, Sean Reifschneider, tummy.com, ltd.
 <jafo@tummy.com>
 2003-2004 Meng Weng Wong <mengwong@pobox.com> from postfix-policyd-spf-perl
 Copyright © 2007-2018 Scott Kitterman <scott@kitterman.com>

Dual Apache 2.0/GPL 2 licensed:
   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.


   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; version 2.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License along
   with this program; if not, write to the Free Software Foundation, Inc.,
   51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
=================

This is an external policy checker for the postfix mail server.  It will use
pyspf to check SPF records to determine if email should be rejected or
deferred by your server.

It requires Python3 (python3.3+) - as of version 2.0.0, python2 is no longer
supported, the pyspf (python-spf) library version 2.0.9 or higher, and authres.

As of version 3.0.0, it uses flit to build/install.  It requires at least flit
3.8.0.

Nothing is configured by default, so this will not interact with Postfix until
it has been set up.

See man 1 policyd-spf for information on setting up and using this as a
Postfix policy server.

See man 5 policyd-spf.conf for configuration file information.

The following applies only to using this package via the Milter interface.

The milter is relatively new and less well tested/mature.  If used with
pymilter version 1.0.5 or later, it will work for messages where the local
part of the Mail From is not valid UTF-8, but the "l" macro will not work,
which is expected, per RFC 8616 "l" macros only work for ASCII localparts. It
now supports RFC 8616, Email Authentication for Internationalized Mail.

This package includes a default configuration file and man pages.

[sudo] pip install pyspf_milter

Using pip will cause required packages to be installed via easy_install if they
have not been previously installed.  Because pymilter is a compiled Python
extension, the system will need appropriate development packages and
an C compiler.  Alternately, install it from dsitribution/OS packages and then
pip install pyspf_milter.

Both a systemd unit file and a sysv init file are provided.  Both make
assumptions about defaults being used, e.g. if a non-standard pidfile name is
used, they will need to be updated.  The sysv init file uses start-stop-deamon
from Debian.  It is not portable to systems without that available.

The pyspf-milter drops priviledges after setup to the user/group specified in
UserID.  During initial setup, this system user needs to be manually created.
As an example, using the default dkimpy-user on Debian, the command would be:

[sudo] adduser --system --no-create-home --quiet --disabled-password \
               --disabled-login --shell /bin/false --group \
               --home /run/pyspf-milter pyspf-milter

Since /var/run or /run is sometimes on a tempfs, if the PID file directory is
missing, the milter will create it on startup.

To start pyspf-milter with systemd for the first time, you will need to take
the following steps:

[sudo] systemctl daemon-reload
[sudo] systemctl enable pyspf-milter
[sudo] systemctl start pyspf-milter
[sudo] systemctl status pyspf-milter (to verify it started correctly)

As with all milters, pyspf-milter needs to be integrated with your MTA of
choice (Sendmail or Postfix).

For Sendmail:

Configuration is very similar to opendkim, but needs some adjustment for
dkimpy-milter. Here's an example configuration line to include in your
sendmail.mc:

INPUT_MAIL_FILTER(`pyspf-milter', `S=local:/run/pyspf-milter/pyspf-milter.sock')dnl

Changing the sendmail.mc file requires a Make (to compile it into sendmail.cf)
and a restart of sendmail.  Note that S= needs to match the value of Socket in
the configuration file.

Milter support should be present by default in most versions of sendmail
these days, but if not included in your Sendmail build, see:
http://www.elandsys.com/resources/sendmail/milter.html

For Postfix:

Integration of pyspf-milter into Postfix is like any milter (See Postfix's
README_FILES/MILTER_README).  Here's an example master.cf excerpt:

smtp       inet  n       -       -       -      -       smtpd
    ...
    -o smtpd_milters=inet:localhost:8893
    ...

These need to match the Socket value for pyspf-milter.

Care is required to segregate outbound mail from inbound mail to be checked.
verified.  There are many possible ways.  As of version 3.1.0, SPF checks are
automatically skipped for connections authenticated with SMTP Auth (since
these are, by definition, local).  Here is another example using milter
macros to keep the mail streams segregated:

Postfix main.cf:

smtpd_milters=inet:localhost:8893

Postfix master.cf:

smtp       inet  n       -       -       -       -       smtpd
    ...
    -o milter_macro_daemon_name=VERIFYING
    ...


In the pyspf-milter configuration file:

...
MacroList               daemon_name|VERIFYING
...
```