# REQ-003 — Reattach from later shells

Re-running the launcher for the same workspace **MUST** attach to the existing background pod/container and live Zellij session when they exist, including from a later SSH login. Reattach **MUST** preserve the running Zellij session, user-created tabs, panes, and agent/subagent task tabs while the Zellij session is still live. Agent tabs and subagent task tabs **MUST** launch Pi/Outfitter with stable per-task `--session-id` values so restarting Zellij or recreating panes can resume the intended Pi session rather than opening an unrelated recent session.
