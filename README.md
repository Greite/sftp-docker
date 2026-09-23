<p align="center">
  <img src="logo.svg" alt="sftp-docker" width="128" height="128">
</p>

<h1 align="center">sftp-docker</h1>

<p align="center">
  SFTP-only OpenSSH server, one chroot per user, rebuilt automatically on Debian security updates.
</p>

<p align="center">
  <a href="https://github.com/Greite/sftp-docker/actions/workflows/build.yml"><img src="https://github.com/Greite/sftp-docker/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <a href="https://github.com/Greite/sftp-docker/pkgs/container/sftp-docker"><img src="https://img.shields.io/badge/ghcr.io-greite%2Fsftp--docker-blue?logo=docker" alt="ghcr.io/greite/sftp-docker"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT"></a>
</p>

---

Debian `trixie-slim` + `openssh-server`, nothing else: no fail2ban, no syslog, no iptables,
no custom code beyond a 30-line entrypoint. Brute-force protection comes from sshd itself
(`PerSourcePenalties`, OpenSSH ≥ 9.8).

`users.conf` follows the [atmoz/sftp](https://github.com/atmoz/sftp) format and the crypto
algorithms are pinned to the OpenSSH 9.9 defaults, so existing clients (including SSHFS-Win)
keep working.

## Image

```
ghcr.io/greite/sftp-docker:latest
ghcr.io/greite/sftp-docker:<yyyymmdd>          # previous builds, for rollback
ghcr.io/greite/sftp-docker:openssh-<version>
```

Platforms: `linux/amd64`, `linux/arm64`.

## Quick start

```bash
mkdir -p /srv/sftp/sshd
echo 'alice:changeme:1000:100' > /srv/sftp/sshd/users.conf

docker run -d --name sftp -p 2222:22 \
  --cap-drop ALL --cap-add SETUID --cap-add SETGID --cap-add SYS_CHROOT --cap-add CHOWN \
  --security-opt no-new-privileges \
  -v /srv/sftp:/config \
  -v /srv/share:/home/alice/share \
  ghcr.io/greite/sftp-docker:latest

sftp -P 2222 alice@localhost
```

## Configuration

Everything lives in `/config`:

| Path | Content |
|---|---|
| `sshd/users.conf` | one user per line: `user:pass[:e]:uid:gid` |
| `sshd/keys/ssh_host_*_key` | host keys, generated on first start if missing |
| `sshd/authorized_keys/<user>` | optional public keys for `<user>` |
| `sshd/sshd_config.d/*.conf` | optional sshd overrides, e.g. `Match User admin Address 10.0.0.0/8` |

`users.conf` uses the [atmoz/sftp](https://github.com/atmoz/sftp) format. Add `:e` when the
password is already a crypt hash (`openssl passwd -6`) instead of plain text:

```
alice:changeme:1000:100
bob:$6$saltsalt$hash...:e:1001:100
```

Several users may share a uid (they all write files as that uid). Lines starting with `#`
are ignored.

### Chroot

Each user is jailed in `/home/<user>`. sshd refuses the login if that directory is not
owned by root or is writable by group/others, so **mount the shares below it**, never on it:

```bash
-v /srv/share:/home/alice/share     # ok
-v /srv/share:/home/alice           # login refused
```

## Security

- SFTP only (`ForceCommand internal-sftp`): no shell, no port/agent/X11 forwarding, no tunnel.
- `root` cannot log in, password and public key only (no keyboard-interactive), at most
  2 attempts and 15 s to authenticate per connection, 5 unauthenticated connections per address.
- `PerSourcePenalties authfail:60 max:86400`: each failed connection blocks the source address
  for a minute, repeated failures up to a day.
- Dead connections are dropped after 10 minutes without answer (`ClientAlive*`).
- `KexAlgorithms` and `Ciphers` are pinned to the OpenSSH 9.9 defaults. OpenSSH 10 dropped the
  `diffie-hellman-*` key exchanges, which older clients may still need.
- The container only needs `SETUID`, `SETGID`, `SYS_CHROOT` and `CHOWN`: drop everything else
  and add `--security-opt no-new-privileges`, as in the quick start.
- Prefer public keys over passwords when the clients allow it, and mount `/config` read-only
  once the host keys exist.
- Restrict privileged accounts to your LAN/VPN with a `Match` block in `sshd/sshd_config.d/`:
  ```
  Match User admin Address 192.168.1.0/24
      PasswordAuthentication yes
  Match User admin
      PasswordAuthentication no
      PubkeyAuthentication no
  ```

## Troubleshooting

Logs go to `docker logs`:

| Log line | Cause |
|---|---|
| `bad ownership or modes for chroot directory` | a share is mounted on `/home/<user>` itself, see [Chroot](#chroot) |
| `Connection reset by peer` right after login | same as above |
| `drop connection ... penalty` | the client address is blocked after failed logins, wait or restart the container |
| `missing /config/sshd/users.conf` | create the file, see [Configuration](#configuration) |

## Updates

`.github/workflows/build.yml` checks 4 times a day and rebuilds when either:

- `debian:trixie-slim` was updated (`lucacome/docker-image-update-checker`), or
- the published image has pending package upgrades (`apt list --upgradable`):
  `openssh-server` is not part of the base image, so its security fixes would otherwise
  never trigger a rebuild.

A push to `main` touching the image files always rebuilds.

## License

[MIT](./LICENSE) © Gauthier Painteaux
