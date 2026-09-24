FROM debian:trixie-slim
# upgrade: the slim base image lags behind Debian security updates for the packages it ships
RUN apt-get update \
 && apt-get upgrade -y \
 && apt-get install -y --no-install-recommends openssh-server \
 && rm -rf /var/lib/apt/lists/* /etc/ssh/ssh_host_* \
 && mkdir -p /run/sshd
COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /entrypoint.sh
EXPOSE 22
# sshd listening on :22 (LISTEN = 0A in /proc/net/tcp): no TCP connect, so nothing lands in the logs
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s CMD grep -qE ':0016 0{8}(0{24})?:0{4} 0A' /proc/net/tcp /proc/net/tcp6
ENTRYPOINT ["/entrypoint.sh"]
