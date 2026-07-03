# REQ-001 — Stable workspace identity

The launcher **MUST** derive stable default names from the resolved absolute workspace path. The default Podman pod/container name **MUST** be `zejent-{cwd-name}` and the default Zellij session name **MUST** be `{cwd-name}`, where `{cwd-name}` is a Kubernetes-safe slug of the workspace basename. The caller **MAY** override these names with environment variables.
