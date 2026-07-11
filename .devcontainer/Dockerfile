FROM ghcr.io/ncrmro/zejent:latest AS zejent

FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Codespaces' SSH integration works best with a standard Dev Containers base
# image. Copy Zejent's Nix closure and /bin symlink farm into that base so SSH
# lands in a normal Codespaces container while Zejent tools still come from the
# published Nix-built image.
COPY --from=zejent /nix/store /nix/store
COPY --from=zejent /bin /usr/local/zejent-bin
COPY --from=zejent /etc/zellij /etc/zellij
COPY --from=zejent /etc/nix /etc/nix

# Overlay the branch's runtime files so Codespaces can test this PR before
# ghcr.io/ncrmro/zejent:latest is rebuilt from main.
COPY code/container/bin/agent-zellij /usr/local/zejent-bin/agent-zellij
COPY code/container/etc/zellij/ /etc/zellij/
RUN chmod 0755 /usr/local/zejent-bin/agent-zellij

ENV PATH="/usr/local/zejent-bin:${PATH}"
ENV EDITOR="hx"
ENV VISUAL="hx"
ENV XDG_CACHE_HOME="/tmp/.cache"
ENV SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt"
ENV NIX_SSL_CERT_FILE="/etc/ssl/certs/ca-certificates.crt"
ENV GITHUB_TOKEN_FILE="/run/secrets/github-token"
ENV GIT_ASKPASS="/usr/local/zejent-bin/github-token-askpass"
ENV GIT_TERMINAL_PROMPT="0"
ENV TERM="xterm-256color"
