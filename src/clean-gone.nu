#!/usr/bin/env nu

# ==================================================================================================
# Clean Gone
# ==================================================================================================

use ./activity.nu [ancestor-pids open-files]
use ./cleanup.nu [clean-branch clean-worktree]
use ./git.nu [git-out local-branches worktree-records]
use ./output.nu [die]
use ./requests.nu [configured-origin github-remote remote-parts]

# Remove finished local branches and stale linked worktrees after preserving ignored agent files.
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
