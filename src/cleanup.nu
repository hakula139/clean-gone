# ==================================================================================================
# Clean Gone: Cleanup
# ==================================================================================================

use ./activity.nu [holders lock-state]
use ./agent-files.nu [agent-file-moves apply-move move-text]
use ./git.nu [changed-files commit-count commit-date last-activity last-touched]
use ./output.nu [error-lines plural print-skip]
use ./requests.nu [branch-status]

const IDLE_AFTER = 1day

# Prints `git ...args` under `subject` as a PLAN line in a dry run, and otherwise runs it and prints
# it as a DONE line. Returns whether it succeeded.
def --wrapped step [subject: string, dry_run: bool, ...args: string]: nothing -> bool {
  let text = (["git"] ++ $args | str join " ")
  if $dry_run {
    print $"PLAN ($subject): ($text)"
    return true
  }

  let run = (^git ...$args | complete)
  if $run.exit_code != 0 {
    print-skip $subject $"($text) failed" (error-lines $run.stderr)
    return false
  }
  print $"DONE ($subject): ($text)"
  true
}

# Removes `worktree` for `reason` after moving its agent files, deleting its branch with `--delete`
# and its uncommitted work with `--force`. Returns `clean` or `skip`.
def remove-worktree [
  worktree: record
  lock: record
  context: record
  reason: string
  --delete
  --force
]: nothing -> string {
  let path = $worktree.path
  print $"CLEAN ($path): ($reason)"
  let tag = (if $context.dry_run { "PLAN" } else { "DONE" })
  for move in (agent-file-moves $path $context.main) {
    if not $context.dry_run {
      apply-move $move
    }
    print $"($tag) ($path): (move-text $move)"
  }

  let steps = [
    (if $lock.kind != "none" { [worktree unlock $path] })
    (if $force { [worktree remove --force $path] } else { [worktree remove $path] })
    (if $delete { [branch -D -- $worktree.branch] })
  ]
  for args in ($steps | compact) {
    if not (step $path $context.dry_run ...$args) {
      return "skip"
    }
  }
  "clean"
}

# Cleans a linked worktree as `main`'s help describes. Returns `clean`, `skip`, or `keep`.
export def clean-worktree [worktree: record, context: record]: nothing -> string {
  let path = $worktree.path
  let lock = (lock-state $worktree.locked $context)
  if not ($path | path exists) {
    if "problem" in $lock {
      print-skip $path "its directory is missing"
      return "skip"
    }
    print $"CLEAN ($path): its directory is missing"
    let unlocked = (step $path $context.dry_run worktree unlock $path)
    let pruned = ($unlocked and (step $path $context.dry_run worktree prune))
    return (if $pruned { "clean" } else { "skip" })
  }

  let users = (holders $context.open_files $path)
  if ($users | is-not-empty) {
    print-skip $path "is in use by running processes" $users
    return "skip"
  }
  if "problem" in $lock {
    print-skip $path $lock.problem
    return "skip"
  }

  let branch = $worktree.branch
  let status = (
    if ($branch | is-empty) {
      {state: "detached"}
    } else {
      branch-status $branch $context
    }
  )
  if "problem" in $status {
    print-skip $path $status.problem $status.details
    return "skip"
  }
  if $status.state == "finished" {
    return (remove-worktree $worktree $lock $context $status.evidence --delete --force)
  }
  if $lock.kind == "own" {
    print-skip $path $"is locked by this session \(pid ($lock.pid)\)"
    return "skip"
  }
  if $status.state == "open" {
    return "keep"
  }

  # Git can rewrite the index while listing changes, so its age is read first.
  let idle = ((date now) - (last-activity $worktree)) > $IDLE_AFTER
  let changed = (changed-files $path)
  if ($changed | is-not-empty) {
    let age = (last-touched $path $changed)
    print-skip $path $"uncommitted work, last touched ($age). Review whether it needs an MR."
    return "skip"
  }
  if not $idle {
    return "keep"
  }

  let age = (commit-date $worktree.head | date humanize)
  if ($branch | is-empty) {
    let loose = (
      commit-count $worktree.head
        --not
        --branches
        --tags
        --remotes
    )
    if $loose > 0 {
      let commits = (plural $loose "commit")
      let problem = $"detached HEAD with ($commits) on no ref, last commit ($age)"
      print-skip $path $"($problem). Review whether it needs an MR."
      return "skip"
    }
    return (remove-worktree $worktree $lock $context $"detached HEAD on a ref, last commit ($age)")
  }

  let unpublished = (
    commit-count $"refs/heads/($branch)"
      --not
      --remotes
  )
  if $unpublished == 0 {
    let reason = $"every commit is on a remote, last commit ($age)"
    return (remove-worktree $worktree $lock $context $reason --delete)
  }
  let commits = (plural $unpublished "unpublished commit")
  let reason = $"($commits), last commit ($age), so branch ($branch) stays"
  remove-worktree $worktree $lock $context $"($reason). Review whether it needs an MR."
}

# Cleans an unchecked-out branch as `main`'s help describes. Returns `clean`, `skip`, or `keep`.
export def clean-branch [branch: record, context: record]: nothing -> string {
  let name = $branch.name
  let status = (branch-status $name $context)
  if "problem" in $status {
    print-skip $name $status.problem $status.details
    return "skip"
  }
  if $status.state == "open" {
    return "keep"
  }

  let ref = $"refs/heads/($name)"
  let unpublished = (
    commit-count $ref
      --not
      --remotes
  )
  let date = (commit-date $ref)
  let age = ($date | date humanize)
  let idle = ((date now) - $date) > $IDLE_AFTER
  let reason = (
    if $status.state == "finished" {
      $status.evidence
    } else if $unpublished == 0 and $idle {
      $"every commit is on a remote, last commit ($age)"
    }
  )
  if $reason != null {
    print $"CLEAN ($name): ($reason)"
    let deleted = (step $name $context.dry_run branch -D -- $name)
    return (if $deleted { "clean" } else { "skip" })
  }

  if $unpublished > 0 and ($branch.gone or $idle) {
    let gone = (if $branch.gone { "its upstream is gone, " } else { "" })
    let commits = (plural $unpublished "unpublished commit")
    print-skip $name $"($gone)($commits), last commit ($age). Review whether it needs an MR."
    return "skip"
  }
  "keep"
}
