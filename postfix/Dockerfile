FROM rockylinux/rockylinux:8.10
RUN dnf -y install procps-ng iproute nmap-ncat bind-utils
RUN dnf -y install postfix mailx
COPY etc/postfix /etc/postfix
COPY entrypoint.sh /
RUN chmod 744 /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
# ローカルでの確認用コマンドメモ
# podman network create test-net
# podman network ls --format "{{.Name}}: {{range .Subnets}}{{.Subnet}} {{end}}"
# リストされたネットワークを main.cf の mynetworks に加える
# POSTFIX_CONTAINER_HOME=~/git/dummy-sever-containers/postfix
# cd ${POSTFIX_CONTAINER_HOME} && podman rmi -f postfix && podman build -t postfix .
# cd ${POSTFIX_CONTAINER_HOME} && podman build -t postfix .
# podman rm -f postfix && podman run --network test-net -d -p 25:25 -p 587:587 -v ${POSTFIX_CONTAINER_HOME}/mnt:/mnt --name postfix postfix && podman logs -f postfix
# podman exec -it postfix /bin/bash
