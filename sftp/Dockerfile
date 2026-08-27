FROM debian:13-slim

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       openssh-server \
       libpam-modules \
       jq \
       procps \
       ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p \
      /run/sshd \
      /config/clients \
      /config/state \
      /config/host_keys \
      /etc/sftp/authorized_keys \
      /etc/ssh/sshd_config.d \
      /data \
    && groupadd --system sftp-clients

COPY sshd_config /etc/ssh/sshd_config
COPY pam-sshd /etc/pam.d/sshd
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY sftpctl /usr/local/bin/sftpctl
COPY healthcheck.sh /usr/local/bin/healthcheck.sh

RUN chmod 0755 \
    /usr/local/bin/entrypoint.sh \
    /usr/local/bin/sftpctl \
    /usr/local/bin/healthcheck.sh

EXPOSE 22001-22100

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
