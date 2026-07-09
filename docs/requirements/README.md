# Zejent requirements

One file per requirement. Requirement IDs (`REQ-001`, ...) are stable anchors; reference them in specs, tests, and code comments so related artifacts can be found with `rg "REQ-001"`.

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **MAY**, and **OPTIONAL** are to be interpreted as described in RFC 2119.

## Index

- [REQ-001 — Stable workspace identity](req-001-stable-workspace-identity.md)
- [REQ-002 — Background Podman lifecycle](req-002-background-podman-lifecycle.md)
- [REQ-003 — Reattach from later shells](req-003-reattach-from-later-shells.md)
- [REQ-004 — Attach-or-create Zellij session](req-004-attach-or-create-zellij-session.md)
- [REQ-005 — Workspace mount semantics](req-005-workspace-mount-semantics.md)
- [REQ-006 — Reproducible image build and Outfitter settings](req-006-reproducible-image-build.md)
- [REQ-007 — Zellij layout](req-007-zellij-layout.md)
- [REQ-008 — Keystone-compatible keybindings](req-008-keystone-compatible-keybindings.md)
- [REQ-009 — Container runtime and credentials](req-009-container-runtime-and-credentials.md)
- [REQ-010 — Observable operations](req-010-observable-operations.md)
- [REQ-011 — Published image](req-011-published-image.md)
- [REQ-012 — Portable runtimes and macOS hosts](req-012-portable-runtimes-and-macos.md)

Requirements originated from the 2026-06-30 podman-nix-zellij-session spike (draft v0.2) and carry forward its prototype plus session-preservation and Outfitter/Pi persistence findings.
