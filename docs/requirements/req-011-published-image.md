# REQ-011 — Published image

Every push to `main` **MUST** publish the flake-built container image to `ghcr.io/ncrmro/zejent:latest` via GitHub Actions. The published artifact **MUST** be the exact image produced by `nix build ./code#image`; the workflow **MUST NOT** rebuild the image with a separate Containerfile or Docker build. The workflow **MUST** authenticate to GHCR with the workflow's `GITHUB_TOKEN` and **MUST NOT** require long-lived registry credentials.
