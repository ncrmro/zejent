# REQ-002 — Background Podman lifecycle

The launcher **MUST** keep one reusable background Podman pod/container per workspace by default. The launcher **MUST** declare that pod/container with generated Kubernetes YAML and start it with `podman play kube`. The launcher **MUST NOT** use a disposable foreground `--rm` container for the primary workflow.
