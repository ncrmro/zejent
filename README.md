# Zejent

A per-workspace agent container: a Nix-flake-built image with Zellij, lazygit, Pi, and Outfitter, run as a durable background Podman pod that you attach to and detach from like a remote session.

Graduated from the 2026-06-30 `podman-nix-zellij-session` spike.

## Layout

- `code/` — the Nix flake that builds the image, source-controlled container files, the `podman play kube` launcher, and the Zejent Outfitter profile.
- `docs/requirements/` — one file per requirement (`REQ-001`…); IDs are grep-able anchors used across specs, tests, and comments.
- `.github/workflows/publish.yml` — publishes the flake-built image to `ghcr.io/ncrmro/zejent:latest` on every push to `main`.

## Quickstart

`make help` lists one-command test environments: `make dev` (terminal attach), `make vscode` (VS Code attached to the container), `make codespace` (GitHub Codespaces), and `make kind` (Kubernetes smoke test in a local kind cluster).

Build and load the image into local Podman:

```bash
code/build-image.sh
```

Launch or attach to the per-workspace background pod and Zellij session:

```bash
code/run-image.sh /path/to/workspace
```

A workspace at `/home/me/notes` gets pod/container `zejent-notes` and Zellij session `notes`. Re-running the same command — including from a later SSH login — reuses the background pod and attaches to the existing session. Detach with `Ctrl+Shift+O`, then `d`; the pod keeps running.

Update flake inputs, bump Outfitter, rebuild, and recreate the workspace pod:

```bash
code/build-image.sh --update            # optionally --outfitter-version X.Y.Z
code/run-image.sh --replace /path/to/workspace
```

## macOS

The image is an `aarch64-linux`/`x86_64-linux` OCI artifact; on a Mac both building and running go through lightweight Linux VMs, same as any container tooling (REQ-012).

Runtime — Podman with a machine VM (mounts `/Users`, so workspace paths match the host):

```bash
brew install podman vfkit
podman machine init --now
```

Image — the lowest-friction option is pulling the published image and retagging it:

```bash
podman pull ghcr.io/ncrmro/zejent:latest
podman tag ghcr.io/ncrmro/zejent:latest localhost/nix-zellij-agent:dev
```

Building locally with `code/build-image.sh` instead requires an `aarch64-linux` Nix builder — e.g. the managed VM from `nix run nixpkgs#darwin.linux-builder` — plus your user in the daemon's `trusted-users` so the `builders` setting is honored:

```bash
echo "trusted-users = $USER" | sudo tee -a /etc/nix/nix.conf
sudo launchctl kickstart -k system/org.nixos.nix-daemon
```

Apple's Containerization framework (`container` CLI, macOS 26+) loads the image as a standard OCI archive, but the launcher currently depends on Podman-specific features (`play kube`, secrets); see REQ-012 for the support path.

## Published image

Pushes to `main` build the image with `nix build ./code#image` and copy it to `ghcr.io/ncrmro/zejent:latest` with skopeo. The local scripts still use the `localhost/nix-zellij-agent:dev` tag; the published image is the same artifact under the registry tag.

```bash
podman pull ghcr.io/ncrmro/zejent:latest
```

## Inspecting running pods

```bash
podman pod ps --filter label=dev.ncrmro.agent.kind=nix-zellij
podman ps --filter label=dev.ncrmro.agent.kind=nix-zellij
```
