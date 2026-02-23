FROM rockylinux/rockylinux:8.10
RUN dnf -y install procps-ng iproute nmap-ncat bind-utils
RUN dnf -y install dovecot fetchmail mailx
COPY etc/dovecot /etc/dovecot
COPY entrypoint.sh /
RUN chmod 744 /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
COPY recreate-sdbox-index.sh /
RUN chmod 755 /recreate-sdbox-index.sh
# ローカルでの確認用コマンドメモ
# podman network create test-net
# DOVECOT_CONTAINER_HOME=~/git/dummy-sever-containers/dovecot
# cd ${DOVECOT_CONTAINER_HOME} && podman rmi -f dovecot && podman build -t dovecot .
# cd ${DOVECOT_CONTAINER_HOME} && podman build -t dovecot .
# podman rm -f dovecot && podman run --network test-net -d -p 24:24 -p 110:110 -v ${DOVECOT_CONTAINER_HOME}/mnt:/mnt -e VMAIL_PASSWORD=zzz --name dovecot dovecot && podman logs -f dovecot
# podman exec -it dovecot /bin/bash