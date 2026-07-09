FROM ghcr.io/ncrmro/zejent:latest

# Codespaces SSH support for the Nix-built Zejent image. The base image keeps
# most binaries under /bin via Nix buildEnv; Codespaces/devcontainer helpers look
# for a few conventional FHS paths when bootstrapping SSH.
RUN set -eux; \
    mkdir -p /usr/bin /usr/sbin /run/sshd /var/run/sshd /var/empty /root/.ssh; \
    ln -sf /bin/env /usr/bin/env; \
    ln -sf /bin/bash /usr/bin/bash; \
    ln -sf /bin/sh /usr/bin/sh; \
    ln -sf /bin/ssh /usr/bin/ssh; \
    ln -sf /bin/ssh-keygen /usr/bin/ssh-keygen; \
    ln -sf /bin/sshd /usr/sbin/sshd; \
    sed -i 's|^root:[^:]*:0:0:[^:]*:[^:]*:.*$|root:x:0:0:root:/root:/bin/bash|' /etc/passwd; \
    grep -q '^vscode:' /etc/group || printf '%s\n' 'vscode:x:1000:' >> /etc/group; \
    grep -q '^vscode:' /etc/passwd || printf '%s\n' 'vscode:x:1000:1000:VS Code:/home/vscode:/bin/bash' >> /etc/passwd; \
    mkdir -p /home/vscode/.ssh; \
    chown -R 1000:1000 /home/vscode; \
    grep -q '^sshd:' /etc/group || printf '%s\n' 'sshd:x:74:' >> /etc/group; \
    grep -q '^sshd:' /etc/passwd || printf '%s\n' 'sshd:x:74:74:Privilege-separated SSH:/var/empty:/bin/false' >> /etc/passwd; \
    rm -rf /etc/ssh; \
    mkdir -p /etc/ssh; \
    /bin/ssh-keygen -t ed25519 -N '' -f /etc/ssh/ssh_host_ed25519_key; \
    /bin/ssh-keygen -t rsa -b 3072 -N '' -f /etc/ssh/ssh_host_rsa_key; \
    printf '%s\n' \
      'Port 2222' \
      'PermitRootLogin yes' \
      'PasswordAuthentication no' \
      'PubkeyAuthentication yes' \
      'AuthorizedKeysFile .ssh/authorized_keys' \
      'UsePAM no' \
      'PidFile /tmp/sshd.pid' \
      'HostKey /etc/ssh/ssh_host_ed25519_key' \
      'HostKey /etc/ssh/ssh_host_rsa_key' \
      > /etc/ssh/sshd_config; \
    mkdir -p /etc/init.d /usr/local/share; \
    printf '%s\n' \
      '#!/bin/sh' \
      'set -eu' \
      'case "${1:-start}" in' \
      '  start)' \
      '    mkdir -p /run/sshd /var/run/sshd' \
      '    if [ -f /tmp/sshd.pid ] && kill -0 "$(cat /tmp/sshd.pid)" 2>/dev/null; then exit 0; fi' \
      '    /usr/sbin/sshd -f /etc/ssh/sshd_config' \
      '    ;;' \
      '  stop)' \
      '    if [ -f /tmp/sshd.pid ]; then kill "$(cat /tmp/sshd.pid)" 2>/dev/null || true; rm -f /tmp/sshd.pid; fi' \
      '    ;;' \
      '  restart)' \
      '    "$0" stop; "$0" start' \
      '    ;;' \
      '  *) echo "usage: $0 {start|stop|restart}" >&2; exit 2 ;;' \
      'esac' \
      > /etc/init.d/ssh; \
    chmod 0755 /etc/init.d/ssh; \
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'set -euo pipefail' \
      '/etc/init.d/ssh start' \
      'exec "$@"' \
      > /usr/local/share/ssh-init.sh; \
    chmod 0755 /usr/local/share/ssh-init.sh

# Overlay the branch's Zejent runtime files on top of the published base image
# so Codespaces can test this PR before ghcr.io/ncrmro/zejent:latest is rebuilt
# from main.
COPY code/container/bin/agent-zellij /bin/agent-zellij
COPY code/container/etc/zellij/ /etc/zellij/
RUN chmod 0755 /bin/agent-zellij
