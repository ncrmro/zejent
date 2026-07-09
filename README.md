# Zejent

A per-workspace agent container: a Nix-flake-built image with Zellij, lazygit, Pi, and Outfitter, run as a durable background Podman pod that you attach to and detach from like a remote session.

Graduated from the 2026-06-30 `podman-nix-zellij-session` spike.

## Layout

- `code/` — the Nix flake that builds the image, source-controlled container files, the `podman play kube` launcher, and the Zejent Outfitter profile.
- `docs/requirements/` — one file per requirement (`REQ-001`…); IDs are grep-able anchors used across specs, tests, and comments.
- `.github/workflows/publish.yml` — publishes the flake-built image to `ghcr.io/ncrmro/zejent:latest` on every push to `main`.

## Quickstart

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

## DevPod compatibility

Zejent includes an optional `.devcontainer/devcontainer.json` for DevPod / Dev Containers tooling. The default local workflow remains `code/run-image.sh`; the DevPod config is a compatibility shim that preserves Zejent's same-absolute-path workspace mount and uses a named `/tmp` volume so Zellij session metadata can be resurrected after DevPod stop/start.

See [`docs/devpod.md`](docs/devpod.md) for Podman provider setup, local image overrides, and known gaps versus the Zejent launcher.

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
