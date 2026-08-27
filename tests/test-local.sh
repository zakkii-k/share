#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

KEY="${KEY:-./client001_key}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-22001}"

if [ ! -f "$KEY" ]; then
  ssh-keygen -q -t ed25519 -N "" -f "$KEY"
fi

PUB="$(cat "$KEY.pub")"

cat > clients/client001.json <<EOF
{
  "user": "client001",
  "enabled": true,
  "port": $PORT,
  "max_file_mb": 10,
  "allowed_ips": [
    "127.0.0.1/32"
  ],
  "public_keys": [
    "$PUB"
  ]
}
EOF

docker exec openssh-sftp sftpctl apply client001

dd if=/dev/zero of=/tmp/sftp-9m.bin bs=1M count=9 status=none
dd if=/dev/zero of=/tmp/sftp-11m.bin bs=1M count=11 status=none

cat >/tmp/sftp-ok.batch <<EOF
put /tmp/sftp-9m.bin /incoming/ok.bin.part
rename /incoming/ok.bin.part /incoming/ok.bin.ready
ls -l /incoming
bye
EOF

sftp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o IdentitiesOnly=yes \
  -P "$PORT" \
  -i "$KEY" \
  -b /tmp/sftp-ok.batch \
  "client001@$HOST"

echo
echo "Expected: oversized upload fails."

cat >/tmp/sftp-too-big.batch <<EOF
put /tmp/sftp-11m.bin /incoming/too-big.bin
bye
EOF

if sftp \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o IdentitiesOnly=yes \
  -P "$PORT" \
  -i "$KEY" \
  -b /tmp/sftp-too-big.batch \
  "client001@$HOST"
then
  echo "ERROR: oversized upload unexpectedly succeeded" >&2
  exit 1
else
  echo "PASS: oversized upload rejected"
fi

echo
echo "Expected: arbitrary SSH command fails."

if ssh \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o IdentitiesOnly=yes \
  -p "$PORT" \
  -i "$KEY" \
  "client001@$HOST" 'id'
then
  echo "ERROR: arbitrary SSH command unexpectedly succeeded" >&2
  exit 1
else
  echo "PASS: arbitrary SSH command blocked"
fi

echo
echo "Configuration status:"
docker exec openssh-sftp sftpctl status client001
