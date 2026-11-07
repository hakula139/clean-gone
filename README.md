# clean-gone

Remove finished local Git branches and stale linked worktrees after preserving ignored agent memory and plans in the main checkout.

## Install

With Nix flakes enabled:

```bash
nix profile install github:hakula139/clean-gone
```

Or run without installing:

```bash
nix run github:hakula139/clean-gone -- --help
```

The package supplies Nushell, Git, lsof, OpenSSH, and GNU coreutils on `aarch64-darwin`, `aarch64-linux`, and `x86_64-linux`. Supply an authenticated `gh` for GitHub or `glab` for GitLab on your own PATH. Keeping the forge CLI on your PATH preserves host authentication wrappers. The flake also exports `packages.<system>.clean-gone` and `overlays.default`.

To run a clone directly, install Nushell 0.116 or later and those runtime tools. From the repository you want to clean, pass the absolute path to the clone's entry file:

```bash
nu --no-config-file /path/to/clean-gone/src/clean-gone.nu --dry-run
```

Keep its sibling modules alongside it.

The [agent workflow skill][workflow] is maintained and distributed by plugins.

## Usage

Run inside the repository to sweep. Refresh remote-tracking refs before cleanup because unpublished-commit checks use local remote-tracking state. Stop if a required fetch fails.

```bash
git fetch --all --prune
clean-gone --dry-run
clean-gone
```

The command applies cleanup by default. `--dry-run` reports `PLAN` actions without changing files, locks, worktrees, or refs.

## Safety

- The main checkout and current worktree are kept. Entries whose directory is gone are pruned, releasing locks from exited sessions or the calling session when needed.
- A finished branch has no open request, and its newest PR or MR is merged or closed with a head that contains the local tip. Its branch and worktree are removed even with uncommitted work. Open requests keep their branches and worktrees.
- Running processes and other live sessions' locks protect a worktree. A lock belonging to the calling session can be released when the branch is finished. A failed process listing stops the run.
- An unfinished worktree with uncommitted files is skipped. A clean worktree is removed when its last commit and index update are both over a day old. A detached HEAD must be reachable from another ref. Its branch is deleted only when every commit is on a remote, otherwise the branch stays.
- A branch checked out nowhere is deleted when finished. Without an open request, it is also deleted when its last commit is over a day old and every commit is on a remote. Unpublished commits cause a skip when the branch is that old or its upstream is gone.
- Before removal, ignored regular files under `.claude/agent-memory-local/` and `.agents/plans/` are copied to the main checkout when absent. Existing files gain only missing nonblank lines. Remote branches and forge requests are never modified.

`SKIP` lines explain items that need attention, and the process exits with status 1 when any item is skipped. Explicit fatal safety checks exit with status 2. A successful sweep exits with status 0. Follow up on the review hint before discarding skipped work.

[workflow]: https://github.com/hakula139/plugins/tree/main/plugins/hakula-workflow/skills/clean-gone
