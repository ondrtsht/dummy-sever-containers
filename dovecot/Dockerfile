# cd ~/container/dovecot && podman rmi -f dovecot && podman build -t dovecot . && podman run -d -p 24:24 -p 110:110 -v ~/container/dovecot/mnt:/mnt --name rl8 rl8 && podman logs -f dovecot
# podman run -itd --name rl8 rl8
# podman exec -it rl8 /bin/bash
FROM rockylinux/rockylinux:8.10
RUN dnf -y install procps-ng iproute nmap-ncat bind-utils
RUN dnf -y install dovecot fetchmail s-nail
COPY etc/dovecot /etc/dovecot
COPY entrypoint.sh /
RUN chmod 744 /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
