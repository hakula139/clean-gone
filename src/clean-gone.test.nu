# ==================================================================================================
# Clean Gone: CLI Tests
# ==================================================================================================

use std/assert

use ./tests/repo.testlib.nu *

def "test errors that leave nothing checkable exit 2 without output" [] {
  let repo = (make-repo)
  let tip = (git-in $repo.main rev-parse origin/main)
  let worktree = (add-worktree $repo "wt")
  let lost = (add-worktree $repo "lost")
  rm --recursive $lost
  let outside = ($repo.root | path join "outside")
  mkdir $outside
  let lsof_error = "lsof: WARNING: can't stat() fuse file system /mnt/example"
  let cases = [
    {
      name: "outside a repository"
      cwd: $outside
      lsof_exit: 0
      stderr: "error: run this command inside a Git worktree\n"
    }
    {
      name: "a failed process listing"
      cwd: $repo.main
      lsof_exit: 1
      stderr: $"error: listing open files failed\n    ($lsof_error)\n"
    }
  ]

  for case in $cases {
    let requests = [(mr 1 "feat/wt" "merged" $tip)]

    let result = (clean $repo --cwd $case.cwd --requests $requests --lsof-exit $case.lsof_exit)

    assert equal $result.exit_code 2 $case.name
    assert equal $result.stdout "" $case.name
    assert equal $result.stderr $case.stderr $case.name
    assert-kept $repo $worktree "feat/wt" $case.name
    assert ($lost in (worktrees $repo)) $case.name
  }
}

def "test a dry run reports the plan and changes nothing" [] {
  let repo = (make-repo)
  let tip = (git-in $repo.main rev-parse origin/main)
  let worktree = (add-worktree $repo "wt")
  let pid = (dead-pid)
  git-in $repo.main worktree lock --reason (claude-lock $pid) $worktree
  mkdir ($worktree | path join $MEMORY)
  "new\n" | save ($worktree | path join $"($MEMORY)/notes.md")
  let lost = (add-worktree $repo "lost")
  rm --recursive $lost
  git-in $repo.main branch feat/merged origin/main
  let requests = [
    (mr 1 "feat/wt" "merged" $tip)
    (mr 2 "feat/merged" "merged" $tip)
    (mr 3 "feat/lost" "merged" $tip)
  ]

  let result = (clean $repo --dry-run --requests $requests)

  let plan = [
    $"copy ($MEMORY)/notes.md to the main checkout"
    $"git worktree unlock ($worktree)"
    $"git worktree remove --force ($worktree)"
    "git branch -D -- feat/wt"
  ]
  assert equal $result.lines (
    [$"CLEAN ($worktree): merge request !1 is merged"]
    ++ ($plan | each {|step| $"PLAN ($worktree): ($step)" })
    ++ [
      "CLEAN feat/lost: merge request !3 is merged"
      "PLAN feat/lost: git branch -D -- feat/lost"
      "CLEAN feat/merged: merge request !2 is merged"
      "PLAN feat/merged: git branch -D -- feat/merged"
    ]
  )
  assert equal $result.exit_code 0
  assert-kept $repo $worktree "feat/wt" "dry run"
  assert ($lost in (worktrees $repo))
  assert str contains (git-in $repo.main worktree list --porcelain) (claude-lock $pid)
  assert not ($repo.main | path join $"($MEMORY)/notes.md" | path exists)
  assert (has-branch $repo "feat/merged")
}

def "test a sweep cleans finished branches and worktrees across the repository" [] {
  let repo = (make-repo)
  let tip = (git-in $repo.main rev-parse origin/main)
  let done = (add-worktree $repo "done")
  make-dirty $done
  let backup = (add-worktree $repo "backup" --branch "backup/old")
  with-env {GIT_COMMITTER_DATE: (git-date 3day)} {
    commit-files $backup {"old.txt": "old\n"} "chore: keep old work"
  }
  make-idle $backup
  let here = (add-worktree $repo "here")
  let subdir = ($here | path join "docs")
  mkdir $subdir
  let lost = (add-worktree $repo "lost")
  rm --recursive $lost

  let stuck = (commit-detached $repo "stuck.txt")
  git-in $repo.main branch feat/stuck $stuck
  make-gone $repo "feat/stuck"
  git-in $repo.main branch feat/fresh-gone (commit-detached $repo "fresh.txt" --age 2hr)
  make-gone $repo "feat/fresh-gone"
  for branch in ["feat/merged" "feat/open" "feat/plain"] {
    git-in $repo.main branch $branch origin/main
  }
  git-in $repo.main branch worktree-agent-old (commit-detached $repo "old-agent.txt")
  git-in $repo.main branch worktree-agent-new (commit-detached $repo "new-agent.txt" --age 2hr)
  git-in $repo.main branch feat/pushed (commit-detached $repo "pushed.txt" --age 2hr)
  git-in $repo.main push origin feat/pushed
  let requests = (
    ["main" "feat/done" "feat/here" "feat/lost" "feat/merged"]
    | enumerate
    | each {|row| mr ($row.index + 1) $row.item "merged" $tip }
    | append (mr 9 "feat/open" "opened" $tip)
  )

  let result = (clean $repo --cwd $subdir --requests $requests)

  let unpublished = "1 unpublished commit, last commit 3 days ago"
  let review = "Review whether it needs an MR."
  let expected = [
    ...(removal $backup $"($unpublished), so branch backup/old stays. ($review)")
    ...(removal $done "merge request !2 is merged" --branch "feat/done" --force)
    $"SKIP feat/fresh-gone: its upstream is gone, 1 unpublished commit, last commit 2 hours ago. ($review)"
    "CLEAN feat/lost: merge request !4 is merged"
    "DONE feat/lost: git branch -D -- feat/lost"
    "CLEAN feat/merged: merge request !5 is merged"
    "DONE feat/merged: git branch -D -- feat/merged"
    "CLEAN feat/plain: every commit is on a remote, last commit 3 days ago"
    "DONE feat/plain: git branch -D -- feat/plain"
    $"SKIP feat/stuck: its upstream is gone, ($unpublished). ($review)"
    $"SKIP worktree-agent-old: ($unpublished). ($review)"
  ]
  assert equal $result.lines $expected
  assert equal $result.exit_code 1
  assert-removed $repo $done "done"
  assert-removed $repo $backup "backup"
  assert ($lost not-in (worktrees $repo))
  assert-kept $repo $here "feat/here" "current worktree"
  let kept = [
    "backup/old"
    "feat/fresh-gone"
    "feat/open"
    "feat/pushed"
    "feat/stuck"
    "main"
    "worktree-agent-new"
    "worktree-agent-old"
  ]
  for branch in $kept {
    assert (has-branch $repo $branch) $branch
  }
  for branch in ["feat/done" "feat/lost" "feat/merged" "feat/plain"] {
    assert not (has-branch $repo $branch) $branch
  }
}
