

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


