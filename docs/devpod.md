# DevPod compatibility

Zejent's default launcher is still `code/run-image.sh`, which renders Kubernetes
YAML and starts it with rootless `podman play kube`. DevPod support is an
optional compatibility shim for people who want to open the Zejent image through
DevPod / Dev Containers tooling.

## Local Podman provider

DevPod's Docker provider can use a rootless Podman socket on NixOS:

```bash
systemctl --user enable --now podman.socket
export DOCKER_HOST="unix:///run/user/$(id -u)/podman/podman.sock"

devpod provider add docker \
  --option DOCKER_HOST="$DOCKER_HOST" \
  --option DOCKER_PATH=docker

devpod up . \
  --provider docker \
  --provider-option DOCKER_HOST="$DOCKER_HOST" \
  --provider-option DOCKER_PATH=docker \
  --ide none
```

If testing an unpublished local image, override the image:

```bash
code/build-image.sh

devpod up . \
  --provider docker \
  --provider-option DOCKER_HOST="$DOCKER_HOST" \
  --provider-option DOCKER_PATH=docker \
  --devcontainer-image localhost/nix-zellij-agent:dev \
  --ide none
```

## Zejent-specific shim

The checked-in `.devcontainer/devcontainer.json` intentionally differs from a
plain DevPod fallback config:

- It builds a Codespaces/devcontainer overlay from the standard Ubuntu Dev
  Containers base, copies Zejent's Nix closure from `ghcr.io/ncrmro/zejent:latest`,
  and overlays the branch's `agent-zellij` plus Zellij config so PR changes can
  be tested before `latest` is rebuilt from `main`.
- `initializeCommand` attempts a non-interactive `docker login ghcr.io` with
  `GHCR_PAT` (preferred) or the Codespaces-provided `GITHUB_TOKEN` before
  pulling the private Zejent base image. If the package is private, configure a
  Codespaces user secret named `GHCR_PAT` with `read:packages` access, or make
  the package visible to this repository.
- The Ubuntu Dev Containers base keeps Codespaces' SSH integration working;
  Zejent tools are exposed through `/usr/local/zejent-bin`.
- `workspaceMount` binds the checkout to the **same absolute path** inside the
  container, preserving Zejent `REQ-005`.
- `/tmp` is a named volume (`zejent-${localWorkspaceFolderBasename}-tmp`) so
  Pi runtime state, Zellij sockets/cache, and serialized session metadata can
  survive DevPod stop/start and container recreation.
- `AGENT_ZELLIJ_SESSION_NAME` defaults to the workspace basename so `agent-zellij`
  attaches to a stable session name.

## Zellij persistence model

Live Zellij processes cannot survive when DevPod stops the container; DevPod is
stopping the process namespace. Zejent persists the useful parts by combining:

1. a persistent `/tmp` volume,
2. `XDG_CACHE_HOME=/tmp/.cache` in the image,
3. `session_serialization true` in `/etc/zellij/config.kdl`, and
4. `agent-zellij` resurrection logic that runs
   `zellij attach --create --force-run-commands <session>` when serialized
   metadata exists.

That means a later attach can resurrect the saved layout, tabs, panes, working
directories, and commands that Zellij can serialize. It is not identical to a
never-stopped live session; terminal scrollback/process state is limited by
Zellij's serialization support.

## Kubernetes provider (kind)

Verified 2026-07-09 against a local kind cluster (`make devpod-kind`). Findings:

- DevPod's Kubernetes driver always builds the devcontainer **inside the
  cluster** ("dockerless" build in the workspace pod). Image refs that only
  exist on the host or were `kind load`-ed are not visible to that build — the
  pod must be able to pull every ref, including the private
  `ghcr.io/ncrmro/zejent:latest` base.
- Registry credentials are injected from the invoking side's docker-format
  config. The Makefile target mints an ephemeral one via
  `gh auth token | podman login --authfile …` and scopes it with
  `DOCKER_CONFIG`; no persistent credential stores are touched.
- The in-pod filesystem snapshot needs real memory: a 2GB `podman machine`
  gets the build OOM-killed. 8GB (`podman machine set --memory 8192`) works.
- First `devpod up` builds in-pod (~5 min warm network); later ups reuse the
  workspace volume.

## Known gaps vs `code/run-image.sh`

- DevPod does not mount the Podman GitHub secret at `/run/secrets/github-token`
  by default. The custom launcher remains the supported path for Zejent's full
  credentials contract.
- DevPod's SSH provider has not been promoted to a default path.
- DevPod generated state can include host environment metadata; do not commit
  `.devpod`, `devpod-home`, or similar generated directories.
