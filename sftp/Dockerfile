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
      /etc/security/limits.d \
      /data \
    && groupadd --system sftp-clients

COPY pam-sshd /etc/pam.d/sshd
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY sftpctl /usr/local/bin/sftpctl
COPY healthcheck.sh /usr/local/bin/healthcheck.sh

# CRLF事故もここで潰す
RUN sed -i 's/\r$//' \
      /usr/local/bin/entrypoint.sh \
      /usr/local/bin/sftpctl \
      /usr/local/bin/healthcheck.sh \
    && chmod 0755 \
      /usr/local/bin/entrypoint.sh \
      /usr/local/bin/sftpctl \
      /usr/local/bin/healthcheck.sh

EXPOSE 22001-22100

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]