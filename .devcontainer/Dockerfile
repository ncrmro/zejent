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
      > /etc/ssh/sshd_config

# Overlay the branch's Zejent runtime files on top of the published base image
# so Codespaces can test this PR before ghcr.io/ncrmro/zejent:latest is rebuilt
# from main.
COPY code/container/bin/agent-zellij /bin/agent-zellij
COPY code/container/etc/zellij/ /etc/zellij/
RUN chmod 0755 /bin/agent-zellij
