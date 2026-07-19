FROM registry.access.redhat.com/ubi10/ubi-minimal:latest

COPY epel-release-latest-10.noarch.rpm /tmp/epel-release.rpm

RUN microdnf update -y && \
    rpm -Uvh /tmp/epel-release.rpm && \
    microdnf install -y \
        postfix \
        rsyslog \
        opendkim \
        opendkim-tools \
        opendmarc \
        python3 \
        pypolicyd-spf \
        python3-dns \
        bind-utils \
    && \
    microdnf clean all && \
    rm -f /tmp/epel-release.rpm


RUN mkdir -p \
        /etc/opendkim \
        /etc/opendmarc \
        /var/spool/postfix/public \
        /run/opendkim \
        /run/opendmarc


COPY postfix/main.cf.template /etc/postfix/main.cf.template
COPY postfix/master.cf /etc/postfix/master.cf

COPY opendkim/opendkim.conf.template /etc/opendkim.conf.template
COPY opendkim/TrustedHosts /etc/opendkim/TrustedHosts
COPY opendkim/KeyTable /etc/opendkim/KeyTable
COPY opendkim/SigningTable /etc/opendkim/SigningTable

COPY opendmarc/opendmarc.conf /etc/opendmarc.conf
COPY opendmarc/ignore.hosts /etc/opendmarc/ignore.hosts

COPY run.sh /usr/local/bin/run.sh

RUN chmod 0755 /usr/local/bin/run.sh


EXPOSE 25

ENV ROLE=receiver

ENTRYPOINT ["/usr/local/bin/run.sh"]