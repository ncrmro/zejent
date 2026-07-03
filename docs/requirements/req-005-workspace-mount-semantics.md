# REQ-005 — Workspace mount semantics

The generated Kubernetes YAML **MUST** mount the host workspace at the same absolute path inside the container and **MUST** set the container working directory to that path.
