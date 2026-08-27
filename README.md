# OpenSSH SFTP reference — shell-only management

Comparison implementation for SFTPGo.

This version intentionally does **not** run a Python server, API server, watcher,
or reconciliation daemon.

Client onboarding is explicit:

```bash
docker exec openssh-sftp sftpctl apply client001
```

The authoritative configuration is one JSON file per client.

## Requirements implemented

- Debian slim
- OpenSSH
- `internal-sftp`
- SSH shell prohibited
- selected SFTP operations denied
- one port per client
- one-file upload limit per client via PAM `pam_limits` / `RLIMIT_FSIZE`
- per-client chroot
- public-key authentication only
- per-client source IP allow-list
- no host OS users; users are created only inside the container
- one JSON file per client
- no Docker restart for add/update/disable
- `sshd -t` before reload
- SIGHUP reload instead of container restart
- approximately 100 clients in one SFTP container

## Files

```text
.
├── docker-compose.yml
├── clients/
│   └── client001.example.json
├── sftp/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── healthcheck.sh
│   ├── pam-sshd
│   ├── sftpctl
│   └── sshd_config
└── tests/
    └── test-local.sh
```

## Client JSON

`clients/client001.json`:

```json
{
  "user": "client001",
  "enabled": true,
  "port": 22001,
  "max_file_mb": 350,
  "allowed_ips": [
    "203.0.113.10/32"
  ],
  "public_keys": [
    "ssh-ed25519 AAAAC3... client001"
  ]
}
```

Fields:

- `user`: container-local Linux username
- `enabled`: connection enabled/disabled
- `port`: dedicated SFTP port
- `max_file_mb`: per-file write limit in MiB
- `allowed_ips`: source IP/CIDR allow-list
- `public_keys`: allowed public keys

`allowed_ips` must not be empty.

If allow-all is intentional:

```json
{
  "allowed_ips": [
    "0.0.0.0/0",
    "::/0"
  ]
}
```

## Start

```bash
docker compose build
docker compose up -d
```

The container listens on the complete configured range from startup:

```text
22001-22100
```

Therefore normal client onboarding does not require adding a new Docker port
mapping or restarting the container.

## Add a client

1. Put a JSON file in `clients/`.
2. Apply it.

```bash
docker exec openssh-sftp sftpctl apply client001
```

or:

```bash
docker exec openssh-sftp \
  sftpctl apply-file /config/clients/client001.json
```

The command performs:

```text
validate JSON
  ↓
create/reuse container-local Linux user
  ↓
create chroot
  ↓
write public keys + source-IP restriction
  ↓
write PAM file-size limit
  ↓
generate user/port sshd rule
  ↓
sshd -t
  ↓
atomic install
  ↓
SIGHUP sshd
```

No Docker restart is used.

## Apply all JSON files

Useful after container recreation:

```bash
docker exec openssh-sftp sftpctl apply-all
```

The entrypoint also runs `apply-all` before starting sshd.

The JSON files are therefore the source of truth.

## Disable a client

Edit:

```json
"enabled": false
```

then:

```bash
docker exec openssh-sftp sftpctl apply client001
```

The user's authorized key and allowed-port rule are removed.
Client data is not deleted.

## Re-enable

Set:

```json
"enabled": true
```

and run `apply` again.

## Change maximum file size

Edit:

```json
"max_file_mb": 500
```

then:

```bash
docker exec openssh-sftp sftpctl apply client001
```

The PAM limit is read when a new SSH/SFTP session starts, so the Docker
container does not need to restart.

## Change source IP

Edit:

```json
"allowed_ips": [
  "203.0.113.20/32",
  "198.51.100.0/24"
]
```

then run `apply`.

The generated authorized-key line uses OpenSSH `from=`:

```text
restrict,from="203.0.113.20/32,198.51.100.0/24" ssh-ed25519 ...
```

Be aware of NAT, reverse proxies, firewalls and load balancers. The address
checked by sshd is the source address it actually sees.

## Dedicated client ports and default deny

The base config has a common managed-client rule:

```text
Match Group sftp-clients
    RefuseConnection yes
    ...
```

For an enabled client, `sftpctl` generates:

```text
Match User client001 LocalPort 22001
    RefuseConnection no
Match all
```

