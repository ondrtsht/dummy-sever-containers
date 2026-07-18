FROM registry.access.redhat.com/ubi10/ubi-minimal:latest
# ubi-minimal: 最低限のパッケージのみ導入された環境とするため
# latest: 本番環境では再現性を確保するため特定のマイナーバージョンを指定すること

# ロケールは ja_JP.UTF-8
 # タイムゾーンは Asia/Tokyo
RUN microdnf update -y && \
    microdnf install -y glibc-locale-source && \
    localedef -i ja_JP -f UTF-8 -A /usr/share/locale/locale.alias ja_JP.UTF-8 && \
    microdnf remove -y glibc-locale-source gzip && \
    microdnf install -y tzdata && \
    ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime && \
    microdnf install -y postfix && \
    microdnf clean all
ENV LANG=ja_JP.UTF-8
ENV TZ=Asia/Tokyo

COPY --chown=root:root config/current/etc/postfix/ /etc/postfix/
RUN chmod 755 /etc/postfix && \
    find /etc/postfix -type f -exec chmod 644 {} \; && \
    postalias lmdb:/etc/aliases

CMD ["postfix", "start-fg"]