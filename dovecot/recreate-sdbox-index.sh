#!/bin/bash
# インデックスの再構築
for domain_dir in /var/dovecot/*; do
    domain=$(basename "$domain_dir")
    for user_dir in "$domain_dir"/*; do
        user=$(basename "$user_dir")
        echo "Indexing: $user@$domain"
        # 全フォルダ ("*") のインデックスを再構築
        doveadm index -u "$user@$domain" "*"
    done
done