OpenSSH uses the first obtained value for a keyword across matching `Match`
blocks.

Therefore:

```text
client001 + port 22001
    -> RefuseConnection no
    -> allowed, with common SFTP restrictions

client001 + port 22002
    -> no allow block
    -> common RefuseConnection yes
    -> rejected
```

## SSH is prohibited

The managed SFTP group gets:

```text
ForceCommand internal-sftp ...
DisableForwarding yes
PermitTTY no
```

An SSH client may establish the transport/authentication layer because SFTP
itself uses SSH, but it cannot obtain an interactive shell or execute an
arbitrary SSH command.

## Chroot

Physical filesystem:

```text
/data/client001/
└── incoming/
```

Ownership:

```text
/data/client001
    root:root 0755

/data/client001/incoming
    client001:sftp-clients 0700
```

The client sees:

```text
/
└── incoming/
```

and cannot traverse to `/data/client002`, `/etc`, etc.

## SFTP command restrictions

The static server policy is:

```text
-P remove,rmdir,mkdir,symlink,link,setstat,fsetstat,lsetstat,copy-data
```

`rename` is deliberately left enabled so clients can use:

```text
put file.csv -> /incoming/file.csv.part
rename        -> /incoming/file.csv.ready
```

That is the recommended completion protocol for the downstream transform
engine.

If your client software requires other SFTP requests, test them before
tightening the list.

You can query supported request names:

```bash
docker exec openssh-sftp \
  /usr/lib/openssh/sftp-server -Q requests
```

## File-size limit

A JSON value:

```json
"max_file_mb": 350
```

generates:

```text
client001 - fsize 358400
```

`pam_limits` defines `fsize` in KB.

This is a Linux resource limit, not an SFTP application-level preflight check.

If the limit is 350 MiB and a client uploads a 500 MiB file:

```text
write...
write...
~350 MiB
  ↓
kernel refuses further growth
  ↓
SFTP transfer fails
```

A partial file may remain.

This is one of the main behavioral differences to compare with SFTPGo.

## Downstream transformation

This project deliberately does not provide an API or Python server.

Recommended separation:

```text
SFTP container
    |
    | sftp_data volume
    v
received files
    |
    v
your existing transform engine / batch / cron / command
```

The transform engine should not run as the SFTP client Linux user, so it does
not inherit that client's `RLIMIT_FSIZE`.

### Recommended completion convention

Client:

```text
upload file.csv.part
rename file.csv.part -> file.csv.ready
```

Downstream command/batch:

```bash
find <mounted-sftp-data> -type f -name '*.ready' ...
```

Then claim/move the file before processing so two workers cannot process it
twice.

A simple periodic batch/cron is safer and simpler than trying to hook
`internal-sftp` directly.

## Host OS users

No client users are created on the host OS.

They exist only in the Docker container:

```text
host
└── Docker container
    ├── client001
    ├── client002
    └── ...
```

## Test locally

Generate a key:

```bash
ssh-keygen -t ed25519 -f ./client001_key -N ''
```

Run:

```bash
KEY=./client001_key ./tests/test-local.sh
```

The script checks:

- valid upload succeeds
- oversized upload fails
- arbitrary SSH command fails
- dedicated SFTP port works

## Operational recommendation

For about 100 clients, use one SFTP container rather than one container per
client.

The client JSON files remain the source of truth:

```text
clients/
├── client001.json
├── client002.json
├── client003.json
└── ...
```

Normal onboarding:

```text
customer application
  ↓
create clientNNN.json
  ↓
docker exec openssh-sftp sftpctl apply clientNNN
  ↓
available
```

No API is required.

## Security notes

- Use a different key pair for each client.
- Store only public keys on the SFTP server.
- Do not mount the Docker socket into the SFTP container.
- Keep passwords and keyboard-interactive authentication disabled.
- Keep `DisableForwarding yes`.
- Keep the chroot root owned by root and not writable by the client.
- Treat every uploaded file as untrusted input.
- If exposing 100 ports externally, also consider firewall rules.
- `RLIMIT_FSIZE` may leave partial files.
- Use `.part -> .ready` if possible so failed/incomplete uploads are not picked
  up by the transform batch.
