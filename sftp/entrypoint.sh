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
  ssh-keygen -q -t ed25519 -N "" -f /config/host_keys/ssh_host_ed25519_key
fi

if [ ! -s /config/host_keys/ssh_host_rsa_key ]; then
  ssh-keygen -q -t rsa -b 3072 -N "" -f /config/host_keys/ssh_host_rsa_key
fi

chmod 600 /config/host_keys/ssh_host_*_key
chmod 644 /config/host_keys/ssh_host_*.pub

# Pre-listen all expected client ports. Client onboarding therefore does not
# change Docker's published port set and does not restart the container.
: > /run/sftp-ports.conf

p="$PORT_START"
while [ "$p" -le "$PORT_END" ]; do
  echo "Port $p" >> /run/sftp-ports.conf
  p=$((p + 1))
done

# The include file must exist before validation.
touch /etc/ssh/sshd_config.d/90-clients.conf

# Rebuild all container-local users/runtime configuration from JSON.
# sshd is not running yet, so sftpctl will skip SIGHUP.
sftpctl apply-all

/usr/sbin/sshd -t -f /etc/ssh/sshd_config

exec /usr/sbin/sshd -D -e -f /etc/ssh/sshd_config
