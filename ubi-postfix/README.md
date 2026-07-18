
# コンテナ関連

## リファレンス

[Red Hat Enterprise Linux > 10 > Deploying mail servers](https://docs.redhat.com/ja/documentation/red_hat_enterprise_linux/10/html/deploying_mail_servers/index)

[Red Hat Enterprise Linux > 10 > ネットワークのセキュリティー保護 > 8.8. Postfix サービスのセキュリティー保護](https://docs.redhat.com/ja/documentation/red_hat_enterprise_linux/10/html-single/securing_networks/index#securing-the-postfix-service)

[Red Hat Enterprise Linux > 10 > Monitoring and managing system status and performance > 第7章 Performance Co-Pilot によるパフォーマンスの監視 > 7.1. pmda-postfix での postfix の監視](https://docs.redhat.com/ja/documentation/red_hat_enterprise_linux/10/html/monitoring_and_managing_system_status_and_performance/monitoring-performance-with-performance-co-pilot#monitoring-postfix-with-pmda-postfix)

   - UBI イメージでは pcp-system-tools は利用できない。procps-ng は利用可能

[ナレッジベース > Universal Base Images (UBI): Images, repositories, packages, and source code](https://access.redhat.com/articles/4238681)

## イメージのビルド

```sh
podman build -t ubi10-postfix:0.0.1 .
```

## 実行

```sh
sudo sysctl net.ipv4.ip_unprivileged_port_start=25
podman run -d \
  --name postfix \
  -p 25:25 \
  --cap-drop=all \
  --cap-add=setuid,setgid,dac_override,net_bind_service \
  --replace \
  ubi10-postfix:0.0.1
```

| Capability 名 | 概要・役割 | Postfix が使用する理由 | 表記上のリスク | 💡 今回の設定で安全（問題ない）と言える理由 |
| :--- | :--- | :--- | :--- | :--- |
| **`CAP_NET_BIND_SERVICE`** | 1024番未満の特権ポートを開く | 外部からのメールを受信するために、**SMTP（25番ポート）で待受ける** | 偽のサービス（悪意あるWebサーバー等）を起動されるリスク。 | **ポートが固定されているため安全**<br>コンテナ側で別のポート（例: 80番）を勝手に開けても、ホスト側が `-p` でポート転送を追加しない限り、外部からは一切アクセスできません。 |
| **`CAP_SETUID`** | プロセスのユーザーID（UID）を変更する | マスタープロセス（root）から、安全な**一般ユーザー（postfix等）へ権限を放棄する** | コンテナ内で一般ユーザーから root へ特権昇格されるリスク。 | **昇格しても「名前だけの root」になるため安全**<br>`--cap-drop=all` によって、rootが持つ危険な特権はすべて事前に剥奪されています。仮にrootを奪われても、ホストの破壊や脱獄はできません。 |
| **`CAP_SETGID`** | プロセスのグループID（GID）を変更する | メールをキューに保存する際、一時的に**専用グループ（postdrop等）に切り替える** | 他のグループが所有するファイルへの不正アクセスリスク。 | **影響がコンテナ内限定のため安全**<br>コンテナ内にある他のグループのファイルを見られたとしても、ホスト側の重要ファイル（`/etc/shadow` など）へアクセスを広げる手段にはなり得ません。 |
| **`CAP_DAC_OVERRIDE`** | ファイルのアクセス権限チェックを無視する | コンテナ起動時に root 所有でマウントされた**各ディレクトリを強制的にチェック・初期化する** | コンテナ内の全設定ファイルやプログラムの書き換え・改ざんリスク。 | **ホストとファイルシステムを共有していないため安全**<br>ホスト側の重要ディレクトリをマウント（共有）していないため、コンテナ内のファイル権限がいくら無視されても、影響は使い捨てのコンテナ内部に限定されます。 |


# Postfix 関連

## リファレンス

### 📋 Postfix 堅牢化設定・公的ガイドライン対応表


| 設定項目 (main.cf) | デフォルト値（標準） | 今回の推奨値（堅牢化） | 変更する目的と効果 | 準拠する主なガイドライン |
| :--- | :--- | :--- | :--- | :--- |
| **`mynetworks`** | `subnet`<br>（同じネットワークの他端末も許可） | **`127.0.0.0/8 [::1]/128`** | 信頼する送信元をサーバー自身（localhost）のみに限定し、第三者中継を完全に防ぐ。 | **【IPA】** 不正中継防止<br>**【NIST】** リレー制限 |
| **`smtpd_relay_restrictions`** | `permit_mynetworks`<br>`permit_sasl_authenticated`<br>`defer_unauth_destination` | **`permit_mynetworks`<br>`reject`** | 自分自身（mynetworks）からの送信以外は、認証の有無に関わらずすべて拒否（reject）する。 | **【IPA】** 不正中継防止 |
| **`smtpd_recipient_restrictions`** | （空欄または未設定） | **`permit_mynetworks`<br>`reject_unauth_destination`** | 宛先アドレスの検証を厳格化し、不正な配送要求を入り口で遮断する。 | **【IPA】** 不正送信の踏み台化防止 |
| **`smtpd_tls_security_level`**<br>**`smtp_tls_security_level`** | `none` または `may`<br>（暗号化は任意・成り行き） | **`encrypt`** | 送受信ともに平文（暗号化なし）の通信を一切禁止し、TLSによる暗号化を強制する。 | **【NISC】** 暗号化通信の必須化<br>**【NIST】** 機密性の確保 |
| **`smtpd_tls_protocols`**<br>**`smtpd_tls_mandatory_protocols`** | `medium` 以上の互換設定<br>（古いTLSも許可される場合あり） | **`!SSLv2, !SSLv3,`<br>`!TLSv1, !TLSv1.1`** | SSLv2/v3、TLSv1.0/1.1 などの脆弱な古いプロトコルを無効化し、TLS 1.2 以上に制限する。 | **【NISC】** 「TLS 1.2 以上を原則とする」<br>**【NIST】** 脆弱な方式の排除 |
| **`smtpd_tls_mandatory_ciphers`**<br>**`tls_high_cipherlist`** | `medium`<br>（中程度の暗号も許可） | **`high`**<br>（強固な暗号リストを定義） | 安全性の高い暗号スイート（AES等）のみを許可し、DESやRC4などの古い暗号を排除する。 | **【NISC / NIST】** 政府基準の暗号アルゴリズム選定 |
| **`smtpd_banner`** | `$myhostname ESMTP $mail_name` | **`$myhostname ESMTP`** | 応答メッセージから「Postfix」というソフトウェア名やバージョン情報を削除し、隠蔽する。 | **【NIST】** 偵察行為（情報漏洩）の防止 |
| **`disable_vrfy_command`** | `no`<br>（アカウント確認を許可） | **`yes`** | アカウントの存在を外部から確認・探索できる `VRFY` コマンドを無効化（禁止）する。 | **【IPA】** ユーザー情報の隠蔽<br>**【NIST】** アカウント収集の防止 |
| **`smtpd_hard_error_limit`** | `20` | **`5`** | 存在しないアドレス宛ての連続送信（辞書攻撃など）が発生した際、より早い段階で接続を切断する。 | **【NIST】** DoS攻撃・サービス妨害への対策 |
| **`smtpd_helo_required`** | `no`<br>（挨拶コマンドなしでも送信可） | **`yes`** | 送信前の `HELO/EHLO` コマンドを必須化し、ルールを無視して送りつける自動ボットを排除する。 | **【NIST】** リソース枯渇・DoS対策 |
| **`message_size_limit`** | `10240000`<br>（約 10 MB） | **`2048000`**<br>（テスト用に制限強化、約 2 MB） | 受信可能な最大メッセージサイズを明示的に制限し、巨大なメールによるストレージ逼迫やDoS攻撃を防ぐ。 | **【RHEL 10】** リソース制限によるセキュリティー保護 |
| **`smtpd_client_connection_count_limit`** | `50` | **`5`** | 単一のクライアントIPから同時に確立できるSMTP接続数を制限し、リソースの独占やDoSを防止する。 | **【RHEL 10】** / **【NIST】** 同時接続によるサービス拒否対策 |
| **`default_process_limit`** | `100` | **`10`** | Postfixが同時に起動できるデーモン（プロセス）の総数を絞り、メモリリソースの枯渇を防ぐ。 | **【RHEL 10】** プロセス数制限によるシステム保護 |
| **`queue_directory`** | `/var/spool/postfix` | **`/var/spool/postfix`**<br>（ローカルディスクに配置） | メールキューおよびスプールは、NFS等の共有ボリュームではなく、必ず**ローカルのセキュアなストレージ**に配置する。 | **【RHEL 10】** ファイル共有による漏洩・破損リスクの排除 |

### 📖 参照ガイドラインの補足情報

表内で引用・準拠している各公的機関のガイドラインの詳細は以下の通りです。

#### 1. IPA（独立行政法人 情報処理推進機構）
* **ガイドライン名**: 『安全なウェブサイトの作り方』（および関連するメールセキュリティ解説）
* **発行機関**: 独立行政法人 情報処理推進機構（日本）
* **本設定における位置づけ**:
  * 主に**「第三者中継（オープンリレー）の禁止」**と**「ユーザー情報の隠蔽」**の根拠としています。
  * 悪意ある第三者がサーバーを「迷惑メールの踏み台」として悪用するリスクを排除するため、`mynetworks` や `smtpd_relay_restrictions` を用いた送信元の厳格な制限を強く求めています。

#### 2. NISC（内閣サイバーセキュリティセンター / 現・国家サイバー統括室）
* **ガイドライン名**: 『政府機関等のサイバーセキュリティ対策のための統一基準群』
* **発行機関**: 内閣官房（日本）
* **本設定における位置づけ**:
  * 主に**「通信の暗号化（TLS 1.2以上）の強制」**の根拠としています。
  * 政府機関や重要インフラにおいて最低限満たすべき「情報セキュリティのベースライン」であり、通信経路におけるデータの盗聴・改ざんを防ぐため、脆弱な暗号化プロトコル（SSLv2/v3、TLSv1.0/1.1）の完全な無効化を義務付けています。

#### 3. NIST（米国国立標準技術研究所）
* **ガイドライン名**: 『NIST SP 800-45 Version 2 : Guidelines on Electronic Mail Security』
* **発行機関**: 米国国立標準技術研究所（米国政府機関）
* **本設定における位置づけ**:
  * 主に**「偵察行為の防止（情報隠蔽）」**と**「DoS攻撃（サービス妨害）への耐性向上」**の根拠としています。
  * 世界的なITセキュリティのデファクトスタンダードであり、SMTPバナー（`smtpd_banner`）からバージョン情報を消して攻撃者の標的になるのを防ぐことや、連続エラー時の切断（`smtpd_hard_error_limit`）によってサーバーのリソース枯渇を防ぐ設計を推奨しています。

#### 4. Red Hat Enterprise Linux 10（RHEL 10）
* **ガイドライン名**: 『Red Hat Enterprise Linux 10 「Securing networks」 - 8.8. Securing the Postfix service』
* **発行機関**: Red Hat, Inc.
* **本設定における位置づけ**:
  * 主に**「システムリソースの制限によるサービス拒否（DoS）攻撃の緩和」**および**「データ配置の安全性確保」**の根拠としています。
  * メッセージサイズや同時接続数、同時プロセス数を制限することで、悪意ある送信やテスト中のバグによるシステムハングアップを防止します。
  * メールデータがネットワーク上に平文で流れるリスクやファイルロックの競合を防ぐため、NFS等のネットワーク共有ではなく、ローカルファイルシステムへのスプール配置（`queue_directory`）を必須としています。

## テスト

```sh
(
  sleep 1; printf "HELO localhost\r\n"; sleep 1;
  printf "MAIL FROM:<test@example.com>\r\n"; sleep 1;
  printf "RCPT TO:<root@localhost>\r\n"; sleep 1;
  printf "DATA\r\n"; sleep 1;
  printf "Subject: Perfect Log Test\r\n\r\nThis is a beautiful test.\r\n.\r\n"; sleep 1;
  printf "QUIT\r\n"
) | nc -w 10 localhost 25

podman exec -it postfix cat /var/mail/root
```