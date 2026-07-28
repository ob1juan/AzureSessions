# Repository Instructions

- After completing requested code or documentation changes, run the most relevant focused validation available.
- When the requested changes validate successfully, commit only the intended files and push the commit to the current branch's configured GitHub remote in the same task.
- Before pushing, fetch the remote and stop if the branch is behind or has diverged. Never force-push or rewrite published history unless the user explicitly requests it.
- Do not commit or push unresolved validation failures, secrets, temporary diagnostics, generated noise, or unrelated user changes.
- Report the commit hash and push result. If pushing is blocked by authentication, branch protection, divergence, or validation failure, report the blocker instead of bypassing it.
