#!/bin/sh
set -eu

SHARD_COUNT="${SHARD_COUNT:-10}"

i=0

while [ "$i" -lt "$SHARD_COUNT" ]; do

  config="/run/sshd/shard-${i}.conf"
  pidfile="/run/sshd/shard-${i}.child.pid"

  #
  # config
  #

  [ -f "$config" ] || exit 1

  /usr/sbin/sshd \
    -t \
    -f "$config"

  #
  # process
  #

  [ -f "$pidfile" ] || exit 1

  pid="$(cat "$pidfile")"

  kill -0 "$pid" 2>/dev/null \
    || exit 1

  i=$((i + 1))
done

exit 0