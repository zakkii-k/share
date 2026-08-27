#!/bin/sh
set -eu

SHARD_COUNT="${SHARD_COUNT:-10}"

mkdir -p \
  /run/sshd \
  /config/clients \
  /config/state \
  /config/host_keys \
  /etc/sftp/authorized_keys \
  /etc/security/limits.d \
  /data

#
# Host key
#

if [ ! -s /config/host_keys/ssh_host_ed25519_key ]; then
  ssh-keygen \
    -q \
    -t ed25519 \
    -N "" \
    -f /config/host_keys/ssh_host_ed25519_key
fi

if [ ! -s /config/host_keys/ssh_host_rsa_key ]; then
  ssh-keygen \
    -q \
    -t rsa \
    -b 3072 \
    -N "" \
    -f /config/host_keys/ssh_host_rsa_key
fi

chmod 600 /config/host_keys/ssh_host_*_key
chmod 644 /config/host_keys/ssh_host_*.pub

#
# JSON → user / PAM / authorized_keys / sshd configs
#

/usr/local/bin/sftpctl apply-all

#
# 10個のsshdを起動
#

i=0

while [ "$i" -lt "$SHARD_COUNT" ]; do

  CONFIG="/run/sshd/shard-${i}.conf"
  PIDFILE="/run/sshd/shard-${i}.child.pid"

  echo "starting sshd shard=${i}"

  /usr/sbin/sshd \
    -D \
    -e \
    -f "$CONFIG" &

  pid=$!

  echo "$pid" > "$PIDFILE"

  i=$((i + 1))
done

#
# コンテナ停止時に全sshdを終了
#

shutdown() {
  echo "stopping sshd shards"

  for f in /run/sshd/shard-*.child.pid; do
    [ -e "$f" ] || continue

    pid="$(cat "$f")"

    kill -TERM "$pid" 2>/dev/null || true
  done

  wait || true
  exit 0
}

trap shutdown TERM INT

#
# 簡易supervisor
#
# sshdのどれかが死んだらコンテナも落とす。
# Docker restart policyで再構築する。
#

while :; do

  for f in /run/sshd/shard-*.child.pid; do
    [ -e "$f" ] || continue

    pid="$(cat "$f")"

    if ! kill -0 "$pid" 2>/dev/null; then
      echo "ERROR: sshd process died: pid=$pid" >&2
      exit 1
    fi
  done

  sleep 5
done