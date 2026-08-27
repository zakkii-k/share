#!/bin/sh
set -eu

PORT_START="${PORT_START:-22001}"
PORT_END="${PORT_END:-22100}"

mkdir -p \
  /run/sshd \
  /config/clients \
  /config/state \
  /config/host_keys \
  /etc/sftp/authorized_keys \
  /etc/ssh/sshd_config.d \
  /data

if [ ! -s /config/host_keys/ssh_host_ed25519_key ]; then
  ssh-keygen -q -t ed25519 -N "" \
    -f /config/host_keys/ssh_host_ed25519_key
fi

if [ ! -s /config/host_keys/ssh_host_rsa_key ]; then
  ssh-keygen -q -t rsa -b 3072 -N "" \
    -f /config/host_keys/ssh_host_rsa_key
fi

chmod 600 /config/host_keys/ssh_host_*_key
chmod 644 /config/host_keys/ssh_host_*.pub

# 22001-22100 を最初からlistenする
: > /run/sftp-ports.conf

p="$PORT_START"
while [ "$p" -le "$PORT_END" ]; do
  echo "Port $p" >> /run/sftp-ports.conf
  p=$((p + 1))
done

# Include対象を先に作成
touch /etc/ssh/sshd_config.d/90-clients.conf

# JSONからユーザー設定を復元
/usr/local/bin/sftpctl apply-all

# sshd設定チェック
/usr/sbin/sshd -t -f /etc/ssh/sshd_config

# foregroundでsshd起動
exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config