#!/bin/sh
set -eu

/usr/sbin/sshd -t -f /etc/ssh/sshd_config
pgrep -x sshd >/dev/null
