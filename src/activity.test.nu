# ==================================================================================================
# Clean Gone: Activity Tests
# ==================================================================================================

use std/assert

use ./activity.nu open-files
use ./tests/repo.testlib.nu *

def "test file records retain process context and listing order" [] {
  let listing = [
    "n/home/u/src/app/before"
    "p4242"
    "cworker"
    "fcwd"
    "n/home/u/src/app"
    "f1"
    "n/home/u/src/app/first"
    "xignored"
    "p5151"
    "n/home/u/src/app/second"
    "cwatcher"
    "n/home/u/src/app/third"
    "p6262"
    "c"
    "n"
    "n/home/u/src/app/last"
  ]
  let expected = [
    {pid: "", command: "", name: "/home/u/src/app/before"}
    {pid: "4242", command: "worker", name: "/home/u/src/app"}
    {pid: "4242", command: "worker", name: "/home/u/src/app/first"}
    {pid: "5151", command: "worker", name: "/home/u/src/app/second"}
    {pid: "5151", command: "watcher", name: "/home/u/src/app/third"}
    {pid: "6262", command: "", name: ""}
    {pid: "6262", command: "", name: "/home/u/src/app/last"}
  ]

  let files = with-env {
    PATH: ($env.PATH | prepend $env.NU_TEST_STUBS)
    STUB_LSOF_OUTPUT: ($listing | str join "\n")
  } {
    open-files
  }

  assert equal $files $expected
}

def "test a worktree in use is kept even when its branch is finished" [] {
  let live = (live-pid)
  let cases = [
    {
      name: "a process inside it"
      lock: null
      processes: [
        {pid: 4242, command: "vim", files: ["{wt}" "{wt}/README.md"]}
        {pid: 5151, command: "tail", files: ["{wt}-other/app.log"]}
      ]
      lines: ["SKIP {wt}: is in use by running processes" "    4242 vim"]
    }
    {
      name: "a lock in another format"
      lock: "workmux: in use"
      processes: []
      lines: ["SKIP {wt}: is locked: workmux: in use"]
    }
    {
      name: "a lock without a reason"
      lock: ""
      processes: []
      lines: ["SKIP {wt}: is locked without a reason"]
    }
    {
      name: "another live session's lock"
      lock: (claude-lock $live)
      processes: []
      lines: [$"SKIP {wt}: is locked by another running session \(pid ($live)\)"]
    }
  ]

  try {
    for case in ($cases | enumerate) {
      let repo = (make-repo)
      let tip = (git-in $repo.main rev-parse origin/main)
      let worktree = (add-worktree $repo "wt")
      make-dirty $worktree
      if $case.item.lock != null {
        if ($case.item.lock | is-empty) {
          git-in $repo.main worktree lock $worktree
        } else {
          git-in $repo.main worktree lock --reason $case.item.lock $worktree
        }
      }
      let open = (lsof-listing $case.item.processes | str replace --all "{wt}" $worktree)
      let requests = [(mr 1 "feat/wt" "merged" $tip)]

      let result = (clean $repo --requests $requests --open $open)

      let expected = ($case.item.lines | each { str replace "{wt}" $worktree })
      assert equal $result.lines $expected $case.item.name
      assert equal $result.exit_code 1 $case.item.name
      assert-kept $repo $worktree "feat/wt" $case.item.name
    }
  } finally {
    ^kill $live
  }
}

def "test a lock is released for an exited session or a finished branch of this session" [] {
  let stale = (dead-pid)
  let cases = [
    {
      name: "an exited session's lock on an idle branch"
      pid: $stale
      requests: false
      removed: true
    }
    {
      name: "this session's lock on a finished branch"
      pid: $nu.pid
      requests: true
      removed: true
    }
    {
      name: "this session's lock on an idle branch"
      pid: $nu.pid
      requests: false
      removed: false
    }
  ]

  for case in $cases {
    let repo = (make-repo)
    let tip = (git-in $repo.main rev-parse origin/main)
    let worktree = (add-worktree $repo "wt")
    make-idle $worktree
    git-in $repo.main worktree lock --reason (claude-lock $case.pid) $worktree
    let requests = (if $case.requests { [(mr 1 "feat/wt" "merged" $tip)] } else { [] })

    let result = (clean $repo --requests $requests)

    let unlock = [$"git worktree unlock ($worktree)"]
    let expected = (
      if not $case.removed {
        [$"SKIP ($worktree): is locked by this session \(pid ($nu.pid)\)"]
      } else if $case.requests {
        removal $worktree "merge request !1 is merged" --branch "feat/wt" --force --steps $unlock
      } else {
        let reason = "every commit is on a remote, last commit 3 days ago"
        removal $worktree $reason --branch "feat/wt" --steps $unlock
      }
    )
    assert equal $result.lines $expected $case.name
    if $case.removed {
      assert equal $result.exit_code 0 $case.name
      assert-removed $repo $worktree $case.name
    } else {
      assert equal $result.exit_code 1 $case.name
      assert-kept $repo $worktree "feat/wt" $case.name
    }
  }
}

def "test a locked worktree whose directory is gone is pruned only after a released lock" [] {
  let cases = [
    {
      name: "an exited session's lock"
      lock: (claude-lock (dead-pid))
      pruned: true
    }
    {
      name: "this session's lock"
      lock: (claude-lock $nu.pid)
      pruned: true
    }
    {
      name: "a lock in another format"
      lock: "workmux: in use"
      pruned: false
    }
  ]

  for case in $cases {
    let repo = (make-repo)
    let worktree = (add-worktree $repo "wt")
    git-in $repo.main worktree lock --reason $case.lock $worktree
    rm --recursive $worktree

    let result = (clean $repo)

    let expected = (
      if $case.pruned {
        [
          $"CLEAN ($worktree): its directory is missing"
          $"DONE ($worktree): git worktree unlock ($worktree)"
          $"DONE ($worktree): git worktree prune"
        ]
      } else {
        [$"SKIP ($worktree): its directory is missing"]
      }
    )
    assert equal $result.lines $expected $case.name
    assert equal $result.exit_code (if $case.pruned { 0 } else { 1 }) $case.name
    assert equal ($worktree in (worktrees $repo)) (not $case.pruned) $case.name
  }
}
