# cd ~/container/postfix && podman rmi -f rl8 && podman build -t rl8 . && podman run -d -p 25:25 -p 110:110 -v ~/container/postfix/mnt:/mnt --name rl8 rl8 && podman logs -f rl8
# podman run -itd --name rl8 rl8
# podman exec -it rl8 /bin/bash
FROM rockylinux/rockylinux:8.10
RUN dnf -y install rsyslog procps-ng iproute nmap-ncat
RUN dnf -y install postfix bind-utils mailx
RUN dnf -y install dovecot
# RUN dnf -y install python3-pip python36 platform-python-pip python3-setuptools
# RUN dnf -y install https://dl.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/s/supervisor-4.2.2-1.el8.noarch.rpm
COPY etc/postfix /etc/postfix
COPY etc/rsyslog.conf /etc
COPY etc/rsyslog.d /etc
COPY etc/dovecot /etc/dovecot
#COPY etc/supervisord.conf /etc/supervisord.conf
#COPY etc/supervisord.d /etc/supervisord.d
COPY entrypoint.sh /
RUN chmod 744 /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
