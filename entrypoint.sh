#!/bin/sh
set -eu

conf=/config/sshd/users.conf
[ -f "$conf" ] || { echo "missing $conf (format: user:pass[:e]:uid:gid)" >&2; exit 1; }

# host keys: generated on first start, then kept in /config so clients never see them change
mkdir -p /config/sshd/keys
for t in ed25519 rsa; do
  k=/config/sshd/keys/ssh_host_${t}_key
  [ -f "$k" ] || ssh-keygen -q -t "$t" -N '' -f "$k"
done

# users.conf: user:pass[:e]:uid:gid (atmoz/sftp format, ":e" = pass is already a crypt hash)
grep -vE '^[[:space:]]*(#|$)' "$conf" | tr -d '\r' | while IFS=: read -r user pass a b c; do
  if [ "$a" = e ]; then enc=-e; uid=$b; gid=$c; else enc=; uid=$a; gid=$b; fi
  getent passwd "$user" >/dev/null ||
    useradd --no-user-group --non-unique ${uid:+--uid "$uid"} ${gid:+--gid "$gid"} -d "/home/$user" -s /usr/sbin/nologin "$user"
  echo "$user:$pass" | chpasswd $enc
done

# public keys: /config/sshd/authorized_keys/<user>, copied root-owned so StrictModes accepts them
mkdir -p /etc/ssh/authorized_keys
cp /config/sshd/authorized_keys/* /etc/ssh/authorized_keys/ 2>/dev/null || true
chmod 755 /etc/ssh/authorized_keys
chmod 644 /etc/ssh/authorized_keys/* 2>/dev/null || true

# timestamps on each log line (log viewers that read `docker logs` without -t show none);
# through a fifo so sshd stays PID 1 and still gets docker stop's SIGTERM. Local time via $TZ
log=/run/sshd/log
rm -f "$log" && mkfifo "$log"
while IFS= read -r line; do printf '%s %s\n' "$(date '+%F %T')" "$line"; done <"$log" >&2 &
exec /usr/sbin/sshd -D -e 2>"$log"
