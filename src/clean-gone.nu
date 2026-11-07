#!/usr/bin/env nu

# ==================================================================================================
# Clean Gone
# ==================================================================================================
# Remove finished local branches and stale linked worktrees after moving each worktree's ignored
# agent memory and plans into the main checkout. Remote branches are never deleted.
#
# Run with --help for usage.
# ==================================================================================================

use ./activity.nu [ancestor-pids open-files]
use ./cleanup.nu [clean-branch clean-worktree]
use ./git.nu [git-out local-branches worktree-records]
use ./output.nu [die]
use ./requests.nu [configured-origin github-remote remote-parts]

# Remove finished local branches and stale linked worktrees, after moving each worktree's ignored
# files under `.claude/agent-memory-local/` and `.agents/plans/` into the main checkout without
# overwriting anything there.
#
# It prunes worktrees whose directory is gone, unlocking those locked by an exited session or this
# one, then checks the rest except the current one. One that a running process or a live session's
# lock holds is skipped, unless the lock is this session's and the branch is finished.
#
# - Finished: the newest request of the branch is merged or closed and contains its tip. The
#   worktree is removed even with uncommitted work, and the branch is deleted.
# - Open request: the worktree is kept.
# - Uncommitted work: the worktree is skipped.
# - Idle for over a day: a detached worktree is removed when a ref holds its HEAD. A worktree on a
#   branch is removed, and its branch is deleted when every commit is on a remote.
#
# A branch checked out nowhere is deleted when it is finished. Without an open request, one whose
# last commit is over a day old is deleted when every commit is on a remote and skipped otherwise,
# as is a gone upstream with unpublished commits. Remote branches are never deleted. Exits with
# status 1 when anything is skipped.
def main [
  --dry-run # Report the plan without changing anything
] {
  let current = (git-out rev-parse --show-toplevel)
  if ($current | is-empty) {
    die "run this command inside a Git worktree"
  }

  let open_files = (open-files)
  if not $dry_run {
    ^git worktree prune
  }
  let records = (worktree-records | where not prunable)
  let github_origin = (
    [(configured-origin) (git-out remote get-url origin)]
    | uniq
    | each {|url| remote-parts $url }
    | where {|parts| github-remote $parts }
    | first
  )
  let processes = (ps | select pid ppid)
  let context = {
    main: $records.0.path
    github: ($github_origin != null)
    slug: (
      $github_origin.path?
      | default ""
      | str trim --char "/"
      | str replace --regex '\.git$' ""
    )
    open_files: $open_files
    processes: $processes
    ancestors: (ancestor-pids $processes $nu.pid)
    dry_run: $dry_run
  }

  let worktrees = (
    $records
    | skip 1
    | where path != $current
    | each {|worktree| clean-worktree $worktree $context }
  )
  let checked_out = ($records | get branch)
  let branches = (
    local-branches
    | where name not-in $checked_out
    | each {|branch| clean-branch $branch $context }
  )

  let outcomes = ($worktrees ++ $branches)
  if ($outcomes | all {|outcome| $outcome == "keep" }) {
    print "Nothing to clean up."
  }
  if "skip" in $outcomes {
    exit 1
  }
}
